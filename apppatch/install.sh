#!/usr/bin/env sh
#
# Copyright (C) 2022 Ing <https://github.com/wjz304>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

if [ "${1}" = "late" ]; then
  echo "Installing addon apppatch - ${1}"
  mkdir -p "/tmpRoot/usr/rr/addons/"
  cp -pf "${0}" "/tmpRoot/usr/rr/addons/"

  cp -vpf /usr/bin/PatchELFSharp /tmpRoot/usr/bin/PatchELFSharp
  cp -vpf /usr/bin/apppatch.sh /tmpRoot/usr/bin/apppatch.sh

  mkdir -p "/tmpRoot/usr/lib/systemd/system"
  DEST="/tmpRoot/usr/lib/systemd/system/apppatch.service"
  {
    echo "[Unit]"
    echo "Description=RR addon apppatch daemon"
    echo "Wants=smpkg-custom-install.service pkgctl-StorageManager.service"
    echo "After=smpkg-custom-install.service"
    # echo "ConditionPathExists=|/var/packages/SynologyPhotos"
    # echo "ConditionPathExists=|/var/packages/SurveillanceStation"
    echo
    echo "[Service]"
    echo "Type=oneshot"
    echo "RemainAfterExit=no"
    echo "ExecStart=-/usr/bin/apppatch.sh"
    echo
    echo "[Install]"
    echo "WantedBy=multi-user.target"
  } >"${DEST}"

  mkdir -p /tmpRoot/usr/lib/systemd/system/multi-user.target.wants
  ln -sf /usr/lib/systemd/system/apppatch.service /tmpRoot/usr/lib/systemd/system/multi-user.target.wants/apppatch.service

  DEST="/tmpRoot/usr/lib/systemd/system/apppatch.path"
  {
    echo "[Unit]"
    echo "Description=RR addon apppatch path"
    echo "Wants=smpkg-custom-install.service pkgctl-StorageManager.service"
    echo "After=smpkg-custom-install.service"
    echo "ConditionPathExists=/var/packages"
    echo
    echo "[Path]"
    echo "PathModified=/var/packages"
    echo "Unit=apppatch.service"
    echo
    echo "[Install]"
    echo "WantedBy=multi-user.target"
  } >"${DEST}"

  mkdir -p /tmpRoot/usr/lib/systemd/system/multi-user.target.wants
  ln -sf /usr/lib/systemd/system/apppatch.path /tmpRoot/usr/lib/systemd/system/multi-user.target.wants/apppatch.path

elif [ "${1}" = "uninstall" ]; then
  echo "Installing addon apppatch - ${1}"

  rm -f "/tmpRoot/usr/lib/systemd/system/multi-user.target.wants/apppatch.service"
  rm -f "/tmpRoot/usr/lib/systemd/system/multi-user.target.wants/apppatch.path"
  rm -f "/tmpRoot/usr/lib/systemd/system/apppatch.service"
  rm -f "/tmpRoot/usr/lib/systemd/system/apppatch.path"

  [ ! -f "/tmpRoot/usr/rr/revert.sh" ] && echo '#!/usr/bin/env bash' >/tmpRoot/usr/rr/revert.sh && chmod +x /tmpRoot/usr/rr/revert.sh
  echo "/usr/bin/apppatch.sh -r" >>/tmpRoot/usr/rr/revert.sh
  echo "rm -f /usr/bin/apppatch.sh" >>/tmpRoot/usr/rr/revert.sh
fi
