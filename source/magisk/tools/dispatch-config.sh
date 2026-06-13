#!/system/bin/sh
set -eu

STATE_DIR=${SDD_STATE_DIR:-/data/adb/ssh-drop-dispatcher}
MODDIR=/data/adb/modules/ssh_drop_dispatcher
SERVICE=$MODDIR/service.sh
CONFIG_ENV=$STATE_DIR/config.env
CONFIG_DIR=$STATE_DIR/config
TARGET_DIR=$CONFIG_DIR/targets.d
SSH_DIR=$STATE_DIR/ssh
SSH_CFG=$SSH_DIR/ssh-config.dispatch
BACKUP_DIR=$STATE_DIR/backups
RUNTIME_BIN=$STATE_DIR/bin
RUNTIME_CMD=$RUNTIME_BIN/dispatch-config
DOWNLOAD_DIR=/storage/emulated/0/Download
TERMUX_BIN=/data/data/com.termux/files/usr/bin
TERMUX_CMD=$TERMUX_BIN/dispatch-config
DEFAULT_SCAN_DIR=/storage/emulated/0/Download
DEFAULT_REMOTE_DROP=/tmp/ssh-drop-dispatcher-drop
VERSION=4.12.2-webui-rc1
mkdir -p "$CONFIG_DIR" "$TARGET_DIR" "$SSH_DIR" "$BACKUP_DIR" "$RUNTIME_BIN" "$DOWNLOAD_DIR" >/dev/null 2>&1 || true

ask(){
  prompt="$1"; default="${2:-}"
  if [ -n "$default" ]; then printf "%s [%s]: " "$prompt" "$default" >&2; else printf "%s: " "$prompt" >&2; fi
  IFS= read -r value || value=""
  [ -n "$value" ] && printf "%s" "$value" || printf "%s" "$default"
}

pause(){ printf "\nPress Enter to continue..."; IFS= read -r _ || true; }

safe_path(){
  case "$1" in ""|*[!abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_./@%:+,=-]*) return 1;; *) return 0;; esac
}

write_key(){
  key="$1"; val="$2"; file="$3"; tmp="$file.tmp.$$"
  mkdir -p "$(dirname "$file")"
  if [ -f "$file" ]; then
    awk -v k="$key" -v v="$val" 'BEGIN{done=0} $0 ~ "^" k "=" {print k "=" v; done=1; next} {print} END{if(done==0) print k "=" v}' "$file" > "$tmp"
  else
    {
      echo "# SSH Drop Dispatcher runtime config"
      echo "KEEP_LOCAL=1"
      echo "SSH_BIN=/data/data/com.termux/files/usr/bin/ssh"
      echo "SCP_BIN=/data/data/com.termux/files/usr/bin/scp"
      echo "$key=$val"
    } > "$tmp"
  fi
  mv "$tmp" "$file"
  chmod 600 "$file" 2>/dev/null || true
}

ensure_default_config(){
  [ -f "$CONFIG_ENV" ] || {
    mkdir -p "$STATE_DIR"
    {
      echo "# SSH Drop Dispatcher runtime config"
      echo "KEEP_LOCAL=1"
      echo "DROP_DISPATCH_SCAN_DIR=$DEFAULT_SCAN_DIR"
      echo "DROP_DISPATCH_SETTLE_SECONDS=2"
      echo "DROP_DISPATCH_FALLBACK_RESCAN_SECONDS=1800"
      echo "DROP_DISPATCH_SCAN_MAX_PASSES=8"
      echo "DROP_DISPATCH_STALE_LOCK_SECONDS=600"
      echo "DROP_DISPATCH_WATCHDOG_SECONDS=60"
      echo "SSH_BIN=/data/data/com.termux/files/usr/bin/ssh"
      echo "SCP_BIN=/data/data/com.termux/files/usr/bin/scp"
    } > "$CONFIG_ENV"
    chmod 600 "$CONFIG_ENV" 2>/dev/null || true
  }
  if [ ! -f "$TARGET_DIR/example.conf" ]; then
    mkdir -p "$TARGET_DIR"
    {
      echo "enabled=0"
      echo "target_name=example"
      echo "ssh_host=sdd_example"
      echo "remote_drop=$DEFAULT_REMOTE_DROP"
      echo "platform=linux"
      echo "shell=bash"
      echo "verify=generic"
      echo "role=example"
    } > "$TARGET_DIR/example.conf"
    chmod 600 "$TARGET_DIR/example.conf" 2>/dev/null || true
  fi
}

