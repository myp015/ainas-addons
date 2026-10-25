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

# 工具包里只有 bin/cpio 需要 glibc 2.26（6.x 是 2.20），其余（file/xz/lz4/zstd/bzip2 及库）全部 ≤ 2.17。
# 6.2 包 = 7.1 包仅替换 bin/cpio 为 x64-6.2.4 交叉编译的版本（由 addons-update.yml 组装）。
if [ "${MajorVersion}" -lt 7 ]; then
  _mountloader_pkg="/addons/mountloader-6.2.tgz"
else
  _mountloader_pkg="/addons/mountloader-7.1.tgz"
fi

if [ "${1}" = "late" ]; then
  echo "Installing addon mountloader - ${1}"
  mkdir -p "/tmpRoot/usr/rr/addons/"
  cp -pf "${0}" "/tmpRoot/usr/rr/addons/"

  [ -f "${_mountloader_pkg}" ] || {
    echo " ERROR: ${_mountloader_pkg} not found (needed for kernel ${_release})" >&2
    exit 1
  }
  mkdir -p /tmpRoot/usr/mountloader
  tar -zxf "${_mountloader_pkg}" -C /tmpRoot/usr/mountloader

  cp -vpf /usr/bin/rr-update.sh /tmpRoot/usr/bin/rr-update.sh
  cp -vpf /usr/bin/rr-loaderdisk.sh /tmpRoot/usr/bin/rr-loaderdisk.sh

  cp -vpf /usr/bin/yq /tmpRoot/usr/bin/yq
  cp -vpf /usr/bin/unzip /tmpRoot/usr/bin/unzip

  cp -vpf /usr/sbin/rrmdo /tmpRoot/sbin/rrmdo
  chown root:root /tmpRoot/sbin/rrmdo
  chmod u+s /tmpRoot/sbin/rrmdo

  [ ! -f /tmpRoot/sbin/fatlabel ] && cp -vpf /usr/sbin/fatlabel /tmpRoot/sbin/fatlabel
  [ ! -f /tmpRoot/sbin/dosfslabel ] && ln -sf fatlabel /tmpRoot/sbin/dosfslabel
  [ ! -f /tmpRoot/sbin/fsck.fat ] && cp -vpf /usr/sbin/fsck.fat /tmpRoot/sbin/fsck.fat
  [ ! -f /tmpRoot/sbin/dosfsck ] && ln -sf fsck.fat /tmpRoot/sbin/dosfsck
  [ ! -f /tmpRoot/sbin/fsck.msdos ] && ln -sf fsck.fat /tmpRoot/sbin/fsck.msdos
  [ ! -f /tmpRoot/sbin/fsck.vfat ] && ln -sf fsck.fat /tmpRoot/sbin/fsck.vfat
  [ ! -f /tmpRoot/sbin/mkfs.fat ] && cp -vpf /usr/sbin/mkfs.fat /tmpRoot/sbin/mkfs.fat
  [ ! -f /tmpRoot/sbin/mkdosfs ] && ln -sf mkfs.fat /tmpRoot/sbin/mkdosfs
  [ ! -f /tmpRoot/sbin/mkfs.msdos ] && ln -sf mkfs.fat /tmpRoot/sbin/mkfs.msdos
  [ ! -f /tmpRoot/sbin/mkfs.vfat ] && ln -sf mkfs.fat /tmpRoot/sbin/mkfs.vfat

  rm -f /tmpRoot/usr/rr/.mountloader

#  export LD_LIBRARY_PATH=/tmpRoot/bin:/tmpRoot/lib
#  ESYNOSCHEDULER_DB="/tmpRoot/usr/syno/etc/esynoscheduler/esynoscheduler.db"
#  if [ ! -f "${ESYNOSCHEDULER_DB}" ] || ! /tmpRoot/bin/sqlite3 "${ESYNOSCHEDULER_DB}" ".tables" | grep -wq "task"; then
#    echo "copy esynoscheduler.db"
#    mkdir -p "$(dirname "${ESYNOSCHEDULER_DB}")"
#    cp -vpf /addons/esynoscheduler.db "${ESYNOSCHEDULER_DB}"
#  fi
#  echo "insert mountloader task to esynoscheduler.db"
#  /tmpRoot/bin/sqlite3 "${ESYNOSCHEDULER_DB}" <<EOF
#DELETE FROM task WHERE task_name LIKE 'MountLoaderDisk';
#INSERT INTO task VALUES('MountLoaderDisk', '', 'bootup', '', 0, 0, 0, 0, '', 0, '/usr/bin/rr-loaderdisk.sh mountLoaderDisk', 'script', '{}', '', '', '{}', '{}');
#DELETE FROM task WHERE task_name LIKE 'UnMountLoaderDisk';
#INSERT INTO task VALUES('UnMountLoaderDisk', '', 'shutdown', '', 0, 0, 0, 0, '', 0, '/usr/bin/rr-loaderdisk.sh unmountLoaderDisk', 'script', '{}', '', '', '{}', '{}');
#EOF
elif [ "${1}" = "uninstall" ]; then
  echo "Installing addon mountloader - ${1}"

  rm -rf "/tmpRoot/usr/mountloader"

  rm -f "/tmpRoot/usr/bin/rr-update.sh"
  rm -f "/tmpRoot/usr/bin/rr-loaderdisk.sh"

  rm -f "/tmpRoot/usr/bin/yq"
  rm -f "/tmpRoot/lib/usr/bin/unzip"

  rm -f "/tmpRoot/sbin/rrmdo"

  #rm -f "/tmpRoot/sbin/fatlabel"
  #rm -f "/tmpRoot/sbin/dosfslabel"
  #rm -f "/tmpRoot/sbin/fsck.fat"
  #rm -f "/tmpRoot/sbin/dosfsck"F
  #rm -f "/tmpRoot/sbin/fsck.msdos"
  #rm -f "/tmpRoot/sbin/fsck.vfat"
  #rm -f "/tmpRoot/sbin/mkfs.fat"
  #rm -f "/tmpRoot/sbin/mkdosfs"
  #rm -f "/tmpRoot/sbin/mkfs.msdos"
  #rm -f "/tmpRoot/sbin/mkfs.vfat"

#  export LD_LIBRARY_PATH=/tmpRoot/bin:/tmpRoot/lib
#  ESYNOSCHEDULER_DB="/tmpRoot/usr/syno/etc/esynoscheduler/esynoscheduler.db"
#  if [ -f "${ESYNOSCHEDULER_DB}" ]; then
#    echo "delete mountloader task from esynoscheduler.db"
#    /tmpRoot/bin/sqlite3 "${ESYNOSCHEDULER_DB}" <<EOF
#DELETE FROM task WHERE task_name LIKE 'MountLoaderDisk';
#DELETE FROM task WHERE task_name LIKE 'UnMountLoaderDisk';
#EOF
#  fi
fi
