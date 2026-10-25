#!/usr/bin/env sh
#
# Copyright (C) 2022 Ing <https://github.com/wjz304>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

if [ "${1}" = "late" ]; then
  echo "Installing addon storagepanel - ${1}"
  mkdir -p "/tmpRoot/usr/rr/addons/"
  cp -pf "${0}" "/tmpRoot/usr/rr/addons/"

  cp -vpf /usr/bin/storagepanel.sh /tmpRoot/usr/bin/storagepanel.sh
  [ ! -f "/tmpRoot/usr/bin/gzip" ] && cp -vpf /usr/bin/gzip /tmpRoot/usr/bin/gzip

  shift
  mkdir -p "/tmpRoot/usr/lib/systemd/system"
  DEST="/tmpRoot/usr/lib/systemd/system/storagepanel.service"
  {
    echo "[Unit]"
    echo "Description=RR addon storagepanel daemon"
    echo "Wants=smpkg-custom-install.service pkgctl-StorageManager.service"
    echo "After=smpkg-custom-install.service"
    echo
    echo "[Service]"
    echo "Type=oneshot"
    echo "RemainAfterExit=yes"
    echo "ExecStart=-/usr/bin/storagepanel.sh $*"
    echo
    echo "[Install]"
    echo "WantedBy=multi-user.target"
  } >"${DEST}"

  mkdir -p /tmpRoot/usr/lib/systemd/system/multi-user.target.wants
  ln -sf /usr/lib/systemd/system/storagepanel.service /tmpRoot/usr/lib/systemd/system/multi-user.target.wants/storagepanel.service
elif [ "${1}" = "uninstall" ]; then
  echo "Installing addon storagepanel - ${1}"

  rm -f "/tmpRoot/usr/lib/systemd/system/multi-user.target.wants/storagepanel.service"
  rm -f "/tmpRoot/usr/lib/systemd/system/storagepanel.service"

  # rm -f /tmpRoot/usr/bin/gzip
  [ ! -f "/tmpRoot/usr/rr/revert.sh" ] && echo '#!/usr/bin/env bash' >/tmpRoot/usr/rr/revert.sh && chmod +x /tmpRoot/usr/rr/revert.sh
  echo "/usr/bin/storagepanel.sh -r" >>/tmpRoot/usr/rr/revert.sh
  echo "rm -f /usr/bin/storagepanel.sh" >>/tmpRoot/usr/rr/revert.sh
fi
