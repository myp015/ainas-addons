#!/usr/bin/env sh
#
# Copyright (C) 2022 Ing <https://github.com/wjz304>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

PLATFORMS="apollolake geminilake epyc7002 epyc7003 epyc7003ntb geminilakenk icelaked r1000nk v1000nk"
PLATFORM="$(/bin/get_key_value /etc.defaults/synoinfo.conf unique | cut -d"_" -f2)"
if ! echo "${PLATFORMS}" | grep -qE "(^|[[:space:]])${PLATFORM}([[:space:]]|$)"; then
  echo "${PLATFORM} is not supported console addon!"
  exit 0
fi

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

# DSM 6.x 用 6.2 载荷：kbd 旧版二进制不依赖 libbsd/libmd
#（6.x 的 glibc 2.20 下 7.1 载荷的 loadkeys/setleds/chvt 会因找不到 libbsd.so.0 而无法运行）。
if [ "${MajorVersion}" -lt 7 ]; then
  _console_pkg="/addons/console-6.2.tgz"
  _console_ver="6.2"
else
  _console_pkg="/addons/console-7.1.tgz"
  _console_ver="7.1"
fi
[ -f "${_console_pkg}" ] || {
  echo " ERROR: ${_console_pkg} not found (needed for kernel ${_release})" >&2
  exit 1
}

if [ "${1}" = "early" ]; then
  echo "Installing addon console - ${1} (${_console_ver})"
  tar -zxf "${_console_pkg}" -C /usr/

elif [ "${1}" = "modules" ]; then
  echo "Installing addon console - ${1}"
  if [ -n "${2}" ]; then
    /usr/sbin/modprobe ${2}
  else
    for M in i915 efifb vesafb vga16fb; do
      [ -e /sys/class/graphics/fb0 ] && break
      /usr/sbin/modprobe ${M}
    done
  fi
  /usr/sbin/modprobe fb
  /usr/sbin/modprobe fbcon
  echo "RR console - wait..." >/dev/tty1
  # Workaround for DVA1622
  if [ "${MODEL}" = "DVA1622" ]; then
    echo >/dev/tty2
    /usr/bin/ioctl /dev/tty0 22022 -v 2
    /usr/bin/ioctl /dev/tty0 22022 -v 1
  fi
elif [ "${1}" = "rcExit" ]; then
  # echo "Installing addon console - ${1}"
  # Run only in junior mode (DSM not installed)
  printf "Junior mode\n" >/etc/issue
  echo "Starting getty..."
  /usr/sbin/getty -L 0 tty1 &
  /usr/bin/loadkeys /usr/share/keymaps/i386/${LAYOUT:-qwerty}/${KEYMAP:-us}.map.gz
  # Workaround for DVA1622
  if [ "${MODEL}" = "DVA1622" ]; then
    echo >/dev/tty2
    /usr/bin/ioctl /dev/tty0 22022 -v 2
    /usr/bin/ioctl /dev/tty0 22022 -v 1
  fi
elif [ "${1}" = "late" ]; then
  echo "Installing addon console - ${1} (${_console_ver})"
  mkdir -p "/tmpRoot/usr/rr/addons/"
  cp -pf "${0}" "/tmpRoot/usr/rr/addons/"

  tar -zxf "${_console_pkg}" -C /tmpRoot/usr/
  # run when boot installed DSM
  printf "DSM mode\n" >/tmpRoot/etc/issue

  if [ "${MajorVersion}" -lt 7 ]; then
    # DSM 6.x 自己就有 tty1 getty（/usr/share/init/tty.conf: exec /sbin/getty 115200 console），
    # 且没有 systemd；这里只补键盘映射（upstart 任务，start on runlevel 1）。
    mkdir -p /tmpRoot/usr/share/init
    {
      echo 'description "RR console keymap"'
      echo 'start on runlevel 1'
      echo 'task'
      echo 'console none'
      echo 'env PATH=/sbin:/bin:/usr/sbin:/usr/bin'
      echo "exec /usr/bin/loadkeys -C /dev/tty1 /usr/share/keymaps/i386/${LAYOUT:-qwerty}/${KEYMAP:-us}.map.gz"
    } >/tmpRoot/usr/share/init/rr-keymap.conf
  else
    cp -vpf /tmpRoot/usr/lib/systemd/system/serial-getty\@.service /tmpRoot/usr/lib/systemd/system/getty\@tty1.service
    sed -i 's|^ExecStart=.*|ExecStart=-/sbin/agetty %I 115200 linux|' /tmpRoot/usr/lib/systemd/system/getty\@tty1.service
    mkdir -p /tmpRoot/usr/lib/systemd/system/getty.target.wants
    ln -sf /usr/lib/systemd/system/getty\@tty1.service /tmpRoot/usr/lib/systemd/system/getty.target.wants/getty\@tty1.service

    mkdir -p "/tmpRoot/usr/lib/systemd/system"
    DEST="/tmpRoot/usr/lib/systemd/system/keymap.service"
    {
      echo "[Unit]"
      echo "Description=RR addon console daemon"
      echo "After=getty.target"
      echo
      echo "[Service]"
      echo "Type=oneshot"
      echo "RemainAfterExit=yes"
      echo "ExecStart=-/usr/bin/loadkeys /usr/share/keymaps/i386/${LAYOUT:-qwerty}/${KEYMAP:-us}.map.gz"
      echo
      echo "[Install]"
      echo "WantedBy=multi-user.target"
    } >"${DEST}"

    mkdir -p /tmpRoot/usr/lib/systemd/system/multi-user.target.wants
    ln -sf /usr/lib/systemd/system/keymap.service /tmpRoot/usr/lib/systemd/system/multi-user.target.wants/keymap.service
  fi

  # Workaround for DVA1622
  if [ "${MODEL}" = "DVA1622" ]; then
    echo >/dev/tty2
    /usr/bin/ioctl /dev/tty0 22022 -v 2
    /usr/bin/ioctl /dev/tty0 22022 -v 1
  fi
elif [ "${1}" = "uninstall" ]; then
  echo "Installing addon console - ${1}"

  rm -f "/tmpRoot/usr/lib/systemd/system/getty.target.wants/getty\@tty1.service"
  # rm -f "/tmpRoot/usr/lib/systemd/system/getty\@.service"  # Do not remove, used by misc addons
  rm -f "/tmpRoot/usr/lib/systemd/system/multi-user.target.wants/keymap.service"
  rm -f "/tmpRoot/usr/lib/systemd/system/keymap.service"
  rm -f "/tmpRoot/usr/share/init/rr-keymap.conf"

  rm -rf /tmpRoot/usr/share/consolefonts
  rm -rf /tmpRoot/usr/share/keymaps
  rm -f /tmpRoot/usr/bin/chvt
  rm -f /tmpRoot/usr/bin/deallocvt
  rm -f /tmpRoot/usr/bin/loadkeys
  rm -f /tmpRoot/usr/bin/setleds
  rm -f /tmpRoot/usr/bin/ioctl
fi
