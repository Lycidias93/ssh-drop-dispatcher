#!/usr/bin/env python3
from pathlib import Path


def replace_once(path, old, new):
    p = Path(path)
    text = p.read_text()
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"anchor mismatch {path}: {count}")
    p.write_text(text.replace(old, new, 1))


helper = "source/vnext-return/sdd-return-helper.go"
replace_once(helper, 'remotePathRE = regexp.MustCompile(`^/[A-Za-z0-9._@+:/-]{1,1023}$`)', 'remotePathRE = regexp.MustCompile(`^/[A-Za-z0-9._@+:/-]{1,1000}$`)')
replace_once(
    helper,
    '\tif err := validateBinding(bind, deliveryID, target); err != nil { return err }\n\tid, err := secureReturnID(); if err != nil { return err }',
    '\tif err := validateBinding(bind, deliveryID, target); err != nil { return err }\n\tdone, err := rt.deliveryTargetDone(deliveryID, target)\n\tif err != nil { return err }\n\tif !done { return fail("RETURN_DELIVERY_NOT_DONE", errors.New("matching successful target delivery record not found")) }\n\tid, err := secureReturnID(); if err != nil { return err }',
)
replace_once(
    helper,
    '''func validateBinding(bind binding, deliveryID, target string) error {
\tif bind.Schema != bindingSchema || bind.DeliveryID != deliveryID || bind.Target != target || !bind.RemoteSHAVerified || bind.CompletedEpoch <= 0 || !shaRE.MatchString(bind.ArtifactSHA256) {
\t\treturn fail("RETURN_BINDING_CONFLICT", errors.New("delivery binding does not match return request"))
\t}
\treturn nil
}
''',
    '''func validateBinding(bind binding, deliveryID, target string) error {
\tif bind.Schema != bindingSchema || bind.DeliveryID != deliveryID || bind.Target != target || !bind.RemoteSHAVerified || bind.CompletedEpoch <= 0 || !shaRE.MatchString(bind.ArtifactSHA256) {
\t\treturn fail("RETURN_BINDING_CONFLICT", errors.New("delivery binding does not match return request"))
\t}
\treturn nil
}

func (rt runtime) deliveryTargetDone(deliveryID, target string) (bool, error) {
\tfile, err := os.Open(filepath.Join(rt.stateDir, "dispatch.done"))
\tif err != nil {
\t\tif os.IsNotExist(err) { return false, nil }
\t\treturn false, err
\t}
\tdefer file.Close()
\tsuffix := "|target=" + target
\tscanner := bufio.NewScanner(file)
\tfor scanner.Scan() {
\t\tline := scanner.Text()
\t\tif !strings.HasSuffix(line, suffix) { continue }
\t\trecord := strings.TrimSuffix(line, suffix)
\t\tsum := sha256.Sum256([]byte(record))
\t\tif "SDD-"+hex.EncodeToString(sum[:])[:16] == deliveryID { return true, nil }
\t}
\treturn false, scanner.Err()
}
''',
)
replace_once(
    helper,
    '''\tstate, err := rt.loadState(id)
\tif err == nil && state.State == "verified" {
\t\treturn rt.emit(map[string]any{"schema": stateSchema, "returnId": id, "state": "verified", "idempotent": true, "receiptSha256": state.ReceiptSHA256})
\t}
''',
    '''\tstate, err := rt.loadState(id)
\tif err == nil && state.State == "verified" {
\t\treq, cfg, target, contextErr := rt.loadRequestContext(id)
\t\tif contextErr != nil { return contextErr }
\t\tremoteReceipt := remoteJoin(cfg.RemoteOutbox, req.ReturnID, "receipt.json")
\t\tif _, sizeErr := rt.remoteRegularSize(target, remoteReceipt, maxReceiptBytes); sizeErr != nil {
\t\t\tvar ce *contractError
\t\t\tif errors.As(sizeErr, &ce) && (ce.Transient || ce.Code == "RETURN_REMOTE_NOT_AVAILABLE") {
\t\t\t\treturn rt.emit(map[string]any{"schema": stateSchema, "returnId": id, "state": "verified", "idempotent": true, "receiptSha256": state.ReceiptSHA256, "remoteReceiptRechecked": false})
\t\t\t}
\t\t\treturn sizeErr
\t\t}
\t\tremoteSHA, shaErr := rt.remoteSHA256(target, remoteReceipt)
\t\tif shaErr != nil { return shaErr }
\t\tif remoteSHA != state.ReceiptSHA256 { return fail("RETURN_REPLAY_CONFLICT", errors.New("remote receipt changed after local verification")) }
\t\treturn rt.emit(map[string]any{"schema": stateSchema, "returnId": id, "state": "verified", "idempotent": true, "receiptSha256": state.ReceiptSHA256, "remoteReceiptRechecked": true})
\t}
''',
)
replace_once(
    helper,
    '''\tremoteSize, err := rt.remoteRegularSize(target, remoteReceipt, maxReceiptBytes)
\tif err != nil { return nil, err }
\tif remoteSize < 1 { return nil, fail("RETURN_RECEIPT_SIZE_INVALID", errors.New("empty receipt")) }
\tlocalReceipt := filepath.Join(stage, "receipt.json")''',
    '''\tremoteSize, err := rt.remoteRegularSize(target, remoteReceipt, maxReceiptBytes)
\tif err != nil { return nil, err }
\tif remoteSize < 1 { return nil, fail("RETURN_RECEIPT_SIZE_INVALID", errors.New("empty receipt")) }
\tremoteReceiptSHA, err := rt.remoteSHA256(target, remoteReceipt)
\tif err != nil { return nil, err }
\tlocalReceipt := filepath.Join(stage, "receipt.json")''',
)
replace_once(
    helper,
    '\treceiptDigest, err := fileSHA256(localReceipt); if err != nil { return nil, err }\n\n\tverifiedTotal := int64(0)',
    '\treceiptDigest, err := fileSHA256(localReceipt); if err != nil { return nil, err }\n\tif receiptDigest != remoteReceiptSHA { return nil, fail("RETURN_RECEIPT_SHA_MISMATCH", errors.New("remote and local receipt sha differ")) }\n\n\tverifiedTotal := int64(0)',
)

test = "tests/verify_return_channel_v1.sh"
replace_once(
    test,
    '''python3 - "$return_id" <<'PY' <<<"$collect_json"
import json,sys
rid=sys.argv[1]
d=json.load(sys.stdin)''',
    '''COLLECT_JSON="$collect_json" python3 - "$return_id" <<'PY'
import json,os,sys
rid=sys.argv[1]
d=json.loads(os.environ["COLLECT_JSON"])''',
)
replace_once(
    test,
    '''python3 - <<'PY' <<<"$idempotent_json"
import json,sys
d=json.load(sys.stdin)''',
    '''IDEMPOTENT_JSON="$idempotent_json" python3 - <<'PY'
import json,os
d=json.loads(os.environ["IDEMPOTENT_JSON"])''',
)
replace_once(
    test,
    '''python3 - <<'PY' <<<"$state_json"
import json,sys
d=json.load(sys.stdin)''',
    '''STATE_JSON="$state_json" python3 - <<'PY'
import json,os
d=json.loads(os.environ["STATE_JSON"])''',
)
print("RESULT: SDD_RETURN_PR_PATCH_APPLIED")
