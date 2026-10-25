#!/usr/bin/env bash
#
# Copyright (C) 2022 Ing <https://github.com/wjz304>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

RR_PATH="/tmp/initrd"

function mountLoaderDisk() {
  if [ ! -f "/usr/rr/.mountloader" ]; then
    while true; do
      if [ ! -b /dev/synoboot ] || [ ! -b /dev/synoboot1 ] || [ ! -b /dev/synoboot2 ] || [ ! -b /dev/synoboot3 ]; then
        echo "Loader disk not found!"
        break
      fi

      # Mount partitions
      modprobe -q vfat
      modprobe -q ext2
      modprobe -q ext4
      echo 1 | ${RR_SUDO} tee /proc/sys/kernel/syno_install_flag >/dev/null

      # Check partitions and ignore errors
      [ -f "/sbin/fsck.vfat" ] && ${RR_SUDO} fsck.vfat -aw "/dev/synoboot1" >/dev/null 2>&1 || true
      [ -f "/sbin/fsck.ext2" ] && ${RR_SUDO} fsck.ext2 -p "/dev/synoboot2" >/dev/null 2>&1 || true
      [ -f "/sbin/fsck.ext4" ] && ${RR_SUDO} fsck.ext4 -p "/dev/synoboot3" >/dev/null 2>&1 || true

      # Make folders to mount partitions
      for i in {1..3}; do
        ${RR_SUDO} rm -rf "/mnt/p${i}"
        ${RR_SUDO} mkdir -p "/mnt/p${i}"
        ${RR_SUDO} mount | grep -q "/dev/synoboot${i}" && ${RR_SUDO} umount "/dev/synoboot${i}" || true
        ${RR_SUDO} mount "/dev/synoboot${i}" "/mnt/p${i}" || {
          echo "Can't mount /dev/synoboot${i}."
          for j in {1..3}; do
            ${RR_SUDO} umount "/mnt/p${j}" 2>/dev/null || true
            ${RR_SUDO} rm -rf "/mnt/p${j}" 2>/dev/null || true
          done
          break 2
        }
      done

      if echo "$@" | grep -qE "(^|[[:space:]])\-all([[:space:]]|$)"; then
        INITRD_TOOLPATH="/usr/mountloader"
        RR_RAMDISK_FILE="/mnt/p3/initrd-rr"
        if [ -d "${INITRD_TOOLPATH}" ] && [ -f "${RR_RAMDISK_FILE}" ]; then
          ${RR_SUDO} rm -rf "${RR_PATH}"
          ${RR_SUDO} mkdir -p "${RR_PATH}"

          PATH=${INITRD_TOOLPATH}/bin:$PATH
          LD_LIBRARY_PATH=${INITRD_TOOLPATH}/lib:$LD_LIBRARY_PATH
          INITRD_FORMAT=$(file -b --mime-type "${RR_RAMDISK_FILE}")
          case "${INITRD_FORMAT}" in
            *'x-cpio'*) ${RR_SUDO} sh -c "cd ${RR_PATH} && cpio -idm <${RR_RAMDISK_FILE} >/dev/null 2>&1" || true ;;
            *'x-xz'*) ${RR_SUDO} sh -c "cd ${RR_PATH} && xz -dc ${RR_RAMDISK_FILE} | cpio -idm >/dev/null 2>&1" || true ;;
            *'x-lz4'*) ${RR_SUDO} sh -c "cd ${RR_PATH} && lz4 -dc ${RR_RAMDISK_FILE} | cpio -idm >/dev/null 2>&1" || true ;;
            *'x-lzma'*) ${RR_SUDO} sh -c "cd ${RR_PATH} && lzma -dc ${RR_RAMDISK_FILE} | cpio -idm >/dev/null 2>&1" || true ;;
            *'x-bzip2'*) ${RR_SUDO} sh -c "cd ${RR_PATH} && bzip2 -dc ${RR_RAMDISK_FILE} | cpio -idm >/dev/null 2>&1" || true ;;
            *'gzip'*) ${RR_SUDO} sh -c "cd ${RR_PATH} && gzip -dc ${RR_RAMDISK_FILE} | cpio -idm >/dev/null 2>&1" || true ;;
            *'zstd'*) ${RR_SUDO} sh -c "cd ${RR_PATH} && zstd -dc ${RR_RAMDISK_FILE} | cpio -idm >/dev/null 2>&1" || true ;;
            *) ;;
          esac
          if [ ! -f "${RR_PATH}/opt/rr/menu.sh" ]; then
            echo "RR initrd work path not found!"
            rm -rf "${RR_PATH}"
            for j in {1..3}; do
              ${RR_SUDO} umount "/mnt/p${j}" 2>/dev/null || true
              ${RR_SUDO} rm -rf "/mnt/p${j}" 2>/dev/null || true
            done
            break
          fi
        else
          echo "RR initrd not found!"
          for j in {1..3}; do
            ${RR_SUDO} umount "/mnt/p${j}" 2>/dev/null || true
            ${RR_SUDO} rm -rf "/mnt/p${j}" 2>/dev/null || true
          done
          break
        fi
      fi
      ${RR_SUDO} mkdir -p /usr/rr
      {
        echo 'export LOADER_DISK="/dev/synoboot"'
        echo 'export LOADER_DISK_PART1="/dev/synoboot1"'
        echo 'export LOADER_DISK_PART2="/dev/synoboot2"'
        echo 'export LOADER_DISK_PART3="/dev/synoboot3"'
        if [ ! -f "${RR_PATH}/opt/rr/menu.sh" ]; then
          echo "export WORK_PATH=\"${RR_PATH}/opt/rr\""
        fi
      } | ${RR_SUDO} tee "/usr/rr/.mountloader" >/dev/null
      ${RR_SUDO} chmod a+x "/usr/rr/.mountloader"

      sync

      break
    done
  fi
  if [ ! -f "/usr/rr/.mountloader" ]; then
    echo "Loader disk mount failed!"
    return 1
  else
    ${RR_SUDO} "/usr/rr/.mountloader"
    echo "Loader disk mount success!"
    return 0
  fi
}

