#!/usr/bin/env sh
#
# Copyright (C) 2022 Ing <https://github.com/wjz304>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

if [ "${1}" = "late" ]; then
  echo "Installing addon trivial - ${1}"
  mkdir -p "/tmpRoot/usr/rr/addons/"
  cp -pf "${0}" "/tmpRoot/usr/rr/addons/"

  addblocklog() {
    [ -z "${1}" ] && return 1
    FNAME="f_$(echo "${1}" | sed 's/[^a-zA-Z0-9]/_/g' | sed 's/.*/\L&/' | cut -c 1-30)"
    REGEX="${1}"
    mkdir -p "${SYSLOG_NG_PATH}"
    sed -i "/${FNAME}/d" "${SYSLOG_NG_PATH}/RR.conf" 2>/dev/null
    # shellcheck disable=SC2059
    printf "filter ${FNAME} { match(\"${REGEX}\" value(\"MESSAGE\")); };\nlog { source(src); filter(${FNAME}); flags(final); };\n" >>"${SYSLOG_NG_PATH}/RR.conf"
    chown system:log "${SYSLOG_NG_PATH}/RR.conf"
    chmod 644 "${SYSLOG_NG_PATH}/RR.conf"

    for D in not2kern not2msg; do
      mkdir -p "${SYSLOG_NG_PATH}/include/${D}"
      sed -i "/${FNAME}/d" "${SYSLOG_NG_PATH}/include/${D}/RR_${D}.conf" 2>/dev/null
      echo "and not filter(${FNAME})" >>"${SYSLOG_NG_PATH}/include/${D}/RR_${D}.conf"
      chown system:log "${SYSLOG_NG_PATH}/include/${D}/RR_${D}.conf"
      chmod 644 "${SYSLOG_NG_PATH}/include/${D}/RR_${D}.conf"
    done
    # systemctl restart syslog-ng
  }

  delblocklog() {
    [ -z "${1}" ] && return 1
    if echo "all *" | grep -wq "${1}"; then
      rm -f "${SYSLOG_NG_PATH}/RR.conf"
      for D in not2kern not2msg; do
        rm -f "${SYSLOG_NG_PATH}/include/${D}/RR_${D}.conf"
      done
    else
      FNAME="f_$(echo "${1}" | sed 's/[^a-zA-Z0-9]/_/g' | sed 's/.*/\L&/' | cut -c 1-30)"
      sed -i "/${FNAME}/d" "${SYSLOG_NG_PATH}/RR.conf" 2>/dev/null
      for D in not2kern not2msg; do
        sed -i "/${FNAME}/d" "${SYSLOG_NG_PATH}/include/${D}/RR_${D}.conf" 2>/dev/null
      done
    fi
  }

  getblocklog() {
    grep -Eo "filter.*match.*" "${SYSLOG_NG_PATH}/RR.conf" 2>/dev/null | sed 's/filter \(.*\) { match(\(.*\) value("MESSAGE")); };/\1=\2/'
  }

  # syslog-ng
  ROOT_PATH="/tmpRoot"
  SYSLOG_NG_PATH="${ROOT_PATH}/etc/syslog-ng/patterndb.d"
  delblocklog "*"
  addblocklog "synobios get empty ttyS current"
  addblocklog "telnet/tcp: bind: Address already in use"
  addblocklog "Invalid parameter"
  addblocklog "Failed to get"
  addblocklog "Failed to load"
  addblocklog "Failed to check"
  addblocklog "Failed to update"
  addblocklog "fail to get all"
  addblocklog "Can't get sata chip name"
  addblocklog "redundant_power_chec"
  addblocklog "fan/fan_"
  addblocklog "fan/fan_"
  addblocklog "plugin_action"
  addblocklog "package_action"
  addblocklog "No NVIDIA"

  # syno-dump-core
  SH_FILE="/tmpRoot/usr/syno/sbin/syno-dump-core.sh"
  [ ! -f "${SH_FILE}.bak" ] && cp -pf "${SH_FILE}" "${SH_FILE}.bak"
  printf '#!/bin/sh\nexit 0\n' >"${SH_FILE}"

  # trivial.service
  cp -vpf /usr/bin/trivial.sh /tmpRoot/usr/bin/trivial.sh

  mkdir -p "/tmpRoot/usr/lib/systemd/system"
  DEST="/tmpRoot/usr/lib/systemd/system/trivial.service"
  {
    echo "[Unit]"
    echo "Description=RR addon trivial daemon"
    echo "After=multi-user.target"
    echo
    echo "[Service]"
    echo "Type=oneshot"
    echo "RemainAfterExit=yes"
    echo "ExecStart=-/usr/bin/trivial.sh"
    echo
    echo "[Install]"
    echo "WantedBy=multi-user.target"
  } >"${DEST}"

  mkdir -p /tmpRoot/usr/lib/systemd/system/multi-user.target.wants
  ln -sf /usr/lib/systemd/system/trivial.service /tmpRoot/usr/lib/systemd/system/multi-user.target.wants/trivial.service

elif [ "${1}" = "uninstall" ]; then
  echo "Installing addon trivial - ${1}"

  # syslog-ng
  SYSLOG_NG_PATH="/tmpRoot/etc/syslog-ng/patterndb.d"
  rm -f "${SYSLOG_NG_PATH}/RR.conf"
  for D in not2kern not2msg; do
    rm -f "${SYSLOG_NG_PATH}/include/${D}/RR_${D}.conf"
  done

  # syno-dump-core
  SH_FILE="/tmpRoot/usr/syno/sbin/syno-dump-core.sh"
  [ -f "${SH_FILE}.bak" ] && mv -f "${SH_FILE}.bak" "${SH_FILE}"

  # trivial.service
  rm -f "/tmpRoot/usr/lib/systemd/system/multi-user.target.wants/trivial.service"
  rm -f "/tmpRoot/usr/lib/systemd/system/trivial.service"

  [ ! -f "/tmpRoot/usr/rr/revert.sh" ] && echo '#!/usr/bin/env bash' >/tmpRoot/usr/rr/revert.sh && chmod +x /tmpRoot/usr/rr/revert.sh
  echo "/usr/bin/trivial.sh -r" >>/tmpRoot/usr/rr/revert.sh
  echo "rm -f /usr/bin/trivial.sh" >>/tmpRoot/usr/rr/revert.sh
fi
