#!/system/bin/sh
set -u

STATE_DIR=${SDD_STATE_DIR:-/data/adb/ssh-drop-dispatcher}
TARGETS_DIR=${SDD_TARGET_DIR:-$STATE_DIR/config/targets.d}
CONFIG_TOOL=${SDD_CONFIG_TOOL:-$STATE_DIR/tools/pidd-config.sh}
BACKUP_DIR=$STATE_DIR/backups

lower(){ printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

sanitize_one(){
  file=$1
  target_name=
  shell=
  [ -f "$file" ] || return 0
  . "$file"
  target=$(lower "${target_name:-${file##*/}}")
  target=${target%.conf}
  case "${shell:-}" in bash|sh) resolved_shell=$shell ;;
    *) case "$target" in berylax|router) resolved_shell=sh ;; *) resolved_shell=bash ;; esac ;;
  esac
  tmp="$file.rc2.$$"
  grep -Ev '^(verify|verify_cmd|verify_kind|shell_kind)=' "$file" > "$tmp" 2>/dev/null || true
  if grep -q '^shell=' "$tmp" 2>/dev/null; then
    awk -v v="$resolved_shell" 'BEGIN{done=0} /^shell=/{print "shell=" v; done=1; next} {print} END{if(done==0) print "shell=" v}' "$tmp" > "$tmp.2"
    mv "$tmp.2" "$tmp"
  else
    printf 'shell=%s\n' "$resolved_shell" >> "$tmp"
  fi
  mv "$tmp" "$file"
  chmod 600 "$file" 2>/dev/null || true
  echo "sanitized_target=$target shell=$resolved_shell file=$file"
}

mkdir -p "$TARGETS_DIR" "$BACKUP_DIR" 2>/dev/null || true
ts=$(date +%Y%m%d-%H%M%S 2>/dev/null || echo now)
backup="$BACKUP_DIR/pre-rc2-config-sanitize-$ts"
mkdir -p "$backup" 2>/dev/null || true
for cf in "$TARGETS_DIR"/*.conf; do
  [ -f "$cf" ] || continue
  cp -f "$cf" "$backup/${cf##*/}" 2>/dev/null || true
  sanitize_one "$cf" || exit 1
done

if [ -x "$CONFIG_TOOL" ]; then
  "$CONFIG_TOOL" lint || { echo "RESULT: SDD_CONFIG_SANITIZE_DONE outcome=fail exit_code=1"; exit 1; }
fi

echo "backup_dir=$backup"
echo "verify_owner=dispatcher"
echo "external_verify_wrapper=no"
echo "RESULT: SDD_CONFIG_SANITIZE_DONE outcome=success exit_code=0"
