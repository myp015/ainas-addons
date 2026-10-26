#!/usr/bin/env sh
#
# Copyright (C) 2022 Ing <https://github.com/wjz304>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

PLATFORM="$(/bin/get_key_value /etc.defaults/synoinfo.conf unique | cut -d"_" -f2)"

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

if [ "${1}" = "early" ]; then
  echo "Installing addon misc - ${1}"

  # DSM 6.x 的 ramdisk 是 busybox 1.16.1，缺 sed/awk/sort/find/readlink/mktemp/blkid/xxd 这些 applet，
  # 而 addon 的 early/patches/modules/late 四个阶段都在这个 ramdisk 里执行 ⇒ 由本载荷补齐。
  # 载荷全部取自 DSM 6.2 自身（GLIBC ≤ 2.17，ramdisk 是 2.20），并带上各自的运行库：
  #   gawk/sqlite3(DSM 根) → libreadline.so.6 + libncursesw.so.5
  #   gawk               → libmpfr.so.4 + libgmp.so.10
  #   sort               → libcrypto.so.1.0.0
  #   blkid              → libblkid.so.1
  # 用 busybox tar 解包，不依赖尚未就位的工具。
  if [ "${MajorVersion}" -lt 7 ]; then
    [ -f /addons/misc-6.2.tgz ] || {
      echo " ERROR: /addons/misc-6.2.tgz not found" >&2
      exit 1
    }
    tar -zxf /addons/misc-6.2.tgz -C / || {
      echo " ERROR: extract /addons/misc-6.2.tgz failed" >&2
      exit 1
    }

    # 本 addon 的 root/usr/bin 来自 rr-misc 的 7.1 spk（x64-7.1 工具链），其中 cp/grep/mv/rm
    # 需要 GLIBC_2.26，而 6.2 ramdisk 只有 glibc 2.20。installAddon 会把 all.tgz 的 root/
    # 无条件拷进 ramdisk 根，于是这四个命令（6.2 上原本是 busybox 的软链接）被整成跑不起来的
    # 7.1 二进制 —— 而 DSM 安装器（scemd → installer.sh）全程依赖它们，任何一步 "GLIBC_2.26
    # not found" 都会让安装流程在最后失败，网页上就变成 error_unknown（安装过程中出现错误…），
    # 但系统其实已经写好了。busybox 自带这四个 applet，恢复成软链接即可。
    for _a in cp grep mv rm; do
      if [ -f "/usr/bin/${_a}" ] && [ ! -h "/usr/bin/${_a}" ]; then
        ln -sf busybox "/usr/bin/${_a}"
      fi
    done
  fi

  # [CREATE][failed] Raidtool initsys（7.x 的 scemd 二进制补丁：-e 0.9 → -e 1.2）
  # 6.x 不做：该问题只出现在 7.x 的 scemd，且这段流水线一旦缺工具（xxd/sed）会把 scemd 截成空文件。
  if [ "${MajorVersion}" -ge 7 ]; then
    SO_FILE="/usr/syno/bin/scemd"
    [ ! -f "${SO_FILE}.bak" ] && cp -pf "${SO_FILE}" "${SO_FILE}.bak"
    cp -pf "${SO_FILE}" "${SO_FILE}.tmp"
    xxd -c "$(xxd -p "${SO_FILE}.tmp" 2>/dev/null | wc -c)" -p "${SO_FILE}.tmp" 2>/dev/null \
      | sed "s/2d6520302e39/2d6520312e32/" \
      | xxd -r -p >"${SO_FILE}" 2>/dev/null
    rm -f "${SO_FILE}.tmp"
  fi

  # 用 case 模式而不是 grep -E 拼变量（变量含正则元字符会被误判；6.2 的 busybox grep 也没有 -w）
  case " epyc7003ntb " in
    *" ${PLATFORM} "*)
      # for epyc7003ntb console error "sh: invalid number 'Read error'"
      sed -i 's/^main "\$@"$/# main "\$@"/' "/usr/syno/sbin/i2c_hb_checker.sh" 2>/dev/null || true
      sed -i -E 's/169\.254\.4\.(1|2)/127.0.0.1/g; s/ --interface ntb_eth[0-9]{1,2}//g; s/check_ntb_connection$/exit 0 # check_ntb_connection/' /usr/syno/share/clusterInstall.sh || true
      ;;
  esac

