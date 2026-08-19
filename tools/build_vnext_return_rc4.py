#!/usr/bin/env python3
from __future__ import annotations

import argparse
import contextlib
import importlib.util
import io
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
RC3_BUILDER = ROOT / "tools" / "build_vnext_return_rc3.py"
VERSION = "4.14.0-return-rc4"
VERSION_CODE = "4140004"
DESCRIPTION = "Android/Magisk SSH file-drop dispatcher with verified outbound delivery, generic pull-based Return Channel v1, standalone WebUI Core 0.6 and bounded named-delivery scan fairness"

spec = importlib.util.spec_from_file_location("sdd_vnext_return_rc3_builder", RC3_BUILDER)
if spec is None or spec.loader is None:
    raise RuntimeError("rc3_builder_import_failed")
rc3 = importlib.util.module_from_spec(spec)
spec.loader.exec_module(rc3)

rc3.VERSION = VERSION
rc3.VERSION_CODE = VERSION_CODE
rc3.DESCRIPTION = DESCRIPTION
rc3.rc1.VERSION = VERSION
rc3.rc1.VERSION_CODE = VERSION_CODE

_rc3_stage_module = rc3.stage_module
_rc3_verify_stage = rc3.verify_stage


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"patch_anchor_mismatch label={label} count={count}")
    return text.replace(old, new, 1)


