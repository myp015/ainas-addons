#!/usr/bin/env sh
#
# Copyright (C) 2022 Ing <https://github.com/wjz304>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

if [ "${1}" = "late" ]; then
  echo "Installing addon addincards - ${1}"
  mkdir -p "/tmpRoot/usr/rr/addons/"
  cp -pf "${0}" "/tmpRoot/usr/rr/addons/"

  MODEL="$(cat /proc/sys/kernel/syno_hw_version)"
  FILE="/tmpRoot/usr/syno/etc/adapter_cards.conf"
  # POSIX-compliant way to replace /etc/ with /etc.defaults/ in the path
  FILE_DEFAULTS="/tmpRoot/usr/syno/etc.defaults/adapter_cards.conf"
  # DSM 6.2 只有 etc.defaults 下这一份（7.x 才在 etc/ 下留运行时副本），此时直接改
  # etc.defaults，6.2 首次启动会用它初始化 etc/。两份都没有则报错退出，不要空转。
  [ -f "${FILE}" ] || FILE="${FILE_DEFAULTS}"
  if [ ! -f "${FILE}" ]; then
    echo " ERROR: adapter_cards.conf not found in etc or etc.defaults" >&2
    exit 1
  fi

  [ ! -f "${FILE}.bak" ] && cp -pf "${FILE}" "${FILE}.bak"
  cp -pf "${FILE}" "${FILE}.tmp"
  : >"${FILE}"
  for N in $(grep '\[' "${FILE}.tmp" 2>/dev/null); do
    echo "${N}" >>"${FILE}"
    echo "${MODEL}=yes" >>"${FILE}"
  done
  rm -f "${FILE}.tmp"
  [ "${FILE}" = "${FILE_DEFAULTS}" ] || cp -pf "${FILE}" "${FILE_DEFAULTS}"

elif [ "${1}" = "uninstall" ]; then
  echo "Installing addon addincards - ${1}"

  FILE="/tmpRoot/usr/syno/etc/adapter_cards.conf"
  # POSIX-compliant way to replace /etc/ with /etc.defaults/ in the path
  FILE_DEFAULTS="/tmpRoot/usr/syno/etc.defaults/adapter_cards.conf"
  [ -f "${FILE}" ] || FILE="${FILE_DEFAULTS}"
  [ -f "${FILE}.bak" ] && mv -f "${FILE}.bak" "${FILE}"
  [ "${FILE}" = "${FILE_DEFAULTS}" ] || cp -pf "${FILE}" "${FILE_DEFAULTS}"
fi
