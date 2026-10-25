#!/usr/bin/env sh
#
# Copyright (C) 2022 Ing <https://github.com/wjz304>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

getlog() {
  if [ -z "${1}" ]; then
    echo "Usage: ${0} {early|jrExit|rcExit|late|dsm}"
    exit 1
  fi

  # 6.2 的 ramdisk 里没有 /sbin/blkid（也没有 /usr/sbin/blkid），写死绝对路径只会静默失败；
  # 走 PATH 才能在 misc 的 6.2 载荷（/usr/sbin/blkid）就位后被找到。找不到就退到 synoboot1。
  LOADER_DISK_PART1="$(blkid -L RR1 2>/dev/null)"
  if [ ! -b "${LOADER_DISK_PART1}" ] && [ -b "/dev/synoboot1" ]; then
    LOADER_DISK_PART1="/dev/synoboot1"
  fi
  if [ ! -b "${LOADER_DISK_PART1}" ]; then
    echo "Boot disk not found"
    exit 1
  fi

  # DSM 6.2 的 ramdisk 没有 modules.dep（eudev 的 depmod 要到 modules 阶段才跑），kmod 的
  # modprobe 解析不了 fat -> vfat 依赖、静默失败；更早的时候 /usr/sbin/modprobe 还可能是
  # redpill 的 iosched-trampoline（只认 elevator-iosched，其余参数直接丢）。vfat 因此没被
  # 注册，busybox 的 mount 把 "文件系统类型未注册" 报成 ENODEV：
  #   mount: mounting /dev/synoboot1 on /mnt/p1 failed: No such device
  # ramdisk 自带未压缩 .ko（6.2 的模块布局）时按依赖顺序直接 insmod，绕开 modprobe。
  if ! grep -q vfat /proc/filesystems 2>/dev/null && [ -f "/usr/lib/modules/vfat.ko" ]; then
    insmod "/usr/lib/modules/fat.ko" 2>/dev/null || true
    insmod "/usr/lib/modules/vfat.ko" 2>/dev/null || true
  fi
  modprobe -q vfat
  # 挂不上 loader 分区就没法留日志，继续跑只会得到一条误导性的 ENODEV，直接失败退出。
  if ! grep -q vfat /proc/filesystems 2>/dev/null; then
    echo " ERROR: vfat is not loaded, cannot mount ${LOADER_DISK_PART1}" >&2
    exit 1
  fi
  # 群晖内核自带"引导盘挂载保护"，这是 6.2/7.x 都挂不上 /dev/synoboot1 的**真正原因**（不是缺
  # nls codepage —— 实测 fat/vfat 已注册、内核 nls 表也能加载）：
  #   drivers 之外的 fs/namespace.c:3000  do_mount()
  #     extern int gSynoInstallFlag;
  #     if (0 == gSynoInstallFlag && gSynoHasDynModule &&
  #         strstr(dev_name, CONFIG_SYNO_USB_FLASH_DEVICE_PATH))   // "/dev/synoboot"
  #         return -EINVAL;
  # 即：只要 dev_name 里含 "/dev/synoboot"，而 gSynoInstallFlag==0，do_mount 直接返回 EINVAL。
  # busybox 的 mount 在不带 -t 时会逐个试 /proc/filesystems 里的类型，把 EINVAL 统一报成
  # "No such device"(ENODEV)，于是日志里那条 ENODEV 极具误导性。
  # 6.2 上除 nextkvmx64 外没有任何人会设这个 flag（见 ramdisk 的 linuxrc.syno / init.post），
  # 所以必须由本 addon 自己开、用完复位。**这两行不能删**，删了 6.2/7.x 全部挂不上。
  echo 1 >/proc/sys/kernel/syno_install_flag 2>/dev/null
  [ -f "/sbin/fsck.vfat" ] && fsck.vfat -aw "${LOADER_DISK_PART1}" >/dev/null 2>&1 || true

  WORK_PATH="/mnt/p1"
  mkdir -p "${WORK_PATH}"
  mount | grep -q "${LOADER_DISK_PART1}" && umount "${LOADER_DISK_PART1}" 2>/dev/null || true
  # 显式 -t vfat：不带 -t 时 busybox 会探测所有类型，任何失败都报成 ENODEV，掩盖真实原因。
  mount -t vfat "${LOADER_DISK_PART1}" "${WORK_PATH}" || {
    echo "Can't mount ${LOADER_DISK_PART1}."
    exit 1
  }

  DEST_PATH="${WORK_PATH}/logs/${1}"
  rm -rf "${DEST_PATH}"
  mkdir -p "${DEST_PATH}"

  dmesg >"${DEST_PATH}/dmesg.log"
  lsmod >"${DEST_PATH}/lsmod.log"
  lspci -nnk >"${DEST_PATH}/lspci.log" || true
  ip addr >"${DEST_PATH}/ip-addr.log" || true

  ls -l /sys/class/net/*/device/driver >"${DEST_PATH}/net-driver.log" || true

  ls -l /sys/class/block >"${DEST_PATH}/disk-block.log" || true
  ls -l /sys/class/scsi_host >"${DEST_PATH}/disk-scsi_host.log" || true
  # 没有匹配设备时 /sys/block/*/device/syno_block_info 通配不展开，cat 会拿字面量去打开并报错；
  # 用循环逐个判存在，避免日志里多出一条与实际无关的 "No such file or directory"。
  for _SBI in /sys/block/*/device/syno_block_info; do
    [ -e "${_SBI}" ] || continue
    cat "${_SBI}"
  done >"${DEST_PATH}/disk-syno_block_info.log" 2>/dev/null || true

  # 目标是 FAT（vfat），不支持保留属主/权限，cp -p 必然打印 "failed to preserve ownership"，
  # 用 -f 即可。
  [ -f "/addons/addons.sh" ] && cp -f "/addons/addons.sh" "${DEST_PATH}/addons.sh" || true
  [ -f "/addons/model.dts" ] && cp -f "/addons/model.dts" "${DEST_PATH}/model.dts" || true

  [ -f "/var/log/messages" ] && cp -f "/var/log/messages" "${DEST_PATH}/messages" || true
  [ -f "/var/log/linuxrc.syno.log" ] && cp -f "/var/log/linuxrc.syno.log" "${DEST_PATH}/linuxrc.syno.log" || true
  [ -f "/tmp/installer_sh.log" ] && cp -f "/tmp/installer_sh.log" "${DEST_PATH}/installer_sh.log" || true

  sync
  umount "${LOADER_DISK_PART1}" 2>/dev/null
  rm -rf "${WORK_PATH}"

  echo 0 >/proc/sys/kernel/syno_install_flag 2>/dev/null
}

if [ "${1}" = "early" ]; then
  echo "Installing addon dbgutils - ${1}"
  getlog "${1}"
elif [ "${1}" = "jrExit" ]; then
  echo "Installing addon dbgutils - ${1}"
  getlog "${1}"
elif [ "${1}" = "rcExit" ]; then
  echo "Installing addon dbgutils - ${1}"
  getlog "${1}"
elif [ "${1}" = "late" ]; then
  echo "Installing addon dbgutils - ${1}"
  getlog "${1}"
fi
