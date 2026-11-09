#!/system/bin/sh
# One reserved follow-up worker per dispatcher state directory. No recursive forks.
STATE_DIR=${SDD_FOLLOWUP_STATE_DIR:-/data/adb/ssh-drop-dispatcher}
SERVICE=${SDD_FOLLOWUP_SERVICE:-/data/adb/modules/ssh_drop_dispatcher/service.sh}
SLOT="$STATE_DIR/.followup.worker.lock"
PENDING="$STATE_DIR/.event.pending"
SCAN="$STATE_DIR/scan.lock"
LOG="$STATE_DIR/log/dispatch.log"
DELAY=${SDD_FOLLOWUP_DELAY_SECONDS:-5}
MAX=${SDD_FOLLOWUP_MAX_ATTEMPTS:-24}
case "$DELAY" in ''|*[!0-9]*) DELAY=5;; esac
case "$MAX" in ''|*[!0-9]*) MAX=24;; esac
[ "$DELAY" -ge 1 ] && [ "$DELAY" -le 60 ] || DELAY=5
[ "$MAX" -ge 1 ] && [ "$MAX" -le 240 ] || MAX=120

now(){ date +%s 2>/dev/null || printf '0\n'; }
note(){ printf '%s %s\n' "$(now)" "$*" >> "$LOG" 2>/dev/null || true; }
slot_owner(){ [ -f "$SLOT/pid" ] && cat "$SLOT/pid" 2>/dev/null || true; }
owner_alive(){
  owner="$(slot_owner)"
  case "$owner" in ''|*[!0-9]*) return 1;; esac
  [ "$owner" -gt 1 ] 2>/dev/null && kill -0 "$owner" 2>/dev/null
}
cleanup(){
  [ "$(slot_owner)" = "$$" ] || return 0
  rm -f "$SLOT/pid" "$SLOT/created_at" 2>/dev/null || true
  rmdir "$SLOT" 2>/dev/null || true
}
reserve(){
  [ -f "$PENDING" ] || return 0
  if mkdir "$SLOT" 2>/dev/null; then
    now > "$SLOT/created_at"
    sh "$0" worker </dev/null >/dev/null 2>&1 &
    note "INFO followup_reserved pid=$! policy=singleflight"
  fi
}
recover_slot(){
  [ -d "$SLOT" ] || return 0
  owner_alive && return 0
  created=0
  [ -f "$SLOT/created_at" ] && created="$(cat "$SLOT/created_at" 2>/dev/null || printf '0')"
  case "$created" in ''|*[!0-9]*) created=0;; esac
  [ "$created" -gt 0 ] 2>/dev/null || created="$(stat -c %Y "$SLOT" 2>/dev/null || printf '0')"
  case "$created" in ''|*[!0-9]*) return 0;; esac
  age=$(( $(now) - created ))
  [ "$age" -ge 60 ] || return 0
  # Atomic rename prevents removing a replacement reservation at the same path.
  retired="$SLOT.stale.$$.$age"
  if mv "$SLOT" "$retired" 2>/dev/null; then
    rm -rf "$retired" 2>/dev/null || true
    note "WARN followup_orphan_recovered age=$age"
  fi
}
run_worker(){
  [ -d "$SLOT" ] || exit 0
  printf '%s\n' "$$" > "$SLOT/pid" || exit 1
  trap 'cleanup' 0
  trap 'exit 129' 1
  trap 'exit 130' 2
  trap 'exit 143' 15
  attempt=0
  backoff=$DELAY
  while [ "$attempt" -lt "$MAX" ]; do
    [ -f "$PENDING" ] || return 0
    if [ ! -d "$SCAN" ]; then
      # A contested scan only marks PENDING: reserve() sees our slot and cannot fork.
      if ! "$SERVICE" --scan-once event_followup >/dev/null 2>&1; then
        printf '1\n' > "$PENDING"
        note "WARN followup_scan_error retry_preserved=yes"
      fi
      [ -f "$PENDING" ] || return 0
    fi
    attempt=$((attempt + 1))
    sleep "$backoff"
    [ "$backoff" -ge 30 ] || backoff=$((backoff * 2))
    [ "$backoff" -le 30 ] || backoff=30
  done
  note "WARN followup_retry_deferred attempts=$MAX event_pending=yes"
  # The existing watchdog reconciles the pending marker and reserves the next slot.
  return 0
}
case "${1:-}" in
  request)
    printf '1\n' > "$PENDING" || exit 1
    reserve
    ;;
  reconcile)
    recover_slot
    reserve
    ;;
  worker)
    run_worker
    ;;
  *)
    echo "usage: sdd-followup-coalesce.sh request|reconcile|worker" >&2
    exit 64
    ;;
esac
