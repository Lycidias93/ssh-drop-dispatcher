#!/system/bin/sh
set -u

STATE_DIR=${SDD_STATE_DIR:-/data/adb/ssh-drop-dispatcher}
MODDIR=${SDD_MODDIR:-/data/adb/modules/ssh_drop_dispatcher}
SERVICE=${SDD_SERVICE:-$MODDIR/service.sh}
TARGET_DIR=${SDD_TARGET_DIR:-$STATE_DIR/config/targets.d}
CONFIG_FILE=${SDD_CONFIG_FILE:-$STATE_DIR/config.env}
LOG_FILE=${SDD_LOG_FILE:-$STATE_DIR/log/dispatch.log}
FORMAT=${SDD_FORMAT:-env}
DONE_DB=$STATE_DIR/dispatch.done
COMPLETE_DB=$STATE_DIR/dispatch.complete
FAIL_DB=$STATE_DIR/dispatch.faildb
INFLIGHT_DB=$STATE_DIR/dispatch.inflight
QUAR_DB=$STATE_DIR/dispatch.quarantined
RECEIPT_DB=$STATE_DIR/delivery.receipts.jsonl
WORKFLOW_SCHEMA=1
RECEIPT_SCHEMA=1
INCIDENT_SCHEMA=1
SELF_DIR=${0%/*}
[ -f "$SELF_DIR/sdd-lib.sh" ] || SELF_DIR=$STATE_DIR/tools
. "$SELF_DIR/sdd-lib.sh"

usage(){
  cat <<'EOF_USAGE'
SSH Drop Dispatcher workflow v3
Usage: sdd-workflow.sh trace <file|delivery-id>
       sdd-workflow.sh queue [limit]
       sdd-workflow.sh failures [limit]
       sdd-workflow.sh quarantine [limit]
       sdd-workflow.sh inspect <file|delivery-id>
       sdd-workflow.sh preflight <file>
       sdd-workflow.sh dispatch-file <file> [timeout] [interval]
       sdd-workflow.sh incident [file|delivery-id]
EOF_USAGE
}

scan_dir(){ env_field "$CONFIG_FILE" DROP_DISPATCH_SCAN_DIR /storage/emulated/0/Download; }
resolve_file(){ case "$1" in /*) printf '%s' "$1" ;; *) printf '%s/%s' "$(scan_dir)" "$1" ;; esac; }
base_name(){ printf '%s' "$1" | sed 's#^.*/##'; }

is_partial_name(){ case "$1" in *.part|*.partial|*.tmp|*.crdownload|*.download|*.opdownload|*.aria2|*.swp|*.lock) return 0;; *) return 1;; esac; }
is_sidecar_name(){ case "$1" in *.sha256|*.sha256sum|*.md5|*.sig|*.asc) return 0;; *) return 1;; esac; }
is_supported_name(){
  is_sidecar_name "$1" && return 1
  case "$1" in *.sh|*.zip|*.tar|*.tar.gz|*.tgz|*.tar.xz|*.txz|*.tar.bz2|*.tbz|*.tbz2|*.gz|*.xz|*.bz2|*.log|*.txt|*.md|*.json|*.conf|*.env) return 0;; *) return 1;; esac
}

record_for_file(){
  f=$1
  [ -f "$f" ] || return 1
  pair=$(cksum "$f" 2>/dev/null | while read -r crc bytes rest; do printf '%s:%s' "$crc" "$bytes"; done)
  [ -n "$pair" ] || return 1
  printf '%s|%s' "$(base_name "$f")" "$pair"
}

record_sha256(){
  rec=$1
  if command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$rec" | sha256sum | awk '{print $1}'
  elif [ -x /system/bin/toybox ] && /system/bin/toybox --list 2>/dev/null | grep -qx sha256sum; then
    printf '%s' "$rec" | /system/bin/toybox sha256sum | awk '{print $1}'
  else
    return 1
  fi
}

delivery_id_from_record(){
  rec=$1
  digest=$(record_sha256 "$rec" 2>/dev/null || true)
  printf '%s' "$digest" | grep -Eq '^[0-9a-fA-F]{64}$' || return 1
  short=$(printf '%s' "$digest" | sed 's/^\(.\{16\}\).*/\1/')
  printf 'SDD-%s' "$short"
}

