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

# DSM 6.x（内核 4.x/3.x）没有 systemd，且二进制布局不同（/usr 前缀、eudev 旧版、无 /usr/lib/modules/update），
# 因此按内核主版本选包：6.x 用 eudev-6.2.tgz（与 RR 24.4.0 同源），7.x 用 eudev-7.1.tgz。
# 两者解包路径互不重叠（6.x 在 /usr/*，7.x 在 /bin、/lib），不会互相污染。
if [ "${_kernel_major}" -lt 5 ]; then
  _eudev_pkg="/addons/eudev-6.2.tgz"
  _eudev_ver="6.2"
else
  _eudev_pkg="/addons/eudev-7.1.tgz"
  _eudev_ver="7.1"
fi
[ -f "${_eudev_pkg}" ] || {
  echo " ERROR: ${_eudev_pkg} not found (needed for kernel ${_release})" >&2
  exit 1
}

if [ "${1}" = "early" ]; then
  echo "Installing addon eudev - ${1} (${_eudev_ver})"
  tar -zxf "${_eudev_pkg}" -C /
  # 6.2 上不建 modprobe/modinfo 软链：ramdisk 里 /usr/sbin/modprobe 由 redpill addon 的
  # iosched-trampoline 接管，覆盖它会破坏 rp.ko 的按需加载（RR 24.4.0 同样不建）。
  if [ "${_kernel_major}" -ge 5 ]; then
    [ -L "/usr/sbin/modprobe" ] || ln -vsf /usr/bin/kmod /usr/sbin/modprobe
    [ -L "/usr/sbin/modinfo" ] || ln -vsf /usr/bin/kmod /usr/sbin/modinfo
    [ -L "/usr/sbin/depmod" ] || ln -vsf /usr/bin/kmod /usr/sbin/depmod
  fi
  exit 0

