package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func fixtureRequest() returnRequest {
	return returnRequest{
		Schema:             requestSchema,
		ReturnID:           "SDR-0123456789abcdef0123456789abcdef",
		DeliveryID:         "SDD-0123456789abcdef",
		ArtifactSHA256:     strings.Repeat("a", 64),
		SourceTarget:       "alpha",
		ExpectedResultType: "example.result.v1",
		CreatedEpoch:       1700000000,
	}
}

func fixtureReceipt() returnReceipt {
	return returnReceipt{
		Schema:          receiptSchema,
		ReturnID:        "SDR-0123456789abcdef0123456789abcdef",
		DeliveryID:      "SDD-0123456789abcdef",
		ArtifactSHA256:  strings.Repeat("a", 64),
		SourceTarget:    "alpha",
		ResultType:      "example.result.v1",
		ResultState:     "success",
		PrimaryArtifact: "result.json",
		Artifacts:       []receiptArtifact{{Name: "result.json", SHA256: strings.Repeat("b", 64), SizeBytes: 1234}},
	}
}

func TestStrictJSONRejectsDuplicateAndUnknownKeys(t *testing.T) {
	var req returnRequest
	duplicate := []byte(`{"schema":"SDD_RETURN_REQUEST_V1","returnId":"SDR-0123456789abcdef0123456789abcdef","returnId":"SDR-fedcba9876543210fedcba9876543210","deliveryId":"SDD-0123456789abcdef","artifactSha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","sourceTarget":"alpha","expectedResultType":"example.result.v1","createdEpoch":1700000000}`)
	if err := decodeStrictBytes(duplicate, &req); err == nil {
		t.Fatal("duplicate JSON key accepted")
	}
	unknown := []byte(`{"schema":"SDD_RETURN_REQUEST_V1","returnId":"SDR-0123456789abcdef0123456789abcdef","deliveryId":"SDD-0123456789abcdef","artifactSha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","sourceTarget":"alpha","expectedResultType":"example.result.v1","createdEpoch":1700000000,"command":"rm -rf /"}`)
	if err := decodeStrictBytes(unknown, &req); err == nil {
		t.Fatal("unknown JSON field accepted")
	}
	trailing := append(mustJSON(t, fixtureRequest()), []byte(` {}`)...)
	if err := decodeStrictBytes(trailing, &req); err == nil {
		t.Fatal("trailing JSON document accepted")
	}
}

func TestReceiptCorrelationAndProducerFailureSeparation(t *testing.T) {
	req := fixtureRequest()
	receipt := fixtureReceipt()
	receipt.ResultState = "failure"
	if err := validateReceipt(receipt, req); err != nil {
		t.Fatalf("producer failure should remain transport-valid metadata: %v", err)
	}
	receipt.DeliveryID = "SDD-fedcba9876543210"
	if err := validateReceipt(receipt, req); err == nil {
		t.Fatal("delivery correlation mismatch accepted")
	}
}

func TestReceiptArtifactPathAndBounds(t *testing.T) {
	req := fixtureRequest()
	for _, bad := range []string{"../result.json", ".hidden", "sub/result.json", `sub\\result.json`, "..", "."} {
		receipt := fixtureReceipt()
		receipt.Artifacts[0].Name = bad
		receipt.PrimaryArtifact = bad
		if err := validateReceipt(receipt, req); err == nil {
			t.Fatalf("unsafe artifact name accepted: %q", bad)
		}
	}
	receipt := fixtureReceipt()
	receipt.Artifacts[0].SizeBytes = maxArtifactBytes + 1
	if err := validateReceipt(receipt, req); err == nil {
		t.Fatal("oversized artifact accepted")
	}
	receipt = fixtureReceipt()
	receipt.Artifacts = nil
	if err := validateReceipt(receipt, req); err == nil {
		t.Fatal("empty artifact list accepted")
	}
}

func TestMarkerAndOpaqueCorrelationArePrintableBounded(t *testing.T) {
	req := fixtureRequest()
	req.ExpectedResultMarker = "RESULT: PASS"
	req.CallerCorrelation = "opaque-consumer-123"
	if err := validateRequest(req); err != nil {
		t.Fatalf("valid marker/correlation rejected: %v", err)
	}
	req.ExpectedResultMarker = "RESULT:\nPASS"
	if err := validateRequest(req); err == nil {
		t.Fatal("multi-line marker accepted")
	}
}