record_from_delivery_id(){
  id=$1
  printf '%s' "$id" | grep -Eq '^SDD-[0-9a-fA-F]{16}$' || return 1
  for db in "$COMPLETE_DB" "$DONE_DB" "$INFLIGHT_DB" "$QUAR_DB" "$FAIL_DB"; do
    [ -f "$db" ] || continue
    while IFS= read -r line || [ -n "$line" ]; do
      [ -n "$line" ] || continue
      rec=$(printf '%s' "$line" | sed 's/|target=.*//;s/|reason=.*//;s/|policy=.*//')
      [ -n "$rec" ] || continue
      [ "$(delivery_id_from_record "$rec" 2>/dev/null || true)" = "$id" ] && { printf '%s' "$rec"; return 0; }
    done < "$db"
  done
  dir=$(scan_dir)
  if [ -d "$dir" ]; then
    for f in "$dir"/*; do
      [ -f "$f" ] || continue
      rec=$(record_for_file "$f" 2>/dev/null || true)
      [ -n "$rec" ] || continue
      [ "$(delivery_id_from_record "$rec" 2>/dev/null || true)" = "$id" ] && { printf '%s' "$rec"; return 0; }
    done
  fi
  return 1
}

record_from_base_history(){
  base=$1
  for db in "$COMPLETE_DB" "$DONE_DB" "$INFLIGHT_DB" "$QUAR_DB" "$FAIL_DB"; do
    [ -f "$db" ] || continue
    line=$(grep -F "$base|" "$db" 2>/dev/null | tail -n 1 || true)
    if [ -n "$line" ]; then
      printf '%s' "$line" | sed 's/|target=.*//;s/|reason=.*//;s/|policy=.*//'
      return 0
    fi
  done
  return 1
}

set_trace_identity(){
  in=$1
  TRACE_INPUT=$in
  TRACE_FILE=
  TRACE_BASE=
  TRACE_REC=
  TRACE_ID=
  TRACE_LOCAL_EXISTS=no
  case "$in" in
    SDD-*)
      TRACE_ID=$in
      TRACE_REC=$(record_from_delivery_id "$in" 2>/dev/null || true)
      [ -n "$TRACE_REC" ] || return 1
      TRACE_BASE=${TRACE_REC%%|*}
      TRACE_FILE=$(resolve_file "$TRACE_BASE")
      ;;
    *)
      TRACE_FILE=$(resolve_file "$in")
      TRACE_BASE=$(base_name "$TRACE_FILE")
      if [ -f "$TRACE_FILE" ]; then
        TRACE_LOCAL_EXISTS=yes
        TRACE_REC=$(record_for_file "$TRACE_FILE" 2>/dev/null || true)
      else
        TRACE_REC=$(record_from_base_history "$TRACE_BASE" 2>/dev/null || true)
      fi
      [ -n "$TRACE_REC" ] || return 1
      TRACE_ID=$(delivery_id_from_record "$TRACE_REC" 2>/dev/null || true)
      ;;
  esac
  [ -f "$TRACE_FILE" ] && TRACE_LOCAL_EXISTS=yes || true
  return 0
}

route_targets(){
  in=$1
  [ -x "$SERVICE" ] || return 69
  "$SERVICE" --route-explain "$in" 2>/dev/null | sed -n 's/^targets=//p' | sed -n '1p'
}

record_has_exact(){ rec=$1; db=$2; [ -f "$db" ] && grep -Fqx "$rec" "$db" 2>/dev/null; }
record_has_any(){ rec=$1; db=$2; [ -f "$db" ] && grep -F "$rec" "$db" >/dev/null 2>&1; }
record_target_done(){ rec=$1; target=$2; [ -f "$DONE_DB" ] && grep -Fqx "$rec|target=$target" "$DONE_DB" 2>/dev/null; }
record_target_quarantine_line(){ rec=$1; target=$2; [ -f "$QUAR_DB" ] && grep -F "$rec|target=$target|reason=" "$QUAR_DB" 2>/dev/null | tail -n 1; }
record_target_inflight(){ rec=$1; target=$2; [ -f "$INFLIGHT_DB" ] && grep -Fqx "$rec|target=$target" "$INFLIGHT_DB" 2>/dev/null; }