def patch_dispatcher_fairness(stage: Path) -> None:
    service = stage / "service.sh"
    text = service.read_text()

    text = replace_once(
        text,
        "EVENT_PENDING_FILE=$STATE_DIR/.event.pending\nLAST_SCAN_FILE=$STATE_DIR/.last_scan",
        "EVENT_PENDING_FILE=$STATE_DIR/.event.pending\nEVENT_FOLLOWUP_WORKER_LOCKDIR=$STATE_DIR/event-followup.worker\nEVENT_FOLLOWUP_WORKER_TS=$STATE_DIR/event-followup.worker.ts\nLAST_SCAN_FILE=$STATE_DIR/.last_scan",
        "followup_worker_paths",
    )

    old_followup = '''schedule_followup(){
  ( $SLEEP_BIN 5; /data/adb/modules/ssh_drop_dispatcher/service.sh --scan-once event_followup ) >/dev/null 2>&1 &
}
'''
    new_followup = '''schedule_followup(){
  echo "1" > "$EVENT_PENDING_FILE" 2>/dev/null || true
  if ! $MKDIR_BIN "$EVENT_FOLLOWUP_WORKER_LOCKDIR" >/dev/null 2>&1; then
    now=$($DATE_BIN +%s 2>/dev/null || echo 0)
    worker_ts=0
    [ -f "$EVENT_FOLLOWUP_WORKER_TS" ] && worker_ts=$($CAT_BIN "$EVENT_FOLLOWUP_WORKER_TS" 2>/dev/null || echo 0)
    worker_age=$((now - worker_ts))
    worker_stale=$(( ${DROP_DISPATCH_STALE_LOCK_SECONDS:-600} + 60 ))
    if [ "$worker_ts" -gt 0 ] 2>/dev/null && [ "$worker_age" -gt "$worker_stale" ] 2>/dev/null; then
      log "WARN stale_event_followup_worker_removed age=$worker_age"
      $RM_BIN -rf "$EVENT_FOLLOWUP_WORKER_LOCKDIR" "$EVENT_FOLLOWUP_WORKER_TS" >/dev/null 2>&1 || true
      $MKDIR_BIN "$EVENT_FOLLOWUP_WORKER_LOCKDIR" >/dev/null 2>&1 || return 0
    else
      return 0
    fi
  fi
  $DATE_BIN +%s > "$EVENT_FOLLOWUP_WORKER_TS" 2>/dev/null || true
  (
    trap "$RM_BIN -rf \"$EVENT_FOLLOWUP_WORKER_LOCKDIR\" \"$EVENT_FOLLOWUP_WORKER_TS\" >/dev/null 2>&1 || true" 0 1 2 3 15
    while [ -f "$EVENT_PENDING_FILE" ]; do
      $SLEEP_BIN 5
      /data/adb/modules/ssh_drop_dispatcher/service.sh --scan-once event_followup >/dev/null 2>&1 || true
      [ -f "$EVENT_PENDING_FILE" ] || break
    done
  ) >/dev/null 2>&1 &
}
'''
    text = replace_once(text, old_followup, new_followup, "single_flight_followup")

    named_scan = '''scan_file_once(){
  in="$1"
  reason="${2:-named_dispatch}"
  lock_timeout="${3:-300}"
  case "$lock_timeout" in ""|*[!0-9]*) lock_timeout=300 ;; esac
  [ "$lock_timeout" -lt 10 ] 2>/dev/null && lock_timeout=10
  [ "$lock_timeout" -gt 600 ] 2>/dev/null && lock_timeout=600
  dispatcher_enabled || { log "SKIP disabled reason=$reason mode=named_file"; health WARN disabled; return 2; }
  case "$in" in /*) file="$in" ;; *) file="$DROP_DISPATCH_SCAN_DIR/$in" ;; esac
  base=$($BASENAME_BIN "$file")
  [ "$file" = "$DROP_DISPATCH_SCAN_DIR/$base" ] || { log "FAIL named_scan invalid_path reason=$reason"; return 64; }
  [ -f "$file" ] || { log "FAIL named_scan missing_file file=$base reason=$reason"; return 66; }
  is_partial "$base" && { log "FAIL named_scan partial_file file=$base reason=$reason"; return 64; }
  is_supported "$base" || { log "FAIL named_scan unsupported_file file=$base reason=$reason"; return 64; }
  targets=$(targets_for "$base")
  [ -n "$targets" ] || { log "FAIL named_scan no_targets file=$base reason=$reason"; return 64; }

  start_epoch=$($DATE_BIN +%s 2>/dev/null || echo 0)
  lock_wait=0
  while ! $MKDIR_BIN "$SCAN_LOCKDIR" >/dev/null 2>&1; do
    stale_lock_guard
    now_epoch=$($DATE_BIN +%s 2>/dev/null || echo "$start_epoch")
    lock_wait=$((now_epoch - start_epoch))
    [ "$lock_wait" -lt 0 ] 2>/dev/null && lock_wait=0
    if [ "$lock_wait" -ge "$lock_timeout" ] 2>/dev/null; then
      log "FAIL named_scan lock_timeout file=$base reason=$reason wait_seconds=$lock_wait"
      echo "1" > "$EVENT_PENDING_FILE" 2>/dev/null || true
      schedule_followup
      health WARN named_scan_lock_timeout
      return 75
    fi
    $SLEEP_BIN 1
  done

  now_epoch=$($DATE_BIN +%s 2>/dev/null || echo 0)
  echo "$now_epoch" > "$SCAN_LOCK_TS" 2>/dev/null || true
  echo "$now_epoch" > "$LAST_SCAN_FILE" 2>/dev/null || true
  trap "$RM_BIN -rf \"$SCAN_LOCKDIR\" \"$SCAN_LOCK_TS\" >/dev/null 2>&1 || true" 0 1 2 3 15
  log "START scan_dir=$DROP_DISPATCH_SCAN_DIR reason=$reason mode=named_file file=$base lock_wait_seconds=$lock_wait"
  $SLEEP_BIN "$DROP_DISPATCH_SETTLE_SECONDS"
  log "QUEUE pass=1 pending=1 reason=$reason mode=named_file"
  log "PROCESS pass=1 file=$base reason=$reason mode=named_file"
  process_file "$file"
  log "END passes=1 processed=1 reason=$reason mode=named_file"
  health OK "$reason"
  $RM_BIN -rf "$SCAN_LOCKDIR" "$SCAN_LOCK_TS" >/dev/null 2>&1 || true
  trap - 0 1 2 3 15
  [ -f "$EVENT_PENDING_FILE" ] && schedule_followup
  return 0
}

'''
    text = replace_once(text, "\nstatus_file(){\n", "\n" + named_scan + "status_file(){\n", "named_scan_function")

    mode_anchor = '''  --verify-targets)
    wait_boot; import_bundle_if_needed; load_config || exit 1; verify_targets
    ;;
'''
    mode_new = '''  --scan-file)
    wait_boot; import_bundle_if_needed; load_config || exit 1; ensure_ssh_ready || exit 1; scan_file_once "${2:-}" "${3:-named_dispatch}" "${4:-300}"
    ;;
''' + mode_anchor
    text = replace_once(text, mode_anchor, mode_new, "named_scan_mode")
    service.write_text(text)

    workflow = stage / "tools" / "sdd-workflow.sh"
    wtext = workflow.read_text()
    wtext = replace_once(
        wtext,
        '  "$SERVICE" --scan-once "cli_dispatch_file_${PREFLIGHT_ID}" >/dev/null 2>&1\n',
        '  "$SERVICE" --scan-file "$PREFLIGHT_FILE" "cli_dispatch_file_${PREFLIGHT_ID}" "$timeout" >/dev/null 2>&1\n',
        "dispatch_file_named_scan",
    )
    wtext = wtext.replace('"$dispatch_rc" "$wait_rc" existing_queue true', '"$dispatch_rc" "$wait_rc" named_file true')
    if "existing_queue true" in wtext:
        raise RuntimeError("dispatch_file_scan_scope_old_marker_remaining")
    workflow.write_text(wtext)


