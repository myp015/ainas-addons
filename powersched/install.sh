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

# 7.1 载荷的 powersched 需要 GLIBCXX_3.4.21（gcc 5+），DSM 6.x 的 libstdc++ 只到 6.0.20（3.4.20），
# 故 6.x 用 x64-6.2.4 交叉编译的版本（由 addons-update.yml 产出）。
if [ "${MajorVersion}" -lt 7 ]; then
  _powersched_bin="/usr/sbin/powersched-6.2"
else
  _powersched_bin="/usr/sbin/powersched"
fi

if [ "${1}" = "late" ]; then
  echo "Installing addon powersched - ${1}"
  mkdir -p "/tmpRoot/usr/rr/addons/"
  cp -pf "${0}" "/tmpRoot/usr/rr/addons/"

  [ -f "${_powersched_bin}" ] || {
    echo " ERROR: ${_powersched_bin} not found (needed for kernel ${_release})" >&2
    exit 1
  }
  cp -vpf "${_powersched_bin}" /tmpRoot/usr/sbin/powersched

  [ ! -f "/tmpRoot/etc/crontab.bak" ] && [ -f "/tmpRoot/etc/crontab" ] && cp -pf "/tmpRoot/etc/crontab" "/tmpRoot/etc/crontab.bak"
  sed -i '/\/usr\/sbin\/powersched/d' /tmpRoot/etc/crontab 2>/dev/null
  echo "*       *       *       *       *       root    /usr/sbin/powersched" >>/tmpRoot/etc/crontab

elif [ "${1}" = "uninstall" ]; then
  echo "Installing addon powersched - ${1}"

  rm -f /tmpRoot/usr/sbin/powersched
  [ -f "/tmpRoot/etc/crontab.bak" ] && mv -f "/tmpRoot/etc/crontab.bak" "/tmpRoot/etc/crontab"
  sed -i '/\/usr\/sbin\/powersched/d' /tmpRoot/etc/crontab 2>/dev/null
fi
