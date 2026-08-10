#!/usr/bin/env bash
set -euo pipefail

ROOT=${1:-$(cd "$(dirname "$0")/.." && pwd)}
SDD="$ROOT/source/magisk/tools/sdd.sh"
LIB="$ROOT/source/magisk/tools/sdd-lib.sh"
MACHINE="$ROOT/source/magisk/tools/sdd-machine.sh"
WORKFLOW="$ROOT/source/magisk/tools/sdd-workflow.sh"
CUSTOMIZE="$ROOT/source/magisk/customize.sh"
PROP="$ROOT/source/magisk/module.prop"

for f in "$SDD" "$LIB" "$MACHINE" "$WORKFLOW" "$CUSTOMIZE"; do
  /bin/sh -n "$f"
done

grep -Fx 'version=4.13.0-verify-owner-rc3' "$PROP" >/dev/null
grep -Fx 'versionCode=4130003' "$PROP" >/dev/null
grep -F 'SDD_CLI_SCHEMA=3' "$SDD" >/dev/null
grep -F 'SDD_WORKFLOW_SCHEMA=1' "$SDD" >/dev/null
grep -F 'dispatch-file <file> --wait' "$SDD" >/dev/null
grep -F 'schema=SDD_INCIDENT_CONTEXT_V1' "$WORKFLOW" >/dev/null
grep -F 'SDD_DELIVERY_RECEIPT_V1' "$WORKFLOW" >/dev/null
grep -F 'existing_queue true' "$WORKFLOW" >/dev/null
grep -F 'automaticRequeue":false' "$WORKFLOW" >/dev/null
! grep -F 'eval ' "$WORKFLOW" >/dev/null
! grep -F -- '--requeue' "$WORKFLOW" >/dev/null

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
state="$work/state"
mod="$work/module"
scan="$work/scan"
termux="$work/termux-bin"
mkdir -p "$state/config/targets.d" "$state/tools" "$state/log" "$mod/tools" "$scan" "$termux"
cp "$PROP" "$mod/module.prop"
cp "$LIB" "$state/tools/sdd-lib.sh"
cp "$MACHINE" "$state/tools/sdd-machine.sh"
cp "$WORKFLOW" "$state/tools/sdd-workflow.sh"
cp "$SDD" "$state/tools/sdd.sh"
chmod +x "$state/tools"/*.sh

cat > "$state/config.env" <<EOF_CONFIG
DROP_DISPATCH_SCAN_DIR=$scan
DROP_DISPATCH_ENABLED=1
EOF_CONFIG
cat > "$state/config/targets.d/pi3.conf" <<'EOF_TARGET'
target_name=pi3
enabled=1
shell=bash
EOF_TARGET
cat > "$state/health.env" <<'EOF_HEALTH'
status=OK
detail=fixture
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
for f in dispatch.done dispatch.complete dispatch.faildb dispatch.inflight dispatch.quarantined; do : > "$state/$f"; done
printf '%s\n' '2026-08-10 09:00:00 FAIL scp file=target-pi3__old.txt target=pi3 host=192.0.2.55' > "$state/log/dispatch.log"

cat > "$state/tools/pidd-config.sh" <<'EOF_CONFIG_TOOL'
#!/bin/sh
[ "${1:-}" = lint ] && { echo 'lint=ok verify_owner=dispatcher external_verify_wrapper=no'; exit 0; }
exit 1
EOF_CONFIG_TOOL
chmod +x "$state/tools/pidd-config.sh"

fixture_file="$scan/target-pi3__hello.txt"
printf '%s\n' 'hello rc3' > "$fixture_file"
export SDD_FIXTURE_FILE="$fixture_file"
export SDD_FIXTURE_STATE="$state"
cat > "$mod/service.sh" <<'EOF_SERVICE'
#!/bin/sh
case "${1:-}" in
  --route-explain)
    echo 'supported=yes'
    echo 'strict_target_prefix=yes'
    echo 'route_reason=target_prefix'
    echo 'targets=pi3'
    exit 0
    ;;
  --verify-target)
    echo "target=${2:-}"
    echo 'final_gate=PASS'
    exit 0
    ;;
  --scan-once)
    f=$SDD_FIXTURE_FILE
    base=${f##*/}
    pair=$(cksum "$f" | while read -r crc bytes rest; do printf '%s:%s' "$crc" "$bytes"; done)
    rec="$base|$pair"
    grep -Fqx "$rec|target=pi3" "$SDD_FIXTURE_STATE/dispatch.done" 2>/dev/null || echo "$rec|target=pi3" >> "$SDD_FIXTURE_STATE/dispatch.done"
    grep -Fqx "$rec" "$SDD_FIXTURE_STATE/dispatch.complete" 2>/dev/null || echo "$rec" >> "$SDD_FIXTURE_STATE/dispatch.complete"
    echo 'scan=PASS'
    exit 0
    ;;
  --wait-delivery)
    f=${2:-$SDD_FIXTURE_FILE}
    base=${f##*/}
    pair=$(cksum "$f" | while read -r crc bytes rest; do printf '%s:%s' "$crc" "$bytes"; done)
    rec="$base|$pair"
    grep -Fqx "$rec" "$SDD_FIXTURE_STATE/dispatch.complete"
    ;;
  --runtime-status) exit 0 ;;
  *) exit 1 ;;