func TestConfigParserRejectsUnknownDuplicateAndSymlink(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "alpha.conf")
	if err := os.WriteFile(path, []byte("return_enabled=\"1\"\nremote_outbox=\"/srv/sdd/outbox\"\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	values, err := parseConf(path, map[string]bool{"return_enabled": true, "remote_outbox": true})
	if err != nil || values["remote_outbox"] != "/srv/sdd/outbox" {
		t.Fatalf("valid config failed values=%v err=%v", values, err)
	}
	if err := os.WriteFile(path, []byte("return_enabled=1\nreturn_enabled=0\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := parseConf(path, map[string]bool{"return_enabled": true}); err == nil {
		t.Fatal("duplicate config key accepted")
	}
	if err := os.WriteFile(path, []byte("return_enabled=1\ncommand=oops\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := parseConf(path, map[string]bool{"return_enabled": true}); err == nil {
		t.Fatal("unknown config key accepted")
	}
	actual := filepath.Join(dir, "actual.conf")
	if err := os.WriteFile(actual, []byte("return_enabled=1\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	link := filepath.Join(dir, "link.conf")
	if err := os.Symlink(actual, link); err != nil {
		t.Fatal(err)
	}
	if _, err := parseConf(link, map[string]bool{"return_enabled": true}); err == nil {
		t.Fatal("symlink config accepted")
	}
}

func TestRemoteOutboxStrictPath(t *testing.T) {
	for _, good := range []string{"/srv/sdd/outbox", "/data/result_v1", "/tmp/a-b.c"} {
		if !safeRemoteOutbox(good) {
			t.Fatalf("valid outbox rejected: %s", good)
		}
	}
	for _, bad := range []string{"/", "relative/path", "/tmp/../etc", "/tmp//outbox", "/tmp/out box", "/tmp/out;rm"} {
		if safeRemoteOutbox(bad) {
			t.Fatalf("unsafe outbox accepted: %s", bad)
		}
	}
}

func TestAtomicRequestAndStateLayout(t *testing.T) {
	state := t.TempDir()
	rt := runtime{stateDir: state, format: "json", inboundDir: filepath.Join(state, "inbound"), scanDir: filepath.Join(t.TempDir(), "scan")}
	if err := rt.ensureLayout(); err != nil {
		t.Fatal(err)
	}
	req := fixtureRequest()
	if err := atomicJSON(rt.requestPath(req.ReturnID), req, 0o600); err != nil {
		t.Fatal(err)
	}
	if err := rt.writeState(returnState{Schema: stateSchema, ReturnID: req.ReturnID, State: "pending", UpdatedEpoch: time.Now().Unix()}); err != nil {
		t.Fatal(err)
	}
	loaded, err := rt.loadRequest(req.ReturnID)
	if err != nil || loaded.DeliveryID != req.DeliveryID {
		t.Fatalf("request roundtrip failed loaded=%+v err=%v", loaded, err)
	}
	st, err := rt.loadState(req.ReturnID)
	if err != nil || st.State != "pending" {
		t.Fatalf("state roundtrip failed state=%+v err=%v", st, err)
	}
	info, err := os.Stat(rt.requestPath(req.ReturnID))
	if err != nil {
		t.Fatal(err)
	}
	if info.Mode().Perm()&0o077 != 0 {
		t.Fatalf("request permissions too broad: %o", info.Mode().Perm())
	}
}

func TestScanPathOverlapGuard(t *testing.T) {
	root := t.TempDir()
	rt := runtime{stateDir: filepath.Join(root, "state"), inboundDir: filepath.Join(root, "scan", "inbound"), scanDir: filepath.Join(root, "scan"), format: "json"}
	if err := rt.ensureLayout(); err == nil {
		t.Fatal("scan/inbound overlap accepted")
	}
}

func TestReplayIdentityUsesReceiptSHA(t *testing.T) {
	dir := t.TempDir()
	one := filepath.Join(dir, "one.json")
	two := filepath.Join(dir, "two.json")
	if err := os.WriteFile(one, []byte("{\"x\":1}\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(two, []byte("{\"x\":2}\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	a, _ := fileSHA256(one)
	b, _ := fileSHA256(two)
	if a == b {
		t.Fatal("different receipts produced same fixture digest")
	}
}

func TestExactMarkerLine(t *testing.T) {
	path := filepath.Join(t.TempDir(), "result.txt")
	if err := os.WriteFile(path, []byte("before\nRESULT: PASS\nafter\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	ok, err := fileHasExactLine(path, "RESULT: PASS")
	if err != nil || !ok {
		t.Fatalf("exact marker not found ok=%v err=%v", ok, err)
	}
	ok, err = fileHasExactLine(path, "PASS")
	if err != nil || ok {
		t.Fatalf("substring incorrectly accepted ok=%v err=%v", ok, err)
	}
}

func mustJSON(t *testing.T, value any) []byte {
	t.Helper()
	data, err := json.Marshal(value)
	if err != nil {
		t.Fatal(err)
	}
	return data
}