elif [ "${1}" = "patches" ]; then
  # getty
  for I in $(cat /proc/cmdline 2>/dev/null | grep -Eo 'getty=[^ ]+' | sed 's/getty=//'); do
    TTYN="$(echo "${I}" | cut -d',' -f1)"
    BAUD="$(echo "${I}" | cut -d',' -f2 | cut -d'n' -f1)"
    # 用 case 模式而不是 grep -E 拼变量（变量含正则元字符会被误判；6.2 的 busybox grep 也没有 -w）
    case " ttyS0 ttyS1 ttyS2 " in *" ${TTYN} "*) continue ;; esac
    if [ -n "${TTYN}" ] && [ -e "/dev/${TTYN}" ]; then
      echo "Starting getty on ${TTYN}"
      if [ -n "${BAUD}" ]; then
        /usr/sbin/getty -L "${TTYN}" "${BAUD}" linux &
      else
        /usr/sbin/getty -L "${TTYN}" linux &
      fi
    fi
  done

  # network
  if grep -q 'network.' /proc/cmdline; then
    for I in $(grep -Eo 'network.[0-9a-fA-F:]{12,17}=[^ ]*' /proc/cmdline); do
      MACR="$(echo "${I}" | cut -d. -f2 | cut -d= -f1 | sed 's/://g; s/.*/\L&/')"
      IPRS="$(echo "${I}" | cut -d= -f2)"
      for F in $(LC_ALL=C printf '%s\n' /sys/class/net/eth* | sort -V); do
        [ ! -e "${F}" ] && continue
        ETH="$(basename "${F}")"
        MACX=$(cat "/sys/class/net/${ETH}/address" 2>/dev/null | sed 's/://g; s/.*/\L&/')
        if [ "${MACR}" = "${MACX}" ]; then
          echo "Setting IP for ${ETH} to ${IPRS}"
          F="/etc/sysconfig/network-scripts/ifcfg-${ETH}"
          BRIDGE=$(/bin/get_key_value "${F}" "BRIDGE")
          [ -n "${BRIDGE}" ] && F="/etc/sysconfig/network-scripts/ifcfg-${BRIDGE}"
          /bin/set_key_value "${F}" "BOOTPROTO" "static"
          /bin/set_key_value "${F}" "ONBOOT" "yes"
          /bin/set_key_value "${F}" "IPADDR" "$(echo "${IPRS}" | cut -d/ -f1)"
          /bin/set_key_value "${F}" "NETMASK" "$(echo "${IPRS}" | cut -d/ -f2)"
          /bin/set_key_value "${F}" "GATEWAY" "$(echo "${IPRS}" | cut -d/ -f3)"
          /etc/rc.network restart ${ETH} >/dev/null 2>&1
          [ -n "$(echo "${IPRS}" | cut -d/ -f4)" ] && /etc/rc.network_routing "$(echo "${IPRS}" | cut -d/ -f4)" &
        fi
      done
    done
  fi

