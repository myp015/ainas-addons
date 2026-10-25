#!/usr/bin/env sh
#
# Copyright (C) 2022 Ing <https://github.com/wjz304>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

if [ "${1}" = "late" ]; then
  echo "Installing addon reboottoloader - ${1}"
  mkdir -p "/tmpRoot/usr/rr/addons/"
  cp -pf "${0}" "/tmpRoot/usr/rr/addons/"

  cp -vpf /usr/bin/loader-reboot.sh /tmpRoot/usr/bin
  cp -vpf /usr/bin/grub-editenv /tmpRoot/usr/bin

  export LD_LIBRARY_PATH=/tmpRoot/bin:/tmpRoot/lib
  ESYNOSCHEDULER_DB="/tmpRoot/usr/syno/etc/esynoscheduler/esynoscheduler.db"
  if [ ! -f "${ESYNOSCHEDULER_DB}" ] || ! /tmpRoot/bin/sqlite3 "${ESYNOSCHEDULER_DB}" ".tables" | grep -qE "(^|[[:space:]])task([[:space:]]|$)"; then
    echo "copy esynoscheduler.db"
    mkdir -p "$(dirname "${ESYNOSCHEDULER_DB}")"
    cp -vpf /addons/esynoscheduler.db "${ESYNOSCHEDULER_DB}"
  fi
  echo "insert reboottoloader task to esynoscheduler.db"
  /tmpRoot/bin/sqlite3 "${ESYNOSCHEDULER_DB}" <<EOF
DELETE FROM task WHERE task_name LIKE 'RebootToLoader';
INSERT INTO task VALUES('RebootToLoader', '', 'shutdown', '', 0, 0, 0, 0, '', 0, '/usr/bin/loader-reboot.sh "config"', 'script', '{}', '', '', '{}', '{}');
EOF
elif [ "${1}" = "uninstall" ]; then
  echo "Installing addon reboottoloader - ${1}"

  rm -f /tmpRoot/usr/bin/loader-reboot.sh
  rm -f /tmpRoot/usr/bin/grub-editenv

  export LD_LIBRARY_PATH=/tmpRoot/bin:/tmpRoot/lib
  ESYNOSCHEDULER_DB="/tmpRoot/usr/syno/etc/esynoscheduler/esynoscheduler.db"
  if [ -f "${ESYNOSCHEDULER_DB}" ]; then
    echo "delete reboottoloader task from esynoscheduler.db"
    /tmpRoot/bin/sqlite3 "${ESYNOSCHEDULER_DB}" <<EOF
DELETE FROM task WHERE task_name LIKE 'RebootToLoader';
EOF
  fi
fi
