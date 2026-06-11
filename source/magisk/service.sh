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
BREAKGLASS_LOG=$STATE_DIR/breakglass.log
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
# v4.12.1 delivery-safety keeps Sortify marker policy unchanged.
SORTIFY_RELEASE_DIR=$STATE_DIR/integration/sortify-release

SSH_BIN_DEFAULT=/data/data/com.termux/files/usr/bin/ssh
SCP_BIN_DEFAULT=/data/data/com.termux/files/usr/bin/scp
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

$MKDIR_BIN -p "$LOG_DIR" "$SSH_DIR" "$SORTIFY_RELEASE_DIR" >/dev/null 2>&1
$TOUCH_BIN "$LOG_FILE" "$DONE_FILE" "$FAIL_DB" "$QUAR_DB" "$INFLIGHT_DB" "$COMPLETE_DB" "$BREAKGLASS_LOG" >/dev/null 2>&1

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

append_active_target(){ case " $ACTIVE_TARGETS " in *" $1 "*) ;; *) ACTIVE_TARGETS="$ACTIVE_TARGETS $1";; esac; }

target_known(){ case " $ACTIVE_TARGETS " in *" $1 "*) return 0;; *) return 1;; esac; }

load_target_registry(){
  ACTIVE_TARGETS=""
  [ -d "$TARGETS_DIR" ] || return 0
  for cf in "$TARGETS_DIR"/*.conf; do
    [ -f "$cf" ] || continue
    target_name=
    enabled=1
    ssh_host=
    remote_drop=
    platform=
    shell=
    verify=
    scp_flags=
    . "$cf"
    target_name=$(lower_name "$target_name")
    case "$target_name" in ""|*[!a-z0-9_]*) log "WARN target_registry invalid_name file=$cf"; continue;; esac
    [ "${enabled:-1}" = "1" ] || continue
    append_active_target "$target_name"
    [ -n "${ssh_host:-}" ] && set_dynamic_var "HOST_$target_name" "$ssh_host"
    [ -n "${remote_drop:-}" ] && set_dynamic_var "REMOTE_DIR_$target_name" "$remote_drop"
    if [ -z "${shell:-}" ]; then
      case "${platform:-}" in openwrt|busybox|ash) shell=sh ;; *) shell=bash ;; esac
    fi
    case "$shell" in sh|bash) ;; *) shell=bash ;; esac
    set_dynamic_var "SHELL_$target_name" "$shell"
    if [ -n "${verify:-}" ]; then
      set_dynamic_var "VERIFY_$target_name" "$verify"
    fi
    if [ -z "${scp_flags:-}" ] && [ "$target_name" = "berylax" ]; then
      scp_flags="-O"
    fi
    if [ -n "${scp_flags:-}" ]; then
      printf "%s" "$scp_flags" | $GREP_BIN -Eq "^[A-Za-z0-9_ .:=,/@+-]*$" || { log "WARN target_registry invalid_scp_flags target=$target_name"; scp_flags=""; }
    fi
    [ -n "${scp_flags:-}" ] && set_dynamic_var "SCP_FLAGS_$target_name" "$scp_flags"
  done
  return 0
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
      scp_flags=
      . "$cf"
      t_l=$(lower_name "${target_name:-}")
      [ -z "${scp_flags:-}" ] && [ "$t_l" = "berylax" ] && scp_flags="-O"
      printf "%s enabled=%s host=%s remote_drop=%s scp_flags=%s\n" "$target_name" "${enabled:-1}" "${ssh_host:-}" "${remote_drop:-}" "${scp_flags:-}"
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
    echo "DROP_DISPATCH_ENABLED=1"
    echo "DROP_DISPATCH_STRICT_TARGET_PREFIX=1"
    echo "DROP_DISPATCH_SCAN_DIR=/storage/emulated/0/Download"
    echo "DROP_DISPATCH_SETTLE_SECONDS=2"
    echo "DROP_DISPATCH_FALLBACK_RESCAN_SECONDS=1800"
    echo "DROP_DISPATCH_SCAN_MAX_PASSES=8"
    echo "DROP_DISPATCH_STALE_LOCK_SECONDS=600"
    echo "DROP_DISPATCH_WATCHDOG_SECONDS=60"
    echo "SSH_BIN=$SSH_BIN_DEFAULT"
    echo "SCP_BIN=$SCP_BIN_DEFAULT"
    echo "NTFY_ENABLED=0"
    echo "NTFY_URL="
    echo "NTFY_TOPIC="
    echo "NTFY_PRIORITY=default"
    echo "NTFY_TAGS=package"
    echo "NTFY_TOKEN_FILE="
    echo "REMOTE_MIN_FREE_KB_pi3=3145728"
    echo "REMOTE_MIN_FREE_KB_pi4=3145728"
    echo "REMOTE_MIN_FREE_KB_zeropi2=524288"
    echo "REMOTE_MIN_FREE_KB_berylax=51200"
    echo "REMOTE_WARN_FREE_KB_pi3=5242880"
    echo "REMOTE_WARN_FREE_KB_pi4=5242880"
    echo "REMOTE_WARN_FREE_KB_zeropi2=1048576"
    echo "REMOTE_WARN_FREE_KB_berylax=102400"
    echo "REMOTE_MAX_ARTIFACT_KB_berylax=20480"
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
  DROP_DISPATCH_ENABLED=${DROP_DISPATCH_ENABLED:-1}
  DROP_DISPATCH_STRICT_TARGET_PREFIX=${DROP_DISPATCH_STRICT_TARGET_PREFIX:-1}
  DROP_DISPATCH_SCAN_DIR=${DROP_DISPATCH_SCAN_DIR:-${SCAN_DIR:-/storage/emulated/0/Download}}
  DROP_DISPATCH_SETTLE_SECONDS=${DROP_DISPATCH_SETTLE_SECONDS:-2}
  DROP_DISPATCH_FALLBACK_RESCAN_SECONDS=${DROP_DISPATCH_FALLBACK_RESCAN_SECONDS:-1800}
  DROP_DISPATCH_LOG_SKIP_COMPLETE=${DROP_DISPATCH_LOG_SKIP_COMPLETE:-0}
  DROP_DISPATCH_SCAN_MAX_PASSES=${DROP_DISPATCH_SCAN_MAX_PASSES:-8}
  DROP_DISPATCH_STALE_LOCK_SECONDS=${DROP_DISPATCH_STALE_LOCK_SECONDS:-600}
  DROP_DISPATCH_WATCHDOG_SECONDS=${DROP_DISPATCH_WATCHDOG_SECONDS:-60}
  SSH_BIN=${SSH_BIN:-$SSH_BIN_DEFAULT}
  [ -x "$SSH_BIN" ] || SSH_BIN="$SSH_BIN_DEFAULT"
  SCP_BIN=${SCP_BIN:-$SCP_BIN_DEFAULT}
  [ -x "$SCP_BIN" ] || SCP_BIN=$(dirname "$SSH_BIN")/scp
  [ -x "$SCP_BIN" ] || SCP_BIN="$SCP_BIN_DEFAULT"
  BASH_BIN=${BASH_BIN:-$BASH_BIN_DEFAULT}
  NTFY_ENABLED=${NTFY_ENABLED:-0}
  NTFY_URL=${NTFY_URL:-}
  NTFY_TOPIC=${NTFY_TOPIC:-}
  NTFY_PRIORITY=${NTFY_PRIORITY:-default}
  NTFY_TAGS=${NTFY_TAGS:-package}
  NTFY_TOKEN_FILE=${NTFY_TOKEN_FILE:-}
  REMOTE_MIN_FREE_KB_pi3=${REMOTE_MIN_FREE_KB_pi3:-3145728}
  REMOTE_MIN_FREE_KB_pi4=${REMOTE_MIN_FREE_KB_pi4:-3145728}
  REMOTE_MIN_FREE_KB_zeropi2=${REMOTE_MIN_FREE_KB_zeropi2:-524288}
  REMOTE_MIN_FREE_KB_berylax=${REMOTE_MIN_FREE_KB_berylax:-51200}
  REMOTE_WARN_FREE_KB_pi3=${REMOTE_WARN_FREE_KB_pi3:-5242880}
  REMOTE_WARN_FREE_KB_pi4=${REMOTE_WARN_FREE_KB_pi4:-5242880}
  REMOTE_WARN_FREE_KB_zeropi2=${REMOTE_WARN_FREE_KB_zeropi2:-1048576}
  REMOTE_WARN_FREE_KB_berylax=${REMOTE_WARN_FREE_KB_berylax:-102400}
  REMOTE_MAX_ARTIFACT_KB_berylax=${REMOTE_MAX_ARTIFACT_KB_berylax:-20480}
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
is_sidecar(){ case "$1" in *.sha256|*.sha256sum|*.md5|*.sig|*.asc) return 0;; *) return 1;; esac; }
is_supported(){ is_sidecar "$1" && return 1; case "$1" in *.sh|*.zip|*.tar|*.tar.gz|*.tgz|*.tar.xz|*.txz|*.tar.bz2|*.tbz|*.tbz2|*.gz|*.xz|*.bz2|*.log|*.txt|*.md|*.json|*.conf|*.env) return 0;; *) return 1;; esac; }
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

file_size_bytes(){
  $WC_BIN -c < "$1" 2>/dev/null | $TR_BIN -d " " 2>/dev/null
}

file_sha256(){
  file="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" 2>/dev/null | while read -r h rest; do printf "%s" "$h"; done
    return 0
  fi
  if [ -x /data/data/com.termux/files/usr/bin/sha256sum ]; then
    /data/data/com.termux/files/usr/bin/sha256sum "$file" 2>/dev/null | while read -r h rest; do printf "%s" "$h"; done
    return 0
  fi
  $CKSUM_BIN "$file" 2>/dev/null | while read -r a b rest; do printf "%s-%s" "$a" "$b"; done
}

release_sortify_marker(){
  file="$1"; base="$2"; rec="$3"; targets="$4"; reason="$5"
  [ -f "$file" ] || return 0
  $MKDIR_BIN -p "$SORTIFY_RELEASE_DIR" >/dev/null 2>&1 || return 0
  sum=$(file_sha256 "$file")
  [ -n "$sum" ] || sum=$($CKSUM_BIN "$file" 2>/dev/null | while read -r a b rest; do printf "%s-%s" "$a" "$b"; done)
  size=$(file_size_bytes "$file")
  [ -n "$size" ] || size=0
  tmp="$SORTIFY_RELEASE_DIR/.$sum.env.tmp.$$"
  marker="$SORTIFY_RELEASE_DIR/$sum.env"
  {
    printf "released=yes\n"
    printf "authority=dispatcher\n"
    printf "filename=%s\n" "$(sq "$base")"
    printf "sha256=%s\n" "$sum"
    printf "size=%s\n" "$size"
    printf "rec=%s\n" "$(sq "$rec")"
    printf "targets=%s\n" "$(sq "$targets")"
    printf "done_targets=%s\n" "$(sq "$targets")"
    printf "pending_targets=''\n"
    printf "reason=%s\n" "$(sq "$reason")"
    printf "policy=%s\n" "$PIDD_POLICY_VERSION"
    printf "updated_at=%s\n" "$(sq "$($DATE_BIN '+%F %T' 2>/dev/null || echo now)")"
  } > "$tmp" 2>/dev/null || return 0
  $CHMOD_BIN 600 "$tmp" >/dev/null 2>&1 || true
  $MV_BIN -f "$tmp" "$marker" >/dev/null 2>&1 || true
  log "RELEASE_MARKER file=$base marker=$marker reason=$reason policy=$PIDD_POLICY_VERSION"
}

local_sh_preflight(){
  file="$1"; base="$2"; targets="$3"
  needs_bash=0
  needs_sh=0
  for t in $targets; do
    case "$(target_shell "$t")" in
      sh) needs_sh=1 ;;
      bash|*) needs_bash=1 ;;
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
    target-*__*)
      tok=${l#target-}
      tok=${tok%%__*}
      case "$tok" in ""|*[!a-z0-9_]*) return 1;; esac
      target_known "$tok" || return 1
      printf " %s" "$tok"
      return 0
      ;;
    targets-*__*)
      prefix=${l%%__*}
      tokens=${prefix#targets-}
      out=""
      oldifs=$IFS
      IFS="-"
      set -- $tokens
      IFS=$oldifs
      for tok in "$@"; do
        case "$tok" in ""|*[!a-z0-9_]*) return 1;; esac
        target_known "$tok" || return 1
        append_target "$tok"
      done
      [ -n "$out" ] || return 1
      printf "%s" "$out"
      return 0
      ;;
  esac
  return 1
}

strict_target_prefix(){
  case "${DROP_DISPATCH_STRICT_TARGET_PREFIX:-1}" in 0|no|NO|false|FALSE|off|OFF) return 1 ;; *) return 0 ;; esac
}

targets_for(){
  l=$(lower_name "$1")
  mt=$(marker_targets_for "$l" 2>/dev/null || true)
  [ -n "$mt" ] && { printf "%s" "$mt"; return 0; }
  strict_target_prefix && return 0
  out=""
  for t in $ACTIVE_TARGETS; do
    has_token "$l" "$t" && append_target "$t"
  done
  printf "%s" "$out"
}

target_host(){ eval "printf '%s' \"\${HOST_$1:-}\""; }
target_dir(){ eval "printf '%s' \"\${REMOTE_DIR_$1:-}\""; }
target_shell(){ eval "v=\"\${SHELL_$1:-bash}\""; printf '%s' "$v"; }
target_verify(){ eval "v=\"\${VERIFY_$1:-}\""; printf '%s' "$v"; }
target_scp_flags(){ eval "v=\"\${SCP_FLAGS_$1:-}\""; printf '%s' "$v"; }

# v4.12.1 delivery-safety helpers: target-specific space gates, diagnostics, ntfy notifications, break-glass SCP and delivery wait/status.
target_min_free_kb(){
  case "$1" in
    pi3|pi4) printf "%s" "${REMOTE_MIN_FREE_KB_pi4:-3145728}" ;;
    zeropi2) printf "%s" "${REMOTE_MIN_FREE_KB_zeropi2:-524288}" ;;
    berylax) printf "%s" "${REMOTE_MIN_FREE_KB_berylax:-51200}" ;;
    *) printf "%s" "${REMOTE_MIN_FREE_KB_default:-524288}" ;;
  esac
}

target_warn_free_kb(){
  case "$1" in
    pi3|pi4) printf "%s" "${REMOTE_WARN_FREE_KB_pi4:-5242880}" ;;
    zeropi2) printf "%s" "${REMOTE_WARN_FREE_KB_zeropi2:-1048576}" ;;
    berylax) printf "%s" "${REMOTE_WARN_FREE_KB_berylax:-102400}" ;;
    *) printf "%s" "${REMOTE_WARN_FREE_KB_default:-1048576}" ;;
  esac
}

target_max_artifact_kb(){
  case "$1" in
    berylax) printf "%s" "${REMOTE_MAX_ARTIFACT_KB_berylax:-20480}" ;;
    zeropi2) printf "%s" "${REMOTE_MAX_ARTIFACT_KB_zeropi2:-524288}" ;;
    *) printf "%s" "${REMOTE_MAX_ARTIFACT_KB_default:-0}" ;;
  esac
}

to_int_or_zero(){
  case "$1" in ""|*[!0-9]*) printf "0" ;; *) printf "%s" "$1" ;; esac
}

file_size_kb(){
  bytes=$(file_size_bytes "$1")
  bytes=$(to_int_or_zero "$bytes")
  printf "%s" $(((bytes + 1023) / 1024))
}

remote_available_kb(){
  host="$1"; dir="$2"; qdir=$(sq "$dir")
  "$SSH_BIN" -F "$RUNTIME_SSH_CONFIG" -o BatchMode=yes -o ConnectTimeout=10 "$host" "sh -c 'df -P -k $qdir 2>/dev/null | awk \"NR==2{print \\\$4}\"'" 2>/dev/null | $GREP_BIN -E "^[0-9]+$" | $TAIL_BIN -n 1
}

remote_inode_available(){
  host="$1"; dir="$2"; qdir=$(sq "$dir")
  "$SSH_BIN" -F "$RUNTIME_SSH_CONFIG" -o BatchMode=yes -o ConnectTimeout=10 "$host" "sh -c 'df -P -i $qdir 2>/dev/null | awk \"NR==2{print \\\$4}\"'" 2>/dev/null | $GREP_BIN -E "^[0-9]+$" | $TAIL_BIN -n 1
}

remote_drop_writable(){
  host="$1"; dir="$2"; qdir=$(sq "$dir")
  "$SSH_BIN" -F "$RUNTIME_SSH_CONFIG" -o BatchMode=yes -o ConnectTimeout=10 "$host" "sh -c 'test -d $qdir && test -w $qdir'" >/dev/null 2>&1
}

delivery_space_gate(){
  target="$1"; host="$2"; dir="$3"; file="$4"; base="$5"
  min_kb=$(to_int_or_zero "$(target_min_free_kb "$target")")
  warn_kb=$(to_int_or_zero "$(target_warn_free_kb "$target")")
  max_kb=$(to_int_or_zero "$(target_max_artifact_kb "$target")")
  art_kb=$(file_size_kb "$file")
  avail_kb=$(remote_available_kb "$host" "$dir")
  avail_kb=$(to_int_or_zero "$avail_kb")
  required_kb=$((min_kb + art_kb))

  if [ "$avail_kb" -le 0 ]; then
    log "FAIL space unreadable file=$base target=$target host=$host dir=$dir"
    return 1
  fi
  if [ "$max_kb" -gt 0 ] && [ "$art_kb" -gt "$max_kb" ]; then
    log "FAIL artifact_too_large file=$base target=$target artifact_kb=$art_kb max_artifact_kb=$max_kb"
    return 1
  fi
  if [ "$avail_kb" -lt "$required_kb" ]; then
    log "FAIL remote_space file=$base target=$target avail_kb=$avail_kb required_kb=$required_kb min_free_kb=$min_kb artifact_kb=$art_kb"
    return 1
  fi
  if [ "$warn_kb" -gt 0 ] && [ "$avail_kb" -lt "$warn_kb" ]; then
    log "WARN remote_space_low file=$base target=$target avail_kb=$avail_kb warn_free_kb=$warn_kb"
  fi
  log "PASS space file=$base target=$target avail_kb=$avail_kb min_free_kb=$min_kb artifact_kb=$art_kb max_artifact_kb=$max_kb"
  return 0
}

verify_target_one(){
  t="$1"
  target_known "$t" || { echo "target=$t known=no final_gate=FAIL"; return 1; }
  host=$(target_host "$t")
  dir=$(target_dir "$t")
  scp_flags=$(target_scp_flags "$t")
  shell=$(target_shell "$t")
  min_kb=$(target_min_free_kb "$t")
  warn_kb=$(target_warn_free_kb "$t")
  max_kb=$(target_max_artifact_kb "$t")
  echo "target=$t"
  echo "enabled=yes"
  echo "host=$host"
  echo "remote_drop=$dir"
  echo "shell=$shell"
  echo "scp_flags=$scp_flags"
  echo "remote_min_free_kb=$min_kb"
  echo "remote_warn_free_kb=$warn_kb"
  echo "remote_max_artifact_kb=$max_kb"

  if "$SSH_BIN" -F "$RUNTIME_SSH_CONFIG" -o BatchMode=yes -o ConnectTimeout=10 "$host" "echo ssh_auth=PASS" 2>/dev/null; then
    :
  else
    echo "ssh_auth=FAIL"
    echo "final_gate=FAIL"
    return 1
  fi

  if remote_drop_writable "$host" "$dir"; then
    echo "remote_drop_writable=PASS"
  else
    echo "remote_drop_writable=FAIL"
    echo "final_gate=FAIL"
    return 1
  fi

  avail=$(remote_available_kb "$host" "$dir")
  avail=$(to_int_or_zero "$avail")
  inodes=$(remote_inode_available "$host" "$dir")
  inodes=$(to_int_or_zero "$inodes")
  echo "remote_available_kb=$avail"
  echo "remote_available_inodes=$inodes"
  if [ "$avail" -lt "$min_kb" ]; then
    echo "remote_space_gate=FAIL"
    echo "final_gate=FAIL"
    return 1
  fi
  if [ "$warn_kb" -gt 0 ] && [ "$avail" -lt "$warn_kb" ]; then
    echo "remote_space_gate=WARN"
  else
    echo "remote_space_gate=PASS"
  fi
  echo "final_gate=PASS"
  return 0
}

verify_targets(){
  ensure_ssh_ready || return 1
  rc=0
  for t in $ACTIVE_TARGETS; do
    echo "== verify target $t =="
    verify_target_one "$t" || rc=1
  done
  return "$rc"
}

route_explain(){
  in="$1"
  [ -n "$in" ] || { echo "route_explain=FAIL missing_file"; return 1; }
  case "$in" in /*) file="$in" ;; *) file="$DROP_DISPATCH_SCAN_DIR/$in" ;; esac
  base=$($BASENAME_BIN "$file")
  lower=$(lower_name "$base")
  echo "file=$file"
  echo "base=$base"
  [ -f "$file" ] && echo "exists=yes" || echo "exists=no"
  is_partial "$base" && echo "partial=yes" || echo "partial=no"
  is_sidecar "$base" && echo "sidecar=yes" || echo "sidecar=no"
  is_supported "$base" && echo "supported=yes" || echo "supported=no"
  strict_target_prefix && echo "strict_target_prefix=yes" || echo "strict_target_prefix=no"
  mt=$(marker_targets_for "$lower" 2>/dev/null || true)
  if [ -n "$mt" ]; then
    echo "marker_targets=$mt"
    echo "route_reason=target_prefix"
  else
    echo "marker_targets="
    strict_target_prefix && echo "route_reason=strict_no_valid_prefix" || echo "route_reason=legacy_token_fallback"
  fi
  tg=$(targets_for "$base")
  echo "targets=$tg"
  if [ -f "$file" ]; then
    rec=$(record "$file")
    echo "rec=$rec"
    for db in dispatch.done dispatch.complete dispatch.faildb dispatch.inflight dispatch.quarantined; do
      echo "--- $db"
      $GREP_BIN -F "$rec" "$STATE_DIR/$db" 2>/dev/null || true
    done
  else
    echo "rec=unknown"
  fi
  echo "--- last scan"
  [ -f "$LAST_SCAN_FILE" ] && $CAT_BIN "$LAST_SCAN_FILE" 2>/dev/null || echo "none"
  echo "--- log"
  $GREP_BIN -F "$base" "$LOG_FILE" 2>/dev/null | $TAIL_BIN -n 80 || true
}


# v4.12.1-rc2 break-glass Direct-SCP helpers.
breakglass_fail(){
  reason="$1"
  file="${2:-}"
  target="${3:-}"
  log "BREAKGLASS_FAIL reason=$reason file=$file target=$target host_run=no policy=$PIDD_POLICY_VERSION"
  bgbase="$file"
  case "$bgbase" in */*) bgbase=$($BASENAME_BIN "$bgbase" 2>/dev/null || echo "$file") ;; esac
  notify_delivery FAIL "$target" "$bgbase" "breakglass_$reason"
  echo "breakglass_scp=FAIL"
  echo "reason=$reason"
  echo "file=$file"
  echo "target=$target"
  echo "host_run=no"
  return 1
}