elif [ "${1}" = "rcExit" ]; then
  echo "Installing addon misc - ${1}"

  # 下面四项是 RR 26.x 为 DSM 7.x 加的，RR 24.4.0（最后一个支持 6.2 的版本）里没有，
  # 也从未在 6.2 上验证过 —— 6.2 按 RR 24.4.0 的语义保持原样，只有 7.x 执行：
  #   - telnet（root 空密码 + inetd）：安装流程不需要
  #   - installable_check_pass 轮询：6.2 全树没有任何使用者（grep 0 处）
  #   - DisabledPortDisks=""：6.2 选盘走 installable_disk_list，不看该字段
  #   - reboot.cgi 的 `reboot -f`：跳过关机流程，改变了系统行为
  # 实证对照：RR 24.4.0 的 misc 装 6.2 正常，我们的 26.10.11 网页停在 98%，但后端其实
  # 已成功（install.progress=stage Success、ErrFHOSTDoUpgrade retv=[0]、synoupdate.log
  # Congratulations），差异只可能出自这几项脚本副作用。
  if [ "${MajorVersion}" -ge 7 ]; then
    # enable telnet
    sed -i 's/^root:x:0:0/root::0:0/' /etc/passwd
    inetd

    # invalid_disks
    # method 1 # (block dsm system migrate)
    # SH_FILE="/usr/syno/share/get_hcl_invalid_disks.sh"
    # [ -f "${SH_FILE}" ] && cp -pf "${SH_FILE}" "${SH_FILE}.bak" && printf '#!/bin/sh\nexit 0\n' >"${SH_FILE}"
    # method 2
    while true; do
      [ ! -f "/tmp/installable_check_pass" ] && touch "/tmp/installable_check_pass"
      sleep 1
    done & # using a while loop in case DSM is running in a VM
  fi

  # for epyc7003ntb web error "无法连接到另一台控制器"
  sed -i 's/check_ntb_connection$/exit 0 # check_ntb_connection/' "/usr/syno/share/clusterInstall.sh" 2>/dev/null || true

  # error message
  # DSM 6.x 的安装器文案在 /usr/syno/web/installer.js（7.x 才是 main.js），且 6.x 前缀是 _T(...)
  if [ "${MajorVersion}" -lt 7 ]; then
    _webjs="/usr/syno/web/installer.js"
    _webpat='_T("welcome","desc_install")'
  else
    _webjs="/usr/syno/web/main.js"
    _webpat='c("welcome","desc_install")'
  fi
  while true; do
    if [ ! -b /dev/synoboot ] || [ ! -b /dev/synoboot1 ] || [ ! -b /dev/synoboot2 ] || [ ! -b /dev/synoboot3 ]; then
      if [ -f "${_webjs}" ] && [ ! -f "${_webjs}.bak" ]; then
        cp -f "${_webjs}" "${_webjs}.bak"
        sed -i "s|${_webpat}|\"Error: Boot disk mounting failed. Please change the USB port of the boot disk and refresh the page.\"|" "${_webjs}" 2>/dev/null
      fi
    else
      if [ -f "${_webjs}.bak" ]; then
        mv -f "${_webjs}.bak" "${_webjs}"
      fi
    fi

    # 安装失败原因诊断：DSM 安装器（scemd）只把结果写进 /tmp 下的这几个文件，而安装完成
    # 后 scemd 直接重启，没有任何 addon 阶段还能读到它们（tmpfs 随即丢失）。网页上那个
    # error_unknown 页面（"安装过程中出现错误…"）正是拿不到已知错误码时的兜底文案，
    # 所以这几个文件是唯一能定案 98% 报错的东西。一出现就打进 kmsg，让 dmesg 带走。
    # 每个文件只打一次，避免每秒刷屏。
    for _diag in /tmp/installer.error /tmp/fhost.status /tmp/recover_fail; do
      [ -f "${_diag}" ] || continue
      [ -f "${_diag}.kmsgd" ] && continue
      touch "${_diag}.kmsgd" 2>/dev/null || true
      echo "AiNasDiag: ${_diag}=$(cat "${_diag}" 2>/dev/null) progress=$(cat /tmp/install.progress 2>/dev/null)" >/dev/kmsg 2>/dev/null || true
    done

    sleep 1
  done &
  # 同上面的理由：这两项只有 7.x 执行，6.2 保持 RR 24.4.0 的原样。
  if [ "${MajorVersion}" -ge 7 ]; then
    # disable DisabledPortDisks
    sed -i 's/^DisabledPortDisks=.*$/DisabledPortDisks=""/' /usr/syno/web/webman/get_state.cgi 2>/dev/null || true

    # reboot
    sed -i 's/reboot$/reboot -f/' /usr/syno/web/webman/reboot.cgi 2>/dev/null || true
  fi

  # recovery（6.x 的脚本名是 recover.cgi，7.x 是 recovery.cgi）
  if grep -qE "(^|[[:space:]])recovery([[:space:]]|$)" /proc/cmdline 2>/dev/null; then
    for RC in /usr/syno/web/webman/recovery.cgi /usr/syno/web/webman/recover.cgi; do
      [ -x "${RC}" ] || continue
      "${RC}"
      break
    done
  fi