function unmountLoaderDisk() {
  if [ -f "/usr/rr/.mountloader" ]; then
    {
      echo 'export LOADER_DISK=""'
      echo 'export LOADER_DISK_PART1=""'
      echo 'export LOADER_DISK_PART2=""'
      echo 'export LOADER_DISK_PART3=""'
      if [ -f "${RR_PATH}/opt/rr/menu.sh" ]; then
        ${RR_SUDO} rm -rf "${RR_PATH}" >/dev/null 2>&1 || true
        echo 'export WORK_PATH=""'
      fi
    } | ${RR_SUDO} tee "/usr/rr/.mountloader" >/dev/null
    ${RR_SUDO} chmod a+x "/usr/rr/.mountloader"
    ${RR_SUDO} "/usr/rr/.mountloader"
    ${RR_SUDO} rm -f "/usr/rr/.mountloader"

    sync

    if echo "$@" | grep -qE "(^|[[:space:]])\-all([[:space:]]|$)"; then
      ${RR_SUDO} rm -rf "${RR_PATH}"
    fi
    for j in {1..3}; do
      ${RR_SUDO} umount "/mnt/p${j}" 2>/dev/null || true
      ${RR_SUDO} rm -rf "/mnt/p${j}" 2>/dev/null || true
    done

    echo 0 | ${RR_SUDO} tee /proc/sys/kernel/syno_install_flag >/dev/null
  fi
  echo "Loader disk umount success!"
  return 0
}

[ -z "${1}" ] && {
  echo " Usage: $0 [mountLoaderDisk|unmountLoaderDisk] [-all]"
  exit 1
}

[ -x "/sbin/rrmdo" ] && RR_SUDO="/sbin/rrmdo" || RR_SUDO=""
${RR_SUDO} ls /root >/dev/null 2>&1 || {
  echo "No root permission!"
  exit 1
}

"$@"
