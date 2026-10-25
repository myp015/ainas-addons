#!/usr/bin/env sh
#
# Copyright (C) 2022 Ing <https://github.com/wjz304>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

# shellcheck disable=SC2010

if [ "${1}" = "early" ]; then
  echo "Installing addon tad6s4n10g - ${1}"

  if [ ! "$(/bin/get_key_value /etc/synoinfo.conf supportportmappingv2)" = "yes" ]; then
    echo "non-DT models is not supported tad6s4n10g addon early!"
    exit 0
  fi

  UNIQUE="$(/bin/get_key_value /etc.defaults/synoinfo.conf unique)"
  DEST="/addons/model.dts"
  mkdir -p "$(dirname "${DEST}" 2>/dev/null)"
  {
    echo "/dts-v1/;"
    echo "/ {"
    echo '    compatible = "Synology";'
    echo "    model = \"${UNIQUE}\";"
    echo "    version = <0x01>;"
    echo '    power_limit = "";'
  } >"${DEST}"

  COUNT=0
  # 02:00.0 SATA controller [0106]: ASMedia Technology Inc. ASM1166 Serial ATA Controller [1b21:1166] (rev 02)
  # removing the mlx5 network card 0000:00:1c.0,00.0
  # inserting the mlx5 network card 0000:00:1c.2,00.0
  ls -ld /sys/block/sata* 2>/dev/null | grep -q "0000:00:1c.0" && PCIEPATH=0000:00:1c.0,00.0 || PCIEPATH=0000:00:1c.2,00.0
  # for I in $(seq 5 -1 0); do # Reverse order
  for I in $(seq 0 5); do # Positive order
    COUNT=$((COUNT + 1))
    {
      echo "    internal_slot@${COUNT} {"
      echo '        protocol_type = "sata";'
      echo "        ahci {"
      echo "            pcie_root = \"${PCIEPATH}\";"
      echo "            ata_port = <0x$(printf '%02X' ${I})>;"
      echo "        };"
      echo "    };"
    } >>"${DEST}"
  done
  # 00:17.0 SATA controller [0106]: Intel Corporation Device [8086:54d3]
  PCIEPATH=0000:00:17.0
  if ls -ld /sys/block/sata* 2>/dev/null | grep -q "${PCIEPATH}"; then
    for I in $(seq 0 1); do
      COUNT=$((COUNT + 1))
      {
        echo "    internal_slot@${COUNT} {"
        echo '        protocol_type = "sata";'
        echo "        ahci {"
        echo "            pcie_root = \"${PCIEPATH}\";"
        echo "            ata_port = <0x$(printf '%02X' ${I})>;"
        echo "        };"
        echo "    };"
      } >>"${DEST}"
    done
  fi

  COUNT=0
  # 04:00.0 Non-Volatile memory controller [0108]: Device [1ed0:2283]
  PCIEPATH=0000:00:1d.N,00.0
  POWER_LIMIT=""
  for I in $(seq 0 3); do
    POWER_LIMIT="${POWER_LIMIT:+${POWER_LIMIT},}0"
    COUNT=$((COUNT + 1))
    {
      echo "    nvme_slot@${COUNT} {"
      echo "        pcie_root = \"$(echo ${PCIEPATH} | sed "s/N/${I}/")\";"
      echo '        port_type = "ssdcache";'
      echo "    };"
    } >>"${DEST}"
  done
  [ -n "${POWER_LIMIT}" ] && sed -i "s/power_limit = .*/power_limit = \"${POWER_LIMIT}\";/" "${DEST}" || sed -i '/power_limit/d' "${DEST}"

  COUNT=0
  # usb
  for I in 1-1 2-1.1 2-1.2 2-1.3 2-1.4 3-3.1 3-3.2 3-3.3 3-3.4 4-1 4-2 4-3 4-4; do
    COUNT=$((COUNT + 1))
    {
      echo "    usb_slot@${COUNT} {"
      echo "      usb2 {"
      echo "        usb_port = \"${I}\";"
      echo "      };"
      echo "      usb3 {"
      echo "        usb_port = \"${I}\";"
      echo "      };"
      echo "    };"
    } >>"${DEST}"
  done

  echo "};" >>"${DEST}"

  # fix pcie_root prefix
  _release=$(/bin/uname -r)
  if [ "$(/bin/echo ${_release%%[-+]*} | /usr/bin/cut -d'.' -f1)" -lt 5 ]; then
    sed -i 's/"0000:00:/"00:/g' "${DEST}"
  else
    sed -i 's/"00:/"0000:00:/g' "${DEST}"
  fi