elif [ "${1}" = "late" ]; then
  echo "Installing addon misc - ${1}"
  mkdir -p "/tmpRoot/usr/rr/addons/"
  # cp -pf "${0}" "/tmpRoot/usr/rr/addons/"

  echo "Killing ttyd dufs ..."
  /usr/bin/killall ttyd 2>/dev/null || true
  /usr/bin/killall dufs 2>/dev/null || true
  cp -pf /usr/sbin/ttyd /tmpRoot/usr/sbin/ttyd
  cp -pf /usr/sbin/dufs /tmpRoot/usr/sbin/dufs

  # synoinfo.conf
  cp -vpf "/addons/synoinfo.conf" /tmpRoot/usr/rr/addons/synoinfo.conf
  for KEY in $(cat "/addons/synoinfo.conf" 2>/dev/null | cut -d= -f1); do
    [ -z "${KEY}" ] && continue
    VALUE="$(/bin/get_key_value /etc/synoinfo.conf "${KEY}")" # Do not use the value in /addons/synoinfo.conf
    echo "Setting ${KEY} to ${VALUE}"
    for F in "/tmpRoot/etc/synoinfo.conf" "/tmpRoot/etc.defaults/synoinfo.conf"; do /bin/set_key_value "${F}" "${KEY}" "${VALUE}"; done
  done

  # lspci
  mkdir -p /tmpRoot/usr/local/share
  cp -vpf /usr/local/share/pci.ids.gz /tmpRoot/usr/local/share/pci.ids.gz

  # CPU performance scaling
  mount -t sysfs sysfs /sys
  modprobe acpi-cpufreq
  if [ -f /tmpRoot/usr/lib/modules-load.d/70-cpufreq-kernel.conf ]; then
    CPUFREQ=$(ls -l /sys/devices/system/cpu/cpufreq/*/* 2>/dev/null | wc -l)
    if [ ${CPUFREQ} -eq 0 ]; then
      echo "CPU does NOT support CPU Performance Scaling, disabling"
      sed -i 's/^acpi-cpufreq/# acpi-cpufreq/g' /tmpRoot/usr/lib/modules-load.d/70-cpufreq-kernel.conf
    else
      echo "CPU supports CPU Performance Scaling, enabling"
      sed -i 's/^# acpi-cpufreq/acpi-cpufreq/g' /tmpRoot/usr/lib/modules-load.d/70-cpufreq-kernel.conf
      cp -vpf /usr/lib/modules/cpufreq_* /tmpRoot/usr/lib/modules/
    fi
  fi
  modprobe -r acpi-cpufreq
  umount /sys

  # crypto-kernel
  if [ -f /tmpRoot/usr/lib/modules-load.d/70-crypto-kernel.conf ]; then
    # crc32c-intel
    if grep flags /proc/cpuinfo 2>/dev/null | grep -qE "(^|[[:space:]])sse4_2([[:space:]]|$)"; then
      echo "CPU Supports SSE4.2, crc32c-intel should load"
    else
      echo "CPU does NOT support SSE4.2, crc32c-intel will not load, disabling"
      sed -i 's/^crc32c-intel/# crc32c-intel/g' /tmpRoot/usr/lib/modules-load.d/70-crypto-kernel.conf
    fi

    # aesni-intel
    if grep flags /proc/cpuinfo 2>/dev/null | grep -qE "(^|[[:space:]])aes([[:space:]]|$)"; then
      echo "CPU Supports AES, aesni-intel should load"
    else
      echo "CPU does NOT support AES, aesni-intel will not load, disabling"
      for F in "/tmpRoot/etc/synoinfo.conf" "/tmpRoot/etc.defaults/synoinfo.conf"; do /bin/set_key_value "${F}" "support_aesni_intel" "no"; done
      sed -i 's/^aesni-intel/# aesni-intel/g' /tmpRoot/usr/lib/modules-load.d/70-crypto-kernel.conf
    fi
  fi

  # Nvidia GPU
  if grep -iq 10de /proc/bus/pci/devices 2>/dev/null; then
    for F in "/tmpRoot/etc/synoinfo.conf" "/tmpRoot/etc.defaults/synoinfo.conf"; do /bin/set_key_value "${F}" "support_nvidia_gpu" "yes"; done
    [ -f /tmpRoot/usr/lib/modules-load.d/70-syno-nvidia-gpu.conf ] && sed -i 's/^# nvidia/nvidia/g' /tmpRoot/usr/lib/modules-load.d/70-syno-nvidia-gpu.conf
  else
    for F in "/tmpRoot/etc/synoinfo.conf" "/tmpRoot/etc.defaults/synoinfo.conf"; do /bin/set_key_value "${F}" "support_nvidia_gpu" "no"; done
    [ -f /tmpRoot/usr/lib/modules-load.d/70-syno-nvidia-gpu.conf ] && sed -i 's/^nvidia/# nvidia/g' /tmpRoot/usr/lib/modules-load.d/70-syno-nvidia-gpu.conf
  fi

  # sdcard（DSM 6.2 的 udev 脚本在 /lib/udev/script/，7.x 在 /usr/lib/udev/script/，两处都写）
  for SDCARD_SH in /tmpRoot/usr/lib/udev/script/sdcard.sh /tmpRoot/lib/udev/script/sdcard.sh; do
    [ -f "${SDCARD_SH}" ] || continue
    [ -f "${SDCARD_SH}.bak" ] || cp -vpf "${SDCARD_SH}" "${SDCARD_SH}.bak"
    printf '#!/bin/sh\nexit 0\n' >"${SDCARD_SH}"
  done

  # beep
  cp -vpf /usr/bin/beep /tmpRoot/usr/bin/beep
  # libubsan 只在 7.x 的 ramdisk 里；6.2 的 ramdisk 没有该库（beep 本身只依赖 libc.so.6），
  # 通配符不展开时 cp 会报 "can't stat '/usr/lib/libubsan.so*'" —— 逐项判存在再拷。
  for _so in /usr/lib/libubsan.so*; do
    [ -e "${_so}" ] || continue
    cp -vpdf "${_so}" /tmpRoot/usr/lib/
  done
  # [ ! -f /tmpRoot/usr/syno/bin/synoschedtool.bak ] && cp -vpf /tmpRoot/usr/syno/bin/synoschedtool /tmpRoot/usr/syno/bin/synoschedtool.bak
  # printf '#!/bin/sh\ncase "${1}" in\n  --beep)\n  beep -r ${2}\n  ;;\n  *)\n    /usr/syno/bin/synoschedtool.bak "$@"  ;;\nesac\n' >/tmpRoot/usr/syno/bin/synoschedtool

  # service
  # systemd-modules-load SynoInitEth syno-oob-check-status syno_update_disk_logs
  rm -vf /tmpRoot/usr/lib/modules-load.d/70-net-kernel.conf /tmpRoot/usr/lib/modules-load.d/70-network*.conf
  sed -i 's|ExecStart=/|ExecStart=-/|g' /tmpRoot/usr/lib/systemd/system/systemd-modules-load.service 2>/dev/null
  sed -i 's|ExecStart=/|ExecStart=-/|g' /tmpRoot/usr/lib/systemd/system/SynoInitEth.service 2>/dev/null
  sed -i 's|ExecStart=/|ExecStart=-/|g' /tmpRoot/usr/lib/systemd/system/syno-oob-check-status.service 2>/dev/null
  sed -i 's|ExecStart=/|ExecStart=-/|g' /tmpRoot/usr/lib/systemd/system/syno_update_disk_logs.service 2>/dev/null

  # getty
  for I in $(cat /proc/cmdline 2>/dev/null | grep -Eo 'getty=[^ ]+' | sed 's/getty=//'); do
    TTYN="$(echo "${I}" | cut -d',' -f1)"
    BAUD="$(echo "${I}" | cut -d',' -f2 | cut -d'n' -f1)"
    # 用 case 模式而不是 grep -E 拼变量（变量含正则元字符会被误判；6.2 的 busybox grep 也没有 -w）
    case " ttyS0 ttyS1 ttyS2 " in *" ${TTYN} "*) continue ;; esac

    if [ "${MajorVersion}" -lt 7 ]; then
      # DSM 6.x 没有 systemd，写 upstart 任务（6.x 的 job 目录是 /usr/share/init）
      if [ -n "${TTYN}" ] && [ -e "/dev/${TTYN}" ]; then
        echo "Make getty for ${TTYN} (upstart)"
        mkdir -p /tmpRoot/usr/share/init
        {
          echo 'description "RR addon getty"'
          echo 'start on runlevel 1'
          echo 'task'
          echo 'console none'
          echo 'env PATH=/sbin:/bin:/usr/sbin:/usr/bin'
          echo "exec /usr/sbin/getty -L ${TTYN} ${BAUD:-115200} linux"
        } >"/tmpRoot/usr/share/init/rr-getty-${TTYN}.conf"
      fi
    else
      mkdir -p /tmpRoot/usr/lib/systemd/system/getty.target.wants
      if [ -n "${TTYN}" ] && [ -e "/dev/${TTYN}" ]; then
        echo "Make getty\@${TTYN}.service"
        cp -vpf /tmpRoot/usr/lib/systemd/system/serial-getty\@.service /tmpRoot/usr/lib/systemd/system/getty\@${TTYN}.service
        sed -i "s|^ExecStart=.*|ExecStart=-/sbin/agetty %I ${BAUD:-115200} linux|" /tmpRoot/usr/lib/systemd/system/getty\@${TTYN}.service
        mkdir -p /tmpRoot/usr/lib/systemd/system/getty.target.wants
        ln -sf /usr/lib/systemd/system/getty\@${TTYN}.service /tmpRoot/usr/lib/systemd/system/getty.target.wants/getty\@${TTYN}.service
      fi
    fi
  done

  # rr-misc
  cp -vpf /usr/bin/rr-misc.sh /tmpRoot/usr/bin/rr-misc.sh
  cp -vpf /usr/sbin/durex /tmpRoot/usr/sbin/durex

  # DSM 6.x 没有 systemd，也就没有 /usr/lib/systemd/system 目录。但 6.x 的服务桥接
  # （loader 侧 dsm6-services.sh）正是靠 multi-user.target.wants/ 里的 unit 取 ExecStart，
  # 所以必须先 mkdir 再写 unit；否则重定向到不存在的目录直接失败，留下的只是一个
  # 指向不存在文件的软链，桥接阶段 `[ -e ]` 直接跳过，服务永远不会执行。
  DEST="/tmpRoot/usr/lib/systemd/system/rr-misc.service"
  mkdir -p /tmpRoot/usr/lib/systemd/system/multi-user.target.wants
  {
    echo "[Unit]"
    echo "Description=RR addon rr-misc daemon"
    echo "After=multi-user.target"
    echo "After=scemd.service rc-network.service"
    echo
    echo "[Service]"
    echo "Type=oneshot"
    echo "RemainAfterExit=yes"
    echo "ExecStart=-/usr/bin/rr-misc.sh"
    echo
    echo "[Install]"
    echo "WantedBy=multi-user.target"
  } >"${DEST}"

  ln -sf /usr/lib/systemd/system/rr-misc.service /tmpRoot/usr/lib/systemd/system/multi-user.target.wants/rr-misc.service

  # rr-once
  cp -vpf /usr/bin/rr-once.sh /tmpRoot/usr/bin/rr-once.sh

  DEST="/tmpRoot/usr/lib/systemd/system/rr-once.service"
  mkdir -p /tmpRoot/usr/lib/systemd/system/multi-user.target.wants
  {
    echo "[Unit]"
    echo "Description=RR addon rr-once daemon"
    echo "After=multi-user.target"
    echo "After=scemd.service rc-network.service"
    echo "After=synoscgi.service nginx.service syno-mkcert.service"
    echo
    echo "[Service]"
    echo "Type=oneshot"
    echo "RemainAfterExit=yes"
    echo "ExecStart=-/usr/bin/rr-once.sh"
    echo
    echo "[Install]"
    echo "WantedBy=multi-user.target"
  } >"${DEST}"

  ln -sf /usr/lib/systemd/system/rr-once.service /tmpRoot/usr/lib/systemd/system/multi-user.target.wants/rr-once.service

fi
