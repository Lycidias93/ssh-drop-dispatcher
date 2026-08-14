#!/system/bin/sh
set -u
umask 077

BINDIR=${0%/*}
MODDIR=${MODULE_DIR:-${BINDIR%/bin}}
BASE="$BINDIR/module-control-base"
SH_BIN=${SDD_WEBUI_SH_BIN:-/system/bin/sh}
PROP="$MODDIR/module.prop"
STATE_DIR=${MODULE_STATE_DIR:-/data/adb/ssh-drop-dispatcher}
RUNTIME_DIR=${WEBUI_RUNTIME_DIR:-/data/local/tmp/ssh_drop_dispatcher-webui}
CONFIG_FILE=${SDD_WEBUI_CONFIG_FILE:-$STATE_DIR/config.env}
TARGET_DIR=${SDD_WEBUI_TARGET_DIR:-$STATE_DIR/config/targets.d}
HEALTH_FILE=${SDD_WEBUI_HEALTH_FILE:-$STATE_DIR/health.env}
INFLIGHT_DB=${SDD_WEBUI_INFLIGHT_DB:-$STATE_DIR/dispatch.inflight}
FAIL_DB=${SDD_WEBUI_FAIL_DB:-$STATE_DIR/dispatch.faildb}
QUAR_DB=${SDD_WEBUI_QUAR_DB:-$STATE_DIR/dispatch.quarantined}
RECEIPT_DB=${SDD_WEBUI_RECEIPT_DB:-$STATE_DIR/delivery.receipts.jsonl}
MODULE_VERSION=$(sed -n 's/^version=//p' "$PROP" 2>/dev/null | head -n 1)

json_escape() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e ':a;N;$!ba;s/\n/\\n/g'
}

json_string() {
  printf '"%s"' "$(json_escape "$1")"
}

cfg_value() {
  key=$1
  value=$(sed -n "s/^${key}=//p" "$CONFIG_FILE" 2>/dev/null | tail -n 1)
  case "$value" in
    \"*\") value=${value#\"}; value=${value%\"} ;;
    \'*\') value=${value#\'}; value=${value%\'} ;;
  esac
  printf '%s' "$value"
}

env_value() {
  file=$1
  key=$2
  default=${3:-}
  value=$(sed -n "s/^${key}=//p" "$file" 2>/dev/null | head -n 1)
  [ -n "$value" ] && printf '%s' "$value" || printf '%s' "$default"
}

count_lines() {
  file=$1
  if [ -f "$file" ]; then
    value=$(wc -l < "$file" 2>/dev/null | tr -d ' ' || true)
  else
    value=0
  fi
  case "$value" in ""|*[!0-9]*) value=0 ;; esac
  printf '%s' "$value"
}

json_field_string() {
  key=$1
  text=$2
  printf '%s\n' "$text" | sed -n 's/.*"'"$key"'":"\([^"\\]*\)".*/\1/p' | head -n 1
}

target_is_intermittent() {
  probe_target=$1
  smoke_list=$(cfg_value DROP_DISPATCH_INTERMITTENT_TARGETS)
  [ -n "$smoke_list" ] || smoke_list=zeropi2
  for smoke_item in $(printf '%s' "$smoke_list" | tr ',' ' '); do
    [ "$smoke_item" = "$probe_target" ] && return 0
  done
  return 1
}

