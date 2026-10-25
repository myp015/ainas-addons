#!/usr/bin/env bash
#
# Copyright (C) 2022 Ing <https://github.com/wjz304>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

function _log() {
  echo "maiyunda: $*"
  /bin/logger -p "error" -t "maiyunda" "$@"
}

function btnOpt() {
  _log "${1} Button ${2}s Option"
  case "${1}-${2}" in
  Reset-3)
    # restart network
    for F in $(LC_ALL=C printf '%s\n' /etc/sysconfig/network-scripts/ifcfg-* /etc.defaults/sysconfig/network-scripts/ifcfg-* | sort -V); do
      [ ! -e "${F}" ] && continue
      ETHX=$(echo "${F}" | sed -E 's/.*ifcfg-(.*)$/\1/')
      case "${ETHX}" in
      ovs_bond*)
        rm -f "${F}"
        ;;
      ovs_eth*)
        ovs-vsctl del-br ${ETHX}
        sed -i "/${ETHX##ovs_}/"d /usr/syno/etc/synoovs/ovs_interface.conf
        rm -f "${F}"
        ;;
      eth*)
        echo -e "DEVICE=${ETHX}\nONBOOT=yes\nBOOTPROTO=dhcp\nIPV6INIT=auto_dhcp\nIPV6_ACCEPT_RA=1" >"${F}"
        ;;
      *) ;;
      esac
    done
    sed -i 's/_mtu=".*"$/_mtu="1500"/g' /etc/synoinfo.conf /etc.defaults/synoinfo.conf
    systemctl restart rc-network.service

    # change admin password
    USERNAME="admin"
    PASSWORD="maiyunda.com"
    NEWPASSWD="$(openssl passwd -6 -salt "$(openssl rand -hex 8)" "${PASSWORD:-rr}")"
    sed -i "s|^${USERNAME}:[^:]*|${USERNAME}:${NEWPASSWD}|" "/etc/shadow"
    sed -i "/^${USERNAME}:/ s/^\(${USERNAME}:[^:]*:[^:]*:[^:]*:[^:]*:[^:]*:[^:]*:\)[^:]*:/\1:/" "/etc/shadow"
    synowebapi -s --exec api=SYNO.Core.User method=set version=1 name=\"admin\" cannot_chg_passwd=false expired=\"normal\"
    ;;
  Reset-9)
    if [ -x "/usr/bin/loader-reboot.sh" ]; then
      # junior reset
      /usr/bin/loader-reboot.sh "junior"
    else
      # factory reset
      synowebapi -s --exec api=SYNO.Core.System method=reset version=1
    fi
    ;;
  Reset-18)
    # factory reset
    synowebapi -s --exec api=SYNO.Core.System method=reset version=1
    ;;
  *)
    _log "Unknown button option: ${1}-${2}"
    ;;
  esac &
}

function btnBeep() {
  local t=3
  [[ "${1}" =~ ^[0-9]+$ ]] && t="${1}"
  beep -f 1000 -l 50 -d 50 -r "${t}" &
}

function main() {

  ResetBtnTimeout=0
  ResetBtnPressed=0
  ResetBtnBaseVal=$(inb "0xA03")
  while true; do
    sleep 1
    ResetBtnCurtVal=$(inb "0xA03")
    if [ ! "${ResetBtnCurtVal}" = "${ResetBtnBaseVal}" ]; then
      ResetBtnTimeout=$((ResetBtnTimeout + 1))
      if [ $((ResetBtnTimeout % 3)) -eq 0 ]; then
        ResetBtnPressed=${ResetBtnTimeout}
        btnBeep 3
      fi
      if echo "3 9 18" | grep -qE "(^|[[:space:]])${ResetBtnTimeout}([[:space:]]|$)"; then
        btnOpt Reset ${ResetBtnPressed}
      fi
    else
      ResetBtnTimeout=0
      ResetBtnPressed=0
    fi
  done
}

main &
