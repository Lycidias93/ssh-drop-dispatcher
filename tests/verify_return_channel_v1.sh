#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

fail(){ echo "FAIL: $*" >&2; exit 1; }

for file in source/vnext-return/*.go; do
  test -z "$(gofmt -l "$file")" || fail "gofmt file=$file"
done
GO111MODULE=off go test ./source/vnext-return

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
helper="$tmp/sdd-return-helper"
CGO_ENABLED=0 go build -buildvcs=false -trimpath -o "$helper" source/vnext-return/sdd-return-helper.go

state="$tmp/state"
scan="$tmp/scan"
remote="$tmp/remote-outbox"
mkdir -p "$state/config/targets.d" "$state/config/returns.d" "$state/ssh" "$scan" "$remote"
printf '%s\n' "DROP_DISPATCH_SCAN_DIR=$scan" > "$state/config.env"
printf '%s\n' \
  'target_name="alpha"' \
  'enabled="1"' \
  'ssh_host="alpha"' \
  'remote_drop="/tmp/drop"' \
  'platform="linux"' \
  'shell="bash"' \
  'scp_flags=""' \
  'role="fixture"' > "$state/config/targets.d/alpha.conf"
printf 'return_enabled="1"\nremote_outbox="%s"\n' "$remote" > "$state/config/returns.d/alpha.conf"
: > "$state/ssh/ssh-config.dispatch"

record='target-alpha__fixture.txt|1234:99'
delivery_id=$(printf '%s' "$record" | sha256sum | awk '{print "SDD-" substr($1,1,16)}')
artifact_sha=$(printf 'outbound-fixture' | sha256sum | awk '{print $1}')
printf '%s|target=alpha\n' "$record" > "$state/dispatch.done"
mkdir -p "$state/delivery-bindings/$delivery_id"
printf '{"schema":"SDD_DELIVERY_BINDING_V1","deliveryId":"%s","artifactSha256":"%s","target":"alpha","completedEpoch":1700000000,"remoteShaVerified":true}\n' "$delivery_id" "$artifact_sha" > "$state/delivery-bindings/$delivery_id/alpha.json"

fake_ssh="$tmp/fake-ssh"
cat > "$fake_ssh" <<'SH'
#!/bin/sh
set -u
log=${SDD_FAKE_TRANSPORT_LOG:?}
printf 'ssh' >> "$log"
while [ "$#" -gt 0 ]; do
  case "$1" in
    -F|-o) printf ' %s %s' "$1" "$2" >> "$log"; shift 2 ;;
    -*) printf ' %s' "$1" >> "$log"; shift ;;
    *) host=$1; printf ' host=%s' "$host" >> "$log"; shift; break ;;
  esac
done
printf ' remote=%s\n' "${1:-}" >> "$log"
[ "${host:-}" = alpha ] || exit 90
[ "$#" -eq 1 ] || exit 91
exec sh -c "$1"
SH
chmod 755 "$fake_ssh"

fake_scp="$tmp/fake-scp"
cat > "$fake_scp" <<'SH'
#!/bin/sh
set -u
log=${SDD_FAKE_TRANSPORT_LOG:?}
printf 'scp' >> "$log"
while [ "$#" -gt 0 ]; do
  case "$1" in
    -F|-o) printf ' %s %s' "$1" "$2" >> "$log"; shift 2 ;;
    -O) printf ' -O' >> "$log"; shift ;;
    -*) printf ' %s' "$1" >> "$log"; shift ;;
    *) break ;;
  esac
done
[ "$#" -eq 2 ] || exit 92
src=$1; dst=$2
printf ' src=%s dst=%s\n' "$src" "$dst" >> "$log"
case "$src" in alpha:/*) cp "${src#alpha:}" "$dst" ;; *) exit 93 ;; esac
SH
chmod 755 "$fake_scp"
transport_log="$tmp/transport.log"
: > "$transport_log"

export SDD_STATE_DIR="$state"
export SDD_RETURN_SSH_BIN="$fake_ssh"
export SDD_RETURN_SCP_BIN="$fake_scp"
export SDD_FAKE_TRANSPORT_LOG="$transport_log"
export SDD_FORMAT=json

request_json=$($helper request "$delivery_id" --target alpha --type example.result.v1 --marker 'RESULT: FIXTURE_PASS' --correlation opaque-fixture)
return_id=$(python3 -c 'import json,sys; print(json.load(sys.stdin)["returnId"])' <<<"$request_json")
[[ "$return_id" =~ ^SDR-[0-9a-f]{32}$ ]] || fail "return id"

remote_dir="$remote/$return_id"
mkdir -p "$remote_dir"
printf 'fixture-result\nRESULT: FIXTURE_PASS\n' > "$remote_dir/result.txt"
result_sha=$(sha256sum "$remote_dir/result.txt" | awk '{print $1}')
result_bytes=$(wc -c < "$remote_dir/result.txt" | tr -d ' ')
printf '{"schema":"SDD_RETURN_RECEIPT_V1","returnId":"%s","deliveryId":"%s","artifactSha256":"%s","sourceTarget":"alpha","resultType":"example.result.v1","resultState":"failure","primaryArtifact":"result.txt","artifacts":[{"name":"result.txt","sha256":"%s","sizeBytes":%s}],"resultMarker":"RESULT: FIXTURE_PASS","callerCorrelation":"opaque-fixture"}\n' \
  "$return_id" "$delivery_id" "$artifact_sha" "$result_sha" "$result_bytes" > "$remote_dir/receipt.json"

collect_json=$($helper collect "$return_id")
COLLECT_JSON="$collect_json" python3 - "$return_id" <<'PY'
import json,os,sys
rid=sys.argv[1]
d=json.loads(os.environ["COLLECT_JSON"])
assert d["returnId"] == rid
assert d["state"] == "verified"
assert d["producerResult"] == "failure"
assert d["artifactCount"] == 1
PY

test -f "$state/inbound/verified/$return_id/receipt.json"
test -f "$state/inbound/verified/$return_id/acceptance.json"
test -f "$state/inbound/verified/$return_id/artifacts/result.txt"
test ! -e "$scan/result.txt"

# Exact-path proof: no wildcard, recursive SCP or generic outbox listing may occur.
! grep -Eq 'scp .*\*|scp .* -r|ls[[:space:]]|find[[:space:]].*remote-outbox' "$transport_log" || fail "unbounded remote traversal detected"
grep -Fq "src=alpha:$remote_dir/receipt.json" "$transport_log" || fail "receipt exact path not pulled"
grep -Fq "src=alpha:$remote_dir/result.txt" "$transport_log" || fail "artifact exact path not pulled"

# Re-collect against unchanged receipt is idempotent.
idempotent_json=$($helper collect "$return_id")
IDEMPOTENT_JSON="$idempotent_json" python3 - <<'PY'
import json,os
d=json.loads(os.environ["IDEMPOTENT_JSON"])
assert d["state"] == "verified"
assert d["idempotent"] is True
PY

# The same return ID published with a different receipt identity must be rejected as replay conflict.
printf 'changed\nRESULT: FIXTURE_PASS\n' > "$remote_dir/result.txt"
changed_sha=$(sha256sum "$remote_dir/result.txt" | awk '{print $1}')
changed_bytes=$(wc -c < "$remote_dir/result.txt" | tr -d ' ')
printf '{"schema":"SDD_RETURN_RECEIPT_V1","returnId":"%s","deliveryId":"%s","artifactSha256":"%s","sourceTarget":"alpha","resultType":"example.result.v1","resultState":"success","primaryArtifact":"result.txt","artifacts":[{"name":"result.txt","sha256":"%s","sizeBytes":%s}],"resultMarker":"RESULT: FIXTURE_PASS","callerCorrelation":"opaque-fixture"}\n' \
  "$return_id" "$delivery_id" "$artifact_sha" "$changed_sha" "$changed_bytes" > "$remote_dir/receipt.json"
if replay_out=$($helper collect "$return_id" 2>/dev/null); then
  fail "replay conflict accepted output=$replay_out"
fi
state_json=$($helper status "$return_id")
STATE_JSON="$state_json" python3 - <<'PY'
import json,os
d=json.loads(os.environ["STATE_JSON"])
# A replay probe must not destroy an already verified local result.
assert d["state"] == "verified"
PY

# A binding without the matching successful target delivery record must not authorize a request.
printf '' > "$state/dispatch.done"
if $helper request "$delivery_id" --target alpha --type example.result.v1 >/dev/null 2>&1; then
  fail "binding-only request accepted without delivery record"
fi

# No result/marker/correlation content may leak through normal inventory.
printf '%s|target=alpha\n' "$record" > "$state/dispatch.done"
inventory=$($helper inventory)
case "$inventory" in
  *'RESULT: FIXTURE_PASS'*|*'opaque-fixture'*|*'remote-outbox'*) fail "inventory leaked sensitive result metadata" ;;
esac

# Static hard boundaries.
! grep -RInE 'exec[[:space:]]+.*(receipt|artifact)|eval\(|source[[:space:]].*(receipt|artifact)' source/vnext-return || fail "execution primitive found"
! grep -RInE 'scp[^\n]*(\*|-r[[:space:]])' source/vnext-return || fail "recursive/wildcard scp found"
grep -Fq 'automaticDeletion": false' source/vnext-return/sdd-return-helper.go || fail "retention safety marker missing"
grep -Fq 'applySupported": false' source/vnext-return/sdd-return-helper.go || fail "cleanup apply unexpectedly enabled"
grep -Fq 'delivery_state=unchanged' source/vnext-return/service-binding.inc.sh || fail "delivery separation evidence missing"

echo 'RESULT: SDD_RETURN_CHANNEL_V1_FIXTURES_PASS'