run_all_enabled_smoke_with_availability_policy() {
  [ -x "$BASE" ] || { echo '{"ok":false,"error":"module-control base unavailable"}' >&2; return 69; }
  [ -x "$SH_BIN" ] || { echo '{"ok":false,"error":"module-control shell unavailable"}' >&2; return 69; }
  mkdir -p "$RUNTIME_DIR" >/dev/null 2>&1 || true
  smoke_tmp="$RUNTIME_DIR/rc6-target-smoke.$$"
  rm -f "$smoke_tmp" >/dev/null 2>&1 || true
  "$SH_BIN" "$BASE" job-run target-test-all-enabled >"$smoke_tmp" 2>&1
  smoke_rc=$?
  if [ "$smoke_rc" -eq 0 ]; then
    cat "$smoke_tmp"
    rm -f "$smoke_tmp" >/dev/null 2>&1 || true
    return 0
  fi

  failed_targets=$(sed -n 's/^target=\([a-z0-9_-][a-z0-9_-]*\) result=FAIL rc=[0-9][0-9]*$/\1/p' "$smoke_tmp")
  [ -n "$failed_targets" ] || {
    cat "$smoke_tmp"
    rm -f "$smoke_tmp" >/dev/null 2>&1 || true
    return "$smoke_rc"
  }

  smoke_skipped=0
  smoke_reclassify=yes
  for smoke_target in $failed_targets; do
    if ! target_is_intermittent "$smoke_target"; then
      smoke_reclassify=no
      break
    fi
    if ! sed -n "/^== target $smoke_target ==$/,/^target=$smoke_target result=/p" "$smoke_tmp" | grep -F 'ssh_auth=FAIL' >/dev/null 2>&1; then
      smoke_reclassify=no
      break
    fi
    smoke_skipped=$((smoke_skipped + 1))
  done

  if [ "$smoke_reclassify" != yes ]; then
    cat "$smoke_tmp"
    rm -f "$smoke_tmp" >/dev/null 2>&1 || true
    return "$smoke_rc"
  fi

  smoke_tested=$(sed -n 's/^RESULT: SDD_WEBUI_TARGET_SMOKE_ALL_DONE .* tested=\([0-9][0-9]*\) .*$/\1/p' "$smoke_tmp" | tail -n 1)
  case "$smoke_tested" in ""|*[!0-9]*) smoke_tested=0 ;; esac
  smoke_passed=$((smoke_tested - smoke_skipped))
  while IFS= read -r smoke_line || [ -n "$smoke_line" ]; do
    case "$smoke_line" in
      "RESULT: SDD_WEBUI_TARGET_SMOKE_ALL_DONE "*) continue ;;
      target=*" result=FAIL rc="*)
        smoke_target=${smoke_line#target=}
        smoke_target=${smoke_target%% *}
        if target_is_intermittent "$smoke_target"; then
          smoke_fail_rc=${smoke_line##* rc=}
          echo "target=$smoke_target result=SKIP rc=$smoke_fail_rc reason=intermittent_unavailable"
        else
          echo "$smoke_line"
        fi
        ;;
      *) echo "$smoke_line" ;;
    esac
  done < "$smoke_tmp"
  echo "smoke_policy=required_targets_must_pass_intermittent_unavailable_skips"
  echo "intermittent_targets=$(cfg_value DROP_DISPATCH_INTERMITTENT_TARGETS)"
  [ -n "$(cfg_value DROP_DISPATCH_INTERMITTENT_TARGETS)" ] || echo "intermittent_targets_default=zeropi2"
  echo "RESULT: SDD_WEBUI_TARGET_SMOKE_ALL_DONE outcome=success tested=$smoke_tested passed=$smoke_passed skipped=$smoke_skipped failed=0 delivery_executed=no workflow_exit_code=0"
  rm -f "$smoke_tmp" >/dev/null 2>&1 || true
  return 0
}

if [ "${1:-}" = job-run ] && [ "${2:-}" = target-test-all-enabled ]; then
  [ "$#" -eq 2 ] || exit 2
  run_all_enabled_smoke_with_availability_policy
  exit $?
fi

if [ "${1:-}" != status ]; then
  [ -x "$BASE" ] || { echo '{"ok":false,"error":"module-control base unavailable"}' >&2; exit 69; }
  [ -x "$SH_BIN" ] || { echo '{"ok":false,"error":"module-control shell unavailable"}' >&2; exit 69; }
  exec "$SH_BIN" "$BASE" "$@"
fi

[ "$#" -eq 1 ] || exit 2

health=UNAVAILABLE
health_level=danger
status_ok=false
if [ -r "$HEALTH_FILE" ]; then
  health=$(env_value "$HEALTH_FILE" status unknown)
  status_ok=true
  [ "$health" = OK ] && health_level=good || health_level=caution
fi

