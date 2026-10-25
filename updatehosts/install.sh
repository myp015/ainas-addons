#!/usr/bin/env sh
#
# Copyright (C) 2022 Ing <https://github.com/wjz304>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

if [ "${1}" = "late" ]; then
  echo "Installing addon updatehosts - ${1}"
  mkdir -p "/tmpRoot/usr/rr/addons/"
  cp -pf "${0}" "/tmpRoot/usr/rr/addons/"

  cp -vpf /usr/bin/pup /tmpRoot/usr/bin/pup
  cp -vpf /usr/bin/rr-updatehosts.sh /tmpRoot/usr/bin/rr-updatehosts.sh

  mkdir -p "/tmpRoot/usr/lib/systemd/system"
  DEST="/tmpRoot/usr/lib/systemd/system/rr-updatehosts.service"
  {
    echo "[Unit]"
    echo "Description=RR addon updatehosts daemon"
    echo "After=multi-user.target"
    echo
    echo "[Service]"
    echo "Type=oneshot"
    echo "RemainAfterExit=yes"
    echo "ExecStart=-/usr/bin/rr-updatehosts.sh create"
    echo
    echo "[Install]"
    echo "WantedBy=multi-user.target"
  } >"${DEST}"

  mkdir -p /tmpRoot/usr/lib/systemd/system/multi-user.target.wants
  ln -sf /usr/lib/systemd/system/rr-updatehosts.service /tmpRoot/usr/lib/systemd/system/multi-user.target.wants/rr-updatehosts.service
elif [ "${1}" = "uninstall" ]; then
  echo "Installing addon updatehosts - ${1}"

  rm -f /tmpRoot/usr/bin/pup

  rm -f "/tmpRoot/usr/lib/systemd/system/multi-user.target.wants/rr-updatehosts.service"
  rm -f "/tmpRoot/usr/lib/systemd/system/rr-updatehosts.service"

  [ ! -f "/tmpRoot/usr/rr/revert.sh" ] && echo '#!/usr/bin/env bash' >/tmpRoot/usr/rr/revert.sh && chmod +x /tmpRoot/usr/rr/revert.sh
  echo "/usr/bin/rr-updatehosts.sh delete" >>/tmpRoot/usr/rr/revert.sh
  echo "rm -f /usr/bin/rr-updatehosts.sh" >>/tmpRoot/usr/rr/revert.sh
fi
