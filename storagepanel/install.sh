#!/usr/bin/env sh
#
# Copyright (C) 2022 Ing <https://github.com/wjz304>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

# DSM 版本判据：读 /etc/defaults/VERSION 的 majorversion（6.2 → 6，7.x → 7）。
# 不能用内核主版本 —— DSM 7.0~7.3 的内核同样是 4.4.x（4.4.180 / 4.4.302），与 6.2 的
# 4.4.59 / 3.10.105 主版本相同，用内核主版本会把整个 7.x 误判成 6.2。
MajorVersion="$(/bin/get_key_value /etc.defaults/VERSION majorversion 2>/dev/null)"
# 兜底：万一某个 ramdisk 没有 /etc.defaults/VERSION，用 /etc/VERSION（两者在 6.2 里内容相同）。
[ -n "${MajorVersion}" ] || MajorVersion="$(/bin/get_key_value /etc/VERSION majorversion 2>/dev/null)"
case "${MajorVersion}" in
  '' | *[!0-9]*)
    echo " ERROR: cannot determine DSM major version from /etc.defaults/VERSION" >&2
    exit 1
    ;;
esac

if [ "${1}" = "late" ]; then
  # storagepanel 改的是 Storage Manager 的 storage_panel.js（盘位图），该文件是 DSM 7.0
  # 重写存储管理器之后才有的。DSM 6.2 的存储管理器只有 ExtJS 的 storage.js（页面：总览 /
  # HDD-SSD / 存储池 / 外接设备），主机自身没有盘位图 —— 6.2 唯一的盘位图在「外接设备」页
  # （StorageOverview.Main，数据来自 SYNO.Storage.CGI.Enclosure），布局模型是
  # hddCount + hddLayout 数组，与 7.x 的 RACK_xx_Bay / driveShape 完全不是一套。
  # 上游 RR 24.4.0（最后一个支持 6.2 的版本）的 storagepanel 也只认 storage_panel.js，
  # 在 6.2 上直接 exit 0，所以这不是我们引入的回归。
  #
  # 实测（DSM 6.2.4-25556u8 / bj3_dsm）：脚本能跑，但输出
  #   "/usr/syno/synoman/webman/modules/StorageManager/storage_panel.js.gz file does not exist"
  # 每次启动空跑一次。这里直接跳过，并清掉旧版本（26.10.12 及之前没有 6.2 判断）留在 DSM
  # 根上的无效 unit / 脚本，避免 6.x 每次开机都白跑。
  if [ "${MajorVersion}" -lt 7 ]; then
    echo "storagepanel addon is not supported on DSM ${MajorVersion}.x (Storage Panel UI / storage_panel.js only exists on DSM 7.0+), skipped"
    rm -f /tmpRoot/usr/lib/systemd/system/multi-user.target.wants/storagepanel.service
    rm -f /tmpRoot/usr/lib/systemd/system/storagepanel.service
    rm -f /tmpRoot/usr/bin/storagepanel.sh
    exit 0
  fi

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
