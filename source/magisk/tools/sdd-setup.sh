#!/system/bin/sh
set -eu

STATE_DIR=${PIDD_STATE_DIR:-/data/adb/ssh-drop-dispatcher}
MODDIR=/data/adb/modules/ssh_drop_dispatcher
CONFIG_ENV="$STATE_DIR/config.env"
DEFAULT_SCAN_DIR="/storage/emulated/0/Download"

ask() {
  prompt="$1"
  default="${2:-}"
  if [ -n "$default" ]; then
    printf "%s [%s]: " "$prompt" "$default"
  else
    printf "%s: " "$prompt"
  fi
  IFS= read -r value || value=""
  if [ -z "$value" ]; then
    printf "%s" "$default"
  else
    printf "%s" "$value"
  fi
}

write_or_replace_config_key() {
  key="$1"
  value="$2"
  file="$3"
  tmp="$file.tmp.$$"

  mkdir -p "$(dirname "$file")"
  if [ -f "$file" ]; then
    awk -v k="$key" -v v="$value" '
      BEGIN { done=0 }
      $0 ~ "^" k "=" {
        print k "=" v
        done=1
        next
      }
      { print }
      END {
        if (done == 0) print k "=" v
      }
    ' "$file" > "$tmp"
  else
    {
      echo "# SSH Drop Dispatcher runtime config"
      echo "KEEP_LOCAL=1"
      echo "SSH_BIN=/data/data/com.termux/files/usr/bin/ssh"
      echo "SCP_BIN=/data/data/com.termux/files/usr/bin/scp"
      echo "$key=$value"
    } > "$tmp"
  fi

  mv "$tmp" "$file"
  chmod 600 "$file"
}

echo "== SSH Drop Dispatcher initial setup =="
echo
echo "This wizard configures the local scan directory."
echo "The default stays:"
echo "$DEFAULT_SCAN_DIR"
echo
echo "Files dropped into this directory are scanned for filename target markers."
echo

scan_dir="$(ask "Local scan directory" "$DEFAULT_SCAN_DIR")"

case "$scan_dir" in
  ""|*[!abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_./@%-]*)
    echo "Invalid scan directory path."
    echo "Allowed characters: letters, numbers, slash, dot, underscore, dash, percent and @."
    exit 2
    ;;
esac

echo
echo "== create/check scan directory =="
mkdir -p "$scan_dir"
test -d "$scan_dir"
test -r "$scan_dir"
test -w "$scan_dir"
echo "scan_dir_ok=$scan_dir"

echo
echo "== write runtime config =="
mkdir -p "$STATE_DIR"
write_or_replace_config_key "DROP_DISPATCH_SCAN_DIR" "$scan_dir" "$CONFIG_ENV"
write_or_replace_config_key "SCAN_DIR" "$scan_dir" "$CONFIG_ENV"

if ! grep -q '^KEEP_LOCAL=' "$CONFIG_ENV"; then
  echo "KEEP_LOCAL=1" >> "$CONFIG_ENV"
fi

echo "config_env=$CONFIG_ENV"
grep -nE '^(SCAN_DIR|KEEP_LOCAL|SSH_BIN|SCP_BIN)=' "$CONFIG_ENV" || true

echo
echo "== optional target setup =="
setup_target="$(ask "Configure an SSH target now? yes/no" "yes")"

case "$setup_target" in
  yes|y|Y)
    if [ -x "$MODDIR/tools/sdd-setup-target.sh" ]; then
      "$MODDIR/tools/sdd-setup-target.sh"
    else
      echo "Target setup tool missing: $MODDIR/tools/sdd-setup-target.sh"
      echo "You can add targets later with:"
      echo "su -c \"$MODDIR/service.sh --setup-target\""
    fi
    ;;
  *)
    echo "Skipped target setup."
    echo "You can add targets later with:"
    echo "su -c \"$MODDIR/service.sh --setup-target\""
    ;;
esac

echo
echo "== next steps =="
echo "Drop files into:"
echo "$scan_dir"
echo
echo "Example after configuring target alpha:"
echo "target-alpha__hello.txt"
echo
echo "Runtime status:"
echo "su -c \"$MODDIR/service.sh --runtime-status\""
echo
echo "RESULT: SSH_DROP_DISPATCHER_INITIAL_SETUP_DONE"
