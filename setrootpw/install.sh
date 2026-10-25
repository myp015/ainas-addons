#!/usr/bin/env sh
#
# Copyright (C) 2022 Ing <https://github.com/wjz304>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

_release="$(/bin/uname -r)"
# DSM 版本判据：读 /etc/defaults/VERSION 的 majorversion（6.2 → 6，7.x → 7）。
# 不能用内核主版本 —— DSM 7.0~7.3 的内核同样是 4.4.x（4.4.180 / 4.4.302），与 6.2 的
# 4.4.59 / 3.10.105 主版本相同，用内核主版本会把整个 7.x 误判成 6.2。
MajorVersion="$(/bin/get_key_value /etc.defaults/VERSION majorversion 2>/dev/null)"
# 兜底：万一某个 ramdisk 没有 /etc.defaults/VERSION，用 /etc/VERSION（loader 的
# ramdisk-patch.sh 本身就以它为必需文件，两者在 6.2 ramdisk 里内容相同）。
[ -n "${MajorVersion}" ] || MajorVersion="$(/bin/get_key_value /etc/VERSION majorversion 2>/dev/null)"
case "${MajorVersion}" in
  '' | *[!0-9]*)
    echo " ERROR: cannot determine DSM major version from /etc/defaults/VERSION" >&2
    exit 1
    ;;
esac

if [ "${1}" = "late" ]; then
  echo "Installing addon setrootpw - ${1} (kernel ${MajorVersion})"
  mkdir -p "/tmpRoot/usr/rr/addons/"
  cp -pf "${0}" "/tmpRoot/usr/rr/addons/"

  if [ "${MajorVersion}" -lt 7 ]; then
    # DSM 6.x：sshd 是 /usr/bin/sshd，sftp 用内置 internal-sftp（不需要 sftp-server 二进制）；
    # /etc/ssh/sshd_config 由 /etc.defaults/ssh/sshd_config 在系统初始化时生成，
    # 故两个位置都改（存在才改）。OpenSSH 7.4 默认 root 禁止密码登录，须显式打开。
    for FILE in /tmpRoot/etc/ssh/sshd_config /tmpRoot/etc.defaults/ssh/sshd_config; do
      [ -f "${FILE}" ] || continue
      [ -f "${FILE}.bak" ] || cp -pf "${FILE}" "${FILE}.bak"
      cp -pf "${FILE}.bak" "${FILE}"
      sed -i 's|^.*PermitRootLogin .*$|PermitRootLogin yes|' "${FILE}"
      grep -q '^PermitRootLogin' "${FILE}" || echo 'PermitRootLogin yes' >>"${FILE}"
    done
  else
    mkdir -p /tmpRoot/usr/lib/openssh
    cp -vpf /usr/lib/openssh/sftp-server /tmpRoot/usr/lib/openssh/sftp-server

    FILE="/tmpRoot/etc/ssh/sshd_config"
    [ ! -f "${FILE}.bak" ] && cp -pf "${FILE}" "${FILE}.bak"

    cp -pf "${FILE}.bak" "${FILE}"
    sed -i 's|^.*PermitRootLogin .*$|PermitRootLogin yes|' ${FILE}
    # sed -i 's|^.*PubkeyAuthentication .*$|PubkeyAuthentication yes|' ${FILE}
    # sed -i 's|^.*PasswordAuthentication .*$|PasswordAuthentication yes|' ${FILE}
    sed -i 's|^Subsystem.*$|Subsystem	sftp	/usr/lib/openssh/sftp-server|' ${FILE}
  fi

  # 6.x 没有 systemd：用 synoservice 重启 sshd，且 synouser/synogroup 在 /usr/syno/sbin。
  if [ "${MajorVersion}" -lt 7 ]; then
    _syno_sbin="/usr/syno/sbin/"
    _sshd_restart="/usr/syno/sbin/synoservice --restart ssh"
  else
    _syno_sbin=""
    _sshd_restart="systemctl restart sshd"
  fi

  export LD_LIBRARY_PATH=/tmpRoot/bin:/tmpRoot/lib
  ESYNOSCHEDULER_DB="/tmpRoot/usr/syno/etc/esynoscheduler/esynoscheduler.db"
  if [ ! -f "${ESYNOSCHEDULER_DB}" ] || ! /tmpRoot/bin/sqlite3 "${ESYNOSCHEDULER_DB}" ".tables" | grep -qE "(^|[[:space:]])task([[:space:]]|$)"; then
    echo "copy esynoscheduler.db"
    mkdir -p "$(dirname "${ESYNOSCHEDULER_DB}")"
    cp -vpf /addons/esynoscheduler.db "${ESYNOSCHEDULER_DB}"
  fi
  if echo "SELECT * FROM task;" | /tmpRoot/bin/sqlite3 "${ESYNOSCHEDULER_DB}" | grep -q "SetRootPw||bootup||1|0|0|0||0|"; then
    echo "setrootpw task already exists and it is enabled"
  else
    echo "insert setrootpw task to esynoscheduler.db"
    /tmpRoot/bin/sqlite3 "${ESYNOSCHEDULER_DB}" <<EOF
DELETE FROM task WHERE task_name LIKE 'SetRootPw';
INSERT INTO task VALUES('SetRootPw', '', 'bootup', '', 0, 0, 0, 0, '', 0, '
PW=""    # Please change to the password you need.
[ -n "\${PW}" ] && ${_syno_sbin}synouser --setpw root \${PW} && ${_syno_sbin}synogroup --memberadd administrators root && ${_sshd_restart}
synowebapi -s --exec api=SYNO.Core.Terminal method=set version=3 enable_ssh=true ssh_port=22
', 'script', '{}', '', '', '{}', '{}');
EOF
  fi
elif [ "${1}" = "uninstall" ]; then
  echo "Installing addon setrootpw - ${1}"

  if [ "${MajorVersion}" -lt 7 ]; then
    for FILE in /tmpRoot/etc/ssh/sshd_config /tmpRoot/etc.defaults/ssh/sshd_config; do
      [ -f "${FILE}.bak" ] && mv -f "${FILE}.bak" "${FILE}"
    done
  else
    rm -f /tmpRoot/usr/lib/openssh/sftp-server

    FILE="/tmpRoot/etc/ssh/sshd_config"
    [ -f "${FILE}.bak" ] && mv -f "${FILE}.bak" "${FILE}"
  fi

  export LD_LIBRARY_PATH=/tmpRoot/bin:/tmpRoot/lib
  ESYNOSCHEDULER_DB="/tmpRoot/usr/syno/etc/esynoscheduler/esynoscheduler.db"
  if [ -f "${ESYNOSCHEDULER_DB}" ]; then
    echo "delete setrootpw task from esynoscheduler.db"
    /tmpRoot/bin/sqlite3 "${ESYNOSCHEDULER_DB}" <<EOF
DELETE FROM task WHERE task_name LIKE 'SetRootPw';
EOF
  fi
fi