esac
EOF_SERVICE
chmod +x "$mod/service.sh"

cat > "$work/workflow-wrapper.sh" <<EOF_WRAPPER
#!/bin/sh
exec /bin/sh "$state/tools/sdd-workflow.sh" "\$@"
EOF_WRAPPER
chmod +x "$work/workflow-wrapper.sh"

export SDD_STATE_DIR="$state"
export SDD_MODDIR="$mod"
export SDD_SERVICE="$mod/service.sh"
export SDD_TARGET_DIR="$state/config/targets.d"
export SDD_MODULE_PROP="$mod/module.prop"
export SDD_HEALTH_FILE="$state/health.env"
export SDD_VERIFY_OWNER_FILE="$state/verification-owner.env"
export SDD_LOG_FILE="$state/log/dispatch.log"
export SDD_WORKFLOW_TOOL="$work/workflow-wrapper.sh"
export SDD_TERMUX_BIN="$termux"

run_sdd(){ /bin/sh "$state/tools/sdd.sh" "$@"; }

run_sdd capabilities --json | python -c 'import json,sys; d=json.load(sys.stdin); assert d["cliSchema"]==3; assert d["workflowSchema"]==1; assert d["workflow"]["automaticRequeue"] is False'
run_sdd preflight "${fixture_file##*/}" --env | grep -F 'outcome=READY' >/dev/null
queue_json=$(run_sdd queue --json)
printf '%s' "$queue_json" | python -c 'import json,sys; d=json.load(sys.stdin); assert len(d["items"])==1; assert d["items"][0]["state"]=="pending"'

receipt_json=$(run_sdd dispatch-file "${fixture_file##*/}" --wait 10 1 --json)
printf '%s' "$receipt_json" | python -c 'import json,sys; d=json.load(sys.stdin); assert d["schema"]=="SDD_DELIVERY_RECEIPT_V1"; assert d["state"]=="verified_complete"; assert d["scanScope"]=="existing_queue"; assert d["automaticRequeue"] is False; assert d["hostRun"] is True; assert d["deliveryId"].startswith("SDD-") and len(d["deliveryId"])==20'
[ -s "$state/delivery.receipts.jsonl" ]

delivery_id=$(printf '%s' "$receipt_json" | python -c 'import json,sys; print(json.load(sys.stdin)["deliveryId"])')
trace_json=$(run_sdd trace "$delivery_id" --json)
printf '%s' "$trace_json" | python -c 'import json,sys; d=json.load(sys.stdin); assert d["schema"]=="SDD_DELIVERY_TRACE_V1"; assert d["state"]=="complete"; assert d["hostRun"] is False'

context_json=$(run_sdd chatgpt-context --json)
printf '%s' "$context_json" | python -c 'import json,sys; d=json.load(sys.stdin); assert d["schema"]=="SDD_CHATGPT_CONTEXT_V1"; assert d["workflowSchema"]==1; assert d["deliveryReceiptRecords"]>=1; assert d["lastReceiptState"]=="verified_complete"'

incident_json=$(run_sdd incident --chatgpt --json)
printf '%s' "$incident_json" | python -c 'import json,sys; d=json.load(sys.stdin); assert d["schema"]=="SDD_INCIDENT_CONTEXT_V1"; assert d["redaction"]["hostFieldsExposed"] is False; assert d["hostRun"] is False'

failures=$(run_sdd failures --env)
! printf '%s\n' "$failures" | grep -F '192.0.2.55' >/dev/null
printf '%s\n' "$failures" | grep -F 'host=<redacted-host>' >/dev/null

printf '%s\n' "${fixture_file##*/}|123:11|target=pi3|reason=remote_sha|policy=v4115" >> "$state/dispatch.quarantined"
run_sdd quarantine --env | grep -F 'reason=remote_sha' >/dev/null

set +e
run_sdd dispatch-file "${fixture_file##*/}" >/dev/null 2>&1
rc=$?
set -e
[ "$rc" -eq 64 ]

printf '%s\n' 'RESULT: SDD_RC3_WORKFLOW_CONTRACT_FIXTURES_PASS version=4.13.0-verify-owner-rc3 cli_schema=3 workflow_schema=1 receipt_schema=1 incident_schema=1'