record_state(){
  rec=$1
  if record_has_exact "$rec" "$COMPLETE_DB"; then printf complete; return; fi
  if record_has_any "$rec" "$INFLIGHT_DB"; then printf inflight; return; fi
  if record_has_any "$rec" "$QUAR_DB"; then printf quarantined; return; fi
  if record_has_any "$rec" "$DONE_DB"; then printf partial_done; return; fi
  if record_has_any "$rec" "$FAIL_DB"; then printf failed; return; fi
  printf pending
}

redact_line(){
  sed -E \
    -e 's/[0-9]{1,3}(\.[0-9]{1,3}){3}/<redacted-ip>/g' \
    -e 's/(host=)[^ ]+/\1<redacted-host>/g' \
    -e 's/(remote_drop=)[^ ]+/\1<redacted>/g' \
    -e 's/(path=)[^ ]+/\1<redacted>/g' \
    -e 's/(IdentityFile[[:space:]]+)[^ ]+/\1<redacted>/g'
}

safe_limit(){
  n=${1:-20}
  case "$n" in ''|*[!0-9]*) n=20;; esac
  [ "$n" -lt 1 ] 2>/dev/null && n=1
  [ "$n" -gt 200 ] 2>/dev/null && n=200
  printf '%s' "$n"
}

trace_env(){
  in=$1
  set_trace_identity "$in" || { echo "schema=SDD_DELIVERY_TRACE_V1"; echo "trace=FAIL"; echo "reason=delivery_identity_not_found"; echo "host_run=no"; echo "RESULT: SDD_DELIVERY_TRACE_DONE outcome=fail exit_code=1"; return 1; }
  targets=$(route_targets "$TRACE_FILE" 2>/dev/null || true)
  state=$(record_state "$TRACE_REC")
  echo "schema=SDD_DELIVERY_TRACE_V1"
  echo "delivery_id=$TRACE_ID"
  echo "file=$TRACE_BASE"
  echo "local_exists=$TRACE_LOCAL_EXISTS"
  echo "record=$TRACE_REC"
  echo "targets=$targets"
  echo "state=$state"
  echo "host_run=no"
  for t in $targets; do
    if record_target_done "$TRACE_REC" "$t"; then
      echo "target=$t state=done"
    elif record_target_inflight "$TRACE_REC" "$t"; then
      echo "target=$t state=inflight"
    else
      q=$(record_target_quarantine_line "$TRACE_REC" "$t" 2>/dev/null || true)
      if [ -n "$q" ]; then
        reason=$(printf '%s' "$q" | sed -n 's/.*|reason=\([^|]*\).*/\1/p')
        echo "target=$t state=quarantined reason=${reason:-unknown}"
      else
        echo "target=$t state=pending"
      fi
    fi
  done
  recent=$(grep -F "file=$TRACE_BASE" "$LOG_FILE" 2>/dev/null | tail -n 20 | redact_line || true)
  [ -n "$recent" ] && { echo "recent_log_begin"; printf '%s\n' "$recent"; echo "recent_log_end"; }
  echo "RESULT: SDD_DELIVERY_TRACE_DONE outcome=success exit_code=0"
}

trace_json(){
  in=$1
  set_trace_identity "$in" || { printf '{"schema":"SDD_DELIVERY_TRACE_V1","outcome":"fail","reason":"delivery_identity_not_found","hostRun":false}\n'; return 1; }
  targets=$(route_targets "$TRACE_FILE" 2>/dev/null || true)
  state=$(record_state "$TRACE_REC")
  printf '{"schema":"SDD_DELIVERY_TRACE_V1","deliveryId":'; json_string "$TRACE_ID"; printf ',"file":'; json_string "$TRACE_BASE"; printf ',"localExists":'; [ "$TRACE_LOCAL_EXISTS" = yes ] && printf true || printf false
  printf ',"record":'; json_string "$TRACE_REC"; printf ',"state":'; json_string "$state"; printf ',"hostRun":false,"targets":['
  first=1
  for t in $targets; do
    [ "$first" = 1 ] || printf ','; first=0
    tstate=pending; reason=
    if record_target_done "$TRACE_REC" "$t"; then tstate=done
    elif record_target_inflight "$TRACE_REC" "$t"; then tstate=inflight
    else
      q=$(record_target_quarantine_line "$TRACE_REC" "$t" 2>/dev/null || true)
      if [ -n "$q" ]; then tstate=quarantined; reason=$(printf '%s' "$q" | sed -n 's/.*|reason=\([^|]*\).*/\1/p'); fi
    fi
    printf '{"name":'; json_string "$t"; printf ',"state":'; json_string "$tstate"; [ -n "$reason" ] && { printf ',"reason":'; json_string "$reason"; }; printf '}'
  done
  printf '],"outcome":"success"}\n'
}

