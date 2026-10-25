#!/usr/bin/env sh
#
# Copyright (C) 2022 Ing <https://github.com/wjz304>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

_release="$(/bin/uname -r)"
_kernel_major="${_release%%[-+]*}"
_kernel_major="${_kernel_major%%.*}"
case "${_kernel_major}" in
  '' | *[!0-9]*)
    echo " ERROR: cannot determine kernel major version from '${_release}'" >&2
    exit 1
    ;;
esac

# 7.1 载荷的 powersched 需要 GLIBCXX_3.4.21（gcc 5+），DSM 6.x 的 libstdc++ 只到 6.0.20（3.4.20），
# 故 6.x 用 x64-6.2.4 交叉编译的版本（由 addons-update.yml 产出）。
if [ "${_kernel_major}" -lt 5 ]; then
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