elif [ "${1}" = "late" ]; then
  echo "Installing addon tad6s4n10g - ${1}"
  mkdir -p "/tmpRoot/usr/rr/addons/"
  cp -pf "${0}" "/tmpRoot/usr/rr/addons/"

  cp -vpf /usr/bin/tad6s4n10g.sh /tmpRoot/usr/bin/tad6s4n10g.sh
  cp -vpf /usr/sbin/ioperm /tmpRoot/usr/sbin/ioperm
  cp -vpf /usr/sbin/inb /tmpRoot/usr/sbin/inb
  cp -vpf /usr/sbin/outb /tmpRoot/usr/sbin/outb

  export LD_LIBRARY_PATH=/tmpRoot/bin:/tmpRoot/lib
  ESYNOSCHEDULER_DB="/tmpRoot/usr/syno/etc/esynoscheduler/esynoscheduler.db"
  if [ ! -f "${ESYNOSCHEDULER_DB}" ] || ! /tmpRoot/bin/sqlite3 "${ESYNOSCHEDULER_DB}" ".tables" | grep -qE "(^|[[:space:]])task([[:space:]]|$)"; then
    echo "copy esynoscheduler.db"
    mkdir -p "$(dirname "${ESYNOSCHEDULER_DB}")"
    cp -vpf /addons/esynoscheduler.db "${ESYNOSCHEDULER_DB}"
  fi
  if echo "SELECT * FROM task;" | /tmpRoot/bin/sqlite3 "${ESYNOSCHEDULER_DB}" | grep -E "Net-Button-3s" -A11 | grep -Eq "usb2/2-1/2-1.4/authorized"; then
    echo "Net-Button-3s task already exists"
  else
    echo "insert Net-Button-3s task to esynoscheduler.db"
    /tmpRoot/bin/sqlite3 "${ESYNOSCHEDULER_DB}" <<EOF