trace(){ if [ "$FORMAT" = json ]; then trace_json "$1"; else trace_env "$1"; fi; }

queue_items(){
  limit=$(safe_limit "${1:-20}")
  dir=$(scan_dir)
  count=0
  [ -d "$dir" ] || return 0
  for f in "$dir"/*; do
    [ -f "$f" ] || continue
    base=$(base_name "$f")
    is_partial_name "$base" && continue
    is_supported_name "$base" || continue
    targets=$(route_targets "$f" 2>/dev/null || true)
    [ -n "$targets" ] || continue
    rec=$(record_for_file "$f" 2>/dev/null || true)
    [ -n "$rec" ] || continue
    record_has_exact "$rec" "$COMPLETE_DB" && continue
    state=$(record_state "$rec")
    [ "$state" = quarantined ] && continue
    printf '%s\t%s\t%s\t%s\n' "$(delivery_id_from_record "$rec")" "$base" "$state" "$targets"
    count=$((count+1))
    [ "$count" -ge "$limit" ] && break
  done
}

queue_cmd(){
  limit=$(safe_limit "${1:-20}")
  items=$(queue_items "$limit")
  tab=$(printf '\t')
  if [ "$FORMAT" = json ]; then
    printf '{"schema":"SDD_QUEUE_V1","hostRun":false,"items":['; first=1
    printf '%s\n' "$items" | while IFS="$tab" read -r id file state targets; do
      [ -n "$id" ] || continue
      [ "$first" = 1 ] || printf ','; first=0
      printf '{"deliveryId":'; json_string "$id"; printf ',"file":'; json_string "$file"; printf ',"state":'; json_string "$state"; printf ',"targets":'; json_string "$targets"; printf '}'
    done
    printf ']}\n'
  else
    echo "schema=SDD_QUEUE_V1"; echo "host_run=no"
    [ -n "$items" ] && printf '%s\n' "$items" | while IFS="$tab" read -r id file state targets; do [ -n "$id" ] && echo "delivery_id=$id file=$file state=$state targets=$targets"; done
    echo "RESULT: SDD_QUEUE_DONE outcome=success exit_code=0"
  fi
}

failures_cmd(){
  limit=$(safe_limit "${1:-20}")
  lines=$(grep ' FAIL ' "$LOG_FILE" 2>/dev/null | tail -n "$limit" | redact_line || true)
  if [ "$FORMAT" = json ]; then
    printf '{"schema":"SDD_FAILURES_V1","hostRun":false,"failDbRecords":%s,"entries":[' "$(count_lines "$FAIL_DB")"; first=1
    printf '%s\n' "$lines" | while IFS= read -r line; do [ -n "$line" ] || continue; [ "$first" = 1 ] || printf ','; first=0; json_string "$line"; done
    printf ']}\n'
  else
    echo "schema=SDD_FAILURES_V1"; echo "host_run=no"; echo "faildb_records=$(count_lines "$FAIL_DB")"
    [ -n "$lines" ] && printf '%s\n' "$lines"
    echo "RESULT: SDD_FAILURES_DONE outcome=success exit_code=0"
  fi
}

quarantine_cmd(){
  limit=$(safe_limit "${1:-20}")
  lines=$(tail -n "$limit" "$QUAR_DB" 2>/dev/null || true)
  if [ "$FORMAT" = json ]; then
    printf '{"schema":"SDD_QUARANTINE_V1","hostRun":false,"totalRecords":%s,"entries":[' "$(count_lines "$QUAR_DB")"; first=1
    printf '%s\n' "$lines" | while IFS= read -r line; do [ -n "$line" ] || continue; [ "$first" = 1 ] || printf ','; first=0; json_string "$line"; done
    printf ']}\n'
  else
    echo "schema=SDD_QUARANTINE_V1"; echo "host_run=no"; echo "total_records=$(count_lines "$QUAR_DB")"
    [ -n "$lines" ] && printf '%s\n' "$lines"
    echo "RESULT: SDD_QUARANTINE_DONE outcome=success exit_code=0"
  fi
}

preflight_collect(){
  in=$1
  PREFLIGHT_FILE=$(resolve_file "$in")
  PREFLIGHT_BASE=$(base_name "$PREFLIGHT_FILE")
  PREFLIGHT_REC=
  PREFLIGHT_ID=
  PREFLIGHT_TARGETS=
  PREFLIGHT_OUTCOME=READY
  PREFLIGHT_REASON=ready
  PREFLIGHT_HOST_RUN=no
  PREFLIGHT_TARGET_RESULTS=

  [ -f "$PREFLIGHT_FILE" ] || { PREFLIGHT_OUTCOME=BLOCKED; PREFLIGHT_REASON=local_file_missing; return 1; }
  is_partial_name "$PREFLIGHT_BASE" && { PREFLIGHT_OUTCOME=BLOCKED; PREFLIGHT_REASON=partial_file; return 1; }
  is_supported_name "$PREFLIGHT_BASE" || { PREFLIGHT_OUTCOME=BLOCKED; PREFLIGHT_REASON=unsupported_file; return 1; }
  config_lint_rc || { PREFLIGHT_OUTCOME=BLOCKED; PREFLIGHT_REASON=config_lint_failed; return 1; }
  PREFLIGHT_REC=$(record_for_file "$PREFLIGHT_FILE" 2>/dev/null || true)
  [ -n "$PREFLIGHT_REC" ] || { PREFLIGHT_OUTCOME=BLOCKED; PREFLIGHT_REASON=record_failed; return 1; }
  PREFLIGHT_ID=$(delivery_id_from_record "$PREFLIGHT_REC" 2>/dev/null || true)
  PREFLIGHT_TARGETS=$(route_targets "$PREFLIGHT_FILE" 2>/dev/null || true)
  [ -n "$PREFLIGHT_TARGETS" ] || { PREFLIGHT_OUTCOME=BLOCKED; PREFLIGHT_REASON=no_targets; return 1; }
  enabled=$(env_field "$CONFIG_FILE" DROP_DISPATCH_ENABLED 1)
  case "$enabled" in 0|no|NO|false|FALSE|off|OFF) PREFLIGHT_OUTCOME=BLOCKED; PREFLIGHT_REASON=dispatcher_disabled; return 1;; esac

  if [ "${PREFLIGHT_BASE##*.}" = sh ]; then
    for t in $PREFLIGHT_TARGETS; do
      cf="$TARGET_DIR/$t.conf"
      shell=$(conf_field "$cf" shell missing)
      case "$shell" in
        sh) /system/bin/sh -n "$PREFLIGHT_FILE" >/dev/null 2>&1 || { PREFLIGHT_OUTCOME=BLOCKED; PREFLIGHT_REASON="local_syntax_$t"; return 1; } ;;
        bash)
          bash_bin=$(env_field "$CONFIG_FILE" BASH_BIN /data/data/com.termux/files/usr/bin/bash)
          [ -x "$bash_bin" ] || { PREFLIGHT_OUTCOME=BLOCKED; PREFLIGHT_REASON="bash_missing_$t"; return 1; }
          "$bash_bin" -n "$PREFLIGHT_FILE" >/dev/null 2>&1 || { PREFLIGHT_OUTCOME=BLOCKED; PREFLIGHT_REASON="local_syntax_$t"; return 1; }
          ;;
        *) PREFLIGHT_OUTCOME=BLOCKED; PREFLIGHT_REASON="shell_profile_missing_$t"; return 1;;
      esac
    done
  fi

  PREFLIGHT_HOST_RUN=yes
  for t in $PREFLIGHT_TARGETS; do
    tmp=$STATE_DIR/.workflow-preflight.$$
    "$SERVICE" --verify-target "$t" > "$tmp" 2>&1
    rc=$?
    final=$(sed -n 's/^final_gate=//p' "$tmp" 2>/dev/null | tail -n 1)
    rm -f "$tmp" >/dev/null 2>&1 || true
    [ "$rc" -eq 0 ] && [ "$final" = PASS ] || { PREFLIGHT_OUTCOME=BLOCKED; PREFLIGHT_REASON="target_not_ready_$t"; PREFLIGHT_TARGET_RESULTS="$PREFLIGHT_TARGET_RESULTS $t:blocked"; return 1; }
    PREFLIGHT_TARGET_RESULTS="$PREFLIGHT_TARGET_RESULTS $t:ready"
  done
  PREFLIGHT_TARGET_RESULTS=$(printf '%s' "$PREFLIGHT_TARGET_RESULTS" | sed 's/^ *//')
  return 0
}

