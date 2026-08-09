#!/system/bin/sh
set -u

STATE_DIR=${SDD_STATE_DIR:-/data/adb/ssh-drop-dispatcher}
MODDIR=${SDD_MODDIR:-/data/adb/modules/ssh_drop_dispatcher}
LEGACY=${SDD_LEGACY_CONFIG_TOOL:-$MODDIR/tools/dispatch-config.sh}
SDD_TOOL=${SDD_TOOL:-$STATE_DIR/tools/sdd.sh}
BRIDGE=${SDD_TERMUX_INSTALL_TOOL:-$STATE_DIR/tools/sdd-termux-install.sh}
SETUP=${SDD_SETUP_TOOL:-$MODDIR/tools/sdd-setup.sh}
SETUP_TARGET=${SDD_SETUP_TARGET_TOOL:-$MODDIR/tools/sdd-setup-target.sh}
SANITIZER=${SDD_CONFIG_SANITIZER:-$STATE_DIR/tools/sdd-config-sanitize.sh}
MODULE_PROP=${SDD_MODULE_PROP:-$MODDIR/module.prop}

[ -x "$SDD_TOOL" ] || SDD_TOOL=$MODDIR/tools/sdd.sh
[ -x "$BRIDGE" ] || BRIDGE=$MODDIR/tools/sdd-termux-install.sh
[ -x "$SANITIZER" ] || SANITIZER=$MODDIR/tools/sdd-config-sanitize.sh

module_field(){
  key=$1
  [ -f "$MODULE_PROP" ] || return 1
  sed -n "s/^${key}=//p" "$MODULE_PROP" | head -n 1
}
VERSION=$(module_field version 2>/dev/null || true)
[ -n "$VERSION" ] || VERSION=unknown

ask(){
  prompt=$1
  default=${2:-}
  if [ -n "$default" ]; then printf '%s [%s]: ' "$prompt" "$default" >&2; else printf '%s: ' "$prompt" >&2; fi
  IFS= read -r value || value=
  [ -n "$value" ] && printf '%s' "$value" || printf '%s' "$default"
}

pause(){ printf '\nPress Enter to continue...'; IFS= read -r _ || true; }

need_exec(){
  label=$1
  path=$2
  [ -x "$path" ] && return 0
  echo "dispatch_config_v2=FAIL missing_${label}=$path"
  return 69
}

run_sdd(){
  need_exec sdd "$SDD_TOOL" || return $?
  "$SDD_TOOL" "$@"
}

run_legacy(){
  need_exec legacy_config "$LEGACY" || return $?
  "$LEGACY" "$@"
}

sanitize_config(){
  need_exec config_sanitizer "$SANITIZER" || return $?
  "$SANITIZER"
}

run_legacy_mutating(){
  cmd=$1
  run_legacy "$cmd" || return $?
  sanitize_config
}

install_termux(){ need_exec bridge "$BRIDGE" || return $?; "$BRIDGE" install; }
remove_termux(){ need_exec bridge "$BRIDGE" || return $?; "$BRIDGE" remove; }
bridge_status(){ need_exec bridge "$BRIDGE" || return $?; "$BRIDGE" status; }

setup(){ need_exec setup "$SETUP" || return $?; "$SETUP"; }
setup_target(){ need_exec setup_target "$SETUP_TARGET" || return $?; "$SETUP_TARGET"; }

test_target(){
  target=${1:-}
  [ -n "$target" ] || target=$(ask "Target name to test" "example")
  run_sdd target test "$target"
}

usage(){
  cat <<'EOF_USAGE'
SSH Drop Dispatcher Config frontend v2
Usage: dispatch-config [command]
Commands: setup, target, targets, test-target [name], status, doctor,
  install-termux-command, remove-termux-command, bridge-status,
  backup|export, restore|import, export-private-runtime,
  import-private-runtime, reset-defaults, issue, help
Legacy imports/resets are sanitized to the dispatcher-owned verification schema before returning.
No command opens the compatibility menu.
EOF_USAGE
}

menu(){
  while true; do
    clear 2>/dev/null || true
    echo "SSH Drop Dispatcher Config $VERSION"
    echo "CLI frontend: v2"
    echo
    echo "1) Initial setup"
    echo "2) Add SSH target"
    echo "3) List targets"
    echo "4) Test target"
    echo "5) Runtime status"
    echo "6) Doctor"
    echo "7) Install/repair Termux commands"
    echo "8) Termux bridge status"
    echo "9) Backup/export config ZIP"
    echo "10) Restore/import config ZIP"
    echo "11) Export existing private runtime ZIP"
    echo "12) Import existing private runtime"
    echo "13) Reset to default config"
    echo "14) Create xda/GitHub issue.txt"
    echo "0) Exit"
    echo
    choice=$(ask "Choose" "0")
    echo
    case "$choice" in
      1) setup; pause ;;
      2) setup_target; pause ;;
      3) run_sdd targets --env; pause ;;
      4) test_target; pause ;;
      5) run_sdd status --env; pause ;;
      6) run_sdd doctor; pause ;;
      7) install_termux; pause ;;
      8) bridge_status; pause ;;
      9) run_legacy backup; pause ;;
      10) run_legacy_mutating restore; pause ;;
      11) run_legacy export-private-runtime; pause ;;
      12) run_legacy_mutating import-private-runtime; pause ;;
      13) run_legacy_mutating reset-defaults; pause ;;
      14) run_legacy issue; pause ;;
      0) exit 0 ;;
      *) echo "Invalid choice"; pause ;;
    esac
  done
}

case "${1:-}" in
  "") menu ;;
  help|--help|-h) usage ;;
  setup) setup ;;
  target) setup_target ;;
  targets|list-targets) run_sdd targets --env ;;
  test-target) shift; test_target "${1:-}" ;;
  status) run_sdd status --env ;;
  doctor) run_sdd doctor ;;
  install-termux-command|install-termux) install_termux ;;
  remove-termux-command|remove-termux) remove_termux ;;
  bridge-status) bridge_status ;;
  restore|import|import-private-runtime|reset-defaults) run_legacy_mutating "$1" ;;
  backup|export|export-private-runtime|issue|issue.txt) run_legacy "$1" ;;
  *) usage >&2; echo "RESULT: SDD_DISPATCH_CONFIG_V2_DONE outcome=usage_error exit_code=64"; exit 64 ;;
esac
