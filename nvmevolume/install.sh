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

if [ "${1}" = "late" ]; then
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