preflight_cmd(){
  preflight_collect "$1"; rc=$?
  if [ "$FORMAT" = json ]; then
    printf '{"schema":"SDD_PREFLIGHT_V1","deliveryId":'; json_string "${PREFLIGHT_ID:-unknown}"; printf ',"file":'; json_string "${PREFLIGHT_BASE:-unknown}"; printf ',"targets":'; json_string "${PREFLIGHT_TARGETS:-}"; printf ',"targetResults":'; json_string "${PREFLIGHT_TARGET_RESULTS:-}"; printf ',"hostRun":'; [ "${PREFLIGHT_HOST_RUN:-no}" = yes ] && printf true || printf false; printf ',"outcome":'; json_string "$PREFLIGHT_OUTCOME"; printf ',"reason":'; json_string "$PREFLIGHT_REASON"; printf '}\n'
  else
    echo "schema=SDD_PREFLIGHT_V1"; echo "delivery_id=${PREFLIGHT_ID:-unknown}"; echo "file=${PREFLIGHT_BASE:-unknown}"; echo "targets=${PREFLIGHT_TARGETS:-}"; echo "target_results=${PREFLIGHT_TARGET_RESULTS:-}"; echo "host_run=${PREFLIGHT_HOST_RUN:-no}"; echo "outcome=$PREFLIGHT_OUTCOME"; echo "reason=$PREFLIGHT_REASON"; echo "RESULT: SDD_PREFLIGHT_DONE outcome=$(printf '%s' "$PREFLIGHT_OUTCOME" | tr '[:upper:]' '[:lower:]') exit_code=$rc"
  fi
  return "$rc"
}