remote_sha256(){
  host="$1"
  path="$2"
  qpath=$(sq "$path")
  "$SSH_BIN" -F "$RUNTIME_SSH_CONFIG" -o BatchMode=yes -o ConnectTimeout=12 "$host" "sh -c 'if command -v sha256sum >/dev/null 2>&1; then sha256sum $qpath; elif command -v busybox >/dev/null 2>&1; then busybox sha256sum $qpath; else cksum $qpath; fi'" 2>/dev/null | $GREP_BIN -E "^[0-9a-f]{64}[[:space:]]" | $TAIL_BIN -n 1 | while read -r h rest; do printf "%s" "$h"; done
}

breakglass_evidence(){
  file="$1"; base="$2"; target="$3"; host="$4"; remote="$5"; local_sha="$6"; remote_sha="$7"; size="$8"; scp_flags="$9"
  {
    printf "%s " "$($DATE_BIN '+%F %T' 2>/dev/null || echo now)"
    printf "BREAKGLASS upload file=%s target=%s host=%s remote=%s sha256=%s remote_sha256=%s size=%s scp_flags=%s policy=%s host_run=no\n" \
      "$base" "$target" "$host" "$remote" "$local_sha" "$remote_sha" "$size" "$(sq "$scp_flags")" "$PIDD_POLICY_VERSION"
  } >> "$BREAKGLASS_LOG" 2>/dev/null || true
  log "BREAKGLASS upload file=$base target=$target host=$host remote=$remote sha256=$local_sha policy=$PIDD_POLICY_VERSION host_run=no"
}