install_termux_command(){
  mkdir -p "$RUNTIME_BIN"
  cat > "$RUNTIME_CMD" <<'EOF_RUNTIME'
#!/system/bin/sh
STATE_DIR=/data/adb/ssh-drop-dispatcher
TOOL=$STATE_DIR/tools/dispatch-config.sh
MODULE_TOOL=/data/adb/modules/ssh_drop_dispatcher/tools/dispatch-config.sh
if [ -x "$TOOL" ]; then exec "$TOOL" "$@"; fi
if [ -x "$MODULE_TOOL" ]; then exec "$MODULE_TOOL" "$@"; fi
echo "dispatch-config tool missing"
exit 1
EOF_RUNTIME
  chmod 755 "$RUNTIME_CMD" 2>/dev/null || true
  if [ ! -d "$TERMUX_BIN" ]; then
    echo "Termux bin directory missing: $TERMUX_BIN"
    echo "Install Termux first, then run this again."
    return 1
  fi
  cat > "$TERMUX_CMD" <<'EOF_TERMUX'
#!/data/data/com.termux/files/usr/bin/sh
cmd="/data/adb/ssh-drop-dispatcher/bin/dispatch-config"
if [ "$(id -u 2>/dev/null)" = "0" ]; then exec "$cmd" "$@"; fi
quoted="$cmd"
for arg in "$@"; do
  safe=$(printf "%s" "$arg" | sed "s/'/'\\\\''/g")
  quoted="$quoted '$safe'"
done
exec su -c "$quoted"
EOF_TERMUX
  chmod 755 "$TERMUX_CMD" 2>/dev/null || true
  echo "installed=$TERMUX_CMD"
}

remove_termux_command(){
  if [ -f "$TERMUX_CMD" ]; then rm -f "$TERMUX_CMD"; echo "removed=$TERMUX_CMD"; else echo "already_absent=$TERMUX_CMD"; fi
}

initial_setup(){
  ensure_default_config
  if [ -x "$STATE_DIR/tools/sdd-setup.sh" ]; then "$STATE_DIR/tools/sdd-setup.sh"; return $?; fi
  if [ -x "$MODDIR/tools/sdd-setup.sh" ]; then "$MODDIR/tools/sdd-setup.sh"; return $?; fi
  scan_dir=$(ask "Local scan directory" "$DEFAULT_SCAN_DIR")
  safe_path "$scan_dir" || { echo "Invalid path"; return 2; }
  mkdir -p "$scan_dir"
  write_key DROP_DISPATCH_SCAN_DIR "$scan_dir" "$CONFIG_ENV"
  write_key SCAN_DIR "$scan_dir" "$CONFIG_ENV"
  echo "scan_dir=$scan_dir"
}

add_target(){
  ensure_default_config
  if [ -x "$STATE_DIR/tools/sdd-setup-target.sh" ]; then "$STATE_DIR/tools/sdd-setup-target.sh"; return $?; fi
  if [ -x "$MODDIR/tools/sdd-setup-target.sh" ]; then "$MODDIR/tools/sdd-setup-target.sh"; return $?; fi
  echo "Target setup tool missing"
  return 1
}

set_scan_dir(){
  ensure_default_config
  scan_dir=$(ask "Local scan directory" "$DEFAULT_SCAN_DIR")
  safe_path "$scan_dir" || { echo "Invalid path"; return 2; }
  mkdir -p "$scan_dir"
  test -d "$scan_dir" && test -r "$scan_dir" && test -w "$scan_dir"
  write_key DROP_DISPATCH_SCAN_DIR "$scan_dir" "$CONFIG_ENV"
  write_key SCAN_DIR "$scan_dir" "$CONFIG_ENV"
  echo "scan_dir_ok=$scan_dir"
}

list_targets(){
  ensure_default_config
  if [ -x "$SERVICE" ]; then "$SERVICE" --config-list || true; fi
  echo
  echo "target_files=$TARGET_DIR"
  ls -la "$TARGET_DIR" 2>/dev/null || true
}

