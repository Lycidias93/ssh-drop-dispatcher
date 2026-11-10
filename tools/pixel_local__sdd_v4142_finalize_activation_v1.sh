#!/data/data/com.termux/files/usr/bin/bash
# CG_HANDOFF_V1_START
# cg_handoff_lane=sdd-v4142-final-enable
# cg_handoff_scope=pixel-dispatcher
# cg_handoff_host=pixel
# cg_handoff_route_class=none
# cg_handoff_secret_class=possible
# cg_handoff_run_mode=run
# cg_handoff_expected_marker=RESULT: SDD_V4142_FINAL_ACTIVATION_PASS
# CG_HANDOFF_V1_END
set -eu

SELF=/data/data/com.termux/files/usr/tmp/pixel_local__sdd_v4142_finalize_activation_v1.sh
MODULE=/data/adb/modules/ssh_drop_dispatcher
SERVICE=$MODULE/service.sh
STATE=/data/adb/ssh-drop-dispatcher
CONFIG=$STATE/config.env
DOWNLOAD=/storage/emulated/0/Download
SSH_CONFIG=$STATE/ssh/ssh-config.dispatch
CONFIG_SHA=d4424e78bf5185dfd19330ad38669093455955235a7fb3f4a30c6e7991439598
SERVICE_SHA=c1a54cd7fb0ceafc973adccc195494b41ae577131e04a9ee406424f58165b583
COORD_SHA=02e6c88633f7787f2aabfe9fe8bc47d5604a13c94fd1f10e8473b7bfe6e56346
BOOT_ID=ff143ce1-681f-4a8a-883b-daa6137f1a4d
SMOKE_LOCAL_NAME='target-pi4__sdd-v4142-smoke-20261110114858-12669.txt'
SMOKE_REMOTE_NAME='target-pi4__sdd-v4142-smoke-20261110114858.txt'
SMOKE_SHA=b75b24c6874910c1e04a9effd2f82330572cc797a271b4af784d5f8a86b2422e
SMOKE_DROP=/mnt/dietpi_userdata/BACKUP/_inbox/drop
BACKUP=

