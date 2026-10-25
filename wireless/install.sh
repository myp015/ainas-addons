#!/usr/bin/env sh
#
# Copyright (C) 2022 Ing <https://github.com/wjz304>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

# shellcheck disable=SC2010

_release="$(/bin/uname -r)"
# DSM 版本判据：读 /etc/defaults/VERSION 的 majorversion（6.2 → 6，7.x → 7）。
# 不能用内核主版本 —— DSM 7.0~7.3 的内核同样是 4.4.x（4.4.180 / 4.4.302），与 6.2 的
# 4.4.59 / 3.10.105 主版本相同，用内核主版本会把整个 7.x 误判成 6.2。
MajorVersion="$(/bin/get_key_value /etc.defaults/VERSION majorversion 2>/dev/null)"
# 兜底：万一某个 ramdisk 没有 /etc.defaults/VERSION，用 /etc/VERSION（loader 的
# ramdisk-patch.sh 本身就以它为必需文件，两者在 6.2 ramdisk 里内容相同）。
[ -n "${MajorVersion}" ] || MajorVersion="$(/bin/get_key_value /etc/VERSION majorversion 2>/dev/null)"
case "${MajorVersion}" in
  '' | *[!0-9]*)
    echo " ERROR: cannot determine DSM major version from /etc/defaults/VERSION" >&2
    exit 1
    ;;
esac

# DSM 6.x 的 ramdisk 没有 iw/wpa_supplicant，且 7.1 载荷的 iw 依赖 libnl-3、
# wpa_supplicant 依赖 libcrypto.so.3 / libdbus-1（均需 glibc 2.25+），6.x 的 glibc 是 2.20。
# 6.2 载荷取自 DSM 6.2 自身（iw / wpa_supplicant / wpa_cli + libnl.so.2 / libssl.so.1.0.0），
# 其中 libcrypto.so.1.0.0 由 misc addon 的 6.2 覆盖层提供（ramdisk）或 DSM 6.2 自带（root）。
if [ "${MajorVersion}" -lt 7 ]; then
  _wireless_pkg="/addons/wireless-6.2.tgz"
else
  _wireless_pkg="/addons/wireless-7.1.tgz"
fi

if [ "${1}" = "rcExit" ]; then
  echo "Installing addon wireless - ${1}"

  SSID="$(cat /proc/cmdline 2>/dev/null | grep -Eo 'wpa.ssid=[^ ]+' | sed 's/wpa.ssid=//' | xxd -r -p)"
  PSK="$(cat /proc/cmdline 2>/dev/null | grep -Eo 'wpa.psk=[^ ]+' | sed 's/wpa.psk=//' | xxd -r -p)"

  if [ -n "${SSID}" ] && [ -n "${PSK}" ]; then
    ETHX=$(ls /sys/class/net/ 2>/dev/null | grep '^eth8' | grep -v '^eth8$')
    if [ -n "${ETHX}" ]; then
      echo "Wireless: ${SSID} ${PSK} for ${ETHX}"
      [ -f "${_wireless_pkg}" ] || {
        echo " ERROR: ${_wireless_pkg} not found (needed for kernel ${_release})" >&2
        exit 1
      }
      tar -zxf "${_wireless_pkg}" -C /
      for N in ${ETHX}; do
        if [ -f "/var/run/wpa_supplicant.pid.${N}" ]; then
          kill "$(cat "/var/run/wpa_supplicant.pid.${N}")"
          rm -f "/var/run/wpa_supplicant.pid.${N}"
        fi
        ISOVS=$([ -L "/sys/class/net/ovs_${N}" ] && echo "true" || echo "false")
        [ "${ISOVS}" = "true" ] && /etc/rc.network "stop" "ovs_${N}" >/dev/null 2>&1
        printf "ctrl_interface=/var/run/wpa_supplicant\nupdate_config=1\nnetwork={\n        ssid=\"${SSID}\"\n        priority=1\n        psk=\"${PSK}\"\n}" >"/usr/syno/etc/wpa_supplicant.conf.${N}"
        /usr/sbin/wpa_supplicant -i "${N}" -c "/usr/syno/etc/wpa_supplicant.conf.${N}" -qq -B -P "/var/run/wpa_supplicant.pid.${N}"
        sleep 3
        if [ -x /sbin/udhcpc ]; then # junior
          if [ -f "/etc/dhcpc/dhcpcd-${N}.pid" ]; then
            kill "$(cat "/etc/dhcpc/dhcpcd-${N}.pid")"
            rm -f "/etc/dhcpc/dhcpcd-${N}.pid"
          fi
          /sbin/udhcpc -i "${N}" -p "/etc/dhcpc/dhcpcd-${N}.pid" -b -x hostname:"$(hostname)" || true
        fi
        sleep 1
        [ "${ISOVS}" = "true" ] && /etc/rc.network "start" "ovs_${N}" >/dev/null 2>&1
        sleep 1
        /usr/sbin/wpa_cli status
      done
    fi
  fi