test_target(){
  ensure_default_config
  target=$(ask "Target name to test" "example")
  case "$target" in ""|*[!abcdefghijklmnopqrstuvwxyz0123456789_-]*) echo "invalid target"; return 2;; esac
  host="$target"
  cf="$TARGET_DIR/$target.conf"
  if [ -f "$cf" ]; then
    ssh_host=
    . "$cf"
    [ -n "${ssh_host:-}" ] && host="$ssh_host"
  fi
  SSH_BIN=${SSH_BIN:-/data/data/com.termux/files/usr/bin/ssh}
  if [ ! -x "$SSH_BIN" ]; then echo "missing ssh=$SSH_BIN"; return 3; fi
  if [ ! -f "$SSH_CFG" ]; then echo "missing ssh config=$SSH_CFG"; return 4; fi
  "$SSH_BIN" -F "$SSH_CFG" "$host" "printf 'SSH_DROP_DISPATCHER_TARGET_OK target=%s\\n' '$target'"
}

redact(){
  sed -E \
    -e 's/[0-9]{1,3}(\.[0-9]{1,3}){3}/<redacted-ip>/g' \
    -e 's#(/data/adb/[^ ]*/ssh/)[^ ]*#\1<redacted>#g' \
    -e 's#(IdentityFile[[:space:]]+).*#\1<redacted>#g' \
    -e 's#(HostName[[:space:]]+).*#\1<redacted-host>#g' \
    -e 's#(Host[[:space:]]+).*#\1<redacted-host>#g'
}

create_issue_txt(){
  ts=$(date +%Y%m%d-%H%M%S 2>/dev/null || echo now)
  out="$DOWNLOAD_DIR/ssh-drop-dispatcher-issue-$ts.txt"
  {
    echo "# SSH Drop Dispatcher support issue"
    echo "created_at=$ts"
    echo "version=$VERSION"
    echo
    echo "## module.prop"
    grep -E '^(id=|name=|version=|versionCode=|author=|description=|updateJson=)' "$MODDIR/module.prop" 2>/dev/null || true
    echo
    echo "## runtime status"
    [ -x "$SERVICE" ] && "$SERVICE" --runtime-status 2>&1 || true
    echo
    echo "## doctor"
    [ -x "$SERVICE" ] && "$SERVICE" --doctor 2>&1 || true
    echo
    echo "## config list"
    [ -x "$SERVICE" ] && "$SERVICE" --config-list 2>&1 || true
    echo
    echo "## files"
    find "$STATE_DIR" -maxdepth 3 -type f 2>/dev/null | sort | sed "s#$STATE_DIR#STATE_DIR#g" || true
    echo
    echo "## recent log"
    tail -n 160 "$STATE_DIR/log/dispatch.log" 2>/dev/null || true
  } | redact > "$out"
  chmod 600 "$out" 2>/dev/null || true
  echo "issue_file=$out"
}

zip_with_python(){
  src="$1"; out="$2"
  py=${PYTHON_BIN:-/data/data/com.termux/files/usr/bin/python3}
  [ -x "$py" ] || py=/data/data/com.termux/files/usr/bin/python
  [ -x "$py" ] || return 1
  "$py" -c 'import os,sys,zipfile; src,out=sys.argv[1],sys.argv[2]; z=zipfile.ZipFile(out,"w",zipfile.ZIP_DEFLATED); root=os.path.abspath(src);
for base,dirs,files in os.walk(root):
  dirs.sort(); files.sort()
  for f in files:
    p=os.path.join(base,f); z.write(p, os.path.relpath(p, root))
z.close()' "$src" "$out"
}

unzip_with_python(){
  zipf="$1"; out="$2"
  py=${PYTHON_BIN:-/data/data/com.termux/files/usr/bin/python3}
  [ -x "$py" ] || py=/data/data/com.termux/files/usr/bin/python
  [ -x "$py" ] || return 1
  "$py" -c 'import sys,zipfile; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])' "$zipf" "$out"
}

