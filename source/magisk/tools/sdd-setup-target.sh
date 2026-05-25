#!/system/bin/sh
set -eu

STATE_DIR=${SDD_STATE_DIR:-/data/adb/ssh-drop-dispatcher}
MODDIR=${0%/tools/sdd-setup-target.sh}
TARGET_DIR="$STATE_DIR/config/targets.d"
SSH_DIR="$STATE_DIR/ssh"
SSH_CFG="$SSH_DIR/ssh-config.dispatch"
KEY_FILE="$SSH_DIR/id_ed25519"
DEFAULT_REMOTE_DROP="/tmp/ssh-drop-dispatcher-drop"

SSH_BIN=${SSH_BIN:-/data/data/com.termux/files/usr/bin/ssh}
SCP_BIN=${SCP_BIN:-/data/data/com.termux/files/usr/bin/scp}
SSH_KEYGEN_BIN=${SSH_KEYGEN_BIN:-/data/data/com.termux/files/usr/bin/ssh-keygen}

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

require_name() {
  name="$1"
  case "$name" in
    ""|*[!abcdefghijklmnopqrstuvwxyz0123456789_-]*)
      echo "Invalid target name. Use lowercase letters, numbers, underscore or dash only."
      exit 2
      ;;
  esac
}

require_tool() {
  label="$1"
  path="$2"
  if [ ! -x "$path" ]; then
    echo "Missing $label at: $path"
    echo "Install Termux openssh or set the matching environment variable."
    exit 3
  fi
}

append_or_replace_host() {
  alias="$1"
  host="$2"
  user="$3"
  port="$4"
  key="$5"

  tmp="$SSH_CFG.tmp.$$"
  if [ -f "$SSH_CFG" ]; then
    awk -v h="$alias" '
      BEGIN { skip=0 }
      /^Host[[:space:]]+/ {
        skip=0
        for (i=2; i<=NF; i++) {
          if ($i == h) skip=1
        }
      }
      skip == 0 { print }
    ' "$SSH_CFG" > "$tmp"
  else
    : > "$tmp"
  fi

  {
    echo ""
    echo "Host $alias"
    echo "  HostName $host"
    echo "  User $user"
    echo "  Port $port"
    echo "  IdentityFile $key"
    echo "  IdentitiesOnly yes"
    echo "  StrictHostKeyChecking accept-new"
  } >> "$tmp"

  mv "$tmp" "$SSH_CFG"
  chmod 600 "$SSH_CFG"
}

echo "== SSH Drop Dispatcher target setup =="
echo
echo "This wizard creates:"
echo "- an SSH key if missing"
echo "- an SSH config alias"
echo "- a dispatcher target config"
echo "- the remote drop directory"
echo
echo "No private data is uploaded anywhere except to the SSH target you choose."
echo

require_tool "ssh" "$SSH_BIN"
require_tool "ssh-keygen" "$SSH_KEYGEN_BIN"

mkdir -p "$TARGET_DIR" "$SSH_DIR"
chmod 700 "$SSH_DIR"

target="$(ask "Target name" "alpha")"
require_name "$target"

ssh_host="$(ask "SSH host or IP" "")"
if [ -z "$ssh_host" ]; then
  echo "SSH host is required."
  exit 4
fi

ssh_user="$(ask "SSH user" "$(id -un 2>/dev/null || echo user)")"
ssh_port="$(ask "SSH port" "22")"
remote_drop="$(ask "Remote drop directory" "$DEFAULT_REMOTE_DROP")"
shell_type="$(ask "Remote shell type, bash or sh" "bash")"

case "$shell_type" in
  bash|sh) ;;
  *)
    echo "Invalid shell type: $shell_type"
    exit 5
    ;;
esac

alias_name="sdd_${target}"

echo
echo "== key =="
if [ ! -f "$KEY_FILE" ]; then
  "$SSH_KEYGEN_BIN" -t ed25519 -f "$KEY_FILE" -N "" -C "ssh-drop-dispatcher-$target"
  chmod 600 "$KEY_FILE"
  chmod 644 "$KEY_FILE.pub"
  echo "Created key: $KEY_FILE"
else
  echo "Key exists: $KEY_FILE"
fi

echo
echo "== ssh config =="
append_or_replace_host "$alias_name" "$ssh_host" "$ssh_user" "$ssh_port" "$KEY_FILE"
echo "Configured SSH alias: $alias_name"

echo
echo "== public key =="
cat "$KEY_FILE.pub"

echo
echo "== install public key on target =="
echo "The next step may ask for the SSH password of $ssh_user@$ssh_host."
install_key="$(ask "Install public key to target authorized_keys now? yes/no" "yes")"

case "$install_key" in
  yes|y|Y)
    cat "$KEY_FILE.pub" | "$SSH_BIN" -F "$SSH_CFG" "$alias_name" \
      "umask 077; mkdir -p ~/.ssh; touch ~/.ssh/authorized_keys; grep -qxF \"$(cat "$KEY_FILE.pub")\" ~/.ssh/authorized_keys || cat >> ~/.ssh/authorized_keys"
    echo "Public key installed or already present."
    ;;
  *)
    echo "Skipped key install."
    echo "Manually add this public key to the target user's ~/.ssh/authorized_keys."
    ;;
esac

echo
echo "== create remote drop directory =="
"$SSH_BIN" -F "$SSH_CFG" "$alias_name" "mkdir -p '$remote_drop' && test -d '$remote_drop'"
echo "Remote drop directory OK: $remote_drop"

echo
echo "== write target config =="
target_conf="$TARGET_DIR/$target.conf"
cat > "$target_conf" <<EOF
enabled=1
target_name=$target
ssh_host=$alias_name
host=$alias_name
remote_drop=$remote_drop
platform=linux
shell=$shell_type
verify=generic
role=user
EOF
chmod 600 "$target_conf"
echo "Target config written: $target_conf"

echo
echo "== ssh smoke test =="
"$SSH_BIN" -F "$SSH_CFG" "$alias_name" "printf 'SSH_DROP_DISPATCHER_TARGET_OK target=%s\n' '$target'"
echo "SSH smoke test OK"

echo
echo "== dispatcher config list =="
if [ -x "/data/adb/modules/ssh_drop_dispatcher/service.sh" ]; then
  /data/adb/modules/ssh_drop_dispatcher/service.sh --config-list || true
else
  echo "service.sh not found at /data/adb/modules/ssh_drop_dispatcher/service.sh"
fi

echo
echo "Next test file name:"
echo "target-${target}__hello.txt"
echo
echo "RESULT: SSH_DROP_DISPATCHER_TARGET_SETUP_DONE"