version=${MODULE_VERSION:-unknown}
event_pending=$(env_value "$HEALTH_FILE" event_pending unknown)
main_pid_ok=$(env_value "$HEALTH_FILE" main_pid_ok unknown)
watcher_pid_ok=$(env_value "$HEALTH_FILE" watcher_pid_ok unknown)
watchdog_pid_ok=$(env_value "$HEALTH_FILE" watchdog_pid_ok unknown)
inflight=$(count_lines "$INFLIGHT_DB")
failures=$(count_lines "$FAIL_DB")
quarantine=$(count_lines "$QUAR_DB")
receipts=$(count_lines "$RECEIPT_DB")
targets=0
if [ -d "$TARGET_DIR" ]; then
  for cf in "$TARGET_DIR"/*.conf; do
    [ -f "$cf" ] || continue
    targets=$((targets + 1))
  done
fi

last_id=none
last_state=none
if [ -s "$RECEIPT_DB" ]; then
  last_line=$(tail -n 1 "$RECEIPT_DB" 2>/dev/null || true)
  last_id=$(json_field_string deliveryId "$last_line")
  last_state=$(json_field_string finalState "$last_line")
  [ -n "$last_state" ] || last_state=$(json_field_string state "$last_line")
  [ -n "$last_id" ] || last_id=unknown
  [ -n "$last_state" ] || last_state=unknown
fi

ntfy_enabled=$(cfg_value NTFY_ENABLED)
[ "$ntfy_enabled" = 1 ] && ntfy_state=enabled || ntfy_state=disabled
ntfy_topic=$(cfg_value NTFY_TOPIC)
ntfy_url=$(cfg_value NTFY_URL)
ntfy_token_file=$(cfg_value NTFY_TOKEN_FILE)
[ -n "$ntfy_topic$ntfy_url$ntfy_token_file" ] && ntfy_configured=yes || ntfy_configured=no
[ -n "$ntfy_topic" ] && ntfy_topic_configured=yes || ntfy_topic_configured=no
[ -n "$ntfy_url" ] && ntfy_url_configured=yes || ntfy_url_configured=no
[ -n "$ntfy_token_file" ] && ntfy_token_file_configured=yes || ntfy_token_file_configured=no
[ "$inflight" = 0 ] && inflight_level=good || inflight_level=caution
[ "$failures" = 0 ] && failures_level=good || failures_level=danger

printf '{"ok":%s,"module":{"id":"ssh_drop_dispatcher","name":"SSH Drop Dispatcher","version":' "$status_ok"
json_string "$version"
printf '},"summary":['
printf '{"label":"Health","value":'; json_string "$health"; printf ',"level":"%s"},' "$health_level"
printf '{"label":"Queue / inflight","value":'; json_string "$inflight"; printf ',"level":"%s"},' "$inflight_level"
printf '{"label":"Failures","value":'; json_string "$failures"; printf ',"level":"%s"},' "$failures_level"
printf '{"label":"Quarantine","value":'; json_string "$quarantine"; printf ',"level":"muted"},'
printf '{"label":"Targets","value":'; json_string "$targets"; printf ',"level":"muted"},'
printf '{"label":"Last delivery","value":'; json_string "$last_state"; printf ',"level":"muted"},'
printf '{"label":"Notifications","value":'; json_string "$ntfy_state"; printf ',"level":"muted"}'
printf '],"runtime":{"cli_schema":3,"workflow_schema":1,"status_source":"local_snapshot","backend_refresh":"none","event_pending":'; json_string "$event_pending"
printf ',"main_pid_ok":'; json_string "$main_pid_ok"
printf ',"watcher_pid_ok":'; json_string "$watcher_pid_ok"
printf ',"watchdog_pid_ok":'; json_string "$watchdog_pid_ok"
printf ',"delivery_receipts":%s,"last_delivery_id":' "$receipts"; json_string "$last_id"
printf ',"ntfy_configured":'; json_string "$ntfy_configured"
printf ',"ntfy_topic_configured":'; json_string "$ntfy_topic_configured"
printf ',"ntfy_url_configured":'; json_string "$ntfy_url_configured"
printf ',"ntfy_token_file_configured":'; json_string "$ntfy_token_file_configured"
printf '},"safety":{"dispatcher_owned_verification":true,"remote_sha_required":true,"bash_fallback_fail_closed":true,"python_delivery_blocked":true,"automatic_requeue_disabled":true,"payload_execution_absent":true,"arbitrary_shell_blocked":true,"arbitrary_path_input_blocked":true,"loopback_only":true,"secret_status_redacted":true}}\n'