fail(){ printf 'RESULT: SDD_V4142_FINAL_ACTIVATION_STOP reason=%s workflow_exit_code=1\n' "$1" >&2; exit 1; }
file_sha(){ sha256sum "$1" | cut -d' ' -f 1; }
hex_field(){
  v=${1%% *}
  case "$v" in ''|*[!0123456789abcdef]*) return 1;; esac
  [ "${#v}" -eq 64 ] || return 1
  printf '%s\n' "$v"
}
is_alive(){
  case "$1" in ''|*[!0-9]*) return 1;; esac
  [ "$1" -gt 1 ] || return 1
  kill -0 "$1" 2>/dev/null
}
queue_protected(){
  total=0; complete=0; blocked=0
  for f in "$DOWNLOAD"/target-*__* "$DOWNLOAD"/targets-*__*; do
    [ -f "$f" ] || continue
    bn=${f##*/}
    case "$bn" in *.sh|*.zip|*.tar|*.tar.gz|*.tgz|*.tar.xz|*.txz|*.tar.bz2|*.tbz|*.tbz2|*.gz|*.xz|*.bz2|*.log|*.txt|*.md|*.json|*.conf|*.env) ;; *) continue;; esac
    case "$bn" in
      target-pi3__*|target-pi4__*|target-berylax__*|target-zeropi2__*)
        targets=${bn#target-}; targets=${targets%%__*};;
      targets-*__*)
        targets=${bn#targets-}; targets=${targets%%__*}; targets="$(printf '%s' "$targets" | tr '-' ' ')" ;;
      *) fail unrecognized_target_filename ;;
    esac
    total=$((total+1))
    rec="$bn|$(/system/bin/cksum "$f" | /system/bin/awk '{print $1":"$2}')"
    if grep -Fqx "$rec" "$STATE/dispatch.complete"; then complete=$((complete+1)); continue; fi
    for target in $targets; do
      case "$target" in pi3|pi4|berylax|zeropi2) ;; *) fail invalid_target ;; esac
      blocked_target=no
      for reason in local_preflight verify remote_sha canonical_collision; do
        if grep -Fqx "$rec|target=$target|reason=$reason|policy=v4115" "$STATE/dispatch.quarantined"; then blocked_target=yes; break; fi
      done
      [ "$blocked_target" = yes ] || fail unprotected_pending_artifact
    done
    blocked=$((blocked+1))
  done
  printf 'QUEUE_READBACK supported=%s complete=%s quarantined=%s\n' "$total" "$complete" "$blocked"
  [ "$total" = 6 ] && [ "$complete" = 4 ] && [ "$blocked" = 2 ] || fail backlog_changed
}
remote_cleanup_proof(){
  [ -f "$STATE/config/targets.d/pi4.conf" ] || fail missing_pi4_registry
  . "$STATE/config/targets.d/pi4.conf"
  [ "${target_name:-}" = pi4 ] || fail target_identity_changed
  [ "${remote_drop:-}" = "$SMOKE_DROP" ] || fail target_drop_changed
  case "${ssh_host:-}" in ''|*[!a-zA-Z0-9_.-]*) fail host_identity_invalid;; esac
  [ -f "$SSH_CONFIG" ] || fail ssh_config_missing
  remote_file="$SMOKE_DROP/$SMOKE_REMOTE_NAME"
  response="$(/data/data/com.termux/files/usr/bin/ssh -F "$SSH_CONFIG" -o BatchMode=yes -o ConnectTimeout=8 "$ssh_host" "if test -e '$remote_file' || test -L '$remote_file'; then echo canary_present; else echo canary_absent; fi" 2>/dev/null)" || fail remote_cleanup_probe_unavailable
  [ "$response" = canary_absent ] || fail remote_canary_not_cleaned
  printf 'SMOKE_ALREADY_CLEANED=pass remote_absent=yes prior_attested_sha256=%s\n' "$SMOKE_SHA"
}
preflight(){
  [ "$(id -u)" = 0 ] || fail uid_not_root
  [ "$(getprop ro.product.device)" = mustang ] || fail device_changed
  [ "$(getprop ro.build.version.sdk)" = 37 ] || fail sdk_changed
  [ "$(getprop sys.boot_completed)" = 1 ] || fail boot_incomplete
  [ "$(cat /proc/sys/kernel/random/boot_id)" = "$BOOT_ID" ] || fail boot_changed
  [ "$(sed -n 's/^version=//p' "$MODULE/module.prop")" = 4.14.2 ] || fail module_version
  [ "$(file_sha "$SERVICE")" = "$SERVICE_SHA" ] || fail service_source
  [ "$(file_sha "$MODULE/tools/sdd-followup-coalesce.sh")" = "$COORD_SHA" ] || fail coordinator_source
  [ "$(file_sha "$CONFIG")" = "$CONFIG_SHA" ] || fail config_drift
  grep -qx 'DROP_DISPATCH_ENABLED=0' "$CONFIG" || fail unexpectedly_enabled
  grep -Fxq 'DROP_DISPATCH_SCAN_DIR="/storage/emulated/0/Download"' "$CONFIG" || fail scan_dir_changed
  [ ! -d "$STATE/scan.lock" ] || fail scan_lock_present
  [ ! -d "$STATE/.followup.worker.lock" ] || fail worker_lock_present
  [ -s "$STATE/backups/v4142-manual-Ewiikz/READY" ] || fail original_rollback_missing
  bat="$(dumpsys battery | sed -n 's/^[[:space:]]*level:[[:space:]]*//p' | head -1)"
  status="$(dumpsys battery | sed -n 's/^[[:space:]]*status:[[:space:]]*//p' | head -1)"
  case "$bat" in ''|*[!0-9]*) fail battery_unknown;; esac
  [ "$bat" -ge 5 ] || fail battery_below_five
  printf 'PIXEL_MODULE_INSTALL_MIN_BATTERY_PERCENT=5 battery_percent=%s battery_status=%s\n' "$bat" "$status"
  queue_protected
  grep -Fqx "$SMOKE_LOCAL_NAME|3501100229:54" "$STATE/dispatch.complete" || fail smoke_delivery_record_missing
  grep -Fqx "$SMOKE_LOCAL_NAME|3501100229:54|target=pi4" "$STATE/dispatch.done" || fail smoke_done_record_missing
  [ ! -e "$DOWNLOAD/$SMOKE_LOCAL_NAME" ] && [ ! -L "$DOWNLOAD/$SMOKE_LOCAL_NAME" ] || fail local_smoke_not_cleaned
  remote_cleanup_proof
  printf 'RESULT: SDD_V4142_FINAL_PREFLIGHT_PASS enabled=0 backlog_unprotected=0 prior_smoke=delivered_and_cleaned\n'
}
rollback(){
  /system/bin/sh "$SERVICE" --disable >/dev/null 2>&1 || true
  if [ -n "$BACKUP" ] && [ -f "$BACKUP/config.env" ] && [ "$(file_sha "$BACKUP/config.env")" = "$CONFIG_SHA" ]; then
    cp "$BACKUP/config.env" "$CONFIG" && chmod 600 "$CONFIG" || true
  fi
  printf 'ROLLBACK_FINAL_ENABLED=' >&2
  grep '^DROP_DISPATCH_ENABLED=' "$CONFIG" >&2 || true
}
exit_trap(){
  rc=$?
  trap - 0
  if [ "$rc" -ne 0 ]; then rollback; fi
}
live_pids(){
  for name in main.pid watchdog.pid inotifyd.pid; do
    p="$(cat "$STATE/$name" 2>/dev/null || true)"
    if ! is_alive "$p"; then
      printf 'RUNTIME_PROBE missing=%s pid=%s\n' "$name" "${p:-none}"
      return 1
    fi
  done
  count="$(ps -A -o ARGS 2>/dev/null | grep -c '[s]dd-followup-coalesce.sh' || true)"
  case "$count" in ''|*[!0-9]*) fail worker_count_unknown;; esac
  [ "$count" -le 4 ] || fail followup_process_storm
  grep -qx 'DROP_DISPATCH_ENABLED=1' "$CONFIG" || fail config_not_enabled
  printf 'RUNTIME_PROBE state=ready followup_workers=%s\n' "$count"
}
await_runtime_ready(){
  attempt=0
  stable=0
  while [ "$attempt" -lt 12 ]; do
    if live_pids; then
      stable=$((stable + 1))
      [ "$stable" -ge 2 ] && { printf 'LIVE_PID_CHECK=pass consecutive=2\n'; return 0; }
    else
      stable=0
    fi
    attempt=$((attempt + 1))
    sleep 3
  done
  fail runtime_pid_timeout
}
run(){
  preflight
  umask 077
  BACKUP="$(mktemp -d "$STATE/backups/v4142-final-enable-XXXXXXXX")" || fail new_backup_creation
  chmod 700 "$BACKUP" || fail backup_permissions
  cp "$CONFIG" "$BACKUP/config.env" || fail backup_config
  [ "$(file_sha "$BACKUP/config.env")" = "$CONFIG_SHA" ] || fail backup_invalid
  trap 'exit_trap' 0
  /system/bin/sh "$SERVICE" --enable > "$BACKUP/enable.log" 2>&1 || fail enable_failed
  await_runtime_ready
  sleep 8
  live_pids || fail runtime_unstable_after_ready
  printf 'CPU_PRESSURE_AFTER='
  grep '^some ' /proc/pressure/cpu | head -1
  printf 'RESULT: SDD_V4142_FINAL_ACTIVATION_PASS enabled=1 new_file_transfers=0 prior_smoke=delivered_and_cleaned live_services=pass rollback_ready=yes\n'
  trap - 0
}
case "${1:-}" in
  fixture-parse)
    h="$(hex_field "${2:-}")" || { echo 'RESULT: SDD_V4142_HEX_PARSE_STOP'; exit 3; }
    printf 'RESULT: SDD_V4142_HEX_PARSE_PASS sha256=%s\n' "$h"
    ;;
  root-verify) preflight ;;
  root-run) run ;;
  '')
    [ "$(id -u)" = 10544 ] || fail unexpected_termux_uid
    [ "${CG_LANE_ID:-}" = sdd-v4142-final-enable ] || fail wrong_lane
    [ "${CG_RUN_SCOPE:-}" = pixel-dispatcher ] || fail wrong_scope
    [ "${CG_RUN_HOST:-}" = pixel ] || fail wrong_host
    [ "${CG_LANE_ROUTE_CLASS:-}" = none ] || fail wrong_route
    [ "${CG_LANE_SECRET_CLASS:-}" = possible ] || fail wrong_secret_class
    case "${CG_RUN_MODE:-}" in
      verify) su -c "/system/bin/sh $SELF root-verify" ;;
      run) su -c "/system/bin/sh $SELF root-run" ;;
      *) fail invalid_run_mode ;;
    esac
    ;;
  *) fail invalid_command ;;
esac