breakglass_scp(){
  in="$1"
  target="$2"
  [ -n "$in" ] || { breakglass_fail missing_file "" "$target"; return 1; }
  [ -n "$target" ] || { breakglass_fail missing_target "$in" ""; return 1; }
  target=$(lower_name "$target")
  target_known "$target" || { breakglass_fail unknown_target "$in" "$target"; return 1; }

  case "$in" in /*) file="$in" ;; *) file="$DROP_DISPATCH_SCAN_DIR/$in" ;; esac
  [ -f "$file" ] || { breakglass_fail missing_local_file "$file" "$target"; return 1; }

  base=$($BASENAME_BIN "$file")
  lower=$(lower_name "$base")
  is_partial "$base" && { breakglass_fail partial_file "$file" "$target"; return 1; }
  is_sidecar "$base" && { breakglass_fail sidecar_blocked "$file" "$target"; return 1; }
  is_supported "$base" || { breakglass_fail unsupported_file_type "$file" "$target"; return 1; }

  route_targets=$(marker_targets_for "$lower" 2>/dev/null || true)
  [ -n "$route_targets" ] || { breakglass_fail invalid_or_missing_target_prefix "$file" "$target"; return 1; }
  case " $route_targets " in *" $target "*) ;; *) breakglass_fail target_not_in_file_prefix "$file" "$target"; return 1;; esac

  if is_shell "$base"; then
    local_sh_preflight "$file" "$base" "$target" || { breakglass_fail local_preflight_failed "$file" "$target"; return 1; }
  fi

  host=$(target_host "$target")
  dir=$(target_dir "$target")
  [ -n "$host" ] || { breakglass_fail missing_host "$file" "$target"; return 1; }
  [ -n "$dir" ] || { breakglass_fail missing_remote_drop "$file" "$target"; return 1; }

  delivery_space_gate "$target" "$host" "$dir" "$file" "$base" || { breakglass_fail space_policy "$file" "$target"; return 1; }

  dst="$dir/$base"
  tmp="$dir/.$base.breakglass.tmp.$$"
  qdir=$(sq "$dir")
  qtmp=$(sq "$tmp")
  qdst=$(sq "$dst")
  size=$(file_size_bytes "$file")
  local_sha=$(file_sha256 "$file")
  scp_flags=$(target_scp_flags "$target")

  "$SSH_BIN" -F "$RUNTIME_SSH_CONFIG" -o BatchMode=yes -o ConnectTimeout=8 "$host" "sh -c 'mkdir -p $qdir && test -d $qdir && test -w $qdir'" >/dev/null 2>&1 || { breakglass_fail remote_drop_not_writable "$file" "$target"; return 1; }
  "$SCP_BIN" $scp_flags -F "$RUNTIME_SSH_CONFIG" -o BatchMode=yes -o ConnectTimeout=12 "$file" "$host:$tmp" >/dev/null 2>&1 || { breakglass_fail scp_failed "$file" "$target"; return 1; }
  "$SSH_BIN" -F "$RUNTIME_SSH_CONFIG" -o BatchMode=yes -o ConnectTimeout=8 "$host" "sh -c 'mv -f $qtmp $qdst'" >/dev/null 2>&1 || { breakglass_fail rename_failed "$file" "$target"; return 1; }

  if is_shell "$base"; then
    "$SSH_BIN" -F "$RUNTIME_SSH_CONFIG" -o BatchMode=yes -o ConnectTimeout=8 "$host" "sh -c 'chmod 755 $qdst'" >/dev/null 2>&1 || true
    remote_verify_script "$target" "$host" "$dst" || { breakglass_fail remote_script_verify_failed "$file" "$target"; return 1; }
  else
    remote_verify_basic "$host" "$dst" || { breakglass_fail remote_basic_verify_failed "$file" "$target"; return 1; }
  fi

  remote_sha=$(remote_sha256 "$host" "$dst")
  local_len=$(printf "%s" "$local_sha" | $WC_BIN -c | $TR_BIN -d " " 2>/dev/null)
  [ "$local_len" = "64" ] || { breakglass_fail local_sha_unavailable "$file" "$target"; return 1; }
  [ "$remote_sha" = "$local_sha" ] || { echo "local_sha256=$local_sha"; echo "remote_sha256=$remote_sha"; breakglass_fail remote_sha_mismatch "$file" "$target"; return 1; }

  breakglass_evidence "$file" "$base" "$target" "$host" "$dst" "$local_sha" "$remote_sha" "$size" "$scp_flags"
  notify_delivery PASS "$target" "$base" breakglass
  echo "breakglass_scp=PASS"
  echo "file=$file"
  echo "base=$base"
  echo "target=$target"
  echo "host=$host"
  echo "remote_path=$dst"
  echo "local_sha256=$local_sha"
  echo "remote_sha256=$remote_sha"
  echo "size=$size"
  echo "scp_flags=$scp_flags"
  echo "policy=$PIDD_POLICY_VERSION"
  echo "host_run=no"
  return 0
}

breakglass_status(){
  in="$1"
  [ -n "$in" ] || { echo "breakglass_status=FAIL missing_file"; return 1; }
  case "$in" in /*) file="$in" ;; *) file="$DROP_DISPATCH_SCAN_DIR/$in" ;; esac
  base=$($BASENAME_BIN "$file")
  echo "breakglass_status_file=$file"
  echo "breakglass_status_base=$base"
  echo "--- breakglass log"
  $GREP_BIN -F "$base" "$BREAKGLASS_LOG" 2>/dev/null | $TAIL_BIN -n 80 || true
  echo "--- dispatch log"
  $GREP_BIN -F "$base" "$LOG_FILE" 2>/dev/null | $TAIL_BIN -n 80 || true
}

breakglass_log_tail(){
  n="${1:-160}"
  case "$n" in ""|*[!0-9]*) n=160 ;; esac
  [ "$n" -lt 20 ] 2>/dev/null && n=20
  [ "$n" -gt 500 ] 2>/dev/null && n=500
  echo "== breakglass log tail =="
  echo "lines=$n"
  if [ -f "$BREAKGLASS_LOG" ]; then
    if [ -x "$TAIL_BIN" ]; then "$TAIL_BIN" -n "$n" "$BREAKGLASS_LOG"; else $CAT_BIN "$BREAKGLASS_LOG"; fi
  else
    echo "breakglass_log_missing=$BREAKGLASS_LOG"
  fi
}

# v4.12.1 rc3 notification + handover helpers: ntfy delivery events, remote-first delivery status and wait diagnostics.
notify_enabled(){
  case "${NTFY_ENABLED:-0}" in 1|yes|YES|true|TRUE|on|ON) return 0 ;; *) return 1 ;; esac
}

ntfy_endpoint(){
  if [ -n "${NTFY_URL:-}" ]; then
    printf "%s" "$NTFY_URL"
    return 0
  fi
  if [ -n "${NTFY_TOPIC:-}" ]; then
    case "$NTFY_TOPIC" in http://*|https://*) printf "%s" "$NTFY_TOPIC" ;; *) printf "https://ntfy.sh/%s" "$NTFY_TOPIC" ;; esac
    return 0
  fi
  return 1
}

notify_delivery(){
  status="$1"
  target="${2:-unknown}"
  base="${3:-unknown}"
  reason="${4:-}"
  notify_enabled || return 0
  url=$(ntfy_endpoint 2>/dev/null || true)
  [ -n "$url" ] || { log "NTFY_SKIP missing_endpoint status=$status target=$target file=$base"; return 0; }
  curl_bin="${CURL_BIN:-}"
  [ -x "$curl_bin" ] || curl_bin=/data/data/com.termux/files/usr/bin/curl
  [ -x "$curl_bin" ] || curl_bin=/system/bin/curl
  [ -x "$curl_bin" ] || { log "NTFY_SKIP curl_missing status=$status target=$target file=$base"; return 0; }
  title="SDD $status target=$target"
  tags="${NTFY_TAGS:-package}"
  priority="${NTFY_PRIORITY:-default}"
  body="file=$base target=$target status=$status reason=$reason host_run=no policy=$PIDD_POLICY_VERSION"
  auth_args=""
  if [ -n "${NTFY_TOKEN_FILE:-}" ] && [ -f "$NTFY_TOKEN_FILE" ]; then
    token=$($CAT_BIN "$NTFY_TOKEN_FILE" 2>/dev/null | $TR_BIN -d "\r\n" 2>/dev/null)
    [ -n "$token" ] && auth_args="-H Authorization: Bearer $token"
  fi
  if [ -n "$auth_args" ]; then
    $curl_bin -fsS -m 8 -H "Title: $title" -H "Priority: $priority" -H "Tags: $tags" -H "Authorization: Bearer $token" -d "$body" "$url" >/dev/null 2>&1 \
      && log "NTFY_SENT status=$status target=$target file=$base reason=$reason" \
      || log "NTFY_FAIL status=$status target=$target file=$base reason=$reason"
  else
    $curl_bin -fsS -m 8 -H "Title: $title" -H "Priority: $priority" -H "Tags: $tags" -d "$body" "$url" >/dev/null 2>&1 \
      && log "NTFY_SENT status=$status target=$target file=$base reason=$reason" \
      || log "NTFY_FAIL status=$status target=$target file=$base reason=$reason"
  fi
  return 0
}

# v4.12.1 rc3 handover helpers: remote-first delivery status and wait diagnostics.
state_has_base(){
  db="$1"; base="$2"
  [ -f "$db" ] || return 1
  $GREP_BIN -F "$base|" "$db" >/dev/null 2>&1
}

state_has_base_target(){
  db="$1"; base="$2"; target="$3"
  [ -f "$db" ] || return 1
  $GREP_BIN -F "$base|" "$db" 2>/dev/null | $GREP_BIN -F "|target=$target" >/dev/null 2>&1
}

sortify_marker_for_base(){
  base="$1"
  [ -d "$SORTIFY_RELEASE_DIR" ] || return 1
  $GREP_BIN -R -F "$base" "$SORTIFY_RELEASE_DIR" >/dev/null 2>&1
}

remote_file_exists(){
  target="$1"; base="$2"
  host=$(target_host "$target")
  dir=$(target_dir "$target")
  dst="$dir/$base"
  qdst=$(sq "$dst")
  "$SSH_BIN" -F "$RUNTIME_SSH_CONFIG" -o BatchMode=yes -o ConnectTimeout=10 "$host" "sh -c 'test -s $qdst'" >/dev/null 2>&1
}

remote_file_digest(){
  target="$1"; base="$2"
  host=$(target_host "$target")
  dir=$(target_dir "$target")
  dst="$dir/$base"
  qdst=$(sq "$dst")
  "$SSH_BIN" -F "$RUNTIME_SSH_CONFIG" -o BatchMode=yes -o ConnectTimeout=10 "$host" "sh -c 'if command -v sha256sum >/dev/null 2>&1; then sha256sum $qdst 2>/dev/null | awk \"{print \\\$1}\"; else cksum $qdst 2>/dev/null | awk \"{print \\\$1\"-\"\\\$2}\"; fi'" 2>/dev/null | $GREP_BIN -E '^[0-9a-fA-F]{64}$|^[0-9]+-[0-9]+$' | $TAIL_BIN -n 1
}

delivery_status(){
  in="$1"
  [ -n "$in" ] || { echo "delivery_status=FAIL missing_file"; echo "host_run=no"; return 1; }
  case "$in" in /*) file="$in" ;; *) file="$DROP_DISPATCH_SCAN_DIR/$in" ;; esac
  base=$($BASENAME_BIN "$file")
  lower=$(lower_name "$base")

  echo "delivery_status_file=$file"
  echo "delivery_status_base=$base"
  echo "host_run=no"
  [ -f "$file" ] && local_exists=yes || local_exists=no
  echo "local_exists=$local_exists"
  is_partial "$base" && partial=yes || partial=no
  is_sidecar "$base" && sidecar=yes || sidecar=no
  is_supported "$base" && supported=yes || supported=no
  strict_target_prefix && strict=yes || strict=no
  echo "partial=$partial"
  echo "sidecar=$sidecar"
  echo "supported=$supported"
  echo "strict_target_prefix=$strict"

  mt=$(marker_targets_for "$lower" 2>/dev/null || true)
  if [ -n "$mt" ]; then
    echo "route_reason=target_prefix"
    echo "marker_targets=$mt"
  else
    echo "route_reason=strict_no_valid_prefix"
    echo "marker_targets="
  fi
  targets=$(targets_for "$base")
  echo "targets=$targets"
  [ -n "$targets" ] || { echo "final_gate=FAIL"; echo "recovery_mode=no_targets"; return 1; }

  if [ "$local_exists" = "yes" ]; then
    rec=$(record "$file")
    echo "rec=$rec"
  else
    rec=""
    echo "rec=unavailable_local_missing"
  fi

  if state_has_base "$COMPLETE_DB" "$base"; then complete=yes; else complete=no; fi
  if sortify_marker_for_base "$base"; then sortify_marker=yes; else sortify_marker=no; fi
  echo "dispatch_complete=$complete"
  echo "sortify_marker=$sortify_marker"

  done_all=yes
  remote_all=yes
  done_targets=""
  remote_targets=""
  missing_targets=""
  for t in $targets; do
    if state_has_base_target "$DONE_FILE" "$base" "$t"; then
      eval "done_${t}=yes"
      done_targets="$done_targets $t"
    else
      eval "done_${t}=no"
      done_all=no
    fi
    eval "echo dispatch_done_${t}=\$done_${t}"

    if remote_file_exists "$t" "$base"; then
      eval "remote_${t}_exists=yes"
      remote_targets="$remote_targets $t"
      digest=$(remote_file_digest "$t" "$base" || true)
      [ -n "$digest" ] || digest=unknown
      eval "remote_${t}_digest=\$digest"
    else
      eval "remote_${t}_exists=no"
      remote_all=no
      missing_targets="$missing_targets $t"
      digest=missing
      eval "remote_${t}_digest=missing"
    fi
    eval "echo remote_${t}_exists=\$remote_${t}_exists"
    eval "echo remote_${t}_digest=\$remote_${t}_digest"
  done
  echo "done_targets=$done_targets"
  echo "remote_targets=$remote_targets"
  echo "missing_targets=$missing_targets"
  echo "dispatch_done_all=$done_all"
  echo "remote_all=$remote_all"

  echo "--- state references"
  for db in dispatch.done dispatch.complete dispatch.quarantined dispatch.faildb dispatch.inflight; do
    echo "--- $db"
    $GREP_BIN -F "$base|" "$STATE_DIR/$db" 2>/dev/null || true
  done
  echo "--- sortify marker references"
  [ -d "$SORTIFY_RELEASE_DIR" ] && $GREP_BIN -R -F "$base" "$SORTIFY_RELEASE_DIR" 2>/dev/null | $TAIL_BIN -n 20 || true
  echo "--- dispatch log tail"
  $GREP_BIN -F "$base" "$LOG_FILE" 2>/dev/null | $TAIL_BIN -n 80 || true

  if [ "$remote_all" = "yes" ] && { [ "$complete" = "yes" ] || [ "$done_all" = "yes" ]; }; then
    echo "final_gate=PASS"
    if [ "$local_exists" = "no" ]; then
      echo "recovery_mode=remote_first"
    else
      echo "recovery_mode=local_source_confirmed"
    fi
    return 0
  fi
  echo "final_gate=FAIL"
  if [ "$local_exists" = "no" ]; then
    echo "recovery_mode=local_missing_incomplete"
  else
    echo "recovery_mode=local_source_waiting"
  fi
  return 1
}

wait_delivery(){
  in="$1"
  timeout="${2:-300}"
  interval="${3:-5}"
  case "$timeout" in ""|*[!0-9]*) timeout=300 ;; esac
  case "$interval" in ""|*[!0-9]*) interval=5 ;; esac
  [ "$timeout" -lt 10 ] 2>/dev/null && timeout=10
  [ "$timeout" -gt 3600 ] 2>/dev/null && timeout=3600
  [ "$interval" -lt 2 ] 2>/dev/null && interval=2
  [ "$interval" -gt 60 ] 2>/dev/null && interval=60
  start=$($DATE_BIN +%s 2>/dev/null || echo 0)
  poll=1
  tmp="$STATE_DIR/wait-delivery.$$.status"
  echo "wait_delivery_file=$in"
  echo "timeout_seconds=$timeout"
  echo "interval_seconds=$interval"
  echo "host_run=no"
  while :; do
    now=$($DATE_BIN +%s 2>/dev/null || echo 0)
    elapsed=$((now - start))
    [ "$elapsed" -lt 0 ] && elapsed=0
    echo "== wait_delivery poll=$poll elapsed=$elapsed timeout=$timeout =="
    echo "phase=delivery_status"
    set +e
    delivery_status "$in" > "$tmp" 2>&1
    st=$?
    set -e
    $CAT_BIN "$tmp" 2>/dev/null || true
    if [ "$st" = "0" ]; then
      $RM_BIN -f "$tmp" >/dev/null 2>&1 || true
      echo "wait_delivery=PASS"
      echo "final_gate=PASS"
      echo "RESULT: SDD_WAIT_DELIVERY_DONE"
      return 0
    fi
    if [ "$elapsed" -ge "$timeout" ]; then
      break
    fi
    echo "phase=sleep interval=$interval"
    $SLEEP_BIN "$interval"
    poll=$((poll + 1))
  done
  $RM_BIN -f "$tmp" >/dev/null 2>&1 || true
  echo "wait_delivery=FAIL"
  echo "final_gate=FAIL"
  echo "RESULT: SDD_WAIT_DELIVERY_TIMEOUT"
  return 1
}

remote_verify_basic(){
  host="$1"; dst="$2"; qdst=$(sq "$dst")
  "$SSH_BIN" -F "$RUNTIME_SSH_CONFIG" -o BatchMode=yes -o ConnectTimeout=8 "$host" "sh -c 'test -f $qdst && test -s $qdst'" >/dev/null 2>&1
}

remote_verify_script(){
  target="$1"; host="$2"; dst="$3"; qdst=$(sq "$dst")
  verifier=$(target_verify "$target")
  if [ -n "$verifier" ]; then
    qver=$(sq "$verifier")
    "$SSH_BIN" -F "$RUNTIME_SSH_CONFIG" -o BatchMode=yes -o ConnectTimeout=12 "$host" "$qver $qdst" >/dev/null 2>&1
    return $?
  fi
  case "$(target_shell "$target")" in
    sh)
      "$SSH_BIN" -F "$RUNTIME_SSH_CONFIG" -o BatchMode=yes -o ConnectTimeout=12 "$host" "sh -n $qdst" >/dev/null 2>&1
      ;;
    bash|*)
      "$SSH_BIN" -F "$RUNTIME_SSH_CONFIG" -o BatchMode=yes -o ConnectTimeout=12 "$host" "if command -v bash >/dev/null 2>&1; then bash -n $qdst; else sh -n $qdst; fi" >/dev/null 2>&1
      ;;
  esac
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
    if [ "$all_done" = "1" ]; then
      record_complete "$rec"
      release_sortify_marker "$file" "$base" "$rec" "$targets" "all_targets_done"
    fi
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

    delivery_space_gate "$t" "$host" "$dir" "$file" "$base" || { notify_delivery FAIL "$t" "$base" space_policy; clear_inflight "$rec" "$t"; continue; }
    "$SSH_BIN" -F "$RUNTIME_SSH_CONFIG" -o BatchMode=yes -o ConnectTimeout=8 "$host" "sh -c 'mkdir -p $qdir'" >/dev/null 2>&1 || { log "FAIL mkdir file=$base target=$t host=$host"; notify_delivery FAIL "$t" "$base" mkdir; clear_inflight "$rec" "$t"; continue; }
    scp_flags=$(target_scp_flags "$t")
    "$SCP_BIN" $scp_flags -F "$RUNTIME_SSH_CONFIG" -o BatchMode=yes -o ConnectTimeout=12 "$file" "$host:$tmp" >/dev/null 2>&1 || { log "FAIL scp file=$base target=$t host=$host scp_flags=$(sq "$scp_flags")"; notify_delivery FAIL "$t" "$base" scp; clear_inflight "$rec" "$t"; continue; }
    "$SSH_BIN" -F "$RUNTIME_SSH_CONFIG" -o BatchMode=yes -o ConnectTimeout=8 "$host" "sh -c 'mv -f $qtmp $qdst'" >/dev/null 2>&1 || { log "FAIL rename file=$base target=$t host=$host"; notify_delivery FAIL "$t" "$base" rename; clear_inflight "$rec" "$t"; continue; }

    if is_shell "$base"; then
      "$SSH_BIN" -F "$RUNTIME_SSH_CONFIG" -o BatchMode=yes -o ConnectTimeout=8 "$host" "sh -c 'chmod 755 $qdst'" >/dev/null 2>&1 || true
      remote_verify_script "$t" "$host" "$dst" || { log "FAIL verify file=$base target=$t host=$host"; notify_delivery FAIL "$t" "$base" verify; add_quarantine "$rec" "$t" verify; clear_inflight "$rec" "$t"; continue; }
    else
      remote_verify_basic "$host" "$dst" || { log "FAIL basic_verify file=$base target=$t host=$host"; notify_delivery FAIL "$t" "$base" basic_verify; clear_inflight "$rec" "$t"; continue; }
    fi

    record_done "$rec" "$t"
    clear_inflight "$rec" "$t"
    log "OK upload file=$base target=$t host=$host"
    notify_delivery PASS "$t" "$base" delivered
  done

  all_done=1
  for t in $targets; do already_done "$rec" "$t" || all_done=0; done
  if [ "$all_done" = "1" ]; then
    record_complete "$rec"
    release_sortify_marker "$file" "$base" "$rec" "$targets" "all_targets_done"
    log "KEEP local file=$base"
  fi
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
  dispatcher_enabled || { log "SKIP disabled reason=$reason"; health WARN disabled; return 0; }
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


dispatcher_enabled(){
  case "${DROP_DISPATCH_ENABLED:-1}" in 0|no|NO|false|FALSE|off|OFF) return 1 ;; *) return 0 ;; esac
}

config_set_key(){
  key="$1"; val="$2"
  case "$key" in ""|*[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_]*) return 2 ;; esac
  $MKDIR_BIN -p "$CONFIG_DIR" >/dev/null 2>&1 || true
  tmp="$CONFIG_FILE.tmp.$$"
  if [ -f "$CONFIG_FILE" ]; then
    $GREP_BIN -v "^$key=" "$CONFIG_FILE" > "$tmp" 2>/dev/null || true
  else
    : > "$tmp"
  fi
  printf "%s=%s\n" "$key" "$val" >> "$tmp"
  $MV_BIN -f "$tmp" "$CONFIG_FILE" >/dev/null 2>&1 || return 1
  $CHMOD_BIN 600 "$CONFIG_FILE" >/dev/null 2>&1 || true
}

set_dispatch_enabled(){
  value="$1"
  case "$value" in 1|true|TRUE|yes|YES|on|ON) normalized=1 ;; 0|false|FALSE|no|NO|off|OFF) normalized=0 ;; *) echo "invalid_enabled_value=$value"; return 2 ;; esac
  config_set_key DROP_DISPATCH_ENABLED "$normalized" || return $?
  DROP_DISPATCH_ENABLED="$normalized"
  if [ "$normalized" = "0" ]; then
    stop_all
    log "CONTROL dispatcher disabled"
    health WARN disabled
    echo "dispatcher_enabled=0"
    echo "runtime_action=stopped"
    return 0
  fi
  log "CONTROL dispatcher enabled"
  echo "dispatcher_enabled=1"
  main_pid=$(read_pid_file "$MAIN_PID_FILE")
  if pid_alive "$main_pid"; then
    echo "service_start_requested=no"
  else
    "$MODDIR/service.sh" >/dev/null 2>&1 &
    echo "service_start_requested=yes"
  fi
  schedule_followup || true
}

webui_log_tail(){
  n="${1:-160}"
  case "$n" in ""|*[!0-9]*) n=160 ;; esac
  [ "$n" -lt 20 ] 2>/dev/null && n=20
  [ "$n" -gt 500 ] 2>/dev/null && n=500
  echo "== dispatch log tail =="
  echo "lines=$n"
  if [ -f "$LOG_FILE" ]; then
    if [ -x "$TAIL_BIN" ]; then "$TAIL_BIN" -n "$n" "$LOG_FILE"; else $CAT_BIN "$LOG_FILE"; fi
  else
    echo "log_missing=$LOG_FILE"
  fi
}

webui_status(){
  echo "== webui control =="
  echo "version=$($GREP_BIN -E '^version=' "$MODDIR/module.prop" 2>/dev/null | $SED_BIN 's/^version=//' | $SED_BIN -n '1p')"
  echo "versionCode=$($GREP_BIN -E '^versionCode=' "$MODDIR/module.prop" 2>/dev/null | $SED_BIN 's/^versionCode=//' | $SED_BIN -n '1p')"
  echo "dispatcher_enabled=${DROP_DISPATCH_ENABLED:-1}"
  echo "strict_target_prefix=${DROP_DISPATCH_STRICT_TARGET_PREFIX:-1}"
  dispatcher_enabled && echo "dispatcher_state=enabled" || echo "dispatcher_state=disabled"
  echo "scan_dir=${DROP_DISPATCH_SCAN_DIR:-}"
  echo "state_dir=$STATE_DIR"
  echo "sortify_release_dir=$SORTIFY_RELEASE_DIR"
  echo "policy=$PIDD_POLICY_VERSION"
  echo
  registry_summary
  echo
  echo "== health =="
  if dispatcher_enabled; then health OK webui_status; else health WARN disabled; fi
  $CAT_BIN "$HEALTH_FILE" 2>/dev/null || true
  echo
  echo "== ntfy delivery notifications =="
  echo "ntfy_enabled=${NTFY_ENABLED:-0}"
  [ -n "${NTFY_URL:-}${NTFY_TOPIC:-}" ] && echo "ntfy_endpoint_configured=yes" || echo "ntfy_endpoint_configured=no"
  echo "ntfy_token_file_configured=$([ -n "${NTFY_TOKEN_FILE:-}" ] && echo yes || echo no)"
  echo "== tools =="
  for x in dispatch-config.sh pidd-config.sh pidd-doctor.sh pidd-health.sh pidd-migrate-config.sh; do
    [ -x "$TOOLS_DIR/$x" ] && echo "$x=ok" || echo "$x=missing"
  done
  echo
  echo "== sortify marker =="
  [ -d "$SORTIFY_RELEASE_DIR" ] && echo "sortify_release_dir=present path=$SORTIFY_RELEASE_DIR" || echo "sortify_release_dir=missing path=$SORTIFY_RELEASE_DIR"
  latest=$($FIND_BIN "$SORTIFY_RELEASE_DIR" -maxdepth 1 -type f -name '*.env' 2>/dev/null | sort | tail -n 1)
  [ -n "$latest" ] && echo "latest_marker=$latest" || echo "latest_marker=none"
  echo
  echo "== pids =="
  for f in "$MAIN_PID_FILE" "$WATCHER_PID_FILE" "$WATCHDOG_PID_FILE"; do
    p=$(read_pid_file "$f")
    echo "$f=${p:-missing}"
    [ -n "$p" ] && pid_alive "$p" && echo "alive=yes" || true
  done
}

runtime_status(){
  echo "== version =="
  $GREP_BIN -E "^(version=|versionCode=)" "$MODDIR/module.prop" 2>/dev/null || true
  registry_summary
  echo "== delivery policy =="
  echo "pi3_min_free_kb=${REMOTE_MIN_FREE_KB_pi3:-3145728}"
  echo "pi4_min_free_kb=${REMOTE_MIN_FREE_KB_pi4:-3145728}"
  echo "zeropi2_min_free_kb=${REMOTE_MIN_FREE_KB_zeropi2:-524288}"
  echo "berylax_min_free_kb=${REMOTE_MIN_FREE_KB_berylax:-51200}"
  echo "berylax_warn_free_kb=${REMOTE_WARN_FREE_KB_berylax:-102400}"
  echo "berylax_max_artifact_kb=${REMOTE_MAX_ARTIFACT_KB_berylax:-20480}"
  echo "== tools =="
  for x in dispatch-config.sh pidd-config.sh pidd-doctor.sh pidd-health.sh pidd-migrate-config.sh; do
    [ -x "$TOOLS_DIR/$x" ] && echo "$x=ok" || echo "$x=missing"
  done
  echo "== health =="
  health OK runtime_status
  $CAT_BIN "$HEALTH_FILE" 2>/dev/null || true
  echo "== sortify marker =="
  [ -d "$SORTIFY_RELEASE_DIR" ] && echo "sortify_release_dir=present path=$SORTIFY_RELEASE_DIR" || echo "sortify_release_dir=missing path=$SORTIFY_RELEASE_DIR"
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
  --enable)
    wait_boot; import_bundle_if_needed; load_config || create_default_config_if_missing || exit 1; set_dispatch_enabled 1
    ;;
  --disable)
    wait_boot; import_bundle_if_needed; load_config || create_default_config_if_missing || exit 1; set_dispatch_enabled 0
    ;;
  --dispatch-now|--scan-now)
    wait_boot; import_bundle_if_needed; load_config || exit 1; dispatcher_enabled || { echo "dispatcher_enabled=0"; health WARN disabled; exit 2; }; ensure_ssh_ready || exit 1; scan_once webui_dispatch_now
    ;;
  --webui-status)
    wait_boot; import_bundle_if_needed; load_config || exit 1; webui_status
    ;;
  --webui-log-tail)
    wait_boot; import_bundle_if_needed; load_config || exit 1; webui_log_tail "${2:-160}"
    ;;
  --scan-once)
    reason="${2:-manual_scan}"
    wait_boot; import_bundle_if_needed; load_config || exit 1; ensure_ssh_ready || exit 1; scan_once "$reason"
    ;;
  --verify-targets)
    wait_boot; import_bundle_if_needed; load_config || exit 1; verify_targets
    ;;
  --verify-target)
    wait_boot; import_bundle_if_needed; load_config || exit 1; ensure_ssh_ready || exit 1; verify_target_one "${2:-}"
    ;;
  --route-explain)
    wait_boot; import_bundle_if_needed; load_config || exit 1; route_explain "${2:-}"
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
  --breakglass-scp)
    wait_boot; import_bundle_if_needed; load_config || exit 1; ensure_ssh_ready || exit 1; breakglass_scp "${2:-}" "${3:-}"
    ;;
  --breakglass-status)
    wait_boot; import_bundle_if_needed; load_config || exit 1; breakglass_status "${2:-}"
    ;;
  --breakglass-log-tail)
    wait_boot; import_bundle_if_needed; load_config || exit 1; breakglass_log_tail "${2:-160}"
    ;;


  --delivery-status)
    wait_boot; import_bundle_if_needed; load_config || exit 1; ensure_ssh_ready || exit 1; delivery_status "${2:-}"
    ;;
  --wait-delivery)
    wait_boot; import_bundle_if_needed; load_config || exit 1; ensure_ssh_ready || exit 1; wait_delivery "${2:-}" "${3:-300}" "${4:-5}"
    ;;

  --requeue)
    wait_boot; import_bundle_if_needed; load_config || exit 1; requeue_file "${2:-}"
    ;;
  --stop)
    stop_all
    ;;
  *)
    wait_boot; import_bundle_if_needed; load_config || exit 0
    if ! dispatcher_enabled; then stop_all; log "DISABLED service_start skipped"; health WARN disabled; exit 0; fi
    stop_all; start_inotify; echo $$ > "$MAIN_PID_FILE"; watchdog_loop & echo $! > "$WATCHDOG_PID_FILE"
    while true; do
      import_bundle_if_needed; load_config || { $SLEEP_BIN 30; continue; }
      if ! dispatcher_enabled; then stop_all; log "DISABLED runtime loop stopped"; health WARN disabled; exit 0; fi
      ensure_ssh_ready || { $SLEEP_BIN 30; continue; }
      scan_once fallback_rescan
      $SLEEP_BIN "$DROP_DISPATCH_FALLBACK_RESCAN_SECONDS"
    done
    ;;
esac
