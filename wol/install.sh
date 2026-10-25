#!/usr/bin/env sh
#
# Copyright (C) 2022 Ing <https://github.com/wjz304>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

if [ "${1}" = "jrExit" ]; then
  echo "Installing addon wol - ${1}"

  /usr/bin/wol.sh

elif [ "${1}" = "late" ]; then
  echo "Installing addon wol - ${1}"
  mkdir -p "/tmpRoot/usr/rr/addons/"
  cp -pf "${0}" "/tmpRoot/usr/rr/addons/"

  [ ! -f "/tmpRoot/usr/bin/ethtool" ] && cp -vpf /usr/bin/ethtool /tmpRoot/usr/bin/ethtool
  cp -vpf /usr/bin/wol.sh /tmpRoot/usr/bin/wol.sh

  mkdir -p "/tmpRoot/usr/lib/systemd/system"
  DEST="/tmpRoot/usr/lib/systemd/system/wol.service"
  {
    echo "[Unit]"
    echo "Description=RR addon wol daemon"
    echo "After=multi-user.target"
    echo
    echo "[Service]"
    echo "Type=oneshot"
    echo "RemainAfterExit=yes"
    echo "ExecStart=-/usr/bin/wol.sh"
    echo
    echo "[Install]"
    echo "WantedBy=multi-user.target"
  } >"${DEST}"

  mkdir -p /tmpRoot/usr/lib/systemd/system/multi-user.target.wants
  ln -sf /usr/lib/systemd/system/wol.service /tmpRoot/usr/lib/systemd/system/multi-user.target.wants/wol.service
elif [ "${1}" = "uninstall" ]; then
  echo "Installing addon wol - ${1}"

  rm -f "/tmpRoot/usr/lib/systemd/system/multi-user.target.wants/wol.service"
  rm -f "/tmpRoot/usr/lib/systemd/system/wol.service"

  # rm -f /tmpRoot/usr/bin/ethtool
  rm -f /tmpRoot/usr/bin/wol.sh
fi
