#!/usr/bin/env sh
#
# Copyright (C) 2022 Ing <https://github.com/wjz304>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#
# From: https://github.com/007revad/Synology_enable_M2_volume
# From: https://github.com/PeterSuh-Q3/tcrp-addons/blob/main/nvmevolume-onthefly/src/install.sh
#

if grep -qF "/addons/nvmesystem.sh" "/addons/addons.sh"; then
  echo "nvmevolume is not required if nvmesystem exists!"
  exit 0
fi

# DSM 版本判据：读 /etc/defaults/VERSION 的 majorversion（6.2 → 6，7.x → 7）。
# 不能用内核主版本 —— DSM 7.0~7.3 的内核同样是 4.4.x，与 6.2 的主版本相同。
MajorVersion="$(/bin/get_key_value /etc.defaults/VERSION majorversion 2>/dev/null)"
[ -n "${MajorVersion}" ] || MajorVersion="$(/bin/get_key_value /etc/VERSION majorversion 2>/dev/null)"
case "${MajorVersion}" in
  '' | *[!0-9]*)
    echo " ERROR: cannot determine DSM major version from /etc/defaults/VERSION" >&2
    exit 1
    ;;
esac

if [ "${1}" = "late" ]; then
  # nvmevolume 依赖两处 DSM 7.x 专属机制：
  #   1. /run/synostorage/disks/nvme*/m2_pool_support —— 打开「M.2 允许建存储池」标志；
  #   2. Storage Manager 的 storage_panel.js（DSM 7.0 重写存储管理器后才有）—— 改前端显示。
  # 实测（DSM 6.2.4-25556u8 / bj3_dsm）：6.2 的 /run/synostorage/disks/<盘>/ 下没有
  # m2_pool_support 属性，存储管理器也没有 storage_panel.js；6.2 的 NVMe 本来就只支持缓存。
  # 所以在 6.x 跳过，避免对 libhwcontrol.so.1 打未验证的字节补丁、并写一个必然空跑的 unit。
  if [ "${MajorVersion}" -lt 7 ]; then
    echo "nvmevolume addon is not supported on DSM ${MajorVersion}.x (no m2_pool_support / storage_panel.js before DSM 7.0), skipped"
    rm -f /tmpRoot/usr/lib/systemd/system/multi-user.target.wants/nvmevolume.service
    rm -f /tmpRoot/usr/lib/systemd/system/nvmevolume.service
    rm -f /tmpRoot/usr/bin/nvmevolume.sh
    exit 0
  fi

  echo "Installing addon nvmevolume - ${1}"
  mkdir -p "/tmpRoot/usr/rr/addons/"
  cp -pf "${0}" "/tmpRoot/usr/rr/addons/"

  SO_FILE="/tmpRoot/usr/lib/libhwcontrol.so.1"
  [ ! -f "${SO_FILE}.bak" ] && cp -pf "${SO_FILE}" "${SO_FILE}.bak"

  cp -pf "${SO_FILE}" "${SO_FILE}.tmp"
  xxd -c "$(xxd -p "${SO_FILE}.tmp" 2>/dev/null | wc -c)" -p "${SO_FILE}.tmp" 2>/dev/null \
    | sed "s/803e00b801000000752.488b/803e00b8010000009090488b/" \
    | xxd -r -p >"${SO_FILE}" 2>/dev/null
  rm -f "${SO_FILE}.tmp"

  # Create storage pool page without RAID type.
  cp -vpf /usr/bin/nvmevolume.sh /tmpRoot/usr/bin/nvmevolume.sh

  [ ! -f "/tmpRoot/usr/bin/gzip" ] && cp -vpf /usr/bin/gzip /tmpRoot/usr/bin/gzip

  mkdir -p "/tmpRoot/usr/lib/systemd/system"
  DEST="/tmpRoot/usr/lib/systemd/system/nvmevolume.service"
  {
    echo "[Unit]"
    echo "Description=RR addon nvmevolume daemon"
    echo "Wants=smpkg-custom-install.service pkgctl-StorageManager.service"
    echo "After=smpkg-custom-install.service"
    echo "After=storagepanel.service" # storagepanel
    echo "After=nvmesystem.service"   # nvmesystem
    echo
    echo "[Service]"
    echo "Type=oneshot"
    echo "RemainAfterExit=yes"
    echo "ExecStart=-/usr/bin/nvmevolume.sh"
    echo
    echo "[Install]"
    echo "WantedBy=multi-user.target"
  } >"${DEST}"

  mkdir -p /tmpRoot/usr/lib/systemd/system/multi-user.target.wants
  ln -sf /usr/lib/systemd/system/nvmevolume.service /tmpRoot/usr/lib/systemd/system/multi-user.target.wants/nvmevolume.service

elif [ "${1}" = "uninstall" ]; then
  echo "Installing addon nvmevolume - ${1}"

  SO_FILE="/tmpRoot/usr/lib/libhwcontrol.so.1"
  [ -f "${SO_FILE}.bak" ] && mv -f "${SO_FILE}.bak" "${SO_FILE}"

  rm -f "/tmpRoot/usr/lib/systemd/system/multi-user.target.wants/nvmevolume.service"
  rm -f "/tmpRoot/usr/lib/systemd/system/nvmevolume.service"

  # rm -f /tmpRoot/usr/bin/gzip
  [ ! -f "/tmpRoot/usr/rr/revert.sh" ] && echo '#!/usr/bin/env bash' >/tmpRoot/usr/rr/revert.sh && chmod +x /tmpRoot/usr/rr/revert.sh
  echo "/usr/bin/nvmevolume.sh -r" >>/tmpRoot/usr/rr/revert.sh
  echo "rm -f /usr/bin/nvmevolume.sh" >>/tmpRoot/usr/rr/revert.sh
fi