backup_export(){
  ensure_default_config
  ts=$(date +%Y%m%d-%H%M%S 2>/dev/null || echo now)
  include_keys=$(ask "Include private SSH keys? yes/no" "no")
  if [ "$include_keys" = "yes" ] || [ "$include_keys" = "y" ]; then
    confirm=$(ask "Type INCLUDE-PRIVATE-KEYS to confirm" "")
    [ "$confirm" = "INCLUDE-PRIVATE-KEYS" ] || { echo "private key export cancelled"; include_keys=no; }
  fi
  work="$STATE_DIR/tmp/export-$ts"
  rm -rf "$work"; mkdir -p "$work/config/targets.d" "$work/ssh"
  {
    echo "backup_format=ssh-drop-dispatcher-v1"
    echo "created_at=$ts"
    echo "version=$VERSION"
    echo "include_private_keys=$include_keys"
  } > "$work/manifest.env"
  [ -f "$CONFIG_ENV" ] && cp -f "$CONFIG_ENV" "$work/config.env"
  if [ -d "$TARGET_DIR" ]; then cp -f "$TARGET_DIR"/*.conf "$work/config/targets.d/" 2>/dev/null || true; fi
  for f in ssh-config.dispatch known_hosts *.pub; do [ -f "$SSH_DIR/$f" ] && cp -f "$SSH_DIR/$f" "$work/ssh/" 2>/dev/null || true; done
  if [ "$include_keys" = "yes" ] || [ "$include_keys" = "y" ]; then
    for f in id_drop_dispatch_ed25519 id_ed25519 id_rsa; do [ -f "$SSH_DIR/$f" ] && cp -f "$SSH_DIR/$f" "$work/ssh/" 2>/dev/null || true; done
  fi
  (cd "$work" && find . -type f | sort | while read -r f; do sha256sum "$f"; done > SHA256SUMS)
  out="$DOWNLOAD_DIR/ssh-drop-dispatcher-backup-$ts.zip"
  rm -f "$out"
  if command -v zip >/dev/null 2>&1; then (cd "$work" && zip -qr "$out" .); else zip_with_python "$work" "$out"; fi
  chmod 600 "$out" 2>/dev/null || true
  echo "backup_zip=$out"
}

backup_current_before_change(){
  ts=$(date +%Y%m%d-%H%M%S 2>/dev/null || echo now)
  dst="$BACKUP_DIR/prechange-$ts"
  mkdir -p "$dst"
  [ -f "$CONFIG_ENV" ] && cp -f "$CONFIG_ENV" "$dst/config.env" 2>/dev/null || true
  [ -d "$TARGET_DIR" ] && mkdir -p "$dst/targets.d" && cp -f "$TARGET_DIR"/*.conf "$dst/targets.d/" 2>/dev/null || true
  [ -d "$SSH_DIR" ] && mkdir -p "$dst/ssh" && cp -f "$SSH_DIR"/* "$dst/ssh/" 2>/dev/null || true
  echo "$dst"
}

restore_import(){
  zipf=$(ask "Backup ZIP path" "$DOWNLOAD_DIR/ssh-drop-dispatcher-backup.zip")
  [ -f "$zipf" ] || { echo "missing zip=$zipf"; return 1; }
  pre=$(backup_current_before_change)
  echo "pre_restore_backup=$pre"
  ts=$(date +%Y%m%d-%H%M%S 2>/dev/null || echo now)
  work="$STATE_DIR/tmp/import-$ts"
  rm -rf "$work"; mkdir -p "$work"
  if command -v unzip >/dev/null 2>&1; then unzip -q "$zipf" -d "$work"; else unzip_with_python "$zipf" "$work"; fi
  [ -f "$work/manifest.env" ] || { echo "missing manifest.env"; return 2; }
  mkdir -p "$TARGET_DIR" "$SSH_DIR"
  [ -f "$work/config.env" ] && cp -f "$work/config.env" "$CONFIG_ENV"
  [ -d "$work/config/targets.d" ] && cp -f "$work/config/targets.d"/*.conf "$TARGET_DIR/" 2>/dev/null || true
  if [ -d "$work/ssh" ]; then
    private_found=$(find "$work/ssh" -maxdepth 1 -type f ! -name '*.pub' ! -name 'known_hosts' ! -name 'ssh-config.dispatch' 2>/dev/null | head -n 1 || true)
    if [ -n "$private_found" ]; then
      confirm=$(ask "Archive contains private SSH key(s). Type IMPORT-PRIVATE-KEYS to import" "")
      if [ "$confirm" = "IMPORT-PRIVATE-KEYS" ]; then cp -f "$work/ssh"/* "$SSH_DIR/" 2>/dev/null || true; else cp -f "$work/ssh"/*.pub "$work/ssh/known_hosts" "$work/ssh/ssh-config.dispatch" "$SSH_DIR/" 2>/dev/null || true; fi
    else
      cp -f "$work/ssh"/* "$SSH_DIR/" 2>/dev/null || true
    fi
  fi
  chmod 600 "$CONFIG_ENV" "$TARGET_DIR"/*.conf "$SSH_DIR"/* 2>/dev/null || true
  echo "restore_done=yes"
}

import_private_runtime(){
  src=/data/adb/pixel-drop-dispatch
  [ -d "$src" ] || { echo "private runtime not found=$src"; return 1; }
  pre=$(backup_current_before_change)
  echo "pre_import_backup=$pre"
  confirm=$(ask "Import config/targets from private runtime? yes/no" "yes")
  case "$confirm" in yes|y|Y) ;; *) echo "cancelled"; return 0;; esac
  mkdir -p "$TARGET_DIR" "$SSH_DIR"
  [ -f "$src/config.env" ] && cp -f "$src/config.env" "$CONFIG_ENV" 2>/dev/null || true
  [ -d "$src/config/targets.d" ] && cp -f "$src/config/targets.d"/*.conf "$TARGET_DIR/" 2>/dev/null || true
  for f in ssh-config.dispatch known_hosts *.pub; do [ -f "$src/ssh/$f" ] && cp -f "$src/ssh/$f" "$SSH_DIR/" 2>/dev/null || true; done
  key_confirm=$(ask "Import private SSH key too? type IMPORT-PRIVATE-KEY or leave empty" "")
  if [ "$key_confirm" = "IMPORT-PRIVATE-KEY" ]; then
    for f in id_drop_dispatch_ed25519 id_ed25519 id_rsa; do [ -f "$src/ssh/$f" ] && cp -f "$src/ssh/$f" "$SSH_DIR/" 2>/dev/null || true; done
  fi
  chmod 600 "$CONFIG_ENV" "$TARGET_DIR"/*.conf "$SSH_DIR"/* 2>/dev/null || true
  echo "private_runtime_import_done=yes"
}


export_private_runtime(){
  src=/data/adb/pixel-drop-dispatch
  [ -d "$src" ] || { echo "private runtime not found=$src"; return 1; }
  ts=$(date +%Y%m%d-%H%M%S 2>/dev/null || echo now)
  include_keys="${SDD_EXPORT_INCLUDE_PRIVATE_KEYS:-}"
  if [ -z "$include_keys" ]; then
    include_keys=$(ask "Include private SSH keys? yes/no" "no")
  fi
  case "$include_keys" in yes|y|Y|1|true|TRUE) include_keys=yes ;; *) include_keys=no ;; esac
  if [ "$include_keys" = "yes" ]; then
    confirm="${SDD_EXPORT_PRIVATE_KEYS_CONFIRM:-}"
    if [ -z "$confirm" ]; then
      confirm=$(ask "Type INCLUDE-PRIVATE-KEYS to confirm" "")
    fi
    [ "$confirm" = "INCLUDE-PRIVATE-KEYS" ] || { echo "private key export cancelled"; include_keys=no; }
  fi
  work="$STATE_DIR/tmp/private-export-$ts"
  rm -rf "$work"; mkdir -p "$work/config/targets.d" "$work/ssh"
  {
    echo "backup_format=ssh-drop-dispatcher-v1"
    echo "source_runtime=pixel-drop-dispatch"
    echo "created_at=$ts"
    echo "version=$VERSION"
    echo "include_private_keys=$include_keys"
  } > "$work/manifest.env"
  [ -f "$src/config.env" ] && cp -f "$src/config.env" "$work/config.env" 2>/dev/null || true
  [ -d "$src/config/targets.d" ] && cp -f "$src/config/targets.d"/*.conf "$work/config/targets.d/" 2>/dev/null || true
  for f in ssh-config.dispatch known_hosts *.pub; do [ -f "$src/ssh/$f" ] && cp -f "$src/ssh/$f" "$work/ssh/" 2>/dev/null || true; done
  if [ "$include_keys" = "yes" ]; then
    for f in id_drop_dispatch_ed25519 id_ed25519 id_rsa; do [ -f "$src/ssh/$f" ] && cp -f "$src/ssh/$f" "$work/ssh/$f" 2>/dev/null || true; done
  fi
  (cd "$work" && find . -type f | sort | while read -r f; do sha256sum "$f"; done > SHA256SUMS)
  out="$DOWNLOAD_DIR/ssh-drop-dispatcher-private-runtime-export-$ts.zip"
  rm -f "$out"
  if command -v zip >/dev/null 2>&1; then (cd "$work" && zip -qr "$out" .); else zip_with_python "$work" "$out"; fi
  chmod 600 "$out" 2>/dev/null || true
  echo "private_runtime_export_zip=$out"
}

reset_defaults(){
  pre=$(backup_current_before_change)
  echo "pre_reset_backup=$pre"
  confirm=$(ask "Reset config and targets to public defaults? yes/no" "no")
  case "$confirm" in yes|y|Y) ;; *) echo "cancelled"; return 0;; esac
  rm -f "$CONFIG_ENV" "$TARGET_DIR"/*.conf 2>/dev/null || true
  delete_keys=$(ask "Delete SSH keys too? yes/no" "no")
  case "$delete_keys" in yes|y|Y) rm -f "$SSH_DIR"/id_* "$SSH_DIR"/*.pub "$SSH_CFG" "$SSH_DIR/known_hosts" 2>/dev/null || true;; esac
  ensure_default_config
  echo "reset_defaults_done=yes"
}

runtime_status(){ [ -x "$SERVICE" ] && "$SERVICE" --runtime-status || echo "service_missing=$SERVICE"; }
doctor(){ [ -x "$SERVICE" ] && "$SERVICE" --doctor || echo "service_missing=$SERVICE"; }

menu(){
  while true; do
    clear 2>/dev/null || true
    echo "SSH Drop Dispatcher Config $VERSION"
    echo
    echo "1) Initial setup"
    echo "2) Add SSH target"
    echo "3) List targets"
    echo "4) Test target"
    echo "5) Set scan directory"
    echo "6) Install Termux command"
    echo "7) Remove Termux command"
    echo "8) Backup/export config ZIP"
    echo "9) Restore/import config ZIP"
    echo "10) Export existing private runtime ZIP"
    echo "11) Import existing private runtime"
    echo "12) Reset to default config"
    echo "13) Create xda/GitHub issue.txt"
    echo "14) Runtime status"
    echo "15) Doctor"
    echo "0) Exit"
    echo
    choice=$(ask "Choose" "0")
    echo
    case "$choice" in
      1) initial_setup; pause ;;
      2) add_target; pause ;;
      3) list_targets; pause ;;
      4) test_target; pause ;;
      5) set_scan_dir; pause ;;
      6) install_termux_command; pause ;;
      7) remove_termux_command; pause ;;
      8) backup_export; pause ;;
      9) restore_import; pause ;;
      10) export_private_runtime; pause ;;
      11) import_private_runtime; pause ;;
      12) reset_defaults; pause ;;
      13) create_issue_txt; pause ;;
      14) runtime_status; pause ;;
      15) doctor; pause ;;
      0) exit 0 ;;
      *) echo "Invalid choice"; pause ;;
    esac
  done
}

case "${1:-}" in
  install-termux-command) install_termux_command ;;
  remove-termux-command) remove_termux_command ;;
  backup|export) backup_export ;;
  restore|import) restore_import ;;
  export-private-runtime) export_private_runtime ;;
  import-private-runtime) import_private_runtime ;;
  reset-defaults) reset_defaults ;;
  issue|issue.txt) create_issue_txt ;;
  status) runtime_status ;;
  doctor) doctor ;;
  setup) initial_setup ;;
  target) add_target ;;
  *) menu ;;
esac
