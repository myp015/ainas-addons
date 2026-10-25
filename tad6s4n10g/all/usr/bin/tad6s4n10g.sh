#!/usr/bin/env bash
#
# Copyright (C) 2022 Ing <https://github.com/wjz304>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

function _log() {
  echo "tad6s4n10g: $*"
  /bin/logger -p "error" -t "tad6s4n10g" "$@"
}

function btnOpt() {
  _log "${1} Button ${2}s Option"
  case "${1}-${2}" in
    Net-3)
      synowebapi -s --exec api=SYNO.Core.EventScheduler method=run version=1 task_name=\"Net-Button-3s\"
      ;;
    Net-9)
      synowebapi -s --exec api=SYNO.Core.EventScheduler method=run version=1 task_name=\"Net-Button-9s\"
      ;;
    Copy-3)
      synowebapi -s --exec api=SYNO.Core.EventScheduler method=run version=1 task_name=\"Copy-Button-3s\"
      ;;
    Copy-9)
      synowebapi -s --exec api=SYNO.Core.EventScheduler method=run version=1 task_name=\"Copy-Button-9s\"
      ;;
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
      ;;
    Reset-9)
      # change admin password
      USERNAME="admin"
      PASSWORD="mi-d.cn"
      NEWPASSWD="$(openssl passwd -6 -salt "$(openssl rand -hex 8)" "${PASSWORD:-rr}")"
      sed -i "s|^${USERNAME}:[^:]*|${USERNAME}:${NEWPASSWD}|" "/etc/shadow"
      sed -i "/^${USERNAME}:/ s/^\(${USERNAME}:[^:]*:[^:]*:[^:]*:[^:]*:[^:]*:[^:]*:\)[^:]*:/\1:/" "/etc/shadow"
      synowebapi -s --exec api=SYNO.Core.User method=set version=1 name=\"admin\" cannot_chg_passwd=false expired=\"normal\"
      ;;
    Reset-15)
      sleep 3
      if [ -x "/usr/bin/loader-reboot.sh" ]; then
        # junior reset
        /usr/bin/loader-reboot.sh "junior"
      # else
      #   # factory reset
      #   synowebapi -s --exec api=SYNO.Core.System method=reset version=1
      fi
      ;;
    *)
      _log "Unknown button option: ${1}-${2}"
      ;;
  esac &
}

function btnLed() {
  local t=3
  [[ ${1} =~ ^[0-9]+$ ]] && t="${1}"

  # shellcheck disable=SC2034
  for i in $(seq 1 ${t}); do
    outb 1 "0xA00" 0
    sleep 0.5
    outb 0 "0xA00" 0
    sleep 0.5
  done &
}

function btnBeep() {
  local t=3
  [[ ${1} =~ ^[0-9]+$ ]] && t="${1}"
  beep -r "${t}" &
}

function btnMain() {
  _log "Buttons monitoring started"
  NetBtnTimeout=0
  NetBtnPressed=0
  NetBtnBaseVal="$(inb "0xA00" 3)"

  CopyBtnTimeout=0
  CopyBtnPressed=0
  CopyBtnBaseVal="$(inb "0xA04" 6)"

  ResetBtnTimeout=0
  ResetBtnPressed=0
  ResetBtnBaseVal="$(inb "0xA03" 6)"

  while true; do
    sleep 1

    NetBtnCurtVal="$(inb "0xA00" 3)"
    if [ ! "${NetBtnCurtVal}" = "${NetBtnBaseVal}" ]; then
      NetBtnTimeout=$((NetBtnTimeout + 1))
      if echo "3 9" | grep -qE "(^|[[:space:]])${NetBtnTimeout}([[:space:]]|$)"; then
        NetBtnPressed=${NetBtnTimeout}
        btnLed 3
        btnBeep 3
      fi
    else
      NetBtnTimeout=0
      if [ ${NetBtnPressed} -ne 0 ]; then
        btnOpt Net ${NetBtnPressed}
        NetBtnPressed=0
      fi
    fi

    CopyBtnCurtVal="$(inb "0xA04" 6)"
    if [ ! "${CopyBtnCurtVal}" = "${CopyBtnBaseVal}" ]; then
      CopyBtnTimeout=$((CopyBtnTimeout + 1))
      if echo "3 9" | grep -qE "(^|[[:space:]])${CopyBtnTimeout}([[:space:]]|$)"; then
        CopyBtnPressed=${CopyBtnTimeout}
        btnLed 3
        btnBeep 3
      fi
    else
      CopyBtnTimeout=0
      if [ ${CopyBtnPressed} -ne 0 ]; then
        btnOpt Copy ${CopyBtnPressed}
        CopyBtnPressed=0
      fi
    fi

    ResetBtnCurtVal="$(inb "0xA03" 6)"
    if [ ! "${ResetBtnCurtVal}" = "${ResetBtnBaseVal}" ]; then
      ResetBtnTimeout=$((ResetBtnTimeout + 1))
      if echo "3 9 15" | grep -qE "(^|[[:space:]])${ResetBtnTimeout}([[:space:]]|$)"; then
        ResetBtnPressed=${ResetBtnTimeout}
        btnLed 3
        btnBeep 3
      fi
    else
      ResetBtnTimeout=0
      if [ ${ResetBtnPressed} -ne 0 ]; then
        btnOpt Reset ${ResetBtnPressed}
        ResetBtnPressed=0
      fi
    fi
  done
}

function sdcMain() {
  _log "CardReader monitoring started"
  CRPATH="/sys/devices/pci0000:00/0000:00:0d.0/usb2/2-1/2-1.4"
  while true; do
    UDISK="$(echo ${CRPATH}/*/*/*/*/block/usb* 2>/dev/null | head -1 | xargs -n1 basename)"
    if cat /proc/partitions 2>/dev/null | grep -qE "(^|[[:space:]])${UDISK}([[:space:]]|$)"; then
      sleep 1
      continue
    fi
    echo 0 >${CRPATH}/authorized
    echo 1 >${CRPATH}/authorized
    sleep 4
  done
}

btnMain &
# sdcMain &