write_receipt(){
  id=$1; file=$2; rec=$3; targets=$4; started=$5; ended=$6; state=$7; preflight=$8; dispatch_rc=$9; shift 9; wait_rc=$1; scan_scope=$2; host_run=$3
  mkdir -p "$STATE_DIR" >/dev/null 2>&1 || true
  {
    printf '{"schema":"SDD_DELIVERY_RECEIPT_V1","deliveryId":'; json_string "$id"; printf ',"file":'; json_string "$file"; printf ',"record":'; json_string "$rec"; printf ',"targets":'; json_string "$targets"; printf ',"startedEpoch":%s,"endedEpoch":%s,"state":' "$started" "$ended"; json_string "$state"; printf ',"preflight":'; json_string "$preflight"; printf ',"dispatchRc":%s,"waitRc":%s,"scanScope":' "$dispatch_rc" "$wait_rc"; json_string "$scan_scope"; printf ',"automaticRequeue":false,"remoteShaRequired":true,"hostRun":%s}\n' "$host_run"
  } >> "$RECEIPT_DB"
}

emit_receipt(){
  id=$1; file=$2; rec=$3; targets=$4; started=$5; ended=$6; state=$7; preflight=$8; dispatch_rc=$9; shift 9; wait_rc=$1; scan_scope=$2; host_run=$3
  if [ "$FORMAT" = json ]; then
    printf '{"schema":"SDD_DELIVERY_RECEIPT_V1","deliveryId":'; json_string "$id"; printf ',"file":'; json_string "$file"; printf ',"record":'; json_string "$rec"; printf ',"targets":'; json_string "$targets"; printf ',"startedEpoch":%s,"endedEpoch":%s,"state":' "$started" "$ended"; json_string "$state"; printf ',"preflight":'; json_string "$preflight"; printf ',"dispatchRc":%s,"waitRc":%s,"scanScope":' "$dispatch_rc" "$wait_rc"; json_string "$scan_scope"; printf ',"automaticRequeue":false,"remoteShaRequired":true,"hostRun":%s}\n' "$host_run"
  else
    echo "schema=SDD_DELIVERY_RECEIPT_V1"; echo "delivery_id=$id"; echo "file=$file"; echo "record=$rec"; echo "targets=$targets"; echo "started_epoch=$started"; echo "ended_epoch=$ended"; echo "state=$state"; echo "preflight=$preflight"; echo "dispatch_rc=$dispatch_rc"; echo "wait_rc=$wait_rc"; echo "scan_scope=$scan_scope"; echo "automatic_requeue=no"; echo "remote_sha_required=yes"; echo "host_run=$host_run"; echo "RESULT: SDD_DELIVERY_RECEIPT_DONE state=$state exit_code=$wait_rc"
  fi
}