DELETE FROM task WHERE task_name LIKE 'Net-Button-3s';
INSERT INTO task VALUES('Net-Button-3s', '', 'bootup', '', 0, 0, 0, 0, '', 0, '
# 长按 Net 按钮 3s(Led 闪烁3次) 后松开, 将自动触发该任务.
# Press and hold the Net button for 3 seconds (the LED flashes 3 times) and then release it to automatically trigger the task.
#
# 请确保 SD 卡已插入到设备后再触发该任务.
echo 0 >/sys/devices/pci0000:00/0000:00:0d.0/usb2/2-1/2-1.4/authorized
echo 1 >/sys/devices/pci0000:00/0000:00:0d.0/usb2/2-1/2-1.4/authorized
#
# 请在下面输入你需要执行的操作.
# Please enter the command you need to execute below.
echo "Net-Button-3s."
', 'script', '{}', '', '', '{}', '{}');
EOF
  fi
  if echo "SELECT * FROM task;" | /tmpRoot/bin/sqlite3 "${ESYNOSCHEDULER_DB}" | grep -q "Net-Button-9s"; then
    echo "Net-Button-9s task already exists"
  else
    echo "insert Net-Button-9s task to esynoscheduler.db"
    /tmpRoot/bin/sqlite3 "${ESYNOSCHEDULER_DB}" <<EOF
DELETE FROM task WHERE task_name LIKE 'Net-Button-9s';
INSERT INTO task VALUES('Net-Button-9s', '', 'bootup', '', 0, 0, 0, 0, '', 0, '
# 长按 Net 按钮 9s(Led 闪烁3次 x 2) 后松开, 将自动触发该任务.
# Press and hold the Net button for 3 seconds (the LED flashes 3 times x 2) and then release it to automatically trigger the task.
# 请在下面输入你需要执行的操作.
# Please enter the command you need to execute below.
echo "Net-Button-9s."
', 'script', '{}', '', '', '{}', '{}');
EOF
  fi
  if echo "SELECT * FROM task;" | /tmpRoot/bin/sqlite3 "${ESYNOSCHEDULER_DB}" | grep -q "Copy-Button-3s"; then
    echo "Copy-Button-3s task already exists"
  else
    echo "insert Copy-Button-3s task to esynoscheduler.db"
    /tmpRoot/bin/sqlite3 "${ESYNOSCHEDULER_DB}" <<EOF
DELETE FROM task WHERE task_name LIKE 'Copy-Button-3s';
INSERT INTO task VALUES('Copy-Button-3s', '', 'bootup', '', 0, 0, 0, 0, '', 0, '
# 长按 Copy 按钮 3s(Led 闪烁3次) 后松开, 将自动触发该任务.
# Press and hold the Copy button for 3 seconds (the LED flashes 3 times) and then release it to automatically trigger the task.
# 请在下面输入你需要执行的操作.
# Please enter the command you need to execute below.
echo "Copy-Button-3s."
', 'script', '{}', '', '', '{}', '{}');
EOF
  fi
  if echo "SELECT * FROM task;" | /tmpRoot/bin/sqlite3 "${ESYNOSCHEDULER_DB}" | grep -q "Copy-Button-9s"; then
    echo "Copy-Button-9s task already exists"
  else
    echo "insert Copy-Button-9s task to esynoscheduler.db"
    /tmpRoot/bin/sqlite3 "${ESYNOSCHEDULER_DB}" <<EOF
DELETE FROM task WHERE task_name LIKE 'Copy-Button-9s';
INSERT INTO task VALUES('Copy-Button-9s', '', 'bootup', '', 0, 0, 0, 0, '', 0, '
# 长按 Copy 按钮 9s(Led 闪烁3次 x 2) 后松开, 将自动触发该任务.
# Press and hold the Copy button for 3 seconds (the LED flashes 3 times x 2) and then release it to automatically trigger the task.
# 请在下面输入你需要执行的操作.
# Please enter the command you need to execute below.
echo "Copy-Button-9s."
', 'script', '{}', '', '', '{}', '{}');
EOF
  fi
  mkdir -p "/tmpRoot/usr/lib/systemd/system"
  DEST="/tmpRoot/usr/lib/systemd/system/tad6s4n10g.service"
  {
    echo "[Unit]"
    echo "Description=RR addon tad6s4n10g daemon"
    echo "After=multi-user.target"
    echo
    echo "[Service]"
    echo "Type=forking"
    echo "ExecStart=/usr/bin/tad6s4n10g.sh"
    echo "ExecReload=/usr/bin/pkill -f /usr/bin/tad6s4n10g.sh"
    echo "Restart=always"
    echo
    echo "[Install]"
    echo "WantedBy=multi-user.target"
  } >"${DEST}"

  mkdir -p /tmpRoot/usr/lib/systemd/system/multi-user.target.wants
  ln -sf /usr/lib/systemd/system/tad6s4n10g.service /tmpRoot/usr/lib/systemd/system/multi-user.target.wants/tad6s4n10g.service
elif [ "${1}" = "uninstall" ]; then
  echo "Installing addon tad6s4n10g - ${1}"

  rm -f "/tmpRoot/usr/lib/systemd/system/multi-user.target.wants/tad6s4n10g.service"
  rm -f "/tmpRoot/usr/lib/systemd/system/tad6s4n10g.service"

  rm -f /tmpRoot/usr/bin/tad6s4n10g.sh
  rm -f /tmpRoot/usr/sbin/ioperm
  rm -f /tmpRoot/usr/sbin/inb
  rm -f /tmpRoot/usr/sbin/outb

  export LD_LIBRARY_PATH=/tmpRoot/bin:/tmpRoot/lib
  ESYNOSCHEDULER_DB="/tmpRoot/usr/syno/etc/esynoscheduler/esynoscheduler.db"
  if [ -f "${ESYNOSCHEDULER_DB}" ]; then
    echo "delete beep task from esynoscheduler.db"
    CopyBtn"${ESYNOSCHEDULER_DB}" <<EOF
DELETE FROM task WHERE task_name LIKE 'Net-Button-3s';
DELETE FROM task WHERE task_name LIKE 'Net-Button-9s';
DELETE FROM task WHERE task_name LIKE 'Copy-Button-3s';
DELETE FROM task WHERE task_name LIKE 'Copy-Button-9s';
EOF
  fi
fi
