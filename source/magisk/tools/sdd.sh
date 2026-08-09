#!/system/bin/sh
set -u

STATE_DIR=${SDD_STATE_DIR:-/data/adb/ssh-drop-dispatcher}
MODDIR=${SDD_MODDIR:-/data/adb/modules/ssh_drop_dispatcher}
SERVICE=${SDD_SERVICE:-$MODDIR/service.sh}
MODULE_PROP=${SDD_MODULE_PROP:-$MODDIR/module.prop}
TARGET_DIR=${SDD_TARGET_DIR:-$STATE_DIR/config/targets.d}
HEALTH_FILE=${SDD_HEALTH_FILE:-$STATE_DIR/health.env}
VERIFY_OWNER_FILE=${SDD_VERIFY_OWNER_FILE:-$STATE_DIR/verification-owner.env}
LOG_FILE=${SDD_LOG_FILE:-$STATE_DIR/log/dispatch.log}
CONFIG_TOOL=${SDD_CONFIG_TOOL:-$STATE_DIR/tools/dispatch-config.sh}
DOCTOR_TOOL=${SDD_DOCTOR_TOOL:-$STATE_DIR/tools/pidd-doctor.sh}
TERMUX_INSTALL_TOOL=${SDD_TERMUX_INSTALL_TOOL:-$STATE_DIR/tools/sdd-termux-install.sh}
TERMUX_BIN=${SDD_TERMUX_BIN:-/data/data/com.termux/files/usr/bin}
SDD_CLI_SCHEMA=2
SDD_CHATGPT_CONTEXT_SCHEMA=1
FORMAT=env
NO_PROMPT=0
ARGC=0; ARG1=; ARG2=; ARG3=; ARG4=; ARG5=; ARG6=
SELF_DIR=${0%/*}
[ -f "$SELF_DIR/sdd-lib.sh" ] || SELF_DIR=$STATE_DIR/tools
. "$SELF_DIR/sdd-lib.sh"
. "$SELF_DIR/sdd-machine.sh"

usage(){
  cat <<'EOF_USAGE'
SSH Drop Dispatcher CLI v2
Usage: sdd [--env|--json] [--no-prompt] <command> [args]
Commands: version, capabilities, status, targets, target test <name>, dispatch,
  delivery status <file>, delivery wait <file> [timeout] [interval], requeue <file>,
  logs [lines], doctor [--chatgpt], chatgpt-context, snapshot, explain <code>,
  config [legacy dispatch-config args], install-termux, bridge-status, help
EOF_USAGE
}

add_arg(){
  ARGC=$((ARGC+1))
  case "$ARGC" in 1) ARG1=$1;; 2) ARG2=$1;; 3) ARG3=$1;; 4) ARG4=$1;; 5) ARG5=$1;; 6) ARG6=$1;; *) usage_error too_many_arguments; exit 64;; esac
}

while [ "$#" -gt 0 ]; do case "$1" in --json) FORMAT=json; shift;; --env) FORMAT=env; shift;; --no-prompt) NO_PROMPT=1; shift;; --help|-h) set -- help; break;; --) shift; break;; *) break;; esac; done
cmd=${1:-help}; [ "$#" -gt 0 ] && shift || true
for arg in "$@"; do case "$arg" in --json) FORMAT=json;; --env) FORMAT=env;; --no-prompt) NO_PROMPT=1;; --chatgpt) add_arg "$arg";; --*) usage_error "unknown_option_$arg"; exit 64;; *) add_arg "$arg";; esac; done

find_doctor(){ [ -x "$DOCTOR_TOOL" ] && { printf '%s' "$DOCTOR_TOOL"; return; }; [ -x "$MODDIR/tools/pidd-doctor.sh" ] && printf '%s' "$MODDIR/tools/pidd-doctor.sh"; }
find_bridge(){ [ -x "$TERMUX_INSTALL_TOOL" ] && { printf '%s' "$TERMUX_INSTALL_TOOL"; return; }; [ -x "$MODDIR/tools/sdd-termux-install.sh" ] && printf '%s' "$MODDIR/tools/sdd-termux-install.sh"; }

case "$cmd" in
  version) [ "$ARGC" -eq 0 ] || { usage_error version_arguments; exit 64; }; emit_version ;;
  capabilities) [ "$ARGC" -eq 0 ] || { usage_error capabilities_arguments; exit 64; }; emit_capabilities ;;
  status) [ "$ARGC" -eq 0 ] || { usage_error status_arguments; exit 64; }; emit_status ;;
  targets) [ "$ARGC" -eq 0 ] || { usage_error targets_arguments; exit 64; }; emit_targets ;;
  target) [ "$ARGC" -eq 2 ] && [ "$ARG1" = test ] || { usage_error target_arguments; exit 64; }; run_service target-test --verify-target "$ARG2" ;;
  dispatch) [ "$ARGC" -eq 0 ] || { usage_error dispatch_arguments; exit 64; }; run_service dispatch --dispatch-now ;;
  delivery)
    [ "$ARGC" -ge 2 ] || { usage_error delivery_arguments; exit 64; }
    case "$ARG1:$ARGC" in status:2) run_service delivery-status --delivery-status "$ARG2";; wait:2) run_service delivery-wait --wait-delivery "$ARG2";; wait:3) run_service delivery-wait --wait-delivery "$ARG2" "$ARG3";; wait:4) run_service delivery-wait --wait-delivery "$ARG2" "$ARG3" "$ARG4";; *) usage_error delivery_arguments; exit 64;; esac ;;
  requeue) [ "$ARGC" -eq 1 ] || { usage_error requeue_arguments; exit 64; }; run_service requeue --requeue "$ARG1" ;;
  logs) case "$ARGC" in 0) run_service logs --webui-log-tail 160;; 1) run_service logs --webui-log-tail "$ARG1";; *) usage_error logs_arguments; exit 64;; esac ;;
  doctor)
    if [ "$ARGC" -eq 0 ]; then run_service doctor --doctor
    elif [ "$ARGC" -eq 1 ] && [ "$ARG1" = --chatgpt ]; then tool=$(find_doctor); [ -n "$tool" ] || { echo "doctor=missing"; exit 69; }; "$tool" --redacted; rc=$?; [ "$rc" -eq 0 ] && outcome=success || outcome=degraded; echo "RESULT: SDD_DOCTOR_CHATGPT_DONE outcome=$outcome exit_code=$rc"; exit "$rc"
    else usage_error doctor_arguments; exit 64; fi ;;
  chatgpt-context|snapshot) [ "$ARGC" -eq 0 ] || { usage_error context_arguments; exit 64; }; emit_chatgpt_context ;;
  explain) [ "$ARGC" -eq 1 ] || { usage_error explain_arguments; exit 64; }; emit_explain "$ARG1" ;;
  config)
    [ "$NO_PROMPT" -eq 0 ] || { echo "sdd_cli=STOP reason=interactive_config_blocked_no_prompt"; echo "RESULT: SDD_CLI_DONE command=config outcome=blocked exit_code=64"; exit 64; }
    [ -x "$CONFIG_TOOL" ] || CONFIG_TOOL=$MODDIR/tools/dispatch-config.sh; [ -x "$CONFIG_TOOL" ] || { echo "sdd_cli=FAIL reason=config_tool_missing"; exit 69; }
    case "$ARGC" in 0) "$CONFIG_TOOL";; 1) "$CONFIG_TOOL" "$ARG1";; 2) "$CONFIG_TOOL" "$ARG1" "$ARG2";; 3) "$CONFIG_TOOL" "$ARG1" "$ARG2" "$ARG3";; *) usage_error config_arguments; exit 64;; esac ;;
  install-termux|bridge-status)
    tool=$(find_bridge); [ -n "$tool" ] || { echo "sdd_cli=FAIL reason=termux_installer_missing"; exit 69; }; [ "$ARGC" -eq 0 ] || { usage_error bridge_arguments; exit 64; }; [ "$cmd" = install-termux ] && "$tool" install || "$tool" status ;;
  help) usage ;;
  *) usage_error "unknown_command_$cmd"; usage >&2; exit 64 ;;
esac
