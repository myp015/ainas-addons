#!/usr/bin/env sh
#
# Copyright (C) 2022 Ing <https://github.com/wjz304>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

if [ "${1}" = "late" ]; then
  echo "Installing addon virtiofs - ${1}"
  mkdir -p "/tmpRoot/usr/rr/addons/"
  cp -pf "${0}" "/tmpRoot/usr/rr/addons/"

  cp -vpf /usr/bin/rr-virtiofs.sh /tmpRoot/usr/bin/rr-virtiofs.sh

  mkdir -p "/tmpRoot/usr/lib/systemd/system"
  DEST="/tmpRoot/usr/lib/systemd/system/virtiofs.service"
  {
    echo "[Unit]"
    echo "Description=RR addon virtiofs daemon"
    echo "After=multi-user.target"
    echo "After=syno-volume.target"
    echo
    echo "[Service]"
    echo "Type=oneshot"
    echo "RemainAfterExit=yes"
    echo "ExecStart=-/usr/bin/rr-virtiofs.sh"
    echo
    echo "[Install]"
    echo "WantedBy=multi-user.target"
  } >"${DEST}"

  mkdir -p /tmpRoot/usr/lib/systemd/system/multi-user.target.wants
  ln -sf /usr/lib/systemd/system/virtiofs.service /tmpRoot/usr/lib/systemd/system/multi-user.target.wants/virtiofs.service
elif [ "${1}" = "uninstall" ]; then
  echo "Installing addon virtiofs - ${1}"

  rm -f "/tmpRoot/usr/lib/systemd/system/multi-user.target.wants/virtiofs.service"
  rm -f "/tmpRoot/usr/lib/systemd/system/virtiofs.service"

  rm -f /tmpRoot/usr/bin/rr-virtiofs.sh
fi