dispatch_file_cmd(){
  in=$1; timeout=${2:-300}; interval=${3:-5}
  case "$timeout" in ''|*[!0-9]*) echo "dispatch_file=FAIL invalid_timeout" >&2; return 64;; esac
  case "$interval" in ''|*[!0-9]*) echo "dispatch_file=FAIL invalid_interval" >&2; return 64;; esac
  [ "$timeout" -ge 1 ] 2>/dev/null || timeout=300
  [ "$interval" -ge 1 ] 2>/dev/null || interval=5
  started=$(date +%s 2>/dev/null || echo 0)
  preflight_collect "$in"; pre_rc=$?
  if [ "$pre_rc" -ne 0 ]; then
    ended=$(date +%s 2>/dev/null || echo "$started")
    [ "${PREFLIGHT_HOST_RUN:-no}" = yes ] && receipt_host_run=true || receipt_host_run=false
    write_receipt "${PREFLIGHT_ID:-unknown}" "${PREFLIGHT_BASE:-$(base_name "$in")}" "${PREFLIGHT_REC:-unknown}" "${PREFLIGHT_TARGETS:-}" "$started" "$ended" blocked_preflight "$PREFLIGHT_REASON" 0 "$pre_rc" not_started "$receipt_host_run"
    emit_receipt "${PREFLIGHT_ID:-unknown}" "${PREFLIGHT_BASE:-$(base_name "$in")}" "${PREFLIGHT_REC:-unknown}" "${PREFLIGHT_TARGETS:-}" "$started" "$ended" blocked_preflight "$PREFLIGHT_REASON" 0 "$pre_rc" not_started "$receipt_host_run"
    return "$pre_rc"
  fi
  "$SERVICE" --scan-once "cli_dispatch_file_${PREFLIGHT_ID}" >/dev/null 2>&1
  dispatch_rc=$?
  if [ "$dispatch_rc" -eq 0 ]; then
    "$SERVICE" --wait-delivery "$PREFLIGHT_FILE" "$timeout" "$interval" >/dev/null 2>&1
    wait_rc=$?
  else
    wait_rc=$dispatch_rc
  fi
  ended=$(date +%s 2>/dev/null || echo "$started")
  [ "$wait_rc" -eq 0 ] && state=verified_complete || state=failed
  write_receipt "$PREFLIGHT_ID" "$PREFLIGHT_BASE" "$PREFLIGHT_REC" "$PREFLIGHT_TARGETS" "$started" "$ended" "$state" READY "$dispatch_rc" "$wait_rc" existing_queue true
  emit_receipt "$PREFLIGHT_ID" "$PREFLIGHT_BASE" "$PREFLIGHT_REC" "$PREFLIGHT_TARGETS" "$started" "$ended" "$state" READY "$dispatch_rc" "$wait_rc" existing_queue true
  return "$wait_rc"
}

incident_next_action(){
  state=$1; reason=$2
  case "$reason" in
    *local_preflight*|local_syntax_*) printf 'Inspect local shell syntax before any retry.' ;;
    *remote_sha*|*REMOTE_SHA*) printf 'Do not retry blindly; inspect transfer integrity and remote digest evidence.' ;;
    *canonical_collision*) printf 'Inspect canonical-name collision state before requeueing.' ;;
    *target_not_ready*|*SSH*|*scp*) printf 'Check target reachability and SSH state without changing DNS or routes implicitly.' ;;
    *space*) printf 'Free target space or review explicit space policy; do not bypass the gate silently.' ;;
    *) case "$state" in complete) printf 'No action required.';; quarantined) printf 'Inspect the quarantine reason before any retry.';; inflight) printf 'Wait for the current delivery or inspect its trace.';; *) printf 'Run sdd trace <file|delivery-id> and review the latest failure evidence.';; esac ;;
  esac
}