elif [ "${1}" = "modules" ]; then
  echo "Installing addon eudev - ${1} (${_eudev_ver})"

  # 以下整段只对 7.x 有意义：/usr/lib/modules/update 双 DRM 栈是 RR 7.x 的产物，
  # 6.x 的 modules 平铺在 /usr/lib/modules 下、没有 update 目录。加 guard 免得误删。
  if [ "${_kernel_major}" -ge 5 ]; then
    # 双 DRM 栈（i915 + amdgpu/radeon 共用同一套 drm/ttm/gpu-sched）：
    # 原逻辑只认 i915，没有 Intel 核显（AMD 平台）或 base i915 支持当前 GPU 时
    # 会 rm -rf update，把 amdgpu/radeon 一起删掉；且 base 与 update 的 drm 版本
    # 不同，只保留其一才安全（混栈 ABI 断裂）。检测到 amd 模块即整栈平铺。
    if [ -f "/usr/lib/modules/update/amdgpu.ko" ] || [ -f "/usr/lib/modules/update/radeon.ko" ]; then
      echo "update stack contains amdgpu/radeon; keep full DRM stack"
      mv -vf /usr/lib/modules/update/* /usr/lib/modules/ 2>/dev/null || true
    elif [ -f "/usr/lib/modules/update/i915.ko" ] && lspci -nd ::300 2>/dev/null | grep -Eq '8086:[0-9a-fA-F]{4}'; then
      GPU="$(lspci -nd ::300 2>/dev/null | grep -Eo '8086:[0-9a-fA-F]{4}' | head -n1 | sed 's/://')"
      PCI="pci:v0000$(echo "${GPU:-}" | cut -c1-4)d0000$(echo "${GPU:-}" | cut -c5-8)"
      if modinfo -F alias "/usr/lib/modules/i915.ko" 2>/dev/null | grep -iq "${PCI}"; then
        echo "base i915.ko supports ${GPU}"
        rm -rf /usr/lib/modules/update 2>/dev/null || true
      else
        if modinfo -F alias "/usr/lib/modules/update/i915.ko" 2>/dev/null | grep -iq "${PCI}"; then
          echo "update i915.ko supports ${GPU}"
          mv -vf /usr/lib/modules/update/* /usr/lib/modules/ 2>/dev/null
        else
          echo "No i915.ko supports ${GPU}"
          rm -rf /usr/lib/modules/update 2>/dev/null || true
        fi
      fi
    else
      rm -rf /usr/lib/modules/update 2>/dev/null || true
    fi
  fi

  # mv -f /usr/lib/udev/rules.d/60-persistent-storage.rules /usr/lib/udev/rules.d/60-persistent-storage.rules.bak
  # mv -f /usr/lib/udev/rules.d/60-persistent-storage-tape.rules /usr/lib/udev/rules.d/60-persistent-storage-tape.rules.bak
  # mv -f /usr/lib/udev/rules.d/75-persistent-net-generator.rules /usr/lib/udev/rules.d/75-persistent-net-generator.rules.bak
  ## mv -f /usr/lib/udev/rules.d/80-net-name-slot.rules /usr/lib/udev/rules.d/80-net-name-slot.rules.bak
  [ -e /proc/sys/kernel/hotplug ] && printf '\000\000\000\000' >/proc/sys/kernel/hotplug
  /usr/sbin/depmod -a
  # 以下三处预加载是 7.x 内核的依赖补齐：4.4/3.10 内核里 cpufreq_governor_dbs 是内置的，
  # 且没有 devlink / intel_auxiliary 模块，6.x 上调用只会经 iosched-trampoline 报错噪音。
  if [ "${_kernel_major}" -ge 5 ]; then
    # early 阶段直接 insmod 列表模块、不做 modules.dep 依赖解析（SYNOLoadModules），
    # 且 devlink / intel_auxiliary 无 modalias alias（udev 也不会自动加载）：
    # i40e→intel_auxiliary、ixgbe→devlink 会在早期加载缺符号失败（err -2）。
    # 这里在 udev trigger 与后续网络模块加载前显式预加载这两个依赖模块。
    /usr/sbin/modprobe intel_auxiliary 2>/dev/null || true
    /usr/sbin/modprobe devlink 2>/dev/null || true
  fi
  # 同类问题：DSM rc（SYNOLoadModules）的 KERNEL_MODULES 列表含 cpufreq_ondemand /
  # cpufreq_conservative，却不含提供者 cpufreq_governor，且按路径 insmod 不做依赖解析。
  # apollolake / denverton / geminilake 的官方内核未导出 gov_queue_work / cpufreq_governor_dbs /
  # dbs_check_cpu（其余平台内核内置），故这两个 .ko 会 unknown symbol 加载失败（DSM rc 在
  # jrExit 之后、rcExit 之前执行）。内核未提供这些符号时预加载提供者，使 DSM rc 的 insmod
  # 得以解析；内核已内置则跳过（否则重复导出符号同样会加载失败）。
  if [ "${_kernel_major}" -ge 5 ] && [ -r /proc/kallsyms ] && ! grep -qw cpufreq_governor_dbs /proc/kallsyms; then
    /usr/sbin/modprobe cpufreq_governor 2>/dev/null || true
  fi
  /usr/sbin/udevd -d || {
    echo "FAIL"
    exit 1
  }
  echo "Triggering add events to udev"
  udevadm trigger --type=subsystems --action=add
  udevadm trigger --type=devices --action=add
  udevadm trigger --type=devices --action=change
  udevadm settle --timeout=30 || echo "udevadm settle failed"
  # Give more time
  sleep 10
  # Remove from memory to not conflict with RAID mount scripts
  /usr/bin/killall udevd
  # modprobe modules for the beep
  /usr/sbin/modprobe pcspeaker || true
  /usr/sbin/modprobe pcspkr || true
  # modprobe modules for the sensors
  for I in coretemp k10temp hwmon-vid it87 nct6683 nct6775 adt7470 adt7475 adm1021 adm1031 adm9240 lm75 lm78 lm90; do
    /usr/sbin/modprobe "${I}" || true
  done
  # modprobe modules for the virtiofs
  /usr/sbin/modprobe 9p || true
  /usr/sbin/modprobe virtiofs || true

  for P in tcp sch; do
    for F in $(LC_ALL=C printf '%s\n' /usr/lib/modules/${P}_*.ko | sort -V); do
      [ ! -e "${F}" ] && continue
      /usr/sbin/modprobe "$(basename "${F}" .ko 2>/dev/null)" || true
    done
  done

  # Remove kvm module
  /usr/sbin/lsmod 2>/dev/null | grep -q ^kvm_intel && /usr/sbin/modprobe -r kvm_intel || true # kvm-intel.ko
  /usr/sbin/lsmod 2>/dev/null | grep -q ^kvm_amd && /usr/sbin/modprobe -r kvm_amd || true     # kvm-amd.ko

elif [ "${1}" = "late" ]; then
  echo "Installing addon eudev - ${1} (${_eudev_ver})"
  if [ "${_kernel_major}" -ge 5 ]; then
    # [ ! -L "/tmpRoot/usr/sbin/modprobe" ] && ln -vsf /usr/bin/kmod /tmpRoot/usr/sbin/modprobe
    [ ! -L "/tmpRoot/usr/sbin/modinfo" ] && ln -vsf /usr/bin/kmod /tmpRoot/usr/sbin/modinfo
    [ ! -L "/tmpRoot/usr/sbin/depmod" ] && ln -vsf /usr/bin/kmod /tmpRoot/usr/sbin/depmod

    [ ! -f "/tmpRoot/usr/bin/eject" ] && cp -vpf /usr/bin/eject /tmpRoot/usr/bin/eject
  fi

  echo "copy modules"
  export LD_LIBRARY_PATH=/tmpRoot/bin:/tmpRoot/lib
  isChange=false
  /tmpRoot/bin/cp -rnf /usr/lib/firmware/* /tmpRoot/usr/lib/firmware/
  /tmpRoot/bin/rm -rf /tmpRoot/usr/lib/firmware/iwlwifi*.pnvm 2>/dev/null || true # for <= v25.9.7 to avoid firmware crash
  if grep -q 'RR@RR' /proc/version 2>/dev/null ; then
    if [ -d /tmpRoot/usr/lib/modules.bak ]; then
      /tmpRoot/bin/rm -rf /tmpRoot/usr/lib/modules
      /tmpRoot/bin/cp -rpf /tmpRoot/usr/lib/modules.bak /tmpRoot/usr/lib/modules
    else
      echo "RR@RR, backup modules."
      /tmpRoot/bin/cp -rpf /tmpRoot/usr/lib/modules /tmpRoot/usr/lib/modules.bak
    fi
    /tmpRoot/bin/cp -rpf /usr/lib/modules/* /tmpRoot/usr/lib/modules
    isChange=true
  else
    if [ -d /tmpRoot/usr/lib/modules.bak ]; then
      echo "RR@RR, restore modules from backup."
      /tmpRoot/bin/rm -rf /tmpRoot/usr/lib/modules
      /tmpRoot/bin/mv -vf /tmpRoot/usr/lib/modules.bak /tmpRoot/usr/lib/modules
    fi
    for L in $(grep -v '^\s*$\|^\s*#' /addons/modulelist 2>/dev/null | awk '{if (NF == 2) print $1"###"$2}'); do
      O=$(echo "${L}" | awk -F'###' '{print $1}')
      M=$(echo "${L}" | awk -F'###' '{print $2}')
      [ -z "${M}" ] || [ ! -f "/usr/lib/modules/${M}" ] && continue
      if [ "$(echo "${O}" | cut -c1 | sed 's/.*/\U&/')" = "F" ]; then
        /tmpRoot/bin/cp -vrf /usr/lib/modules/${M} /tmpRoot/usr/lib/modules/
      else
        /tmpRoot/bin/cp -vrn /usr/lib/modules/${M} /tmpRoot/usr/lib/modules/
      fi
      isChange=true
    done
  fi
  echo "isChange: ${isChange}"
  [ "${isChange}" = "true" ] && /usr/sbin/depmod -a -b /tmpRoot

  # Restore kvm module
  /usr/sbin/modprobe kvm_intel || true # kvm-intel.ko
  /usr/sbin/modprobe kvm_amd || true   # kvm-amd.ko

  echo "Copy rules"
  mkdir -p /tmpRoot/usr/lib/udev
  /tmpRoot/bin/cp -vrf /usr/lib/udev/* /tmpRoot/usr/lib/udev/

  # 重载规则：7.x 用 systemd oneshot unit，6.x 没有 systemd，用 upstart 的 /etc/init/*.conf
  # （与 RR 24.4.0 的 eudev addon 一致；6.2 的 /sbin/init 是 upstart）。
  if [ "${_kernel_major}" -lt 5 ]; then
    mkdir -p /tmpRoot/etc/init
    DEST=/tmpRoot/etc/init/eudev.conf
    echo 'description "EUDEV daemon"'                   >"${DEST}"
    echo 'start on runlevel 1'                          >>"${DEST}"
    echo 'stop on runlevel [06]'                        >>"${DEST}"
    echo 'expect fork'                                  >>"${DEST}"
    echo 'respawn'                                      >>"${DEST}"
    echo 'respawn limit 5 10'                           >>"${DEST}"
    echo 'console log'                                  >>"${DEST}"
    echo 'exec /usr/bin/udevadm hwdb --update'          >>"${DEST}"
    echo 'exec /usr/bin/udevadm control --reload-rules' >>"${DEST}"
  else
    mkdir -p "/tmpRoot/usr/lib/systemd/system"
    DEST="/tmpRoot/usr/lib/systemd/system/udevrules.service"
    {
      echo "[Unit]"
      echo "Description=RR addon udev daemon"
      echo
      echo "[Service]"
      echo "Type=oneshot"
      echo "RemainAfterExit=yes"
      echo "ExecStart=/usr/bin/udevadm hwdb --update"
      echo "ExecStart=/usr/bin/udevadm control --reload-rules"
      echo
      echo "[Install]"
      echo "WantedBy=multi-user.target"
    } >"${DEST}"

    mkdir -vp /tmpRoot/usr/lib/systemd/system/multi-user.target.wants
    ln -vsf /usr/lib/systemd/system/udevrules.service /tmpRoot/usr/lib/systemd/system/multi-user.target.wants/udevrules.service
  fi
fi
