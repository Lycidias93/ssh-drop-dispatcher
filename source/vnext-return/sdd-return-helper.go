package main

import (
	"bufio"
	"bytes"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"
)

const (
	bindingSchema    = "SDD_DELIVERY_BINDING_V1"
	requestSchema    = "SDD_RETURN_REQUEST_V1"
	receiptSchema    = "SDD_RETURN_RECEIPT_V1"
	acceptanceSchema = "SDD_RETURN_ACCEPTANCE_V1"
	stateSchema      = "SDD_RETURN_STATE_V1"
	maxReceiptBytes  = int64(65536)
	maxArtifacts     = 8
	maxArtifactBytes = int64(268435456)
	maxTotalBytes    = int64(536870912)
	maxWaitSeconds   = int64(3600)
	defaultPoll      = int64(5)
)

var (
	returnIDRE     = regexp.MustCompile(`^SDR-[0-9a-f]{32}$`)
	deliveryIDRE   = regexp.MustCompile(`^SDD-[0-9a-f]{16}$`)
	shaRE          = regexp.MustCompile(`^[0-9a-f]{64}$`)
	targetRE       = regexp.MustCompile(`^[a-z0-9_-]{1,32}$`)
	resultTypeRE   = regexp.MustCompile(`^[A-Za-z0-9._:-]{1,128}$`)
	artifactNameRE = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$`)
	remotePathRE   = regexp.MustCompile(`^/[A-Za-z0-9._@+:/-]{1,1000}$`)
)

type binding struct {
	Schema            string `json:"schema"`
	DeliveryID        string `json:"deliveryId"`
	ArtifactSHA256    string `json:"artifactSha256"`
	Target            string `json:"target"`
	CompletedEpoch    int64  `json:"completedEpoch"`
	RemoteSHAVerified bool   `json:"remoteShaVerified"`
}

type returnRequest struct {
	Schema               string `json:"schema"`
	ReturnID             string `json:"returnId"`
	DeliveryID           string `json:"deliveryId"`
	ArtifactSHA256       string `json:"artifactSha256"`
	SourceTarget         string `json:"sourceTarget"`
	ExpectedResultType   string `json:"expectedResultType"`
	CreatedEpoch         int64  `json:"createdEpoch"`
	ExpectedResultMarker string `json:"expectedResultMarker,omitempty"`
	CallerCorrelation    string `json:"callerCorrelation,omitempty"`
}

type receiptArtifact struct {
	Name      string `json:"name"`
	SHA256    string `json:"sha256"`
	SizeBytes int64  `json:"sizeBytes"`
}

type returnReceipt struct {
	Schema               string            `json:"schema"`
	ReturnID             string            `json:"returnId"`
	DeliveryID           string            `json:"deliveryId"`
	ArtifactSHA256       string            `json:"artifactSha256"`
	SourceTarget         string            `json:"sourceTarget"`
	ResultType           string            `json:"resultType"`
	ResultState          string            `json:"resultState"`
	PrimaryArtifact      string            `json:"primaryArtifact"`
	Artifacts            []receiptArtifact `json:"artifacts"`
	ResultMarker         string            `json:"resultMarker,omitempty"`
	CallerCorrelation    string            `json:"callerCorrelation,omitempty"`
	ProducerStartedEpoch *int64            `json:"producerStartedEpoch,omitempty"`
	ProducerEndedEpoch   *int64            `json:"producerEndedEpoch,omitempty"`
}

type returnState struct {
	Schema         string `json:"schema"`
	ReturnID       string `json:"returnId"`
	State          string `json:"state"`
	UpdatedEpoch   int64  `json:"updatedEpoch"`
	ProducerResult string `json:"producerResult,omitempty"`
	ReceiptSHA256  string `json:"receiptSha256,omitempty"`
	ErrorCode      string `json:"errorCode,omitempty"`
}

type acceptance struct {
	Schema              string `json:"schema"`
	ReturnID            string `json:"returnId"`
	DeliveryID          string `json:"deliveryId"`
	SourceTarget        string `json:"sourceTarget"`
	ReceiptSHA256       string `json:"receiptSha256"`
	ArtifactCount       int    `json:"artifactCount"`
	VerifiedTotalBytes  int64  `json:"verifiedTotalBytes"`
	CorrelationVerified bool   `json:"correlationVerified"`
	OriginVerified      bool   `json:"originVerified"`
	SHAVerified         bool   `json:"shaVerified"`
	MarkerVerified      bool   `json:"markerVerified,omitempty"`
	VerifiedEpoch       int64  `json:"verifiedEpoch"`
	State               string `json:"state"`
}

type targetConfig struct {
	Name     string
	Enabled  bool
	SSHHost  string
	SCPFlags string
}

type returnConfig struct {
	Enabled      bool
	RemoteOutbox string
}

type runtime struct {
	stateDir   string
	moduleDir  string
	format     string
	sshBin     string
	scpBin     string
	sshConfig  string
	scanDir    string
	inboundDir string
}

type contractError struct {
	Code      string
	Transient bool
	Err       error
}

func (e *contractError) Error() string  { return e.Code + ": " + e.Err.Error() }
func fail(code string, err error) error { return &contractError{Code: code, Err: err} }
func transient(code string, err error) error {
	return &contractError{Code: code, Transient: true, Err: err}
}

func main() {
	rt := loadRuntime()
	if err := rt.run(os.Args[1:]); err != nil {
		code := "RETURN_INTERNAL_ERROR"
		transientFlag := false
		var ce *contractError
		if errors.As(err, &ce) {
			code = ce.Code
			transientFlag = ce.Transient
		}
		if rt.format == "json" {
			_ = json.NewEncoder(os.Stdout).Encode(map[string]any{"ok": false, "error": code, "transient": transientFlag})
		} else {
			fmt.Printf("return=FAIL\nerror_code=%s\ntransient=%s\nRESULT: SDD_RETURN_DONE outcome=fail exit_code=1\n", code, yesNo(transientFlag))
		}
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func loadRuntime() runtime {
	state := envOr("SDD_STATE_DIR", "/data/adb/ssh-drop-dispatcher")
	return runtime{
		stateDir:   state,
		moduleDir:  envOr("SDD_MODDIR", "/data/adb/modules/ssh_drop_dispatcher"),
		format:     envOr("SDD_FORMAT", "env"),
		sshBin:     envOr("SDD_RETURN_SSH_BIN", "/data/data/com.termux/files/usr/bin/ssh"),
		scpBin:     envOr("SDD_RETURN_SCP_BIN", "/data/data/com.termux/files/usr/bin/scp"),
		sshConfig:  filepath.Join(state, "ssh", "ssh-config.dispatch"),
		scanDir:    configValue(filepath.Join(state, "config.env"), "DROP_DISPATCH_SCAN_DIR", "/storage/emulated/0/Download"),
		inboundDir: filepath.Join(state, "inbound"),
	}
}

func envOr(key, fallback string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return fallback
}

func (rt runtime) run(args []string) error {
	if len(args) < 1 {
		return fail("RETURN_USAGE", errors.New("missing return command"))
	}
	switch args[0] {
	case "capability":
		if len(args) > 2 {
			return fail("RETURN_USAGE", errors.New("capability [target]"))
		}
		target := ""
		if len(args) == 2 {
			target = args[1]
		}
		return rt.capability(target)
	case "request":
		return rt.requestCommand(args[1:])
	case "status":
		if len(args) != 2 {
			return fail("RETURN_USAGE", errors.New("status <return-id>"))
		}
		return rt.status(args[1])
	case "probe":
		if len(args) != 2 {
			return fail("RETURN_USAGE", errors.New("probe <return-id>"))
		}
		return rt.probe(args[1])
	case "collect":
		if len(args) != 2 {
			return fail("RETURN_USAGE", errors.New("collect <return-id>"))
		}
		return rt.collect(args[1])
	case "wait":
		return rt.waitCommand(args[1:])
	case "trace":
		if len(args) != 2 {
			return fail("RETURN_USAGE", errors.New("trace <return-id>"))
		}
		return rt.trace(args[1])
	case "inventory":
		if len(args) != 1 {
			return fail("RETURN_USAGE", errors.New("inventory"))
		}
		return rt.inventory()
	case "cleanup-preview":
		if len(args) != 1 {
			return fail("RETURN_USAGE", errors.New("cleanup-preview"))
		}
		return rt.cleanupPreview()
	case "job-file":
		return rt.jobFile(args[1:])
	case "validate-receipt-fixture":
		return rt.validateReceiptFixture(args[1:])
	default:
		return fail("RETURN_USAGE", fmt.Errorf("unknown return command %q", args[0]))
	}
}

func (rt runtime) ensureLayout() error {
	if pathsOverlap(filepath.Clean(rt.scanDir), filepath.Clean(rt.inboundDir)) {
		return fail("RETURN_SCAN_PATH_OVERLAP", errors.New("inbound store overlaps dispatcher scan path"))
	}
	for _, path := range []string{
		filepath.Join(rt.inboundDir, "requests"), filepath.Join(rt.inboundDir, "state"),
		filepath.Join(rt.inboundDir, ".staging"), filepath.Join(rt.inboundDir, "verified"),
		filepath.Join(rt.stateDir, "delivery-bindings"), filepath.Join(rt.stateDir, "config", "returns.d"),
	} {
		if err := os.MkdirAll(path, 0o700); err != nil {
			return err
		}
		_ = os.Chmod(path, 0o700)
	}
	return nil
}

func pathsOverlap(a, b string) bool {
	if a == b {
		return true
	}
	sep := string(os.PathSeparator)
	return strings.HasPrefix(a+sep, b+sep) || strings.HasPrefix(b+sep, a+sep)
}

func (rt runtime) capability(target string) error {
	if err := rt.ensureLayout(); err != nil {
		return err
	}
	items := []map[string]any{}
	if target != "" {
		if !targetRE.MatchString(target) {
			return fail("RETURN_TARGET_INVALID", errors.New("invalid target"))
		}
		base, err := rt.loadTarget(target)
		if err != nil {
			return err
		}
		cfg, _ := rt.loadReturnConfig(target)
		items = append(items, map[string]any{"target": target, "targetEnabled": base.Enabled, "returnEnabled": cfg.Enabled})
	} else {
		entries, _ := os.ReadDir(filepath.Join(rt.stateDir, "config", "targets.d"))
		for _, entry := range entries {
			if entry.IsDir() || !strings.HasSuffix(entry.Name(), ".conf") {
				continue
			}
			name := strings.TrimSuffix(entry.Name(), ".conf")
			if !targetRE.MatchString(name) {
				continue
			}
			base, err := rt.loadTarget(name)
			if err != nil {
				continue
			}
			cfg, _ := rt.loadReturnConfig(name)
			items = append(items, map[string]any{"target": name, "targetEnabled": base.Enabled, "returnEnabled": cfg.Enabled})
		}
		sort.Slice(items, func(i, j int) bool { return items[i]["target"].(string) < items[j]["target"].(string) })
	}
	return rt.emit(map[string]any{"schema": "SDD_RETURN_CAPABILITY_V1", "items": items, "outboxPathsExposed": false})
}

func (rt runtime) requestCommand(args []string) error {
	if len(args) < 5 {
		return fail("RETURN_USAGE", errors.New("request <delivery-id> --target <target> --type <type> [--marker <literal>] [--correlation <opaque>]"))
	}
	deliveryID := args[0]
	options, err := parseOptions(args[1:], map[string]bool{"--target": true, "--type": true, "--marker": true, "--correlation": true})
	if err != nil {
		return err
	}
	return rt.createRequest(deliveryID, options["--target"], options["--type"], options["--marker"], options["--correlation"])
}

func parseOptions(args []string, allowed map[string]bool) (map[string]string, error) {
	out := map[string]string{}
	for len(args) > 0 {
		key := args[0]
		args = args[1:]
		if !allowed[key] || len(args) == 0 {
			return nil, fail("RETURN_USAGE", fmt.Errorf("invalid option %s", key))
		}
		if _, exists := out[key]; exists {
			return nil, fail("RETURN_USAGE", fmt.Errorf("duplicate option %s", key))
		}
		out[key] = args[0]
		args = args[1:]
	}
	return out, nil
}

func (rt runtime) createRequest(deliveryID, target, resultType, marker, correlation string) error {
	if err := rt.ensureLayout(); err != nil {
		return err
	}
	if !deliveryIDRE.MatchString(deliveryID) {
		return fail("RETURN_DELIVERY_ID_INVALID", errors.New("invalid delivery id"))
	}
	if !targetRE.MatchString(target) {
		return fail("RETURN_TARGET_INVALID", errors.New("invalid target"))
	}
	if !resultTypeRE.MatchString(resultType) {
		return fail("RETURN_RESULT_TYPE_INVALID", errors.New("invalid result type"))
	}
	if marker != "" && !printableSingleLine(marker, 256) {
		return fail("RETURN_MARKER_INVALID", errors.New("invalid expected marker"))
	}
	if correlation != "" && !printableSingleLine(correlation, 256) {
		return fail("RETURN_CORRELATION_INVALID", errors.New("invalid caller correlation"))
	}
	base, err := rt.loadTarget(target)
	if err != nil {
		return err
	}
	if !base.Enabled {
		return fail("RETURN_TARGET_DISABLED", errors.New("target disabled"))
	}
	returnCfg, err := rt.loadReturnConfig(target)
	if err != nil {
		return err
	}
	if !returnCfg.Enabled {
		return fail("RETURN_CAPABILITY_DISABLED", errors.New("return capability disabled"))
	}
	bindingPath := filepath.Join(rt.stateDir, "delivery-bindings", deliveryID, target+".json")
	var bind binding
	if err := decodeStrictFile(bindingPath, maxReceiptBytes, &bind); err != nil {
		return fail("RETURN_BINDING_MISSING_OR_INVALID", err)
	}
	if err := validateBinding(bind, deliveryID, target); err != nil {
		return err
	}
	done, err := rt.deliveryTargetDone(deliveryID, target)
	if err != nil {
		return err
	}
	if !done {
		return fail("RETURN_DELIVERY_NOT_DONE", errors.New("matching successful target delivery record not found"))
	}
	id, err := secureReturnID()
	if err != nil {
		return err
	}
	req := returnRequest{Schema: requestSchema, ReturnID: id, DeliveryID: deliveryID, ArtifactSHA256: bind.ArtifactSHA256, SourceTarget: target, ExpectedResultType: resultType, CreatedEpoch: time.Now().Unix(), ExpectedResultMarker: marker, CallerCorrelation: correlation}
	path := rt.requestPath(id)
	if err := atomicJSON(path, req, 0o600); err != nil {
		return err
	}
	if err := rt.writeState(returnState{Schema: stateSchema, ReturnID: id, State: "pending", UpdatedEpoch: time.Now().Unix()}); err != nil {
		_ = os.Remove(path)
		return err
	}
	return rt.emit(map[string]any{"schema": requestSchema, "returnId": id, "deliveryId": deliveryID, "sourceTarget": target, "state": "pending", "artifactSha256Bound": true})
}

func validateBinding(bind binding, deliveryID, target string) error {
	if bind.Schema != bindingSchema || bind.DeliveryID != deliveryID || bind.Target != target || !bind.RemoteSHAVerified || bind.CompletedEpoch <= 0 || !shaRE.MatchString(bind.ArtifactSHA256) {
		return fail("RETURN_BINDING_CONFLICT", errors.New("delivery binding does not match return request"))
	}
	return nil
}

func (rt runtime) deliveryTargetDone(deliveryID, target string) (bool, error) {
	file, err := os.Open(filepath.Join(rt.stateDir, "dispatch.done"))
	if err != nil {
		if os.IsNotExist(err) {
			return false, nil
		}
		return false, err
	}
	defer file.Close()
	suffix := "|target=" + target
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := scanner.Text()
		if !strings.HasSuffix(line, suffix) {
			continue
		}
		record := strings.TrimSuffix(line, suffix)
		sum := sha256.Sum256([]byte(record))
		if "SDD-"+hex.EncodeToString(sum[:])[:16] == deliveryID {
			return true, nil
		}
	}
	return false, scanner.Err()
}

func secureReturnID() (string, error) {
	buf := make([]byte, 16)
	if _, err := io.ReadFull(rand.Reader, buf); err != nil {
		return "", err
	}
	return "SDR-" + hex.EncodeToString(buf), nil
}

func (rt runtime) status(id string) error {
	state, err := rt.loadState(id)
	if err != nil {
		return err
	}
	return rt.emit(map[string]any{"schema": state.Schema, "returnId": state.ReturnID, "state": state.State, "producerResult": state.ProducerResult, "receiptSha256": state.ReceiptSHA256, "errorCode": state.ErrorCode, "updatedEpoch": state.UpdatedEpoch})
}

func (rt runtime) probe(id string) error {
	req, cfg, target, err := rt.loadRequestContext(id)
	if err != nil {
		return err
	}
	path := remoteJoin(cfg.RemoteOutbox, req.ReturnID, "receipt.json")
	_, err = rt.remoteRegularSize(target, path, maxReceiptBytes)
	if err != nil {
		var ce *contractError
		if errors.As(err, &ce) && ce.Transient {
			return err
		}
		if errors.As(err, &ce) && ce.Code == "RETURN_REMOTE_NOT_AVAILABLE" {
			_ = rt.writeState(returnState{Schema: stateSchema, ReturnID: id, State: "pending", UpdatedEpoch: time.Now().Unix()})
			return rt.emit(map[string]any{"schema": stateSchema, "returnId": id, "state": "pending", "available": false})
		}
		return rt.failState(id, err)
	}
	if err := rt.writeState(returnState{Schema: stateSchema, ReturnID: id, State: "available", UpdatedEpoch: time.Now().Unix()}); err != nil {
		return err
	}
	return rt.emit(map[string]any{"schema": stateSchema, "returnId": id, "state": "available", "available": true})
}

func (rt runtime) collect(id string) error {
	if err := rt.ensureLayout(); err != nil {
		return err
	}
	state, err := rt.loadState(id)
	if err == nil && state.State == "verified" {
		req, cfg, target, contextErr := rt.loadRequestContext(id)
		if contextErr != nil {
			return contextErr
		}
		remoteReceipt := remoteJoin(cfg.RemoteOutbox, req.ReturnID, "receipt.json")
		if _, sizeErr := rt.remoteRegularSize(target, remoteReceipt, maxReceiptBytes); sizeErr != nil {
			var ce *contractError
			if errors.As(sizeErr, &ce) && (ce.Transient || ce.Code == "RETURN_REMOTE_NOT_AVAILABLE") {
				return rt.emit(map[string]any{"schema": stateSchema, "returnId": id, "state": "verified", "idempotent": true, "receiptSha256": state.ReceiptSHA256, "remoteReceiptRechecked": false})
			}
			return sizeErr
		}
		remoteSHA, shaErr := rt.remoteSHA256(target, remoteReceipt)
		if shaErr != nil {
			return shaErr
		}
		if remoteSHA != state.ReceiptSHA256 {
			return fail("RETURN_REPLAY_CONFLICT", errors.New("remote receipt changed after local verification"))
		}
		return rt.emit(map[string]any{"schema": stateSchema, "returnId": id, "state": "verified", "idempotent": true, "receiptSha256": state.ReceiptSHA256, "remoteReceiptRechecked": true})
	}
	result, err := rt.collectOnce(id)
	if err != nil {
		var ce *contractError
		if errors.As(err, &ce) && (ce.Transient || ce.Code == "RETURN_REMOTE_NOT_AVAILABLE") {
			return err
		}
		return rt.failState(id, err)
	}
	return rt.emit(result)
}

func (rt runtime) collectOnce(id string) (map[string]any, error) {
	req, cfg, target, err := rt.loadRequestContext(id)
	if err != nil {
		return nil, err
	}
	stageParent := filepath.Join(rt.inboundDir, ".staging")
	stage, err := os.MkdirTemp(stageParent, id+".")
	if err != nil {
		return nil, err
	}
	defer os.RemoveAll(stage)
	if err := os.Chmod(stage, 0o700); err != nil {
		return nil, err
	}
	artifactDir := filepath.Join(stage, "artifacts")
	if err := os.Mkdir(artifactDir, 0o700); err != nil {
		return nil, err
	}

	remoteReceipt := remoteJoin(cfg.RemoteOutbox, id, "receipt.json")
	remoteSize, err := rt.remoteRegularSize(target, remoteReceipt, maxReceiptBytes)
	if err != nil {
		return nil, err
	}
	if remoteSize < 1 {
		return nil, fail("RETURN_RECEIPT_SIZE_INVALID", errors.New("empty receipt"))
	}
	remoteReceiptSHA, err := rt.remoteSHA256(target, remoteReceipt)
	if err != nil {
		return nil, err
	}
	localReceipt := filepath.Join(stage, "receipt.json")
	if err := rt.scpFrom(target, remoteReceipt, localReceipt); err != nil {
		return nil, err
	}
	if err := chmodRegular(localReceipt); err != nil {
		return nil, err
	}
	info, err := os.Lstat(localReceipt)
	if err != nil {
		return nil, err
	}
	if info.Size() != remoteSize || info.Size() > maxReceiptBytes {
		return nil, fail("RETURN_RECEIPT_SIZE_MISMATCH", errors.New("receipt size changed during pull"))
	}
	var receipt returnReceipt
	if err := decodeStrictFile(localReceipt, maxReceiptBytes, &receipt); err != nil {
		return nil, fail("RETURN_RECEIPT_INVALID", err)
	}
	if err := validateReceipt(receipt, req); err != nil {
		return nil, err
	}
	receiptDigest, err := fileSHA256(localReceipt)
	if err != nil {
		return nil, err
	}
	if receiptDigest != remoteReceiptSHA {
		return nil, fail("RETURN_RECEIPT_SHA_MISMATCH", errors.New("remote and local receipt sha differ"))
	}

	verifiedTotal := int64(0)
	for _, artifact := range receipt.Artifacts {
		remotePath := remoteJoin(cfg.RemoteOutbox, id, artifact.Name)
		size, err := rt.remoteRegularSize(target, remotePath, maxArtifactBytes)
		if err != nil {
			return nil, err
		}
		if size != artifact.SizeBytes {
			return nil, fail("RETURN_ARTIFACT_SIZE_MISMATCH", fmt.Errorf("declared size mismatch for %s", artifact.Name))
		}
		remoteSHA, err := rt.remoteSHA256(target, remotePath)
		if err != nil {
			return nil, err
		}
		if remoteSHA != artifact.SHA256 {
			return nil, fail("RETURN_ARTIFACT_REMOTE_SHA_MISMATCH", fmt.Errorf("remote sha mismatch for %s", artifact.Name))
		}
		localPath := filepath.Join(artifactDir, artifact.Name)
		if err := rt.scpFrom(target, remotePath, localPath); err != nil {
			return nil, err
		}
		if err := chmodRegular(localPath); err != nil {
			return nil, err
		}
		info, err := os.Lstat(localPath)
		if err != nil {
			return nil, err
		}
		if info.Size() != artifact.SizeBytes {
			return nil, fail("RETURN_ARTIFACT_LOCAL_SIZE_MISMATCH", fmt.Errorf("local size mismatch for %s", artifact.Name))
		}
		localSHA, err := fileSHA256(localPath)
		if err != nil {
			return nil, err
		}
		if localSHA != artifact.SHA256 || localSHA != remoteSHA {
			return nil, fail("RETURN_ARTIFACT_LOCAL_SHA_MISMATCH", fmt.Errorf("local sha mismatch for %s", artifact.Name))
		}
		verifiedTotal += artifact.SizeBytes
		if verifiedTotal > maxTotalBytes {
			return nil, fail("RETURN_TOTAL_SIZE_EXCEEDED", errors.New("aggregate size exceeds limit"))
		}
	}

	markerVerified := false
	if req.ExpectedResultMarker != "" {
		primary := filepath.Join(artifactDir, receipt.PrimaryArtifact)
		ok, err := fileHasExactLine(primary, req.ExpectedResultMarker)
		if err != nil {
			return nil, err
		}
		if !ok {
			return nil, fail("RETURN_MARKER_MISSING", errors.New("expected marker not present in primary artifact"))
		}
		markerVerified = true
	}

	accepted := acceptance{Schema: acceptanceSchema, ReturnID: id, DeliveryID: req.DeliveryID, SourceTarget: req.SourceTarget, ReceiptSHA256: receiptDigest, ArtifactCount: len(receipt.Artifacts), VerifiedTotalBytes: verifiedTotal, CorrelationVerified: true, OriginVerified: true, SHAVerified: true, MarkerVerified: markerVerified, VerifiedEpoch: time.Now().Unix(), State: "verified"}
	if err := atomicJSON(filepath.Join(stage, "acceptance.json"), accepted, 0o600); err != nil {
		return nil, err
	}
	final := filepath.Join(rt.inboundDir, "verified", id)
	if _, err := os.Lstat(final); err == nil {
		var existing acceptance
		if decodeStrictFile(filepath.Join(final, "acceptance.json"), maxReceiptBytes, &existing) == nil && existing.ReceiptSHA256 == receiptDigest {
			_ = rt.writeState(returnState{Schema: stateSchema, ReturnID: id, State: "verified", UpdatedEpoch: time.Now().Unix(), ProducerResult: receipt.ResultState, ReceiptSHA256: receiptDigest})
			return map[string]any{"schema": acceptanceSchema, "returnId": id, "state": "verified", "producerResult": receipt.ResultState, "receiptSha256": receiptDigest, "artifactCount": len(receipt.Artifacts), "verifiedBytes": verifiedTotal, "idempotent": true}, nil
		}
		return nil, fail("RETURN_REPLAY_CONFLICT", errors.New("verified return id already exists with different receipt identity"))
	} else if !os.IsNotExist(err) {
		return nil, err
	}
	if err := os.Rename(stage, final); err != nil {
		return nil, err
	}
	if err := rt.writeState(returnState{Schema: stateSchema, ReturnID: id, State: "verified", UpdatedEpoch: time.Now().Unix(), ProducerResult: receipt.ResultState, ReceiptSHA256: receiptDigest}); err != nil {
		return nil, err
	}
	if err := rt.appendAcceptanceIndex(accepted, receipt.ResultState); err != nil {
		return nil, err
	}
	return map[string]any{"schema": acceptanceSchema, "returnId": id, "state": "verified", "producerResult": receipt.ResultState, "receiptSha256": receiptDigest, "artifactCount": len(receipt.Artifacts), "verifiedBytes": verifiedTotal, "idempotent": false}, nil
}

func validateReceipt(receipt returnReceipt, req returnRequest) error {
	if receipt.Schema != receiptSchema {
		return fail("RETURN_RECEIPT_SCHEMA_MISMATCH", errors.New("wrong receipt schema"))
	}
	if receipt.ReturnID != req.ReturnID || receipt.DeliveryID != req.DeliveryID || receipt.ArtifactSHA256 != req.ArtifactSHA256 || receipt.SourceTarget != req.SourceTarget || receipt.ResultType != req.ExpectedResultType {
		return fail("RETURN_CORRELATION_MISMATCH", errors.New("receipt correlation does not match local request"))
	}
	if receipt.ResultMarker != req.ExpectedResultMarker || receipt.CallerCorrelation != req.CallerCorrelation {
		return fail("RETURN_CORRELATION_MISMATCH", errors.New("optional correlation metadata mismatch"))
	}
	if !returnIDRE.MatchString(receipt.ReturnID) || !deliveryIDRE.MatchString(receipt.DeliveryID) || !shaRE.MatchString(receipt.ArtifactSHA256) || !targetRE.MatchString(receipt.SourceTarget) || !resultTypeRE.MatchString(receipt.ResultType) {
		return fail("RETURN_RECEIPT_FIELD_INVALID", errors.New("receipt identity field invalid"))
	}
	switch receipt.ResultState {
	case "success", "failure", "partial", "cancelled":
	default:
		return fail("RETURN_RESULT_STATE_INVALID", errors.New("invalid producer result state"))
	}
	if receipt.ResultMarker != "" && !printableSingleLine(receipt.ResultMarker, 256) {
		return fail("RETURN_MARKER_INVALID", errors.New("invalid result marker"))
	}
	if receipt.CallerCorrelation != "" && !printableSingleLine(receipt.CallerCorrelation, 256) {
		return fail("RETURN_CORRELATION_INVALID", errors.New("invalid caller correlation"))
	}
	if len(receipt.Artifacts) < 1 || len(receipt.Artifacts) > maxArtifacts {
		return fail("RETURN_ARTIFACT_COUNT_INVALID", errors.New("artifact count out of range"))
	}
	seen := map[string]bool{}
	primary := false
	total := int64(0)
	for _, item := range receipt.Artifacts {
		if !safeArtifactName(item.Name) || !shaRE.MatchString(item.SHA256) || item.SizeBytes < 1 || item.SizeBytes > maxArtifactBytes {
			return fail("RETURN_ARTIFACT_DECLARATION_INVALID", fmt.Errorf("invalid artifact declaration %q", item.Name))
		}
		if seen[item.Name] {
			return fail("RETURN_ARTIFACT_DUPLICATE", fmt.Errorf("duplicate artifact %q", item.Name))
		}
		seen[item.Name] = true
		if item.Name == receipt.PrimaryArtifact {
			primary = true
		}
		if item.SizeBytes > maxTotalBytes-total {
			return fail("RETURN_TOTAL_SIZE_EXCEEDED", errors.New("aggregate declared size exceeds limit"))
		}
		total += item.SizeBytes
	}
	if !primary || !safeArtifactName(receipt.PrimaryArtifact) {
		return fail("RETURN_PRIMARY_ARTIFACT_INVALID", errors.New("primary artifact not declared"))
	}
	if receipt.ProducerStartedEpoch != nil && *receipt.ProducerStartedEpoch < 0 {
		return fail("RETURN_TIMESTAMP_INVALID", errors.New("invalid producer start"))
	}
	if receipt.ProducerEndedEpoch != nil && *receipt.ProducerEndedEpoch < 0 {
		return fail("RETURN_TIMESTAMP_INVALID", errors.New("invalid producer end"))
	}
	if receipt.ProducerStartedEpoch != nil && receipt.ProducerEndedEpoch != nil && *receipt.ProducerEndedEpoch < *receipt.ProducerStartedEpoch {
		return fail("RETURN_TIMESTAMP_INVALID", errors.New("producer end precedes start"))
	}
	return nil
}

func safeArtifactName(name string) bool {
	return artifactNameRE.MatchString(name) && name != "." && name != ".." && !strings.HasPrefix(name, ".")
}
func printableSingleLine(value string, max int) bool {
	if value == "" || len(value) > max || !utf8.ValidString(value) {
		return false
	}
	for _, r := range value {
		if r < 0x20 || r > 0x7e {
			return false
		}
	}
	return true
}

func (rt runtime) waitCommand(args []string) error {
	if len(args) < 1 || len(args) > 3 {
		return fail("RETURN_USAGE", errors.New("wait <return-id> [timeout] [interval]"))
	}
	id := args[0]
	timeout := int64(300)
	interval := defaultPoll
	var err error
	if len(args) >= 2 {
		timeout, err = boundedInt(args[1], 1, maxWaitSeconds)
		if err != nil {
			return err
		}
	}
	if len(args) == 3 {
		interval, err = boundedInt(args[2], 2, 60)
		if err != nil {
			return err
		}
	}
	deadline := time.Now().Add(time.Duration(timeout) * time.Second)
	for {
		result, collectErr := rt.collectOnce(id)
		if collectErr == nil {
			return rt.emit(result)
		}
		var ce *contractError
		if errors.As(collectErr, &ce) && (ce.Transient || ce.Code == "RETURN_REMOTE_NOT_AVAILABLE") {
			if time.Now().Add(time.Duration(interval) * time.Second).After(deadline) {
				_ = rt.writeState(returnState{Schema: stateSchema, ReturnID: id, State: "timeout", UpdatedEpoch: time.Now().Unix()})
				return fail("RETURN_TIMEOUT", errors.New("bounded return wait expired"))
			}
			time.Sleep(time.Duration(interval) * time.Second)
			continue
		}
		return rt.failState(id, collectErr)
	}
}

func boundedInt(value string, min, max int64) (int64, error) {
	n, err := strconv.ParseInt(value, 10, 64)
	if err != nil || n < min || n > max {
		return 0, fail("RETURN_BOUND_INVALID", errors.New("numeric bound out of range"))
	}
	return n, nil
}

func (rt runtime) trace(id string) error {
	req, err := rt.loadRequest(id)
	if err != nil {
		return err
	}
	state, err := rt.loadState(id)
	if err != nil {
		return err
	}
	_, cfgErr := rt.loadReturnConfig(req.SourceTarget)
	return rt.emit(map[string]any{"schema": "SDD_RETURN_TRACE_V1", "returnId": id, "deliveryId": req.DeliveryID, "sourceTarget": req.SourceTarget, "expectedResultType": req.ExpectedResultType, "state": state.State, "producerResult": state.ProducerResult, "bindingRequired": true, "capabilityConfigured": cfgErr == nil, "callerCorrelationExposed": false, "markerExposed": false, "outboxPathExposed": false})
}

func (rt runtime) inventory() error {
	if err := rt.ensureLayout(); err != nil {
		return err
	}
	entries, err := os.ReadDir(filepath.Join(rt.inboundDir, "state"))
	if err != nil {
		return err
	}
	items := []map[string]any{}
	for _, entry := range entries {
		if entry.IsDir() || !strings.HasSuffix(entry.Name(), ".json") {
			continue
		}
		id := strings.TrimSuffix(entry.Name(), ".json")
		if !returnIDRE.MatchString(id) {
			continue
		}
		state, err := rt.loadState(id)
		if err != nil {
			continue
		}
		req, err := rt.loadRequest(id)
		if err != nil {
			continue
		}
		items = append(items, map[string]any{"return_id": id, "target": req.SourceTarget, "result_type": req.ExpectedResultType, "state": state.State, "producer_result": emptyAs(state.ProducerResult, "unknown"), "updated_epoch": state.UpdatedEpoch})
	}
	sort.Slice(items, func(i, j int) bool { return items[i]["return_id"].(string) < items[j]["return_id"].(string) })
	return rt.emit(map[string]any{"ok": true, "name": "returns", "columns": []string{"return_id", "target", "result_type", "state", "producer_result", "updated_epoch"}, "items": items})
}

func (rt runtime) cleanupPreview() error {
	if err := rt.ensureLayout(); err != nil {
		return err
	}
	root := filepath.Join(rt.inboundDir, "verified")
	entries, err := os.ReadDir(root)
	if err != nil {
		return err
	}
	count := 0
	bytesTotal := int64(0)
	oldest := int64(0)
	for _, entry := range entries {
		if !entry.IsDir() || !returnIDRE.MatchString(entry.Name()) {
			continue
		}
		var acc acceptance
		if decodeStrictFile(filepath.Join(root, entry.Name(), "acceptance.json"), maxReceiptBytes, &acc) != nil || acc.State != "verified" {
			continue
		}
		count++
		bytesTotal += acc.VerifiedTotalBytes
		if oldest == 0 || acc.VerifiedEpoch < oldest {
			oldest = acc.VerifiedEpoch
		}
	}
	return rt.emit(map[string]any{"schema": "SDD_RETURN_RETENTION_PREVIEW_V1", "verifiedCount": count, "verifiedArtifactBytes": bytesTotal, "oldestVerifiedEpoch": oldest, "automaticDeletion": false, "applySupported": false})
}

func (rt runtime) jobFile(args []string) error {
	if len(args) != 2 {
		return fail("RETURN_USAGE", errors.New("job-file <job> <private-request-file>"))
	}
	job, path := args[0], args[1]
	if !rt.privateWebUIRequest(path) {
		return fail("RETURN_WEBUI_REQUEST_PATH_INVALID", errors.New("request file outside private WebUI runtime"))
	}
	var envelope struct {
		Name       string                     `json:"name"`
		Parameters map[string]json.RawMessage `json:"parameters"`
	}
	if err := decodeStrictFile(path, 65536, &envelope); err != nil {
		return fail("RETURN_WEBUI_REQUEST_INVALID", err)
	}
	if envelope.Name != job {
		return fail("RETURN_WEBUI_REQUEST_INVALID", errors.New("job name mismatch"))
	}
	getString := func(key string) (string, error) {
		raw, ok := envelope.Parameters[key]
		if !ok {
			return "", nil
		}
		var v string
		if err := decodeStrictBytes(raw, &v); err != nil {
			return "", err
		}
		return v, nil
	}
	getInt := func(key string) (int64, error) {
		raw, ok := envelope.Parameters[key]
		if !ok {
			return 0, nil
		}
		var v int64
		if err := decodeStrictBytes(raw, &v); err != nil {
			return 0, err
		}
		return v, nil
	}
	switch job {
	case "return-request":
		deliveryID, e1 := getString("delivery_id")
		target, e2 := getString("target")
		resultType, e3 := getString("result_type")
		marker, e4 := getString("marker")
		correlation, e5 := getString("correlation")
		if firstErr(e1, e2, e3, e4, e5) != nil {
			return fail("RETURN_WEBUI_REQUEST_INVALID", firstErr(e1, e2, e3, e4, e5))
		}
		return rt.createRequest(deliveryID, target, resultType, marker, correlation)
	case "return-probe", "return-collect", "return-wait":
		id, err := getString("return_id")
		if err != nil {
			return err
		}
		switch job {
		case "return-probe":
			return rt.probe(id)
		case "return-collect":
			return rt.collect(id)
		}
		timeout, err := getInt("timeout_seconds")
		if err != nil {
			return err
		}
		if timeout == 0 {
			timeout = 300
		}
		return rt.waitCommand([]string{id, strconv.FormatInt(timeout, 10), strconv.FormatInt(defaultPoll, 10)})
	case "return-cleanup-preview":
		return rt.cleanupPreview()
	default:
		return fail("RETURN_WEBUI_JOB_UNSUPPORTED", errors.New("unsupported typed return job"))
	}
}

func firstErr(values ...error) error {
	for _, err := range values {
		if err != nil {
			return err
		}
	}
	return nil
}

func (rt runtime) privateWebUIRequest(path string) bool {
	abs, err := filepath.Abs(path)
	if err != nil {
		return false
	}
	root, err := filepath.Abs(envOr("WEBUI_RUNTIME_DIR", "/data/local/tmp/ssh_drop_dispatcher-webui"))
	if err != nil {
		return false
	}
	rel, err := filepath.Rel(filepath.Join(root, "requests"), abs)
	if err != nil || rel == "." || rel == ".." || strings.HasPrefix(rel, ".."+string(os.PathSeparator)) {
		return false
	}
	info, err := os.Lstat(abs)
	return err == nil && info.Mode().IsRegular() && info.Mode()&os.ModeSymlink == 0 && info.Size() > 0 && info.Size() <= 65536
}

func (rt runtime) validateReceiptFixture(args []string) error {
	if len(args) != 2 {
		return fail("RETURN_USAGE", errors.New("validate-receipt-fixture <request> <receipt>"))
	}
	var req returnRequest
	if err := decodeStrictFile(args[0], maxReceiptBytes, &req); err != nil {
		return err
	}
	if err := validateRequest(req); err != nil {
		return err
	}
	var receipt returnReceipt
	if err := decodeStrictFile(args[1], maxReceiptBytes, &receipt); err != nil {
		return err
	}
	if err := validateReceipt(receipt, req); err != nil {
		return err
	}
	return rt.emit(map[string]any{"schema": receiptSchema, "validation": "pass", "artifactCount": len(receipt.Artifacts), "resultState": receipt.ResultState})
}

func validateRequest(req returnRequest) error {
	if req.Schema != requestSchema || !returnIDRE.MatchString(req.ReturnID) || !deliveryIDRE.MatchString(req.DeliveryID) || !shaRE.MatchString(req.ArtifactSHA256) || !targetRE.MatchString(req.SourceTarget) || !resultTypeRE.MatchString(req.ExpectedResultType) || req.CreatedEpoch <= 0 {
		return fail("RETURN_REQUEST_INVALID", errors.New("request fields invalid"))
	}
	if req.ExpectedResultMarker != "" && !printableSingleLine(req.ExpectedResultMarker, 256) {
		return fail("RETURN_REQUEST_INVALID", errors.New("marker invalid"))
	}
	if req.CallerCorrelation != "" && !printableSingleLine(req.CallerCorrelation, 256) {
		return fail("RETURN_REQUEST_INVALID", errors.New("correlation invalid"))
	}
	return nil
}

func (rt runtime) loadRequestContext(id string) (returnRequest, returnConfig, targetConfig, error) {
	req, err := rt.loadRequest(id)
	if err != nil {
		return req, returnConfig{}, targetConfig{}, err
	}
	cfg, err := rt.loadReturnConfig(req.SourceTarget)
	if err != nil {
		return req, cfg, targetConfig{}, err
	}
	if !cfg.Enabled {
		return req, cfg, targetConfig{}, fail("RETURN_CAPABILITY_DISABLED", errors.New("return capability disabled"))
	}
	target, err := rt.loadTarget(req.SourceTarget)
	if err != nil {
		return req, cfg, target, err
	}
	if !target.Enabled {
		return req, cfg, target, fail("RETURN_TARGET_DISABLED", errors.New("target disabled"))
	}
	var bind binding
	if err := decodeStrictFile(filepath.Join(rt.stateDir, "delivery-bindings", req.DeliveryID, req.SourceTarget+".json"), maxReceiptBytes, &bind); err != nil {
		return req, cfg, target, fail("RETURN_BINDING_MISSING_OR_INVALID", err)
	}
	if err := validateBinding(bind, req.DeliveryID, req.SourceTarget); err != nil {
		return req, cfg, target, err
	}
	if bind.ArtifactSHA256 != req.ArtifactSHA256 {
		return req, cfg, target, fail("RETURN_BINDING_CONFLICT", errors.New("request artifact sha no longer matches binding"))
	}
	return req, cfg, target, nil
}

func (rt runtime) loadRequest(id string) (returnRequest, error) {
	var req returnRequest
	if !returnIDRE.MatchString(id) {
		return req, fail("RETURN_ID_INVALID", errors.New("invalid return id"))
	}
	if err := decodeStrictFile(rt.requestPath(id), maxReceiptBytes, &req); err != nil {
		return req, fail("RETURN_REQUEST_MISSING_OR_INVALID", err)
	}
	if err := validateRequest(req); err != nil {
		return req, err
	}
	if req.ReturnID != id {
		return req, fail("RETURN_REQUEST_INVALID", errors.New("request filename/id mismatch"))
	}
	return req, nil
}

func (rt runtime) requestPath(id string) string {
	return filepath.Join(rt.inboundDir, "requests", id+".json")
}
func (rt runtime) statePath(id string) string {
	return filepath.Join(rt.inboundDir, "state", id+".json")
}

func (rt runtime) loadState(id string) (returnState, error) {
	var state returnState
	if !returnIDRE.MatchString(id) {
		return state, fail("RETURN_ID_INVALID", errors.New("invalid return id"))
	}
	if err := decodeStrictFile(rt.statePath(id), maxReceiptBytes, &state); err != nil {
		return state, fail("RETURN_STATE_MISSING_OR_INVALID", err)
	}
	if state.Schema != stateSchema || state.ReturnID != id || !validReturnState(state.State) {
		return state, fail("RETURN_STATE_INVALID", errors.New("invalid state document"))
	}
	return state, nil
}

func validReturnState(value string) bool {
	switch value {
	case "not_requested", "pending", "available", "verified", "failed", "timeout":
		return true
	}
	return false
}
func (rt runtime) writeState(state returnState) error {
	if !validReturnState(state.State) {
		return errors.New("invalid return state")
	}
	return atomicJSON(rt.statePath(state.ReturnID), state, 0o600)
}
func (rt runtime) failState(id string, err error) error {
	code := "RETURN_FAILED"
	var ce *contractError
	if errors.As(err, &ce) {
		code = ce.Code
	}
	_ = rt.writeState(returnState{Schema: stateSchema, ReturnID: id, State: "failed", UpdatedEpoch: time.Now().Unix(), ErrorCode: code})
	return err
}

func (rt runtime) loadTarget(name string) (targetConfig, error) {
	var cfg targetConfig
	if !targetRE.MatchString(name) {
		return cfg, fail("RETURN_TARGET_INVALID", errors.New("invalid target"))
	}
	values, err := parseConf(filepath.Join(rt.stateDir, "config", "targets.d", name+".conf"), map[string]bool{"target_name": true, "enabled": true, "aliases": true, "ssh_user": true, "ssh_host": true, "host": true, "ssh_port": true, "remote_drop": true, "platform": true, "shell": true, "scp_flags": true, "role": true, "critical_role": true, "allow_fallback": true})
	if err != nil {
		return cfg, fail("RETURN_TARGET_CONFIG_INVALID", err)
	}
	cfg.Name = values["target_name"]
	if cfg.Name != name {
		return cfg, fail("RETURN_TARGET_CONFIG_INVALID", errors.New("target filename/name mismatch"))
	}
	cfg.Enabled = values["enabled"] == "" || values["enabled"] == "1"
	if values["enabled"] != "" && values["enabled"] != "0" && values["enabled"] != "1" {
		return cfg, fail("RETURN_TARGET_CONFIG_INVALID", errors.New("invalid enabled"))
	}
	cfg.SSHHost = values["ssh_host"]
	if cfg.SSHHost == "" {
		cfg.SSHHost = values["host"]
	}
	if cfg.SSHHost == "" || len(cfg.SSHHost) > 128 || !regexp.MustCompile(`^[A-Za-z0-9._-]+$`).MatchString(cfg.SSHHost) {
		return cfg, fail("RETURN_TARGET_CONFIG_INVALID", errors.New("invalid ssh host alias"))
	}
	cfg.SCPFlags = strings.TrimSpace(values["scp_flags"])
	if cfg.SCPFlags != "" && cfg.SCPFlags != "-O" {
		return cfg, fail("RETURN_TARGET_CONFIG_INVALID", errors.New("return channel supports only empty or -O scp profile"))
	}
	return cfg, nil
}

func (rt runtime) loadReturnConfig(name string) (returnConfig, error) {
	var cfg returnConfig
	values, err := parseConf(filepath.Join(rt.stateDir, "config", "returns.d", name+".conf"), map[string]bool{"return_enabled": true, "remote_outbox": true})
	if err != nil {
		return cfg, fail("RETURN_CAPABILITY_CONFIG_INVALID", err)
	}
	cfg.Enabled = values["return_enabled"] == "1"
	if values["return_enabled"] != "0" && values["return_enabled"] != "1" {
		return cfg, fail("RETURN_CAPABILITY_CONFIG_INVALID", errors.New("return_enabled must be 0 or 1"))
	}
	cfg.RemoteOutbox = values["remote_outbox"]
	if cfg.Enabled {
		if !safeRemoteOutbox(cfg.RemoteOutbox) {
			return cfg, fail("RETURN_OUTBOX_PATH_INVALID", errors.New("invalid remote outbox"))
		}
	}
	return cfg, nil
}

func safeRemoteOutbox(value string) bool {
	if value == "" || value == "/" || !remotePathRE.MatchString(value) || strings.Contains(value, "//") {
		return false
	}
	clean := filepath.Clean(value)
	return clean == value && strings.HasPrefix(clean, "/")
}

func parseConf(path string, allowed map[string]bool) (map[string]string, error) {
	info, err := os.Lstat(path)
	if err != nil {
		return nil, err
	}
	if !info.Mode().IsRegular() || info.Mode()&os.ModeSymlink != 0 || info.Size() > 65536 {
		return nil, errors.New("config must be bounded regular file")
	}
	file, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer file.Close()
	out := map[string]string{}
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		parts := strings.SplitN(line, "=", 2)
		if len(parts) != 2 {
			return nil, errors.New("invalid config line")
		}
		key := strings.TrimSpace(parts[0])
		if !allowed[key] {
			return nil, fmt.Errorf("unsupported config key %s", key)
		}
		if _, exists := out[key]; exists {
			return nil, fmt.Errorf("duplicate config key %s", key)
		}
		value, err := shellScalar(strings.TrimSpace(parts[1]))
		if err != nil {
			return nil, err
		}
		out[key] = value
	}
	if err := scanner.Err(); err != nil {
		return nil, err
	}
	return out, nil
}

func shellScalar(value string) (string, error) {
	if len(value) >= 2 && ((value[0] == '"' && value[len(value)-1] == '"') || (value[0] == '\'' && value[len(value)-1] == '\'')) {
		value = value[1 : len(value)-1]
	}
	if strings.ContainsAny(value, "\r\n\x00") {
		return "", errors.New("invalid config scalar")
	}
	return value, nil
}
func configValue(path, key, fallback string) string {
	values, err := parseConf(path, map[string]bool{key: true})
	if err == nil && values[key] != "" {
		return values[key]
	}
	file, err := os.Open(path)
	if err != nil {
		return fallback
	}
	defer file.Close()
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if strings.HasPrefix(line, key+"=") {
			v, _ := shellScalar(strings.TrimPrefix(line, key+"="))
			if v != "" {
				return v
			}
		}
	}
	return fallback
}

func remoteJoin(root, id, name string) string {
	return strings.TrimSuffix(root, "/") + "/" + id + "/" + name
}
func shellQuote(value string) string { return "'" + strings.ReplaceAll(value, "'", "'\\''") + "'" }

func (rt runtime) remoteRegularSize(target targetConfig, path string, limit int64) (int64, error) {
	if !safeConstructedRemotePath(path) {
		return 0, fail("RETURN_REMOTE_PATH_INVALID", errors.New("constructed path invalid"))
	}
	cmd := `p=$1; if [ -L "$p" ]; then exit 42; fi; if [ ! -f "$p" ]; then exit 43; fi; wc -c < "$p"`
	out, code, err := rt.ssh(target, "sh -c "+shellQuote(cmd)+" sh "+shellQuote(path))
	if err != nil {
		if code == 43 {
			return 0, fail("RETURN_REMOTE_NOT_AVAILABLE", errors.New("remote file not available"))
		}
		if code == 42 {
			return 0, fail("RETURN_REMOTE_SPECIAL_FILE", errors.New("remote path is symlink"))
		}
		return 0, transient("RETURN_TRANSPORT_UNAVAILABLE", err)
	}
	size, err := strconv.ParseInt(strings.TrimSpace(out), 10, 64)
	if err != nil || size < 1 || size > limit {
		return 0, fail("RETURN_REMOTE_SIZE_INVALID", errors.New("remote size out of bounds"))
	}
	return size, nil
}
func safeConstructedRemotePath(path string) bool {
	return remotePathRE.MatchString(path) && filepath.Clean(path) == path && !strings.Contains(path, "//")
}
func (rt runtime) remoteSHA256(target targetConfig, path string) (string, error) {
	cmd := `p=$1; if [ -L "$p" ] || [ ! -f "$p" ]; then exit 42; fi; if command -v sha256sum >/dev/null 2>&1; then sha256sum "$p"; elif command -v busybox >/dev/null 2>&1; then busybox sha256sum "$p"; else exit 44; fi`
	out, code, err := rt.ssh(target, "sh -c "+shellQuote(cmd)+" sh "+shellQuote(path))
	if err != nil {
		if code == 44 {
			return "", fail("RETURN_REMOTE_SHA_UNAVAILABLE", errors.New("remote sha256 unavailable"))
		}
		if code == 42 {
			return "", fail("RETURN_REMOTE_SPECIAL_FILE", errors.New("remote file invalid"))
		}
		return "", transient("RETURN_TRANSPORT_UNAVAILABLE", err)
	}
	fields := strings.Fields(out)
	if len(fields) < 1 || !shaRE.MatchString(strings.ToLower(fields[0])) {
		return "", fail("RETURN_REMOTE_SHA_INVALID", errors.New("invalid remote sha output"))
	}
	return strings.ToLower(fields[0]), nil
}
func (rt runtime) ssh(target targetConfig, remote string) (string, int, error) {
	if _, err := os.Stat(rt.sshBin); err != nil {
		return "", -1, err
	}
	args := []string{"-F", rt.sshConfig, "-o", "BatchMode=yes", "-o", "ConnectTimeout=12", target.SSHHost, remote}
	cmd := exec.Command(rt.sshBin, args...)
	output, err := cmd.CombinedOutput()
	if err == nil {
		return string(output), 0, nil
	}
	code := -1
	var ee *exec.ExitError
	if errors.As(err, &ee) {
		code = ee.ExitCode()
	}
	return string(output), code, err
}
func (rt runtime) scpFrom(target targetConfig, remote, local string) error {
	if _, err := os.Stat(rt.scpBin); err != nil {
		return transient("RETURN_TRANSPORT_UNAVAILABLE", err)
	}
	args := []string{}
	if target.SCPFlags == "-O" {
		args = append(args, "-O")
	}
	args = append(args, "-F", rt.sshConfig, "-o", "BatchMode=yes", "-o", "ConnectTimeout=20", target.SSHHost+":"+remote, local)
	cmd := exec.Command(rt.scpBin, args...)
	if out, err := cmd.CombinedOutput(); err != nil {
		return transient("RETURN_SCP_FAILED", fmt.Errorf("scp failed: %v (%s)", err, strings.TrimSpace(string(out))))
	}
	return nil
}

func decodeStrictFile(path string, max int64, dst any) error {
	info, err := os.Lstat(path)
	if err != nil {
		return err
	}
	if !info.Mode().IsRegular() || info.Mode()&os.ModeSymlink != 0 || info.Size() < 1 || info.Size() > max {
		return errors.New("file must be bounded regular non-symlink")
	}
	data, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	return decodeStrictBytes(data, dst)
}
func decodeStrictBytes(data []byte, dst any) error {
	if !utf8.Valid(data) {
		return errors.New("invalid utf-8")
	}
	if err := rejectDuplicateJSONKeys(data); err != nil {
		return err
	}
	dec := json.NewDecoder(bytes.NewReader(data))
	dec.DisallowUnknownFields()
	if err := dec.Decode(dst); err != nil {
		return err
	}
	var extra any
	if err := dec.Decode(&extra); err != io.EOF {
		return errors.New("json must contain exactly one value")
	}
	return nil
}
func rejectDuplicateJSONKeys(data []byte) error {
	dec := json.NewDecoder(bytes.NewReader(data))
	dec.UseNumber()
	var parse func() error
	parse = func() error {
		tok, err := dec.Token()
		if err != nil {
			return err
		}
		delim, ok := tok.(json.Delim)
		if !ok {
			return nil
		}
		switch delim {
		case '{':
			seen := map[string]bool{}
			for dec.More() {
				keyTok, err := dec.Token()
				if err != nil {
					return err
				}
				key, ok := keyTok.(string)
				if !ok {
					return errors.New("object key is not string")
				}
				if seen[key] {
					return fmt.Errorf("duplicate json key %q", key)
				}
				seen[key] = true
				if err := parse(); err != nil {
					return err
				}
			}
			end, err := dec.Token()
			if err != nil || end != json.Delim('}') {
				return errors.New("invalid object termination")
			}
		case '[':
			for dec.More() {
				if err := parse(); err != nil {
					return err
				}
			}
			end, err := dec.Token()
			if err != nil || end != json.Delim(']') {
				return errors.New("invalid array termination")
			}
		default:
			return errors.New("unexpected json delimiter")
		}
		return nil
	}
	if err := parse(); err != nil {
		return err
	}
	if _, err := dec.Token(); err != io.EOF {
		return errors.New("trailing json value")
	}
	return nil
}

func atomicJSON(path string, value any, mode os.FileMode) error {
	dir := filepath.Dir(path)
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return err
	}
	data, err := json.Marshal(value)
	if err != nil {
		return err
	}
	data = append(data, '\n')
	tmp, err := os.CreateTemp(dir, ".tmp-")
	if err != nil {
		return err
	}
	name := tmp.Name()
	ok := false
	defer func() {
		_ = tmp.Close()
		if !ok {
			_ = os.Remove(name)
		}
	}()
	if err := tmp.Chmod(mode); err != nil {
		return err
	}
	if _, err := tmp.Write(data); err != nil {
		return err
	}
	if err := tmp.Sync(); err != nil {
		return err
	}
	if err := tmp.Close(); err != nil {
		return err
	}
	if err := os.Rename(name, path); err != nil {
		return err
	}
	ok = true
	return nil
}
func chmodRegular(path string) error {
	info, err := os.Lstat(path)
	if err != nil {
		return err
	}
	if !info.Mode().IsRegular() || info.Mode()&os.ModeSymlink != 0 {
		return fail("RETURN_LOCAL_SPECIAL_FILE", errors.New("local staging file is not regular"))
	}
	return os.Chmod(path, 0o600)
}
func fileSHA256(path string) (string, error) {
	f, err := os.Open(path)
	if err != nil {
		return "", err
	}
	defer f.Close()
	h := sha256.New()
	if _, err := io.Copy(h, f); err != nil {
		return "", err
	}
	return hex.EncodeToString(h.Sum(nil)), nil
}
func fileHasExactLine(path, marker string) (bool, error) {
	f, err := os.Open(path)
	if err != nil {
		return false, err
	}
	defer f.Close()
	scanner := bufio.NewScanner(f)
	scanner.Buffer(make([]byte, 4096), 1<<20)
	for scanner.Scan() {
		if scanner.Text() == marker {
			return true, nil
		}
	}
	return false, scanner.Err()
}

func (rt runtime) appendAcceptanceIndex(acc acceptance, producer string) error {
	path := filepath.Join(rt.inboundDir, "receipts.jsonl")
	line, err := json.Marshal(map[string]any{"schema": acceptanceSchema, "returnId": acc.ReturnID, "deliveryId": acc.DeliveryID, "sourceTarget": acc.SourceTarget, "state": "verified", "producerResult": producer, "receiptSha256": acc.ReceiptSHA256, "verifiedEpoch": acc.VerifiedEpoch})
	if err != nil {
		return err
	}
	file, err := os.OpenFile(path, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0o600)
	if err != nil {
		return err
	}
	defer file.Close()
	line = append(line, '\n')
	if _, err := file.Write(line); err != nil {
		return err
	}
	return file.Sync()
}
func (rt runtime) emit(value any) error {
	if rt.format == "json" {
		return json.NewEncoder(os.Stdout).Encode(value)
	}
	data, err := json.Marshal(value)
	if err != nil {
		return err
	}
	var obj map[string]any
	if err := json.Unmarshal(data, &obj); err != nil {
		return err
	}
	keys := make([]string, 0, len(obj))
	for key := range obj {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	for _, key := range keys {
		switch v := obj[key].(type) {
		case string:
			fmt.Printf("%s=%s\n", envKey(key), v)
		case bool:
			fmt.Printf("%s=%s\n", envKey(key), yesNo(v))
		case float64:
			fmt.Printf("%s=%.0f\n", envKey(key), v)
		default:
			encoded, _ := json.Marshal(v)
			fmt.Printf("%s=%s\n", envKey(key), encoded)
		}
	}
	fmt.Println("RESULT: SDD_RETURN_DONE outcome=success exit_code=0")
	return nil
}
func envKey(value string) string {
	var out strings.Builder
	for i, r := range value {
		if r >= 'A' && r <= 'Z' && i > 0 {
			out.WriteByte('_')
		}
		if r >= 'A' && r <= 'Z' {
			r = r - 'A' + 'a'
		}
		out.WriteRune(r)
	}
	return out.String()
}
func yesNo(value bool) string {
	if value {
		return "yes"
	}
	return "no"
}
func emptyAs(value, fallback string) string {
	if value == "" {
		return fallback
	}
	return value
}