elif [ "${1}" = "late" ]; then
  echo "Installing addon wireless - ${1}"
  mkdir -p "/tmpRoot/usr/rr/addons/"
  cp -pf "${0}" "/tmpRoot/usr/rr/addons/"

  cp -vpf /usr/bin/wireless_supplicant.sh /tmpRoot/usr/bin/wireless_supplicant.sh
  if [ "${MajorVersion}" -lt 7 ]; then
    # DSM 6.x 自带 /usr/sbin/{iw,wpa_supplicant,wpa_cli}（/sbin -> usr/sbin），运行期直接用系统自带；
    # 载荷只用于安装阶段（rcExit 时还没有 DSM 根文件系统）。
    echo "DSM 6.x uses its built-in iw/wpa_supplicant, skip payload extraction"
  else
    tar -zxf "${_wireless_pkg}" -C /tmpRoot/usr ./sbin/iw ./sbin/rfkill
  fi

  SSID="$(cat /proc/cmdline 2>/dev/null | grep -Eo 'wpa.ssid=[^ ]+' | sed 's/wpa.ssid=//' | xxd -r -p)"
  PSK="$(cat /proc/cmdline 2>/dev/null | grep -Eo 'wpa.psk=[^ ]+' | sed 's/wpa.psk=//' | xxd -r -p)"

  export LD_LIBRARY_PATH=/tmpRoot/bin:/tmpRoot/lib
  ESYNOSCHEDULER_DB="/tmpRoot/usr/syno/etc/esynoscheduler/esynoscheduler.db"
  if [ ! -f "${ESYNOSCHEDULER_DB}" ] || ! /tmpRoot/bin/sqlite3 "${ESYNOSCHEDULER_DB}" ".tables" | grep -qE "(^|[[:space:]])task([[:space:]]|$)"; then
    echo "copy esynoscheduler.db"
    mkdir -p "$(dirname "${ESYNOSCHEDULER_DB}")"
    cp -vpf /addons/esynoscheduler.db "${ESYNOSCHEDULER_DB}"
  fi
  ENABLE=0
  if [ -n "${SSID}" ] && [ -n "${PSK}" ]; then
    ENABLE=1
    ETHX=$(ls /sys/class/net/ 2>/dev/null | grep '^eth8' | grep -v '^eth8$')
    for N in ${ETHX}; do
      if [ -f "/var/run/wpa_supplicant.pid.${N}" ]; then
        kill "$(cat "/var/run/wpa_supplicant.pid.${N}")"
        rm -f "/var/run/wpa_supplicant.pid.${N}"
      fi
      if [ -x /sbin/udhcpc ]; then # junior
        if [ -f "/etc/dhcpc/dhcpcd-${N}.pid" ]; then
          kill "$(cat "/etc/dhcpc/dhcpcd-${N}.pid")"
          rm -f "/etc/dhcpc/dhcpcd-${N}.pid"
        fi
      fi
    done
  fi
  if echo "SELECT * FROM task;" | /tmpRoot/bin/sqlite3 "${ESYNOSCHEDULER_DB}" | grep -q "Wireless"; then
    echo "wireless task already exists"
  else
    echo "insert wireless task to esynoscheduler.db"
    /tmpRoot/bin/sqlite3 "${ESYNOSCHEDULER_DB}" <<EOF
INSERT INTO task VALUES('Wireless', '', 'bootup', '', ${ENABLE}, 0, 0, 0, '', 0, '
# 1: The NAME of the wireless network interface, "*" is All, Support "," segmentation; e.g. wlan0,eth81. (wlan0 = eth80, wlan1 = eth81, ...)
# 2: The SSID of the wireless network.
# 3: The PSK of the wireless network.
/usr/bin/wireless_supplicant.sh "*" "${SSID:-SSID}" "${PSK:-PSK}"
', 'script', '{}', '', '', '{}', '{}');
EOF
  fi
elif [ "${1}" = "uninstall" ]; then
  echo "Uninstalling daemon for wireless - ${1}"

  rm -f /tmpRoot/usr/bin/wireless_supplicant.sh
  rm -f /tmpRoot/usr/sbin/iw
  rm -f /tmpRoot/usr/sbin/rfkill

  export LD_LIBRARY_PATH=/tmpRoot/bin:/tmpRoot/lib
  ESYNOSCHEDULER_DB="/tmpRoot/usr/syno/etc/esynoscheduler/esynoscheduler.db"
  if [ -f "${ESYNOSCHEDULER_DB}" ]; then
    echo "delete wireless task from esynoscheduler.db"
    /tmpRoot/bin/sqlite3 "${ESYNOSCHEDULER_DB}" <<EOF
DELETE FROM task WHERE task_name LIKE 'Wireless';
EOF
  fi
fi
