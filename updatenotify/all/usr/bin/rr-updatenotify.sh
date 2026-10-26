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
TASK_NAME="RR-UpdateNotify"

# 6.2：按任务名查 id，没有则输出空
function TaskId() {
  synoschedtask --get 2>/dev/null | awk -v n="${TASK_NAME}" '
    /^[[:space:]]*ID:/ { id = $0; gsub(/[^0-9]/, "", id) }
    index($0, "Name: [" n "]") { print id; exit }'
}

function Create() {
  if [ "${MajorVersion}" -lt 7 ]; then
    if [ -n "$(TaskId)" ]; then
      echo "Existence tasks"
      exit 0
    fi
    echo "Create tasks"
    # 6.2 的任务以 owner 身份执行（实测 owner=admin → uid 1024，无法写 /etc）。owner 可以
    # 是 root（实测 owner=root → uid 0），与 7.x 的 .Root 版本行为一致。
    RUNNER="$(synogroup --get administrators 2>/dev/null | sed -n 's/^[0-9]*:\[\(.*\)\]$/\1/p' | head -n1)"
    if [ -z "${RUNNER}" ]; then
      echo " ERROR: no administrator user found to create the task" >&2
      exit 1
    fi
    schedule='{"date_type":0,"week_day":"0,1,2,3,4,5,6","repeat_date":1001,"monthly_week":[],"hour":0,"minute":0,"repeat_hour":2,"repeat_min":0,"last_work_hour":0,"repeat_min_store_config":[1,5,10,15,20,30],"repeat_hour_store_config":[1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23]}'
    extra='{"notify_enable":false,"script":"/usr/bin/rr-updatenotify.sh","notify_mail":"","notify_if_error":false}'
    if ! synowebapi --exec api=SYNO.Core.TaskScheduler method=create version=2 runner="${RUNNER}" name="\"${TASK_NAME}\"" owner='"root"' enable=true schedule="${schedule}" extra="${extra}" type='"script"'; then
      echo " ERROR: failed to create task ${TASK_NAME}" >&2
      exit 1
    fi
    exit 0
  fi

  if grep -q '^name=RR-UpdateNotify' /usr/syno/etc/synoschedule.d/root/*.task; then
    echo "Existence tasks"
  else
    echo "Create tasks"
    schedule='{"date_type":0,"week_day":"0,1,2,3,4,5,6","repeat_date":1001,"monthly_week":[],"hour":0,"minute":0,"repeat_hour":2,"repeat_min":0,"last_work_hour":0,"repeat_min_store_config":[1,5,10,15,20,30],"repeat_hour_store_config":[1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23]}'
    extra='{"notify_enable":false,"script":"/usr/bin/rr-updatenotify.sh","notify_mail":"","notify_if_error":false}'
    synowebapi -s --exec api=SYNO.Core.TaskScheduler.Root method=create version=4 name='"RR-UpdateNotify"' owner='"root"' enable=true schedule="${schedule}" extra="${extra}" type='"script"'
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
    if grep -q '^name=RR-UpdateNotify' "${F}"; then
      id=$(grep '^id=' "${F}" | cut -d'=' -f2)
      [ -n "${id}" ] && synoschedtask --del id=${id}
    fi
  done
  exit 0
}

function Check() {
  LOCALTAG="$(cat /usr/rr/VERSION 2>/dev/null | grep LOADERVERSION | cut -d'=' -f2 | sed 's/\"//g')"
  if [ -z "${LOCALTAG}" ]; then
    echo "Unknown bootloader version!"
    exit 0
  fi

  URL="https://github.com/RROrg/rr"
  TAG=""
  if echo "$@" | grep -qE "(^|[[:space:]])\-p([[:space:]]|$)"; then
    TAG="$(curl -skL --connect-timeout 10 "${URL}/tags" | grep "/refs/tags/.*\.zip" | head -1 | sed -E 's/.*\/refs\/tags\/(.*)\.zip.*$/\1/')"
  else
    # shellcheck disable=SC1083
    TAG="$(curl -skL --connect-timeout 10 -w %{url_effective} -o /dev/null "${URL}/releases/latest" | awk -F'/' '{print $NF}')"
  fi
  [ "${TAG:0:1}" = "v" ] && TAG="${TAG:1}"
  if [ -z "${TAG}" ] || [ "${TAG}" = "latest" ]; then
    echo "Error checking new version. TAG is ${TAG}"
    exit 0
  fi
  if [ "${TAG}" = "${LOCALTAG}" ]; then
    echo "Actual version is ${TAG}"
    exit 0
  fi

  # NOTIFICATION="RR Notify"
  # synodsmnotify -e false -b false "@administrators" "rr_notify" "{\"%NOTIFICATION%\": \"${NOTIFICATION}\"}"
  # NOTIFICATION="RR Update"
  # SUBJECT="RR <a href=\\\"${URL}/releases/tag/${TAG}\\\" target=blank>${TAG}</a> version has been released!"
  # synodsmnotify -e false -b false "@administrators" "rr_notify_subject" "{\"%NOTIFICATION%\": \"${NOTIFICATION}\", \"%SUBJECT%\": \"${SUBJECT}\"}"

  NOTIFICATION="RR Relase ${TAG}"
  SUBJECT="$(curl -skL --connect-timeout 10 "${URL}/releases/tag/${TAG}" | pup 'div[data-test-selector="body-content"]')"
  SUBJECT="${SUBJECT//\"/\\\\\\\"}"
  synodsmnotify -e false -b false "@administrators" "rr_notify_subject" "{\"%NOTIFICATION%\": \"${NOTIFICATION}\", \"%SUBJECT%\": \"${SUBJECT}\"}"

  exit 0
}

ACTION="${1}"
[ -z "${ACTION}" ] && ACTION="check"

case "${ACTION,,}" in
  "create")
    Create
    ;;
  "delete")
    Delete
    ;;
  "check")
    shift
    Check "$@"
    ;;
  *)
    echo "Unknown command!"
    ;;
esac
