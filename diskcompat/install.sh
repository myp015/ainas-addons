#!/usr/bin/env sh
#
# Copyright (C) 2022 Ing <https://github.com/wjz304>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

if [ "${1}" = "late" ]; then
  echo "Installing addon diskcompat - ${1}"
  mkdir -p "/tmpRoot/usr/rr/addons/"
  cp -pf "${0}" "/tmpRoot/usr/rr/addons/"

  cp -vpf /usr/bin/diskcompat.sh /tmpRoot/usr/bin/diskcompat.sh

  mkdir -p "/tmpRoot/usr/lib/systemd/system"
  DEST="/tmpRoot/usr/lib/systemd/system/diskcompat.service"
  {
    echo "[Unit]"
    echo "Description=RR addon diskcompat daemon"
    echo "Wants=smpkg-custom-install.service pkgctl-StorageManager.service"
    echo "After=smpkg-custom-install.service pkgctl-StorageManager.service"
    echo
    echo "[Service]"
    echo "Type=oneshot"
    echo "RemainAfterExit=yes"
    echo "ExecStart=-/usr/bin/diskcompat.sh"
    echo
    echo "[Install]"
    echo "WantedBy=multi-user.target"
  } >"${DEST}"

  mkdir -p /tmpRoot/usr/lib/systemd/system/multi-user.target.wants
  ln -sf /usr/lib/systemd/system/diskcompat.service /tmpRoot/usr/lib/systemd/system/multi-user.target.wants/diskcompat.service
elif [ "${1}" = "uninstall" ]; then
  echo "Installing addon diskcompat - ${1}"

  rm -f "/tmpRoot/usr/lib/systemd/system/multi-user.target.wants/diskcompat.service"
  rm -f "/tmpRoot/usr/lib/systemd/system/diskcompat.service"

  [ ! -f "/tmpRoot/usr/rr/revert.sh" ] && echo '#!/usr/bin/env bash' >/tmpRoot/usr/rr/revert.sh && chmod +x /tmpRoot/usr/rr/revert.sh
  echo "/usr/bin/diskcompat.sh --restore" >>/tmpRoot/usr/rr/revert.sh
  echo "rm -f /usr/bin/diskcompat.sh" >>/tmpRoot/usr/rr/revert.sh
fi
