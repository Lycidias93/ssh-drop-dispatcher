#!/system/bin/sh
set -u

STATE_DIR=${PIDD_STATE_DIR:-/data/adb/ssh-drop-dispatcher}
CONFIG_FILE=$STATE_DIR/config.env
TARGETS_DIR=$STATE_DIR/config/targets.d
SSH_BIN_DEFAULT=/data/data/com.termux/files/usr/bin/ssh

usage(){ echo "pidd-config.sh list|lint|dry-run <filename>|migrate-dry-run|help"; }
lower_name(){ printf "%s" "$1" | tr "[:upper:]" "[:lower:]"; }

load_legacy(){
  [ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE"
  SSH_BIN=${SSH_BIN:-$SSH_BIN_DEFAULT}
  HOST_alpha=${HOST_alpha:-alpha}
  HOST_beta=${HOST_beta:-beta}
  HOST_edge=${HOST_edge:-edge}
  HOST_router=${HOST_router:-router}
  REMOTE_DIR_alpha=${REMOTE_DIR_alpha:-/tmp/ssh-drop-dispatcher-drop}
  REMOTE_DIR_beta=${REMOTE_DIR_beta:-/tmp/ssh-drop-dispatcher-drop}
  REMOTE_DIR_edge=${REMOTE_DIR_edge:-/tmp/ssh-drop-dispatcher-drop}
  REMOTE_DIR_router=${REMOTE_DIR_router:-/tmp/ssh-drop-dispatcher-drop}
}

list_targets(){
  load_legacy
  echo "== legacy config =="
  for t in alpha beta router edge; do
    eval "h=\${HOST_$t}"
    eval "d=\${REMOTE_DIR_$t}"
    printf "%s host=%s remote_drop=%s source=config.env\n" "$t" "$h" "$d"
  done
  echo
  echo "== registry =="
  if [ -d "$TARGETS_DIR" ]; then
    for cf in "$TARGETS_DIR"/*.conf; do
      [ -f "$cf" ] || continue
      target_name= enabled=1 ssh_host= remote_drop= platform= shell= critical_role= scp_flags=
      . "$cf"
      printf "%s enabled=%s host=%s remote_drop=%s platform=%s shell=%s scp_flags=%s verify_owner=dispatcher external_verify_wrapper=no role=%s source=%s\n" \
        "$target_name" "$enabled" "$ssh_host" "$remote_drop" "$platform" "${shell:-missing}" "${scp_flags:-}" "$critical_role" "$cf"
    done
  else
    echo "missing targets_dir=$TARGETS_DIR"
  fi
}

lint_targets(){
  rc=0
  [ -d "$TARGETS_DIR" ] || { echo "WARN missing targets_dir=$TARGETS_DIR"; return 0; }
  seen=" "
  for cf in "$TARGETS_DIR"/*.conf; do
    [ -f "$cf" ] || continue
    if grep -Eq '^(verify|verify_cmd|verify_kind|shell_kind)=' "$cf" 2>/dev/null; then
      echo "FAIL legacy_verify_or_shell_key file=$cf verify_owner=dispatcher external_verify_wrapper=no"
      rc=1
    fi
    target_name= enabled=1 ssh_host= remote_drop= shell=
    . "$cf"
    t=$(lower_name "$target_name")
    case "$t" in
      "") echo "FAIL missing target_name file=$cf"; rc=1; continue ;;
      *[!a-z0-9_]*) echo "FAIL invalid target_name file=$cf value=$target_name"; rc=1; continue ;;
    esac
    case "$seen" in *" $t "*) echo "FAIL duplicate target=$t file=$cf"; rc=1;; *) seen="$seen$t ";; esac
    [ "$enabled" = "0" ] || [ "$enabled" = "1" ] || { echo "FAIL invalid enabled target=$t value=$enabled"; rc=1; }
    [ -n "$ssh_host" ] || { echo "FAIL missing ssh_host target=$t"; rc=1; }
    [ -n "$remote_drop" ] || { echo "FAIL missing remote_drop target=$t"; rc=1; }
    case "$shell" in bash|sh) ;; "") echo "FAIL missing explicit shell target=$t"; rc=1;; *) echo "FAIL invalid shell target=$t value=$shell"; rc=1;; esac
  done
  [ "$rc" = "0" ] && echo "lint=ok verify_owner=dispatcher external_verify_wrapper=no"
  return "$rc"
}

marker_targets_for(){
  l=$(printf "%s" "$1" | tr "[:upper:]" "[:lower:]")
  out=""
  append(){ case " $out " in *" $1 "*) ;; *) out="$out $1";; esac; }
  case "$l" in
    target-alpha__*) echo "alpha"; return;;
    target-beta__*) echo "beta"; return;;
    target-edge__*) echo "edge"; return;;
    target-router__*) echo "router"; return;;
    targets-*__*)
      prefix=${l%%__*}
      tokens=${prefix#targets-}
      oldifs=$IFS; IFS=-
      set -- $tokens
      IFS=$oldifs
      for tok in "$@"; do case "$tok" in alpha|beta|edge|router) append "$tok";; esac; done
      echo "$out"; return;;
  esac
  for tok in alpha beta edge router; do
    echo "$l" | grep -Eq "(^|[^[:alnum:]])${tok}([^[:alnum:]]|$)" && append "$tok"
  done
  echo "$out"
}

dry_run(){
  f="$1"; b=${f##*/}; targets=$(marker_targets_for "$b")
  echo "file=$b"
  echo "targets=$targets"
  [ -n "$targets" ] || { echo "action=ignore"; return 0; }
  load_legacy
  for t in $targets; do
    if [ -f "$TARGETS_DIR/$t.conf" ]; then
      target_name= enabled=1 ssh_host= remote_drop= shell=
      . "$TARGETS_DIR/$t.conf"
      echo "$t host=$ssh_host remote_drop=$remote_drop shell=${shell:-missing} verify_owner=dispatcher external_verify_wrapper=no source=registry"
    else
      eval "h=\${HOST_$t:-}"
      eval "d=\${REMOTE_DIR_$t:-}"
      echo "$t host=$h remote_drop=$d source=legacy"
    fi
  done
  echo "action=would_upload"
}

migrate_dry_run(){
  load_legacy
  echo "mkdir -p $TARGETS_DIR"
  for t in alpha beta router edge; do
    eval "h=\${HOST_$t}"
    eval "d=\${REMOTE_DIR_$t}"
    echo "--- $TARGETS_DIR/$t.conf"
    echo "target_name=\"$t\""
    echo "enabled=\"1\""
    echo "ssh_host=\"$h\""
    echo "remote_drop=\"$d\""
    echo "shell=\"bash\""
  done
}

case "${1:-help}" in
  list) list_targets ;;
  lint) lint_targets ;;
  dry-run) shift; [ $# -eq 1 ] || { usage; exit 2; }; dry_run "$1" ;;
  migrate-dry-run) migrate_dry_run ;;
  help|--help|-h) usage ;;
  *) usage; exit 2 ;;
esac
