#!/usr/bin/env sh
#
# Copyright (C) 2022 Ing <https://github.com/wjz304>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

if [ "${1}" = "late" ]; then
  echo "Installing addon maiyunda - ${1}"
  mkdir -p "/tmpRoot/usr/rr/addons/"
  cp -pf "${0}" "/tmpRoot/usr/rr/addons/"

  cp -vpf /usr/bin/maiyunda.sh /tmpRoot/usr/bin/maiyunda.sh
  cp -vpf /usr/sbin/ioperm /tmpRoot/usr/sbin/ioperm
  cp -vpf /usr/sbin/inb /tmpRoot/usr/sbin/inb
  cp -vpf /usr/sbin/outb /tmpRoot/usr/sbin/outb

  mkdir -p "/tmpRoot/usr/lib/systemd/system"
  DEST="/tmpRoot/usr/lib/systemd/system/maiyunda.service"
  {
    echo "[Unit]"
    echo "Description=RR addon maiyunda daemon"
    echo "After=multi-user.target"
    echo
    echo "[Service]"
    echo "Type=forking"
    echo "ExecStart=/usr/bin/maiyunda.sh"
    echo "ExecReload=/usr/bin/pkill -f /usr/bin/maiyunda.sh"
    echo "Restart=always"
    echo
    echo "[Install]"
    echo "WantedBy=multi-user.target"
  } >"${DEST}"

  mkdir -p /tmpRoot/usr/lib/systemd/system/multi-user.target.wants
  ln -sf /usr/lib/systemd/system/maiyunda.service /tmpRoot/usr/lib/systemd/system/multi-user.target.wants/maiyunda.service
elif [ "${1}" = "uninstall" ]; then
  echo "Installing addon maiyunda - ${1}"

  rm -f "/tmpRoot/usr/lib/systemd/system/multi-user.target.wants/maiyunda.service"
  rm -f "/tmpRoot/usr/lib/systemd/system/maiyunda.service"

  rm -f /tmpRoot/usr/bin/maiyunda.sh
  rm -f /tmpRoot/usr/sbin/ioperm
  rm -f /tmpRoot/usr/sbin/inb
  rm -f /tmpRoot/usr/sbin/outb
fi
