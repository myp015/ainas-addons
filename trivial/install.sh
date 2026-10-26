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
    # 用 case 模式匹配而不是 grep -E：参数可能是 "*"（清全部），把它拼进 ERE 会变成
    # 非法量词（")*"），grep 直接报错并返回 2，本应清空的分支永远走不到。
    case " all * " in
      *" ${1} "*)
        rm -f "${SYSLOG_NG_PATH}/RR.conf"
        for D in not2kern not2msg; do
          rm -f "${SYSLOG_NG_PATH}/include/${D}/RR_${D}.conf"
        done
        ;;
      *)
        FNAME="f_$(echo "${1}" | sed 's/[^a-zA-Z0-9]/_/g' | sed 's/.*/\L&/' | cut -c 1-30)"
        sed -i "/${FNAME}/d" "${SYSLOG_NG_PATH}/RR.conf" 2>/dev/null
        for D in not2kern not2msg; do
          sed -i "/${FNAME}/d" "${SYSLOG_NG_PATH}/include/${D}/RR_${D}.conf" 2>/dev/null
        done
        ;;
    esac
  }

  getblocklog() {
    grep -Eo "filter.*match.*" "${SYSLOG_NG_PATH}/RR.conf" 2>/dev/null | sed 's/filter \(.*\) { match(\(.*\) value("MESSAGE")); };/\1=\2/'
  }

  # syslog-ng
  # DSM 6.2 每次启动都会 `rm -rf /etc/syslog-ng/patterndb.d`（/etc/init/root-file-system.conf），
  # 再由 /etc/init/syslog-ng.conf 从 /etc.defaults 复制回来 ⇒ 写进 /etc 的过滤规则开机即被冲掉。
  # 6.2 只保留 /usr/local/etc/syslog-ng/patterndb.d 这个本地覆盖目录（syslog-ng.conf 里有
  # include "/usr/local/etc/syslog-ng/patterndb.d/"，DSM 自己也把 HighAvailability.conf 放这里）。
  ROOT_PATH="/tmpRoot"
  MajorVersion="$(/bin/get_key_value /etc.defaults/VERSION majorversion 2>/dev/null)"
  [ -n "${MajorVersion}" ] || MajorVersion="$(/bin/get_key_value /etc/VERSION majorversion 2>/dev/null)"
  case "${MajorVersion}" in
    '' | *[!0-9]*)
      echo " ERROR: cannot determine DSM major version from /etc/defaults/VERSION" >&2
      exit 1
      ;;
  esac
  if [ "${MajorVersion}" -lt 7 ]; then
    SYSLOG_NG_PATH="${ROOT_PATH}/usr/local/etc/syslog-ng/patterndb.d"
  else
    SYSLOG_NG_PATH="${ROOT_PATH}/etc/syslog-ng/patterndb.d"
  fi
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

  # syslog-ng：6.2 在 /usr/local 覆盖目录、7.x 在 /etc，两处都清（兼容旧版本安装的位置）
  for P in "/tmpRoot/usr/local/etc/syslog-ng/patterndb.d" "/tmpRoot/etc/syslog-ng/patterndb.d"; do
    rm -f "${P}/RR.conf"
    for D in not2kern not2msg; do
      rm -f "${P}/include/${D}/RR_${D}.conf"
    done
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
