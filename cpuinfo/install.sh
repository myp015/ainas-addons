#!/usr/bin/env sh
#
# Copyright (C) 2022 Ing <https://github.com/wjz304>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

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

if [ "${1}" = "late" ]; then
  echo "Installing addon cpuinfo - ${1} (kernel ${MajorVersion})"
  mkdir -p "/tmpRoot/usr/rr/addons/"
  cp -pf "${0}" "/tmpRoot/usr/rr/addons/"

  # cpuinfo
  # DSM 6.x 用同版本（DSM 6.2 时代）的脚本，只改 admin_center.js，不依赖 synoscgiproxy；
  # 7.x 用现版。两者都装成 /usr/bin/cpuinfo.sh，unit 的 ExecStart 不变。
  if [ "${MajorVersion}" -lt 7 ]; then
    cp -vpf /usr/bin/cpuinfo-6.2.sh /tmpRoot/usr/bin/cpuinfo.sh
  else
    cp -vpf /usr/bin/cpuinfo.sh /tmpRoot/usr/bin/cpuinfo.sh
  fi

  shift
  mkdir -p "/tmpRoot/usr/lib/systemd/system"
  DEST="/tmpRoot/usr/lib/systemd/system/cpuinfo.service"
  {
    echo "[Unit]"
    echo "Description=RR addon cpuinfo daemon"
    echo "After=synoscgi.service nginx.service"
    echo
    echo "[Service]"
    echo "Type=oneshot"
    echo "RemainAfterExit=yes"
    echo "ExecStart=-/usr/bin/cpuinfo.sh $*"
    echo
    echo "[Install]"
    echo "WantedBy=multi-user.target"
  } >"${DEST}"

  mkdir -p /tmpRoot/usr/lib/systemd/system/multi-user.target.wants
  ln -sf /usr/lib/systemd/system/cpuinfo.service /tmpRoot/usr/lib/systemd/system/multi-user.target.wants/cpuinfo.service

  # synoscgiproxy（仅 7.x：6.x 不用它，且 6.x 的 ramdisk 里没有这个二进制）
  if [ "${MajorVersion}" -ge 7 ]; then
    cp -vpf /usr/sbin/synoscgiproxy /tmpRoot/usr/sbin/synoscgiproxy
  fi

  # for FILE in "/tmpRoot/etc/nginx/nginx.conf" "/tmpRoot/usr/syno/share/nginx/nginx.mustache"; do
  #   [ ! -f "${FILE}.bak" ] && cp -pf "${FILE}" "${FILE}.bak"
  #   sed -i 's|/run/synoscgi.sock;|/run/synoscgi_rr.sock;|' "${FILE}"
  # done
  #
  # mkdir -p "/tmpRoot/usr/lib/systemd/system"
  # DEST="/tmpRoot/usr/lib/systemd/system/synoscgiproxy.service"
  # {
  #   echo "[Unit]"
  #   echo "Description=RR addon synoscgiproxy daemon"
  #   echo "After=network.target nginx.service"
  #   echo
  #   echo "[Service]"
  #   echo "Type=forking"
  #   echo "ExecStart=/usr/sbin/synoscgiproxy"
  #   echo "ExecReload=/usr/bin/pkill -f /usr/sbin/synoscgiproxy"
  #   echo "Restart=always"
  #   echo
  #   echo "[Install]"
  #   echo "WantedBy=multi-user.target"
  # } >"${DEST}"
  #
  # mkdir -p /tmpRoot/usr/lib/systemd/system/multi-user.target.wants
  # ln -sf /usr/lib/systemd/system/synoscgiproxy.service /tmpRoot/usr/lib/systemd/system/multi-user.target.wants/synoscgiproxy.service

elif [ "${1}" = "uninstall" ]; then
  echo "Installing addon cpuinfo - ${1}"

  # cpuinfo
  rm -f "/tmpRoot/usr/lib/systemd/system/multi-user.target.wants/cpuinfo.service"
  rm -f "/tmpRoot/usr/lib/systemd/system/cpuinfo.service"

  [ ! -f "/tmpRoot/usr/rr/revert.sh" ] && echo '#!/usr/bin/env bash' >/tmpRoot/usr/rr/revert.sh && chmod +x /tmpRoot/usr/rr/revert.sh
  echo "/usr/bin/cpuinfo.sh -r" >>/tmpRoot/usr/rr/revert.sh
  echo "rm -f /usr/bin/cpuinfo.sh" >>/tmpRoot/usr/rr/revert.sh

  # synoscgiproxy
  rm -f /tmpRoot/usr/sbin/synoscgiproxy

  # for FILE in "/tmpRoot/etc/nginx/nginx.conf" "/tmpRoot/usr/syno/share/nginx/nginx.mustache"; do
  #   [ -f "${FILE}.bak" ] && mv -f "${FILE}.bak" "${FILE}"
  # done
  #
  # rm -f "/tmpRoot/usr/lib/systemd/system/multi-user.target.wants/synoscgiproxy.service"
  # rm -f "/tmpRoot/usr/lib/systemd/system/synoscgiproxy.service"
  #
fi
