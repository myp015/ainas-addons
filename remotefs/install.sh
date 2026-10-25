#!/usr/bin/env sh
#
# Copyright (C) 2022 Ing <https://github.com/wjz304>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

# libsynosdk 的 soname 主版本跟随 DSM 大版本：6.2 是 libsynosdk.so.6，7.x 是 .so.7。
# 写死 .so.7 会让 6.2 上必然打印 "libsynosdk.so.7 not found" 且补丁完全没打上。
MajorVersion="$(/bin/get_key_value /etc.defaults/VERSION majorversion 2>/dev/null)"
# 兜底：与其它 8 个 addon 的版本判定保持一致。实测 6.2（rd.gz）与 7.2.1（rd.gz）的 ramdisk
# 都带 /etc.defaults/VERSION（majorversion 分别为 6 / 7），第一行即可命中；这行只是
# 万一某个 ramdisk 缺该文件时的手册兜底，避免本 addon 在整个 DSM 版本上 fail-fast 退出。
[ -n "${MajorVersion}" ] || MajorVersion="$(/bin/get_key_value /etc/VERSION majorversion 2>/dev/null)"
case "${MajorVersion}" in
  '' | *[!0-9]*)
    echo " ERROR: cannot determine DSM major version from /etc/defaults/VERSION" >&2
    exit 1
    ;;
esac
SO_FILE="/tmpRoot/usr/lib/libsynosdk.so.${MajorVersion}"

if [ "${1}" = "late" ]; then
  echo "Installing addon remotefs - ${1}"
  mkdir -p "/tmpRoot/usr/rr/addons/"
  cp -pf "${0}" "/tmpRoot/usr/rr/addons/"

  if [ ! -f "${SO_FILE}" ]; then
    echo " ERROR: ${SO_FILE} not found, remote fs patch not applied" >&2
    exit 1
  fi
  echo "Patching $(basename "${SO_FILE}")"
  [ ! -f "${SO_FILE}.bak" ] && cp -pf "${SO_FILE}" "${SO_FILE}.bak"
  # force to support remote fs
  PatchELFSharp "${SO_FILE}" "SYNOFSIsRemoteFS" "B8 00 00 00 00 C3"
elif [ "${1}" = "uninstall" ]; then
  echo "Installing addon remotefs - ${1}"

  [ -f "${SO_FILE}.bak" ] && mv -f "${SO_FILE}.bak" "${SO_FILE}"
fi