def stage_module(work: Path, fetched: dict[str, Path]) -> Path:
    stage = _rc3_stage_module(work, fetched)
    patch_dispatcher_fairness(stage)
    return stage


def verify_stage(stage: Path, work: Path) -> None:
    _rc3_verify_stage(stage, work)
    service = (stage / "service.sh").read_text()
    workflow = (stage / "tools" / "sdd-workflow.sh").read_text()
    for marker in (
        "EVENT_FOLLOWUP_WORKER_LOCKDIR=$STATE_DIR/event-followup.worker",
        "stale_event_followup_worker_removed",
        "scan_file_once(){",
        "mode=named_file",
        "--scan-file)",
    ):
        if marker not in service:
            raise RuntimeError(f"scan_fairness_service_marker_missing:{marker}")
    if "( $SLEEP_BIN 5; /data/adb/modules/ssh_drop_dispatcher/service.sh --scan-once event_followup )" in service:
        raise RuntimeError("unbounded_event_followup_fanout_remaining")
    if '"$SERVICE" --scan-file "$PREFLIGHT_FILE" "cli_dispatch_file_${PREFLIGHT_ID}" "$timeout"' not in workflow:
        raise RuntimeError("dispatch_file_named_scan_missing")
    if "named_file true" not in workflow or "existing_queue true" in workflow:
        raise RuntimeError("dispatch_file_scan_scope_not_named")


rc3.rc1.stage_module = stage_module
rc3.rc1.verify_stage = verify_stage


def build(output: Path) -> None:
    buffer = io.StringIO()
    with contextlib.redirect_stdout(buffer):
        rc3.rc1.build(output)
    rendered = buffer.getvalue().replace(
        "RESULT: SDD_VNEXT_RETURN_RC1_BUILD_DONE outcome=success workflow_exit_code=0",
        "RESULT: SDD_VNEXT_RETURN_RC4_BUILD_DONE outcome=success workflow_exit_code=0",
    ).replace(
        "delivery_core_changed=yes_additive_return_binding_only",
        "delivery_core_changed=yes_return_binding_plus_scan_fairness",
    )
    print(rendered, end="")


def main() -> int:
    parser = argparse.ArgumentParser(description="Build SSH Drop Dispatcher v4.14.0 Return Channel RC4 with named-delivery scan fairness")
    parser.add_argument("--output", type=Path, default=ROOT / "dist" / "ssh-drop-dispatcher-magisk-v4.14.0-return-rc4.zip")
    args = parser.parse_args()
    try:
        build(args.output.resolve())
    except Exception as exc:
        print(f"RESULT: SDD_VNEXT_RETURN_RC4_BUILD_DONE outcome=fail reason={exc} workflow_exit_code=1", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
