#!/system/bin/sh
MODDIR=${0%/*}
STATE_DIR=/data/adb/ssh-drop-dispatcher
LOG_DIR=$STATE_DIR/log
LOG_FILE=$LOG_DIR/dispatch.log
CONFIG_FILE=$STATE_DIR/config.env
CONFIG_DIR=$STATE_DIR/config
TARGETS_DIR=$CONFIG_DIR/targets.d
TOOLS_DIR=$STATE_DIR/tools
MODULE_TOOLS_DIR=$MODDIR/tools
MODULE_TARGET_DEFAULTS_DIR=$MODDIR/config/defaults/targets.d
SSH_DIR=$STATE_DIR/ssh
RUNTIME_SSH_CONFIG=$SSH_DIR/ssh-config.dispatch
DONE_FILE=$STATE_DIR/dispatch.done
FAIL_DB=$STATE_DIR/dispatch.faildb
QUAR_DB=$STATE_DIR/dispatch.quarantined
INFLIGHT_DB=$STATE_DIR/dispatch.inflight
COMPLETE_DB=$STATE_DIR/dispatch.complete
HEALTH_FILE=$STATE_DIR/health.env
IMPORT_STAMP=$STATE_DIR/.bundle.imported.version
BUNDLE_DIR=/storage/emulated/0/PixelDropDispatch/main-bundle
BUNDLE_VERSION_FILE=$BUNDLE_DIR/bundle.version
HANDLER_SCRIPT=$STATE_DIR/inotify-handler.sh
WATCHER_PID_FILE=$STATE_DIR/inotifyd.pid
MAIN_PID_FILE=$STATE_DIR/main.pid
WATCHDOG_PID_FILE=$STATE_DIR/watchdog.pid
SCAN_LOCKDIR=$STATE_DIR/scan.lock
SCAN_LOCK_TS=$STATE_DIR/scan.lock.ts
EVENT_PENDING_FILE=$STATE_DIR/.event.pending
LAST_SCAN_FILE=$STATE_DIR/.last_scan
LAST_EVENT_FILE=$STATE_DIR/.last_event
TMP_SCAN_LIST=$STATE_DIR/.scan.list
TMP_PENDING_LIST=$STATE_DIR/.scan.pending
PIDD_POLICY_VERSION=v4115

SSH_BIN_DEFAULT=/data/data/com.termux/files/usr/bin/ssh
BASH_BIN_DEFAULT=/data/data/com.termux/files/usr/bin/bash
GETPROP_BIN=/system/bin/getprop
FIND_BIN=/system/bin/find
WC_BIN=/system/bin/wc
TR_BIN=/system/bin/tr
CKSUM_BIN=/system/bin/cksum
GREP_BIN=/system/bin/grep
SED_BIN=/system/bin/sed
CAT_BIN=/system/bin/cat
SLEEP_BIN=/system/bin/sleep
BASENAME_BIN=/system/bin/basename
MKDIR_BIN=/system/bin/mkdir
TOUCH_BIN=/system/bin/touch
CHMOD_BIN=/system/bin/chmod
RM_BIN=/system/bin/rm
MV_BIN=/system/bin/mv
CP_BIN=/system/bin/cp
DATE_BIN=/system/bin/date
MKTEMP_BIN=/system/bin/mktemp
KILL_BIN=/system/bin/kill
TOYBOX_BIN=/system/bin/toybox
TAIL_BIN=/system/bin/tail

$MKDIR_BIN -p "$LOG_DIR" "$SSH_DIR" >/dev/null 2>&1
$TOUCH_BIN "$LOG_FILE" "$DONE_FILE" "$FAIL_DB" "$QUAR_DB" "$INFLIGHT_DB" "$COMPLETE_DB" >/dev/null 2>&1

log(){ printf "%s %s\n" "$( $DATE_BIN "+%F %T")" "$*" >> "$LOG_FILE"; }
pid_alive(){ p="$1"; [ -n "$p" ] && $KILL_BIN -0 "$p" >/dev/null 2>&1; }
read_pid_file(){ [ -f "$1" ] && $CAT_BIN "$1" 2>/dev/null || true; }
health(){
  st="$1"
  detail="$2"
  main_pid=$(read_pid_file "$MAIN_PID_FILE")
  watcher_pid=$(read_pid_file "$WATCHER_PID_FILE")
  watchdog_pid=$(read_pid_file "$WATCHDOG_PID_FILE")
  main_ok=no
  watcher_ok=no
  watchdog_ok=missing
  [ -n "$main_pid" ] && pid_alive "$main_pid" && main_ok=yes
  [ -n "$watcher_pid" ] && pid_alive "$watcher_pid" && watcher_ok=yes
  if [ -n "$watchdog_pid" ]; then
    watchdog_ok=no
    pid_alive "$watchdog_pid" && watchdog_ok=yes
  fi
  effective="$st"
  [ "$st" = "OK" ] && [ "$main_ok" = "no" ] && effective=DEGRADED
  [ "$st" = "OK" ] && [ "$watcher_ok" = "no" ] && effective=DEGRADED
  inflight_bytes=0
  [ -f "$INFLIGHT_DB" ] && inflight_bytes=$($WC_BIN -c < "$INFLIGHT_DB" 2>/dev/null | $TR_BIN -d " " 2>/dev/null) || true
  [ -n "$inflight_bytes" ] || inflight_bytes=0
  last_scan=""
  [ -f "$LAST_SCAN_FILE" ] && last_scan=$($CAT_BIN "$LAST_SCAN_FILE" 2>/dev/null || true)
  event_pending=no
  [ -f "$EVENT_PENDING_FILE" ] && event_pending=yes
  printf "updated_at='%s'\nstatus=%s\ndetail=%s\nmain_pid_ok=%s\nwatcher_pid_ok=%s\nwatchdog_pid_ok=%s\ninflight_bytes=%s\nevent_pending=%s\nlast_scan_epoch=%s\n" \
    "$( $DATE_BIN "+%F %T")" "$effective" "$detail" "$main_ok" "$watcher_ok" "$watchdog_ok" "$inflight_bytes" "$event_pending" "$last_scan" > "$HEALTH_FILE"
}
sq(){ printf "'%s'" "$(printf "%s" "$1" | $SED_BIN "s/'/'\\\\''/g")"; }
lower_name(){ printf "%s" "$1" | $TR_BIN "[:upper:]" "[:lower:]"; }
has_token(){ name="$1"; token="$2"; printf "%s\n" "$name" | $GREP_BIN -Eq "(^|[^[:alnum:]])${token}([^[:alnum:]]|$)"; }

wait_boot(){
  c=0
  while [ "$c" -lt 120 ]; do
    [ "$($GETPROP_BIN sys.boot_completed 2>/dev/null)" = "1" ] && return 0
    $SLEEP_BIN 2
    c=$((c+1))
  done
  return 0
}

normalize_runtime_ssh_config(){ return 0; }


set_dynamic_var(){
  n="$1"; v="$2"
  case "$n" in ""|*[!A-Za-z0-9_]*) return 1;; esac
  eval "$n=$(sq "$v")"
}

load_target_registry(){
  [ -d "$TARGETS_DIR" ] || return 0
  for cf in "$TARGETS_DIR"/*.conf; do
    [ -f "$cf" ] || continue
    target_name=
    enabled=1
    ssh_host=
    remote_drop=
    . "$cf"
    target_name=$(lower_name "$target_name")
    case "$target_name" in ""|*[!a-z0-9_]*) log "WARN target_registry invalid_name file=$cf"; continue;; esac
    [ "${enabled:-1}" = "1" ] || continue
    [ -n "${ssh_host:-}" ] && set_dynamic_var "HOST_$target_name" "$ssh_host"
    [ -n "${remote_drop:-}" ] && set_dynamic_var "REMOTE_DIR_$target_name" "$remote_drop"
  done
}

registry_summary(){
  echo "== target registry =="
  if [ -d "$TARGETS_DIR" ]; then
    for cf in "$TARGETS_DIR"/*.conf; do
      [ -f "$cf" ] || continue
      target_name=
      enabled=1
      ssh_host=
      remote_drop=
      . "$cf"
      printf "%s enabled=%s host=%s remote_drop=%s\n" "$target_name" "${enabled:-1}" "${ssh_host:-}" "${remote_drop:-}"
    done
  else
    echo "missing targets_dir=$TARGETS_DIR"
  fi
}

copy_module_runtime_defaults(){
  $MKDIR_BIN -p "$SSH_DIR" "$CONFIG_DIR" "$TARGETS_DIR" "$TOOLS_DIR" >/dev/null 2>&1 || return 1

  if [ -d "$MODULE_TOOLS_DIR" ]; then
    for x in "$MODULE_TOOLS_DIR"/*.sh; do
      [ -f "$x" ] || continue
      bn=$($BASENAME_BIN "$x")
      $CP_BIN -f "$x" "$TOOLS_DIR/$bn" >/dev/null 2>&1 || true
      $CHMOD_BIN 755 "$TOOLS_DIR/$bn" >/dev/null 2>&1 || true
    done
  fi

  if [ -d "$MODULE_TARGET_DEFAULTS_DIR" ]; then
    for x in "$MODULE_TARGET_DEFAULTS_DIR"/*.conf; do
      [ -f "$x" ] || continue
      bn=$($BASENAME_BIN "$x")
      dst="$TARGETS_DIR/$bn"
      [ -f "$dst" ] || $CP_BIN -f "$x" "$dst" >/dev/null 2>&1 || true
      $CHMOD_BIN 600 "$dst" >/dev/null 2>&1 || true
    done
  fi
}

create_default_config_if_missing(){
  [ -f "$CONFIG_FILE" ] && return 0
  {
    echo "DROP_DISPATCH_SCAN_DIR=/storage/emulated/0/Download"
    echo "DROP_DISPATCH_SETTLE_SECONDS=2"
    echo "DROP_DISPATCH_FALLBACK_RESCAN_SECONDS=1800"
    echo "DROP_DISPATCH_SCAN_MAX_PASSES=8"
    echo "DROP_DISPATCH_STALE_LOCK_SECONDS=600"
    echo "DROP_DISPATCH_WATCHDOG_SECONDS=60"
    echo "SSH_BIN=$SSH_BIN_DEFAULT"
    echo "HOST_alpha=alpha"
    echo "HOST_beta=beta"
    echo "HOST_edge=edge"
    echo "HOST_router=router"
    echo "REMOTE_DIR_alpha=/tmp/ssh-drop-dispatcher-drop"
    echo "REMOTE_DIR_beta=/tmp/ssh-drop-dispatcher-drop"
    echo "REMOTE_DIR_edge=/tmp/ssh-drop-dispatcher-drop"
    echo "REMOTE_DIR_router=/tmp/ssh-drop-dispatcher-drop"
  } > "$CONFIG_FILE"
  $CHMOD_BIN 600 "$CONFIG_FILE" >/dev/null 2>&1 || true
}

import_bundle_if_needed(){
  $MKDIR_BIN -p "$SSH_DIR" "$CONFIG_DIR" "$TARGETS_DIR" "$TOOLS_DIR" >/dev/null 2>&1 || return 1

  # RC2: module-contained tools/default registry are authoritative for v4.10.x.
  # Existing runtime config.env stays authoritative and is not overwritten.
  copy_module_runtime_defaults || return 1
  create_default_config_if_missing || return 1

  bundle_ver=""
  [ -f "$BUNDLE_VERSION_FILE" ] && bundle_ver=$($CAT_BIN "$BUNDLE_VERSION_FILE" 2>/dev/null || true)

  if [ -d "$BUNDLE_DIR/tools" ]; then
    for x in "$BUNDLE_DIR"/tools/*.sh; do
      [ -f "$x" ] || continue
      bn=$($BASENAME_BIN "$x")
      dst="$TOOLS_DIR/$bn"
      [ -f "$dst" ] || $CP_BIN -f "$x" "$dst" >/dev/null 2>&1 || true
      $CHMOD_BIN 755 "$dst" >/dev/null 2>&1 || true
    done
  fi

  if [ -d "$BUNDLE_DIR/config/defaults/targets.d" ]; then
    for x in "$BUNDLE_DIR"/config/defaults/targets.d/*.conf; do
      [ -f "$x" ] || continue
      bn=$($BASENAME_BIN "$x")
      dst="$TARGETS_DIR/$bn"
      [ -f "$dst" ] || $CP_BIN -f "$x" "$dst" >/dev/null 2>&1 || true
      $CHMOD_BIN 600 "$dst" >/dev/null 2>&1 || true
    done
  fi

  # Legacy bundle may still only contain SSH/config from v4.9.x. Import SSH only.
  if [ -d "$BUNDLE_DIR/ssh" ]; then
    for x in id_drop_dispatch_ed25519 id_ed25519 id_rsa known_hosts ssh-config.dispatch; do
      [ -f "$BUNDLE_DIR/ssh/$x" ] && $CP_BIN -f "$BUNDLE_DIR/ssh/$x" "$SSH_DIR/$x" >/dev/null 2>&1 || true
    done
  fi

  [ -f "$SSH_DIR/id_drop_dispatch_ed25519" ] && $CHMOD_BIN 600 "$SSH_DIR/id_drop_dispatch_ed25519" >/dev/null 2>&1 || true
  [ -f "$SSH_DIR/known_hosts" ] && $CHMOD_BIN 600 "$SSH_DIR/known_hosts" >/dev/null 2>&1 || true
  [ -f "$RUNTIME_SSH_CONFIG" ] && $CHMOD_BIN 600 "$RUNTIME_SSH_CONFIG" >/dev/null 2>&1 || true

  module_ver=""
  [ -f "$MODDIR/module.prop" ] && module_ver=$($GREP_BIN -E "^version=" "$MODDIR/module.prop" 2>/dev/null | $SED_BIN "s/^version=//" | $SED_BIN -n "1p")
  [ -n "$module_ver" ] || module_ver="$bundle_ver"
  [ -n "$module_ver" ] || module_ver="unknown"
  printf "%s\n" "$module_ver" > "$IMPORT_STAMP"
}

load_config(){
  [ -f "$CONFIG_FILE" ] || return 1
  . "$CONFIG_FILE"
  DROP_DISPATCH_SCAN_DIR=${DROP_DISPATCH_SCAN_DIR:-${SCAN_DIR:-/storage/emulated/0/Download}}
  DROP_DISPATCH_SETTLE_SECONDS=${DROP_DISPATCH_SETTLE_SECONDS:-2}
  DROP_DISPATCH_FALLBACK_RESCAN_SECONDS=${DROP_DISPATCH_FALLBACK_RESCAN_SECONDS:-1800}
  DROP_DISPATCH_LOG_SKIP_COMPLETE=${DROP_DISPATCH_LOG_SKIP_COMPLETE:-0}
  DROP_DISPATCH_SCAN_MAX_PASSES=${DROP_DISPATCH_SCAN_MAX_PASSES:-8}
  DROP_DISPATCH_STALE_LOCK_SECONDS=${DROP_DISPATCH_STALE_LOCK_SECONDS:-600}
  DROP_DISPATCH_WATCHDOG_SECONDS=${DROP_DISPATCH_WATCHDOG_SECONDS:-60}
  SSH_BIN=${SSH_BIN:-$SSH_BIN_DEFAULT}
  SCP_BIN=$(dirname "$SSH_BIN")/scp
  BASH_BIN=${BASH_BIN:-$BASH_BIN_DEFAULT}
  HOST_alpha=${HOST_alpha:-alpha}
  HOST_beta=${HOST_beta:-beta}
  HOST_edge=${HOST_edge:-edge}
  HOST_router=${HOST_router:-router}
  REMOTE_DIR_alpha=${REMOTE_DIR_alpha:-/tmp/ssh-drop-dispatcher-drop}
  REMOTE_DIR_beta=${REMOTE_DIR_beta:-/tmp/ssh-drop-dispatcher-drop}
  REMOTE_DIR_edge=${REMOTE_DIR_edge:-/tmp/ssh-drop-dispatcher-drop}
  REMOTE_DIR_router=${REMOTE_DIR_router:-/tmp/ssh-drop-dispatcher-drop}
  load_target_registry
}

ensure_ssh_ready(){
  [ -x "$SSH_BIN" ] && [ -x "$SCP_BIN" ] || { log "WAIT missing Termux ssh binary"; health WARN missing_termux_ssh_binary; return 1; }
  if [ ! -f "$SSH_DIR/id_drop_dispatch_ed25519" ] && [ ! -f "$SSH_DIR/id_ed25519" ] && [ ! -f "$SSH_DIR/id_rsa" ]; then
    log "WAIT missing dispatch private key"
    health WARN missing_dispatch_key
    return 1
  fi
  [ -f "$RUNTIME_SSH_CONFIG" ] || { log "WAIT missing runtime ssh config"; health WARN missing_runtime_ssh_config; return 1; }
}

is_partial(){ case "$1" in *.part|*.partial|*.tmp|*.crdownload|*.download|*.opdownload|*.aria2|*.swp|*.lock) return 0;; *) return 1;; esac; }
is_supported(){ case "$1" in *.sh|*.zip|*.tar|*.tar.gz|*.tgz|*.tar.xz|*.txz|*.tar.bz2|*.tbz|*.tbz2|*.gz|*.xz|*.bz2|*.log|*.txt|*.md|*.json|*.conf|*.env) return 0;; *) return 1;; esac; }
is_shell(){ case "$1" in *.sh) return 0;; *) return 1;; esac; }

record(){
  f="$1"
  c=$($CKSUM_BIN "$f" 2>/dev/null | while read -r a b rest; do printf "%s:%s" "$a" "$b"; done)
  b=$($BASENAME_BIN "$f")
  printf "%s|%s" "$b" "$c"
}

already_done(){ $GREP_BIN -Fqx "$1|target=$2" "$DONE_FILE"; }
record_done(){ already_done "$1" "$2" && return 0; printf "%s|target=%s\n" "$1" "$2" >> "$DONE_FILE"; }
complete_recorded(){ $GREP_BIN -Fqx "$1" "$COMPLETE_DB"; }
record_complete(){ complete_recorded "$1" && return 0; printf "%s\n" "$1" >> "$COMPLETE_DB"; }
quarantined(){ $GREP_BIN -Fqx "$1|target=$2|reason=$3|policy=$PIDD_POLICY_VERSION" "$QUAR_DB"; }
add_quarantine(){ quarantined "$1" "$2" "$3" && return 0; printf "%s|target=%s|reason=%s|policy=%s\n" "$1" "$2" "$3" "$PIDD_POLICY_VERSION" >> "$QUAR_DB"; }
inflight(){ $GREP_BIN -Fqx "$1|target=$2" "$INFLIGHT_DB"; }
add_inflight(){ inflight "$1" "$2" && return 0; printf "%s|target=%s\n" "$1" "$2" >> "$INFLIGHT_DB"; }
clear_inflight(){
  rec="$1"; target="$2"; tmp=$($MKTEMP_BIN "$STATE_DIR/inflight.XXXXXX" 2>/dev/null) || tmp="$STATE_DIR/inflight.tmp.$$"
  $GREP_BIN -Fvx "$rec|target=$target" "$INFLIGHT_DB" > "$tmp" 2>/dev/null || true
  $MV_BIN -f "$tmp" "$INFLIGHT_DB" >/dev/null 2>&1 || true
}

local_sh_preflight(){
  file="$1"; base="$2"; targets="$3"
  # target-aware v4.10.0 registry final
  needs_bash=0
  needs_sh=0
  for t in $targets; do
    case "$t" in
      alpha|beta|edge) needs_bash=1 ;;
      router) needs_sh=1 ;;
    esac
  done
  [ "$needs_bash" = "1" ] && [ "$needs_sh" = "1" ] && { log "FAIL local_preflight mixed_shell_targets file=$base"; return 1; }

  first=$($SED_BIN -n "1p" "$file" 2>/dev/null || true)
  if $GREP_BIN -q "$(printf "\r")" "$file" 2>/dev/null; then
    log "FAIL local_preflight crlf file=$base"
    return 1
  fi

  if [ "$needs_sh" = "1" ]; then
    case "$first" in "#!/bin/sh"|"#!/usr/bin/env sh") ;; *) log "FAIL local_preflight shebang file=$base"; return 1;; esac
    /system/bin/sh -n "$file" >/dev/null 2>&1 || { log "FAIL local_preflight sh_syntax file=$base"; return 1; }
    [ -x "$file" ] || log "INFO local_preflight not_executable_normalized_remote file=$base"
    return 0
  fi

  case "$first" in "#!/usr/bin/env bash") ;; *) log "FAIL local_preflight shebang file=$base"; return 1;; esac
  [ -x "$BASH_BIN" ] || { log "FAIL local_preflight bash_unavailable file=$base bin=$BASH_BIN"; return 1; }
  "$BASH_BIN" -n "$file" >/dev/null 2>&1 || { log "FAIL local_preflight bash_syntax file=$base"; return 1; }
  [ -x "$file" ] || log "INFO local_preflight not_executable_normalized_remote file=$base"
  return 0
}

append_target(){ case " $out " in *" $1 "*) ;; *) out="$out $1";; esac; }

marker_targets_for(){
  l="$1"
  case "$l" in
    target-alpha__*) printf " alpha"; return 0 ;;
    target-beta__*) printf " beta"; return 0 ;;
    target-edge__*) printf " edge"; return 0 ;;
    target-router__*) printf " router"; return 0 ;;
  esac
  case "$l" in
    targets-*__*)
      prefix=${l%%__*}
      tokens=${prefix#targets-}
      out=""
      oldifs=$IFS
      IFS="-"
      set -- $tokens
      IFS=$oldifs
      for tok in "$@"; do
        case "$tok" in
          alpha|beta|edge|router) append_target "$tok" ;;
          *) return 1 ;;
        esac
      done
      [ -n "$out" ] || return 1
      printf "%s" "$out"
      return 0
      ;;
  esac
  return 1
}

targets_for(){
  l=$(lower_name "$1")
  mt=$(marker_targets_for "$l" 2>/dev/null || true)
  [ -n "$mt" ] && { printf "%s" "$mt"; return 0; }
  out=""
  has_token "$l" alpha && append_target alpha
  has_token "$l" beta && append_target beta
  has_token "$l" edge && append_target edge
  has_token "$l" router && append_target router
  printf "%s" "$out"
}

target_host(){ eval "printf '%s' \"\${HOST_$1}\""; }
target_dir(){ eval "printf '%s' \"\${REMOTE_DIR_$1}\""; }

remote_verify_basic(){
  host="$1"; dst="$2"; qdst=$(sq "$dst")
  "$SSH_BIN" -F "$RUNTIME_SSH_CONFIG" -o BatchMode=yes -o ConnectTimeout=8 "$host" "sh -c 'test -f $qdst && test -s $qdst'" >/dev/null 2>&1
}

remote_verify_script(){
  target="$1"; host="$2"; dst="$3"; qdst=$(sq "$dst")
  case "$target" in
    alpha) verifier="/usr/local/bin/verify-script.sh" ;;
    beta) verifier="/usr/local/bin/verify-script.sh" ;;
    edge) verifier="/usr/local/bin/verify-script.sh" ;;
    router) verifier="/usr/local/bin/verify-script.sh" ;;
    *) return 1 ;;
  esac
  qver=$(sq "$verifier")
  "$SSH_BIN" -F "$RUNTIME_SSH_CONFIG" -o BatchMode=yes -o ConnectTimeout=12 "$host" "sh -c '$qver $qdst'" >/dev/null 2>&1
}

fully_done_or_blocked(){
  rec="$1"; targets="$2"
  all_done=1
  all_quar=1
  for t in $targets; do
    already_done "$rec" "$t" || all_done=0
    quarantined "$rec" "$t" local_preflight || quarantined "$rec" "$t" verify || all_quar=0
  done
  [ "$all_done" = "1" ] && return 0
  [ "$all_quar" = "1" ] && return 0
  return 1
}

process_file(){
  file="$1"
  [ -f "$file" ] || return 0
  base=$($BASENAME_BIN "$file")
  is_partial "$base" && return 0
  is_supported "$base" || return 0

  rec=$(record "$file")
  targets=$(targets_for "$base")
  [ -n "$targets" ] || return 0

  if complete_recorded "$rec"; then
    [ "${DROP_DISPATCH_LOG_SKIP_COMPLETE:-0}" = "1" ] && log "SKIP complete file=$base"
    return 0
  fi

  if fully_done_or_blocked "$rec" "$targets"; then
    all_done=1
    for t in $targets; do already_done "$rec" "$t" || all_done=0; done
    [ "$all_done" = "1" ] && record_complete "$rec"
    return 0
  fi

  if is_shell "$base"; then
    if ! local_sh_preflight "$file" "$base" "$targets"; then
      for t in $targets; do
        already_done "$rec" "$t" && continue
        add_quarantine "$rec" "$t" local_preflight
        clear_inflight "$rec" "$t"
        log "QUARANTINE target file=$base target=$t reason=local_preflight"
      done
      return 0
    fi
  fi

  for t in $targets; do
    already_done "$rec" "$t" && continue
    quarantined "$rec" "$t" local_preflight && continue
    quarantined "$rec" "$t" verify && continue
    inflight "$rec" "$t" && continue
    add_inflight "$rec" "$t"

    host=$(target_host "$t")
    dir=$(target_dir "$t")
    dst="$dir/$base"
    tmp="$dir/.$base.tmp.$$"
    qdir=$(sq "$dir")
    qtmp=$(sq "$tmp")
    qdst=$(sq "$dst")

    "$SSH_BIN" -F "$RUNTIME_SSH_CONFIG" -o BatchMode=yes -o ConnectTimeout=8 "$host" "sh -c 'mkdir -p $qdir'" >/dev/null 2>&1 || { log "FAIL mkdir file=$base target=$t host=$host"; clear_inflight "$rec" "$t"; continue; }
    "$SCP_BIN" -F "$RUNTIME_SSH_CONFIG" -o BatchMode=yes -o ConnectTimeout=12 "$file" "$host:$tmp" >/dev/null 2>&1 || { log "FAIL scp file=$base target=$t host=$host"; clear_inflight "$rec" "$t"; continue; }
    "$SSH_BIN" -F "$RUNTIME_SSH_CONFIG" -o BatchMode=yes -o ConnectTimeout=8 "$host" "sh -c 'mv -f $qtmp $qdst'" >/dev/null 2>&1 || { log "FAIL rename file=$base target=$t host=$host"; clear_inflight "$rec" "$t"; continue; }

    if is_shell "$base"; then
      "$SSH_BIN" -F "$RUNTIME_SSH_CONFIG" -o BatchMode=yes -o ConnectTimeout=8 "$host" "sh -c 'chmod 755 $qdst'" >/dev/null 2>&1 || true
      remote_verify_script "$t" "$host" "$dst" || { log "FAIL verify file=$base target=$t host=$host"; add_quarantine "$rec" "$t" verify; clear_inflight "$rec" "$t"; continue; }
    else
      remote_verify_basic "$host" "$dst" || { log "FAIL basic_verify file=$base target=$t host=$host"; clear_inflight "$rec" "$t"; continue; }
    fi

    record_done "$rec" "$t"
    clear_inflight "$rec" "$t"
    log "OK upload file=$base target=$t host=$host"
  done

  all_done=1
  for t in $targets; do already_done "$rec" "$t" || all_done=0; done
  [ "$all_done" = "1" ] && { record_complete "$rec"; log "KEEP local file=$base"; }
}

queue_candidate(){
  f="$1"
  [ -f "$f" ] || return 0
  b=$($BASENAME_BIN "$f")
  is_partial "$b" && return 0
  is_supported "$b" || return 0
  targets=$(targets_for "$b")
  [ -n "$targets" ] || return 0
  rec=$(record "$f")
  if complete_recorded "$rec"; then
    [ "${DROP_DISPATCH_LOG_SKIP_COMPLETE:-0}" = "1" ] && log "SKIP complete file=$b"
    return 0
  fi
  fully_done_or_blocked "$rec" "$targets" && return 0
  printf "%s\n" "$f" >> "$TMP_PENDING_LIST"
}

schedule_followup(){
  ( $SLEEP_BIN 5; /data/adb/modules/ssh_drop_dispatcher/service.sh --scan-once event_followup ) >/dev/null 2>&1 &
}

scan_once(){
  reason="$1"
  if ! $MKDIR_BIN "$SCAN_LOCKDIR" >/dev/null 2>&1; then
    log "SKIP scan_locked reason=$reason"
    echo "1" > "$EVENT_PENDING_FILE"
    health WARN scan_locked
    schedule_followup
    return 0
  fi
  now_epoch=$($DATE_BIN +%s 2>/dev/null || echo 0)
  echo "$now_epoch" > "$SCAN_LOCK_TS" 2>/dev/null || true
  echo "$now_epoch" > "$LAST_SCAN_FILE" 2>/dev/null || true
  $RM_BIN -f "$EVENT_PENDING_FILE" >/dev/null 2>&1 || true
  trap "$RM_BIN -rf \"$SCAN_LOCKDIR\" \"$SCAN_LOCK_TS\" \"$TMP_SCAN_LIST\" \"$TMP_PENDING_LIST\" >/dev/null 2>&1 || true" 0 1 2 3 15

  log "START scan_dir=$DROP_DISPATCH_SCAN_DIR reason=$reason"
  $SLEEP_BIN "$DROP_DISPATCH_SETTLE_SECONDS"

  pass=1
  total_processed=0
  max_passes=${DROP_DISPATCH_SCAN_MAX_PASSES:-8}
  while [ "$pass" -le "$max_passes" ]; do
    $FIND_BIN "$DROP_DISPATCH_SCAN_DIR" -maxdepth 1 -type f > "$TMP_SCAN_LIST" 2>/dev/null || true
    : > "$TMP_PENDING_LIST"

    while IFS= read -r f || [ -n "$f" ]; do
      queue_candidate "$f"
    done < "$TMP_SCAN_LIST"

    pending_count=$($WC_BIN -l < "$TMP_PENDING_LIST" 2>/dev/null | $TR_BIN -d " " 2>/dev/null)
    [ -n "$pending_count" ] || pending_count=0
    log "QUEUE pass=$pass pending=$pending_count reason=$reason"
    [ "$pending_count" = "0" ] && break

    processed_count=0
    while IFS= read -r f || [ -n "$f" ]; do
      [ -f "$f" ] || continue
      b=$($BASENAME_BIN "$f")
      log "PROCESS pass=$pass file=$b"
      process_file "$f"
      processed_count=$((processed_count+1))
      total_processed=$((total_processed+1))
    done < "$TMP_PENDING_LIST"

    [ "$processed_count" = "0" ] && break
    pass=$((pass+1))
  done

  log "END passes=$pass processed=$total_processed"
  health OK "$reason"
  $RM_BIN -rf "$SCAN_LOCKDIR" "$SCAN_LOCK_TS" "$TMP_SCAN_LIST" "$TMP_PENDING_LIST" >/dev/null 2>&1 || true
  trap - 0 1 2 3 15
}

status_file(){
  in="$1"
  case "$in" in /*) file="$in" ;; *) file="$DROP_DISPATCH_SCAN_DIR/$in" ;; esac
  base=$($BASENAME_BIN "$file")
  echo "base=$base"
  echo "path=$file"
  if [ -f "$file" ]; then
    rec=$(record "$file")
    echo "exists=yes"
    echo "rec=$rec"
    echo "targets=$(targets_for "$base")"
  else
    rec="unknown"
    echo "exists=no"
    echo "rec=unknown"
    echo "targets=$(targets_for "$base")"
  fi
  for db in dispatch.done dispatch.complete dispatch.faildb dispatch.inflight dispatch.quarantined; do
    echo "--- $db"
    $GREP_BIN -F "$base" "$STATE_DIR/$db" 2>/dev/null || true
  done
  echo "--- log"
  if [ -x "$TAIL_BIN" ]; then
    $GREP_BIN -F "$base" "$LOG_FILE" 2>/dev/null | $TAIL_BIN -n 120 || true
  else
    $GREP_BIN -F "$base" "$LOG_FILE" 2>/dev/null || true
  fi
}

runtime_status(){
  echo "== version =="
  $GREP_BIN -E "^(version=|versionCode=)" "$MODDIR/module.prop" 2>/dev/null || true
  registry_summary
  echo "== tools =="
  for x in dispatch-config.sh pidd-config.sh pidd-doctor.sh pidd-health.sh pidd-migrate-config.sh; do
    [ -x "$TOOLS_DIR/$x" ] && echo "$x=ok" || echo "$x=missing"
  done
  echo "== health =="
  health OK runtime_status
  $CAT_BIN "$HEALTH_FILE" 2>/dev/null || true
  echo "== pids =="
  for f in "$MAIN_PID_FILE" "$WATCHER_PID_FILE" "$WATCHDOG_PID_FILE"; do
    p=$(read_pid_file "$f")
    echo "$f=${p:-missing}"
    [ -n "$p" ] && pid_alive "$p" && echo "alive=yes" || true
  done
}

requeue_file(){
  in="$1"
  [ -n "$in" ] || { echo "FAIL missing_file"; return 1; }
  case "$in" in /*) file="$in" ;; *) file="$DROP_DISPATCH_SCAN_DIR/$in" ;; esac
  [ -f "$file" ] || { echo "FAIL missing_local_file=$file"; return 1; }
  base=$($BASENAME_BIN "$file")
  rec=$(record "$file")
  for db in "$DONE_FILE" "$COMPLETE_DB" "$FAIL_DB" "$INFLIGHT_DB" "$QUAR_DB"; do
    tmp=$($MKTEMP_BIN "$STATE_DIR/requeue.XXXXXX" 2>/dev/null) || tmp="$STATE_DIR/requeue.tmp.$$"
    $GREP_BIN -Fv "$rec" "$db" > "$tmp" 2>/dev/null || true
    $MV_BIN -f "$tmp" "$db" >/dev/null 2>&1 || true
  done
  log "REQUEUE file=$base policy=$PIDD_POLICY_VERSION"
  echo "REQUEUE file=$base rec=$rec policy=$PIDD_POLICY_VERSION"
}

write_handler(){
  cat > "$HANDLER_SCRIPT" <<HANDLER_EOF
#!/system/bin/sh
printf '%s\n' "event" > /data/adb/ssh-drop-dispatcher/.last_event 2>/dev/null || true
/data/adb/modules/ssh_drop_dispatcher/service.sh --scan-once inotify_event >/dev/null 2>&1 &
exit 0
HANDLER_EOF
  $CHMOD_BIN 700 "$HANDLER_SCRIPT" >/dev/null 2>&1 || true
}

start_inotify(){
  write_handler
  if [ -x /system/bin/inotifyd ]; then
    /system/bin/inotifyd "$HANDLER_SCRIPT" "$DROP_DISPATCH_SCAN_DIR:wnm" >/dev/null 2>&1 &
  elif [ -x "$TOYBOX_BIN" ] && "$TOYBOX_BIN" --list 2>/dev/null | $GREP_BIN -qx inotifyd; then
    "$TOYBOX_BIN" inotifyd "$HANDLER_SCRIPT" "$DROP_DISPATCH_SCAN_DIR:wnm" >/dev/null 2>&1 &
  else
    log "WARN inotifyd_unavailable"
    health DEGRADED inotifyd_unavailable
    return 0
  fi
  echo $! > "$WATCHER_PID_FILE"
  log "INFO event-driven watcher started"
}

stop_all(){
  for f in "$WATCHER_PID_FILE" "$MAIN_PID_FILE" "$WATCHDOG_PID_FILE"; do
    [ -f "$f" ] || continue
    p=$($CAT_BIN "$f" 2>/dev/null || true)
    [ -n "$p" ] && $KILL_BIN "$p" >/dev/null 2>&1 || true
    $RM_BIN -f "$f" >/dev/null 2>&1 || true
  done
  $RM_BIN -rf "$SCAN_LOCKDIR" "$SCAN_LOCK_TS" >/dev/null 2>&1 || true
  : > "$INFLIGHT_DB"
}

stale_lock_guard(){
  [ -d "$SCAN_LOCKDIR" ] || return 0
  now=$($DATE_BIN +%s 2>/dev/null || echo 0)
  ts=0
  [ -f "$SCAN_LOCK_TS" ] && ts=$($CAT_BIN "$SCAN_LOCK_TS" 2>/dev/null || echo 0)
  age=$((now - ts))
  [ "$ts" -gt 0 ] || return 0
  if [ "$age" -gt "${DROP_DISPATCH_STALE_LOCK_SECONDS:-600}" ]; then
    log "WARN stale_scan_lock_removed age=$age"
    $RM_BIN -rf "$SCAN_LOCKDIR" "$SCAN_LOCK_TS" >/dev/null 2>&1 || true
    : > "$INFLIGHT_DB"
  fi
}

watchdog_loop(){
  while true; do
    import_bundle_if_needed; load_config || { $SLEEP_BIN 30; continue; }
    watcher_pid=$(read_pid_file "$WATCHER_PID_FILE")
    if ! pid_alive "$watcher_pid"; then
      log "WARN watcher_dead_restart"
      start_inotify
      schedule_followup
    fi
    stale_lock_guard
    health OK watchdog
    $SLEEP_BIN "${DROP_DISPATCH_WATCHDOG_SECONDS:-60}"
  done
}

case "${1:-}" in
  --scan-once)
    reason="${2:-manual_scan}"
    wait_boot; import_bundle_if_needed; load_config || exit 1; ensure_ssh_ready || exit 1; scan_once "$reason"
    ;;
  --status)
    wait_boot; import_bundle_if_needed; load_config || exit 1; status_file "${2:-}"
    ;;
  --runtime-status)
    wait_boot; import_bundle_if_needed; load_config || exit 1; runtime_status
    ;;
  --dispatch-config)
    shift
    wait_boot; import_bundle_if_needed
    if [ -x "$TOOLS_DIR/dispatch-config.sh" ]; then "$TOOLS_DIR/dispatch-config.sh" "$@"; exit $?; fi
    if [ -x "$MODULE_TOOLS_DIR/dispatch-config.sh" ]; then "$MODULE_TOOLS_DIR/dispatch-config.sh" "$@"; exit $?; fi
    echo "dispatch_config_tool=missing"
    exit 1
    ;;

  --setup)
    if [ -x "$MODULE_TOOLS_DIR/sdd-setup.sh" ]; then
      "$MODULE_TOOLS_DIR/sdd-setup.sh"
      exit $?
    fi
    echo "missing setup tool: $MODULE_TOOLS_DIR/sdd-setup.sh"
    exit 1
    ;;

  --setup-target)
    if [ -x "$MODULE_TOOLS_DIR/sdd-setup-target.sh" ]; then
      "$MODULE_TOOLS_DIR/sdd-setup-target.sh"
      exit $?
    fi
    echo "missing setup tool: $MODULE_TOOLS_DIR/sdd-setup-target.sh"
    exit 1
    ;;

  --doctor)
    wait_boot; import_bundle_if_needed; load_config || exit 1
    if [ -x "$TOOLS_DIR/pidd-doctor.sh" ]; then "$TOOLS_DIR/pidd-doctor.sh"; else echo "doctor=missing path=$TOOLS_DIR/pidd-doctor.sh"; exit 1; fi
    ;;
  --config-list)
    wait_boot; import_bundle_if_needed; load_config || exit 1
    if [ -x "$TOOLS_DIR/pidd-config.sh" ]; then "$TOOLS_DIR/pidd-config.sh" list; else echo "config_tool=missing path=$TOOLS_DIR/pidd-config.sh"; exit 1; fi
    ;;
  --config-lint)
    wait_boot; import_bundle_if_needed; load_config || exit 1
    if [ -x "$TOOLS_DIR/pidd-config.sh" ]; then "$TOOLS_DIR/pidd-config.sh" lint; else echo "config_tool=missing path=$TOOLS_DIR/pidd-config.sh"; exit 1; fi
    ;;
  --migrate-config-dry-run)
    wait_boot; import_bundle_if_needed; load_config || exit 1
    if [ -x "$TOOLS_DIR/pidd-migrate-config.sh" ]; then "$TOOLS_DIR/pidd-migrate-config.sh" --dry-run; else echo "migrate_tool=missing path=$TOOLS_DIR/pidd-migrate-config.sh"; exit 1; fi
    ;;
  --requeue)
    wait_boot; import_bundle_if_needed; load_config || exit 1; requeue_file "${2:-}"
    ;;
  --stop)
    stop_all
    ;;
  *)
    wait_boot; import_bundle_if_needed; load_config || exit 0; stop_all; start_inotify; echo $$ > "$MAIN_PID_FILE"; watchdog_loop & echo $! > "$WATCHDOG_PID_FILE"
    while true; do
      import_bundle_if_needed; load_config || { $SLEEP_BIN 30; continue; }
      ensure_ssh_ready || { $SLEEP_BIN 30; continue; }
      scan_once fallback_rescan
      $SLEEP_BIN "$DROP_DISPATCH_FALLBACK_RESCAN_SECONDS"
    done
    ;;
esac