incident_cmd(){
  in=${1:-}
  health=$(env_field "$STATE_DIR/health.env" status unknown)
  lint=ok; config_lint_rc || lint=fail
  qcount=$(count_lines "$QUAR_DB"); fcount=$(count_lines "$FAIL_DB"); inflight=$(count_lines "$INFLIGHT_DB")
  recent_fail=$(count_log_token FAIL); recent_warn=$(count_log_token WARN)
  delivery_id=none; file=none; state=global; reason=none
  if [ -n "$in" ] && set_trace_identity "$in"; then
    delivery_id=$TRACE_ID; file=$TRACE_BASE; state=$(record_state "$TRACE_REC")
    q=$(grep -F "$TRACE_REC" "$QUAR_DB" 2>/dev/null | tail -n 1 || true)
    [ -n "$q" ] && reason=$(printf '%s' "$q" | sed -n 's/.*|reason=\([^|]*\).*/\1/p')
    if [ "$reason" = none ]; then
      fail_line=$(grep -F "file=$TRACE_BASE" "$LOG_FILE" 2>/dev/null | grep ' FAIL ' | tail -n 1 | redact_line || true)
      [ -n "$fail_line" ] && reason=$(printf '%s' "$fail_line" | sed -n 's/.* FAIL \([^ ]*\).*/\1/p')
    fi
  fi
  action=$(incident_next_action "$state" "$reason")
  if [ "$FORMAT" = json ]; then
    printf '{"schema":"SDD_INCIDENT_CONTEXT_V1","health":'; json_string "$health"; printf ',"configLint":'; json_string "$lint"; printf ',"deliveryId":'; json_string "$delivery_id"; printf ',"file":'; json_string "$file"; printf ',"state":'; json_string "$state"; printf ',"reason":'; json_string "$reason"; printf ',"inflightRecords":%s,"failDbRecords":%s,"quarantineRecords":%s,"recentFailLines":%s,"recentWarnLines":%s,"safeNextAction":' "$inflight" "$fcount" "$qcount" "$recent_fail" "$recent_warn"; json_string "$action"; printf ',"redaction":{"secretContentRead":false,"hostFieldsExposed":false,"remoteDropFieldsExposed":false,"networkAddressesExposed":false},"hostRun":false}\n'
  else
    echo "schema=SDD_INCIDENT_CONTEXT_V1"; echo "health=$health"; echo "config_lint=$lint"; echo "delivery_id=$delivery_id"; echo "file=$file"; echo "state=$state"; echo "reason=$reason"; echo "inflight_records=$inflight"; echo "faildb_records=$fcount"; echo "quarantine_records=$qcount"; echo "recent_fail_lines=$recent_fail"; echo "recent_warn_lines=$recent_warn"; echo "safe_next_action=$action"; echo "secret_content_read=no"; echo "host_fields_exposed=no"; echo "remote_drop_fields_exposed=no"; echo "network_addresses_exposed=no"; echo "host_run=no"; echo "RESULT: SDD_INCIDENT_CONTEXT_DONE outcome=success schema=$INCIDENT_SCHEMA exit_code=0"
  fi
}

case "${1:-}" in
  trace) [ $# -eq 2 ] || { usage >&2; exit 64; }; trace "$2" ;;
  inspect) [ $# -eq 2 ] || { usage >&2; exit 64; }; trace "$2" ;;
  queue) [ $# -le 2 ] || { usage >&2; exit 64; }; queue_cmd "${2:-20}" ;;
  failures) [ $# -le 2 ] || { usage >&2; exit 64; }; failures_cmd "${2:-20}" ;;
  quarantine) [ $# -le 2 ] || { usage >&2; exit 64; }; quarantine_cmd "${2:-20}" ;;
  preflight) [ $# -eq 2 ] || { usage >&2; exit 64; }; preflight_cmd "$2" ;;
  dispatch-file) [ $# -ge 2 ] && [ $# -le 4 ] || { usage >&2; exit 64; }; dispatch_file_cmd "$2" "${3:-300}" "${4:-5}" ;;
  incident) [ $# -le 2 ] || { usage >&2; exit 64; }; incident_cmd "${2:-}" ;;
  help|--help|-h|'') usage ;;
  *) usage >&2; exit 64 ;;
esac
