#!/usr/bin/env bash
set -euo pipefail

ROOT=${1:-$(cd "$(dirname "$0")/.." && pwd)}
SDD="$ROOT/source/magisk/tools/sdd.sh"
BRIDGE="$ROOT/source/magisk/tools/sdd-termux-install.sh"
DOCTOR="$ROOT/source/magisk/tools/pidd-doctor.sh"
CUSTOMIZE="$ROOT/source/magisk/customize.sh"
PROP="$ROOT/source/magisk/module.prop"

for f in "$SDD" "$ROOT/source/magisk/tools/sdd-lib.sh" "$ROOT/source/magisk/tools/sdd-machine.sh" "$BRIDGE" "$DOCTOR" "$CUSTOMIZE"; do
  /bin/sh -n "$f"
done

grep -Fx 'version=4.13.0-verify-owner-rc2' "$PROP" >/dev/null
grep -Fx 'versionCode=4130002' "$PROP" >/dev/null
grep -F 'SDD_CLI_SCHEMA=2' "$SDD" >/dev/null
grep -F 'SDD_CHATGPT_CONTEXT_SCHEMA=1' "$SDD" >/dev/null
grep -F 'RESULT: SDD_CHATGPT_CONTEXT_DONE' "$ROOT/source/magisk/tools/sdd-machine.sh" >/dev/null
grep -F 'bridge_contract=sdd-termux-v2' "$BRIDGE" >/dev/null
! grep -F 'eval ' "$BRIDGE" >/dev/null

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
state="$work/state"
mod="$work/module"
termux="$work/termux-bin"
mkdir -p "$state/config/targets.d" "$state/tools" "$state/log" "$mod/tools" "$termux"
cp "$PROP" "$mod/module.prop"

cat > "$mod/service.sh" <<EOF_SERVICE
#!/bin/sh
case "\${1:-}" in
  --runtime-status) exit 0 ;;
  --verify-target) echo "target_verify=PASS target=\${2:-}"; exit 0 ;;
  --dispatch-now) echo "dispatch=PASS"; exit 0 ;;
  --delivery-status) echo "delivery_status=PASS file=\${2:-}"; exit 0 ;;
  --wait-delivery) echo "wait_delivery=PASS file=\${2:-}"; exit 0 ;;
  --requeue) echo "requeue=PASS file=\${2:-}"; exit 0 ;;
  --webui-log-tail) echo "log_tail=PASS"; exit 0 ;;
  --doctor) echo "doctor=ok"; exit 0 ;;
  *) exit 0 ;;
esac
EOF_SERVICE
chmod +x "$mod/service.sh"

cat > "$state/health.env" <<'EOF_HEALTH'
status=OK
detail=test
main_pid_ok=yes
watcher_pid_ok=yes
watchdog_pid_ok=yes
inflight_bytes=0
event_pending=no
EOF_HEALTH
cat > "$state/verification-owner.env" <<'EOF_OWNER'
verify_owner=dispatcher
external_verify_wrapper=no
remote_sha_required=yes
bash_missing_fallback=fail_closed
python_delivery=unsupported
policy=sdd-v4.13.0-verify-owner-v1
EOF_OWNER
cat > "$state/config/targets.d/pi3.conf" <<'EOF_TARGET'
target_name=pi3
enabled=1
ssh_host=192.0.2.10
remote_drop=/private/drop
shell=bash
EOF_TARGET
: > "$state/dispatch.inflight"
: > "$state/dispatch.faildb"
: > "$state/dispatch.quarantined"
printf '%s\n' '2026-08-09 00:00:00 WARN test' > "$state/log/dispatch.log"

cat > "$state/tools/pidd-config.sh" <<'EOF_CONFIG'
#!/bin/sh
[ "${1:-}" = lint ] && { echo 'lint=ok verify_owner=dispatcher external_verify_wrapper=no'; exit 0; }
exit 0
EOF_CONFIG
chmod +x "$state/tools/pidd-config.sh"
cat > "$state/tools/pidd-doctor.sh" <<'EOF_DOCTOR'
#!/bin/sh
echo 'doctor=ok redacted=yes'
exit 0
EOF_DOCTOR
chmod +x "$state/tools/pidd-doctor.sh"
cp "$BRIDGE" "$state/tools/sdd-termux-install.sh"
chmod +x "$state/tools/sdd-termux-install.sh"

run_sdd(){
  SDD_STATE_DIR="$state" \
  SDD_MODDIR="$mod" \
  SDD_SERVICE="$mod/service.sh" \
  SDD_MODULE_PROP="$mod/module.prop" \
  SDD_TARGET_DIR="$state/config/targets.d" \
  SDD_HEALTH_FILE="$state/health.env" \
  SDD_VERIFY_OWNER_FILE="$state/verification-owner.env" \
  SDD_LOG_FILE="$state/log/dispatch.log" \
  SDD_CONFIG_TOOL="$state/tools/dispatch-config.sh" \
  SDD_DOCTOR_TOOL="$state/tools/pidd-doctor.sh" \
  SDD_TERMUX_INSTALL_TOOL="$state/tools/sdd-termux-install.sh" \
  SDD_TERMUX_BIN="$termux" \
  /bin/sh "$SDD" "$@"
}

run_sdd version --json | grep -F '"version":"4.13.0-verify-owner-rc2"' >/dev/null
run_sdd capabilities --json | grep -F '"cliSchema":2' >/dev/null
status_json=$(run_sdd status --json)
printf '%s' "$status_json" | python -c 'import json,sys; json.load(sys.stdin)'
context_json=$(run_sdd chatgpt-context --json)
printf '%s' "$context_json" | python -c 'import json,sys; json.load(sys.stdin)'
run_sdd status --env | grep -F 'RESULT: SDD_CLI_DONE command=status outcome=success exit_code=0' >/dev/null
run_sdd targets --json | grep -F '"name":"pi3"' >/dev/null
context=$(run_sdd chatgpt-context --env)
printf '%s\n' "$context" | grep -F 'schema=SDD_CHATGPT_CONTEXT_V1' >/dev/null
printf '%s\n' "$context" | grep -F 'target=pi3 enabled=1 shell=bash' >/dev/null
printf '%s\n' "$context" | grep -F 'host_fields_exposed=no' >/dev/null
! printf '%s\n' "$context" | grep -F '192.0.2.10' >/dev/null
! printf '%s\n' "$context" | grep -F '/private/drop' >/dev/null
run_sdd doctor --chatgpt | grep -F 'RESULT: SDD_DOCTOR_CHATGPT_DONE outcome=success exit_code=0' >/dev/null

set +e
run_sdd --no-prompt config >/dev/null 2>&1
rc=$?
set -e
[ "$rc" -eq 64 ]
set +e
run_sdd definitely-not-a-command >/dev/null 2>&1
rc=$?
set -e
[ "$rc" -eq 64 ]

SDD_STATE_DIR="$state" SDD_MODDIR="$mod" SDD_TERMUX_BIN="$termux" /bin/sh "$BRIDGE" install >/dev/null
/bin/sh -n "$termux/sdd"
/bin/sh -n "$termux/dispatch-config"
SDD_STATE_DIR="$state" SDD_MODDIR="$mod" SDD_TERMUX_BIN="$termux" /bin/sh "$BRIDGE" status | grep -F 'RESULT: SDD_TERMUX_BRIDGE_STATUS outcome=ready exit_code=0' >/dev/null

printf '%s\n' 'RESULT: SDD_CLI_V2_CONTRACT_FIXTURES_PASS version=4.13.0-verify-owner-rc2 cli_schema=2 chatgpt_context_schema=1'
