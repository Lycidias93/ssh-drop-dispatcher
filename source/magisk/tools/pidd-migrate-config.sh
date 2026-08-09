#!/system/bin/sh
set -u

STATE_DIR=${PIDD_STATE_DIR:-/data/adb/ssh-drop-dispatcher}
CONFIG_FILE=$STATE_DIR/config.env
TARGETS_DIR=$STATE_DIR/config/targets.d
BACKUP_DIR=$STATE_DIR/config/backups
mode=${1:---dry-run}

load_legacy(){
  [ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE"
  HOST_alpha=${HOST_alpha:-alpha}
  HOST_beta=${HOST_beta:-beta}
  HOST_edge=${HOST_edge:-edge}
  HOST_router=${HOST_router:-router}
  REMOTE_DIR_alpha=${REMOTE_DIR_alpha:-/tmp/ssh-drop-dispatcher-drop}
  REMOTE_DIR_beta=${REMOTE_DIR_beta:-/tmp/ssh-drop-dispatcher-drop}
  REMOTE_DIR_edge=${REMOTE_DIR_edge:-/tmp/ssh-drop-dispatcher-drop}
  REMOTE_DIR_router=${REMOTE_DIR_router:-/tmp/ssh-drop-dispatcher-drop}
}

emit_conf(){
  t="$1"; h="$2"; d="$3"; role="$4"; shell="$5"
  cat <<CONF
target_name="$t"
enabled="1"
aliases="$t"
ssh_user="root"
ssh_host="$h"
ssh_port="22"
remote_drop="$d"
platform="generic"
shell="$shell"
critical_role="$role"
allow_fallback="0"
CONF
}

write_target(){
  t="$1"; h="$2"; d="$3"; role="$4"; shell="$5"
  dst="$TARGETS_DIR/$t.conf"
  [ -f "$dst" ] && { echo "keep existing $dst"; return 0; }
  emit_conf "$t" "$h" "$d" "$role" "$shell" > "$dst"
  chmod 600 "$dst" 2>/dev/null || true
  echo "wrote $dst"
}

load_legacy

case "$mode" in
  --dry-run)
    echo "mode=dry-run"
    echo "verify_owner=dispatcher"
    echo "external_verify_wrapper=no"
    for t in alpha beta router edge; do
      eval "h=\${HOST_$t}"
      eval "d=\${REMOTE_DIR_$t}"
      echo "--- $TARGETS_DIR/$t.conf"
      case "$t" in
        alpha) emit_conf "$t" "$h" "$d" master bash ;;
        beta) emit_conf "$t" "$h" "$d" backup bash ;;
        router) emit_conf "$t" "$h" "$d" router sh ;;
        edge) emit_conf "$t" "$h" "$d" external bash ;;
      esac
    done ;;
  --apply)
    ts=$(date +%Y%m%d-%H%M%S)
    mkdir -p "$TARGETS_DIR" "$BACKUP_DIR"
    tar -czf "$BACKUP_DIR/pre-rc2-$ts.tar.gz" -C "$STATE_DIR" config.env config 2>/dev/null || true
    write_target alpha "$HOST_alpha" "$REMOTE_DIR_alpha" master bash
    write_target beta "$HOST_beta" "$REMOTE_DIR_beta" backup bash
    write_target router "$HOST_router" "$REMOTE_DIR_router" router sh
    write_target edge "$HOST_edge" "$REMOTE_DIR_edge" external bash
    echo "migration=ok backup_dir=$BACKUP_DIR"
    echo "verify_owner=dispatcher"
    echo "external_verify_wrapper=no"
    echo "RESULT: SDD_CONFIG_MIGRATION_DONE outcome=success exit_code=0" ;;
  *) echo "usage: pidd-migrate-config.sh --dry-run|--apply"; exit 2 ;;
esac
