#!/usr/bin/env bash
#
# Copyright (C) 2022 Ing <https://github.com/wjz304>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

# DSM 版本判据：读 /etc/defaults/VERSION 的 majorversion（6.2 → 6，7.x → 7）。
# 不能用内核主版本 —— DSM 7.0~7.3 的内核同样是 4.4.x，与 6.2 的主版本相同。
MajorVersion="$(/bin/get_key_value /etc.defaults/VERSION majorversion 2>/dev/null)"
[ -n "${MajorVersion}" ] || MajorVersion="$(/bin/get_key_value /etc/VERSION majorversion 2>/dev/null)"
case "${MajorVersion}" in
  '' | *[!0-9]*)
    echo " ERROR: cannot determine DSM major version from /etc/defaults/VERSION" >&2
    exit 1
    ;;
esac

# 任务计划的存储在 6.2 与 7.x 上是两套，API 也不同：
#   6.2：/usr/syno/etc/scheduled_tasks（[id] 段文本，由它生成 /etc/crontab）；
#        API 为 SYNO.Core.TaskScheduler v2，只授权 administrators 组成员，
#        必须 `--exec runner=<管理员>`（加 -s 以 root 调用会 Create CredRequest fail）。
#   7.x：/usr/syno/etc/synoschedule.d/<owner>/*.task；
#        API 为 SYNO.Core.TaskScheduler.Root v4。
TASK_NAME="RR-UpdateHosts"

# 6.2：按任务名查 id，没有则输出空
function TaskId() {
  synoschedtask --get 2>/dev/null | awk -v n="${TASK_NAME}" '
    /^[[:space:]]*ID:/ { id = $0; gsub(/[^0-9]/, "", id) }
    index($0, "Name: [" n "]") { print id; exit }'
}

function Create() {
  schedule='{"date_type":0,"week_day":"0,1,2,3,4,5,6","repeat_date":1001,"monthly_week":[],"hour":0,"minute":0,"repeat_hour":2,"repeat_min":0,"last_work_hour":0,"repeat_min_store_config":[1,5,10,15,20,30],"repeat_hour_store_config":[1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23]}'
    extra='{"notify_enable":false,"script":"
DOMAINS=(
  www.synology.com
  find.synology.com
  account.synology.com
  kb.synology.com
  help.synology.com
  router.synology.com
  notification.synology.com
  sns.synology.com
  www-ai.synology.com
  archive.synology.com
  update7.synology.com
  pkgupdate7.synology.com
  dataautoupdate7.synology.com
  global.download.synology.com
  webec.synology.com
  fileres.synology.com
  gallery.synology.com
  synostatic.synology.com
  www.synology.cn
  find.synology.cn
  account.synology.cn
  kb.synology.cn
  archive.synology.cn
  cndl.synology.cn
  global.synologydownload.com
)

/usr/bin/rr-updatehosts.sh hosts \"${DOMAINS[@]}\"
","notify_mail":"","notify_if_error":false}'

  if [ "${MajorVersion}" -lt 7 ]; then
    if [ -n "$(TaskId)" ]; then
      echo "Existence tasks"
      exit 0
    fi
    echo "Create tasks"
    # 6.2 的任务以 owner 身份执行（实测 owner=admin → uid 1024，写 /etc/hosts 会 Permission
    # denied 而脚本仍 exit 0），所以 owner 必须是 root（实测 owner=root → uid 0），与 7.x 一致。
    RUNNER="$(synogroup --get administrators 2>/dev/null | sed -n 's/^[0-9]*:\[\(.*\)\]$/\1/p' | head -n1)"
    if [ -z "${RUNNER}" ]; then
      echo " ERROR: no administrator user found to create the task" >&2
      exit 1
    fi
    if ! synowebapi --exec api=SYNO.Core.TaskScheduler method=create version=2 runner="${RUNNER}" name="\"${TASK_NAME}\"" owner='"root"' enable=true schedule="${schedule}" extra="${extra}" type='"script"'; then
      echo " ERROR: failed to create task ${TASK_NAME}" >&2
      exit 1
    fi
    exit 0
  fi

  if grep -q '^name=RR-UpdateHosts' /usr/syno/etc/synoschedule.d/root/*.task; then
    echo "Existence tasks"
  else
    echo "Create tasks"
    synowebapi -s --exec api=SYNO.Core.TaskScheduler.Root method=create version=4 name='"RR-UpdateHosts"' owner='"root"' enable=true schedule="${schedule}" extra="${extra}" type='"script"'
  fi
  exit 0
}

function Delete() {
  if [ "${MajorVersion}" -lt 7 ]; then
    ID="$(TaskId)"
    [ -n "${ID}" ] && synoschedtask --del id="${ID}"
    exit 0
  fi
  for F in $(LC_ALL=C printf '%s\n' /usr/syno/etc/synoschedule.d/root/*.task | sort -V); do
    [ ! -e "${F}" ] && continue
    if grep -q '^name=RR-UpdateHosts' "${F}"; then
      id=$(grep '^id=' "${F}" | cut -d'=' -f2)
      [ -n "${id}" ] && synoschedtask --del id=${id}
    fi
  done
  exit 0
}

function Hosts() {
  echo "Update hosts..."

  _resolve() {
    local DOMAIN="${1}"
    local IP=""
    [ -z "${DOMAIN}" ] && return 1
    # LC_ALL=C ping -c 1 -W 1 "${DOMAIN}" >/dev/null 2>&1 && return 0
    # Try Cloudflare DoH
    [ -z "${IP}" ] && IP="$(curl -skL --connect-timeout 5 "https://cloudflare-dns.com/dns-query?name=${DOMAIN}&type=A" -H "accept: application/dns-json" 2>/dev/null | jq -r '.Answer[]? | select(.type == 1) | .data' 2>/dev/null | head -1)"
    # Try Google DoH
    [ -z "${IP}" ] && IP="$(curl -skL --connect-timeout 5 "https://dns.google/resolve?name=${DOMAIN}&type=A" 2>/dev/null | jq -r '.Answer[]? | select(.type == 1) | .data' 2>/dev/null | head -1)"
    # Try AliDNS DoH
    [ -z "${IP}" ] && IP="$(curl -skL --connect-timeout 5 "https://dns.alidns.com/resolve?name=${DOMAIN}&type=A" 2>/dev/null | jq -r '.Answer[]? | select(.type == 1) | .data' 2>/dev/null | head -1)"
    [ -n "${IP}" ] && printf '%- 16s%s\n' "${IP}" "${DOMAIN}"
    return 0
  }

  data=()
  data+=("# RR Hosts Start")
  for D in "${@}"; do
    STR="$(_resolve "${D}" 2>/dev/null)"
    [ -n "${STR}" ] && data+=("${STR}")
  done
  data+=("# RR Hosts End")

  sed -i '/# RR Hosts Start/,/# RR Hosts End/d' /etc/hosts
  [ -n "$(tail -n 1 /etc/hosts)" ] && printf '\n' >>/etc/hosts # # Add new line at the end of /etc/hosts if it doesn't already have one
  printf '%s\n' "${data[@]}" >>/etc/hosts

  exit 0
}

ACTION="${1}"
[ -z "${ACTION}" ] && ACTION="hosts"

case "${ACTION,,}" in
  "create")
    Create
    ;;
  "delete")
    Delete
    ;;
  "hosts")
    shift
    Hosts "$@"
    ;;
  *)
    echo "Unknown command!"
    ;;
esac
