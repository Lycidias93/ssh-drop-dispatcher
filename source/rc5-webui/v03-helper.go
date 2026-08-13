package main

import (
	"bufio"
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
)

const backupSchema = "sdd-target-profiles-backup-v1"

var (
	nameRE    = regexp.MustCompile(`^[a-z0-9_-]{1,32}$`)
	aliasRE   = regexp.MustCompile(`^[A-Za-z0-9._-]{1,128}$`)
	aliasesRE = regexp.MustCompile(`^[A-Za-z0-9,._ -]{0,256}$`)
	userRE    = regexp.MustCompile(`^[A-Za-z0-9._-]{0,64}$`)
	pathRE    = regexp.MustCompile(`^/[-A-Za-z0-9._/@+:]{1,255}$`)
	labelRE   = regexp.MustCompile(`^[A-Za-z0-9._-]{0,64}$`)
)

type target struct {
	Name       string `json:"name"`
	Enabled    bool   `json:"enabled"`
	Aliases    string `json:"aliases"`
	SSHUser    string `json:"ssh_user"`
	SSHAlias   string `json:"ssh_alias"`
	SSHPort    int    `json:"ssh_port"`
	RemoteDrop string `json:"remote_drop"`
	Platform   string `json:"platform"`
	Shell      string `json:"shell"`
	SCPMode    string `json:"scp_mode"`
	Role       string `json:"role"`
}

type collectionRequest struct {
	Name         string   `json:"name"`
	Mode         string   `json:"mode"`
	Records      []target `json:"records"`
	PreviewToken string   `json:"preview_token,omitempty"`
	Confirmation string   `json:"confirmation,omitempty"`
}

type backupDocument struct {
	Schema  string   `json:"schema"`
	Targets []target `json:"targets"`
}

type diffSummary struct {
	Current  int      `json:"current"`
	Proposed int      `json:"proposed"`
	Added    []string `json:"added"`
	Changed  []string `json:"changed"`
	Removed  []string `json:"removed"`
}

type runtime struct {
	stateDir   string
	targetDir  string
	runtimeDir string
	configTool string
}

func main() {
	if len(os.Args) < 2 {
		fail(errors.New("missing operation"))
	}
	rt, err := loadRuntime()
	if err != nil {
		fail(err)
	}
	var output any
	switch os.Args[1] {
	case "targets-get":
		requireArgs(2)
		records, err := rt.loadTargets()
		if err != nil {
			fail(err)
		}
		output = map[string]any{"ok": true, "name": "targets", "records": records}
	case "targets-preview":
		requireArgs(3)
		request, err := rt.readCollectionRequest(os.Args[2])
		if err != nil {
			fail(err)
		}
		current, err := rt.loadTargets()
		if err != nil {
			fail(err)
		}
		output = map[string]any{"ok": true, "validation": "pass", "changes": summarize(current, request.Records), "apply_requires_confirmation": "APPLY TARGETS"}
	case "targets-apply":
		requireArgs(3)
		request, err := rt.readCollectionRequest(os.Args[2])
		if err != nil {
			fail(err)
		}
		output, err = rt.applyTargets(request.Records, "collection")
		if err != nil {
			fail(err)
		}
	case "export-safe":
		requireArgs(2)
		records, err := rt.loadTargets()
		if err != nil {
			fail(err)
		}
		enc := json.NewEncoder(os.Stdout)
		enc.SetEscapeHTML(false)
		if err := enc.Encode(backupDocument{Schema: backupSchema, Targets: records}); err != nil {
			fail(err)
		}
		return
	case "import-preview":
		requireArgs(3)
		records, err := rt.readBackup(os.Args[2])
		if err != nil {
			fail(err)
		}
		current, err := rt.loadTargets()
		if err != nil {
			fail(err)
		}
		output = map[string]any{"ok": true, "validation": "pass", "schema": backupSchema, "changes": summarize(current, records), "apply_requires_confirmation": "IMPORT TARGETS"}
	case "import-apply":
		requireArgs(4)
		if err := rt.requireRuntimeFile(os.Args[3], "requests", 256<<10); err != nil {
			fail(err)
		}
		records, err := rt.readBackup(os.Args[2])
		if err != nil {
			fail(err)
		}
		output, err = rt.applyTargets(records, "import")
		if err != nil {
			fail(err)
		}
	default:
		fail(fmt.Errorf("unsupported operation: %s", os.Args[1]))
	}
	writeJSON(output)
}

func loadRuntime() (runtime, error) {
	state := envOr("MODULE_STATE_DIR", "/data/adb/ssh-drop-dispatcher")
	targetDir := envOr("SDD_WEBUI_TARGET_DIR", filepath.Join(state, "config", "targets.d"))
	runtimeDir := envOr("WEBUI_RUNTIME_DIR", "/data/local/tmp/ssh_drop_dispatcher-webui")
	tool := os.Getenv("SDD_WEBUI_V03_CONFIG_TOOL")
	return runtime{stateDir: state, targetDir: targetDir, runtimeDir: runtimeDir, configTool: tool}, nil
}

func envOr(key, fallback string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return fallback
}

func requireArgs(n int) {
	if len(os.Args) != n {
		fail(fmt.Errorf("invalid argument count for %s", os.Args[1]))
	}
}

func fail(err error) {
	fmt.Fprintf(os.Stderr, "v03-helper: %v\n", err)
	os.Exit(2)
}

func writeJSON(value any) {
	enc := json.NewEncoder(os.Stdout)
	enc.SetEscapeHTML(false)
	if err := enc.Encode(value); err != nil {
		fail(err)
	}
}

func (rt runtime) requireRuntimeFile(path, bucket string, max int64) error {
	abs, err := filepath.Abs(path)
	if err != nil {
		return err
	}
	root, err := filepath.Abs(filepath.Join(rt.runtimeDir, bucket))
	if err != nil {
		return err
	}
	rel, err := filepath.Rel(root, abs)
	if err != nil || rel == "." || strings.HasPrefix(rel, ".."+string(os.PathSeparator)) || rel == ".." {
		return errors.New("runtime file outside allowed bucket")
	}
	info, err := os.Lstat(abs)
	if err != nil {
		return err
	}
	if !info.Mode().IsRegular() || info.Mode()&os.ModeSymlink != 0 {
		return errors.New("runtime file must be regular and non-symlink")
	}
	if info.Size() < 1 || info.Size() > max {
		return errors.New("runtime file size out of range")
	}
	return nil
}

func (rt runtime) readCollectionRequest(path string) (collectionRequest, error) {
	var req collectionRequest
	if err := rt.requireRuntimeFile(path, "requests", 256<<10); err != nil {
		return req, err
	}
	if err := decodeStrictFile(path, &req); err != nil {
		return req, err
	}
	if req.Name != "targets" {
		return req, errors.New("collection name mismatch")
	}
	if req.Mode != "preview" && req.Mode != "apply" {
		return req, errors.New("invalid collection mode")
	}
	records, err := normalizeTargets(req.Records)
	if err != nil {
		return req, err
	}
	req.Records = records
	return req, nil
}

func (rt runtime) readBackup(path string) ([]target, error) {
	if err := rt.requireRuntimeFile(path, "uploads", 1<<20); err != nil {
		return nil, err
	}
	var doc backupDocument
	if err := decodeStrictFile(path, &doc); err != nil {
		return nil, err
	}
	if doc.Schema != backupSchema {
		return nil, errors.New("backup schema mismatch")
	}
	return normalizeTargets(doc.Targets)
}

func decodeStrictFile(path string, dst any) error {
	file, err := os.Open(path)
	if err != nil {
		return err
	}
	defer file.Close()
	dec := json.NewDecoder(file)
	dec.DisallowUnknownFields()
	if err := dec.Decode(dst); err != nil {
		return fmt.Errorf("invalid JSON: %w", err)
	}
	var extra any
	if err := dec.Decode(&extra); err != io.EOF {
		return errors.New("JSON must contain one value")
	}
	return nil
}

func normalizeTargets(records []target) ([]target, error) {
	if len(records) < 1 || len(records) > 16 {
		return nil, errors.New("target count must be 1..16")
	}
	seen := map[string]bool{}
	out := append([]target(nil), records...)
	for i := range out {
		if err := validateTarget(out[i]); err != nil {
			return nil, fmt.Errorf("target %d: %w", i+1, err)
		}
		if seen[out[i].Name] {
			return nil, fmt.Errorf("duplicate target %s", out[i].Name)
		}
		seen[out[i].Name] = true
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Name < out[j].Name })
	return out, nil
}

func validateTarget(t target) error {
	if !nameRE.MatchString(t.Name) {
		return errors.New("invalid name")
	}
	if !aliasesRE.MatchString(t.Aliases) {
		return errors.New("invalid aliases")
	}
	if !userRE.MatchString(t.SSHUser) {
		return errors.New("invalid ssh_user")
	}
	if !aliasRE.MatchString(t.SSHAlias) {
		return errors.New("invalid ssh_alias")
	}
	if t.SSHPort < 1 || t.SSHPort > 65535 {
		return errors.New("ssh_port must be 1..65535")
	}
	if !pathRE.MatchString(t.RemoteDrop) || filepath.Clean(t.RemoteDrop) != t.RemoteDrop {
		return errors.New("invalid remote_drop")
	}
	if !labelRE.MatchString(t.Platform) {
		return errors.New("invalid platform")
	}
	if t.Shell != "bash" && t.Shell != "sh" {
		return errors.New("shell must be bash or sh")
	}
	if t.SCPMode != "default" && t.SCPMode != "legacy" {
		return errors.New("scp_mode must be default or legacy")
	}
	if !labelRE.MatchString(t.Role) {
		return errors.New("invalid role")
	}
	return nil
}

func (rt runtime) loadTargets() ([]target, error) {
	info, err := os.Lstat(rt.targetDir)
	if err != nil {
		return nil, err
	}
	if !info.IsDir() || info.Mode()&os.ModeSymlink != 0 {
		return nil, errors.New("target directory must be non-symlink directory")
	}
	entries, err := os.ReadDir(rt.targetDir)
	if err != nil {
		return nil, err
	}
	records := make([]target, 0, len(entries))
	for _, entry := range entries {
		if entry.IsDir() || !strings.HasSuffix(entry.Name(), ".conf") {
			continue
		}
		path := filepath.Join(rt.targetDir, entry.Name())
		item, err := parseTargetFile(path)
		if err != nil {
			return nil, err
		}
		if strings.TrimSuffix(entry.Name(), ".conf") != item.Name {
			return nil, fmt.Errorf("target filename/name mismatch: %s", entry.Name())
		}
		records = append(records, item)
	}
	return normalizeTargets(records)
}

func parseTargetFile(path string) (target, error) {
	var out target
	info, err := os.Lstat(path)
	if err != nil {
		return out, err
	}
	if !info.Mode().IsRegular() || info.Mode()&os.ModeSymlink != 0 {
		return out, errors.New("target file must be regular")
	}
	file, err := os.Open(path)
	if err != nil {
		return out, err
	}
	defer file.Close()
	values := map[string]string{}
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		parts := strings.SplitN(line, "=", 2)
		if len(parts) != 2 {
			return out, fmt.Errorf("invalid target line in %s", filepath.Base(path))
		}
		key := strings.TrimSpace(parts[0])
		value, err := shellScalar(strings.TrimSpace(parts[1]))
		if err != nil {
			return out, err
		}
		switch key {
		case "target_name", "enabled", "aliases", "ssh_user", "ssh_host", "host", "ssh_port", "remote_drop", "platform", "shell", "scp_flags", "role", "critical_role", "allow_fallback":
		case "verify", "verify_cmd", "verify_kind", "shell_kind":
			return out, fmt.Errorf("forbidden legacy verification key %s", key)
		default:
			return out, fmt.Errorf("unsupported target key %s", key)
		}
		values[key] = value
	}
	if err := scanner.Err(); err != nil {
		return out, err
	}
	out.Name = values["target_name"]
	switch values["enabled"] {
	case "", "1":
		out.Enabled = true
	case "0":
		out.Enabled = false
	default:
		return out, errors.New("enabled must be 0 or 1")
	}
	out.Aliases = values["aliases"]
	if out.Aliases == "" {
		out.Aliases = out.Name
	}
	out.SSHUser = values["ssh_user"]
	out.SSHAlias = values["ssh_host"]
	if out.SSHAlias == "" {
		out.SSHAlias = values["host"]
	}
	out.SSHPort = 22
	if values["ssh_port"] != "" {
		port, err := strconv.Atoi(values["ssh_port"])
		if err != nil {
			return out, errors.New("ssh_port must be numeric")
		}
		out.SSHPort = port
	}
	if values["allow_fallback"] != "" && values["allow_fallback"] != "0" {
		return out, errors.New("allow_fallback must remain 0")
	}
	out.RemoteDrop = values["remote_drop"]
	out.Platform = values["platform"]
	out.Shell = values["shell"]
	switch values["scp_flags"] {
	case "":
		out.SCPMode = "default"
	case "-O":
		out.SCPMode = "legacy"
	default:
		return out, errors.New("unsupported scp_flags; only -O is allowed")
	}
	out.Role = values["critical_role"]
	if out.Role == "" {
		out.Role = values["role"]
	}
	if err := validateTarget(out); err != nil {
		return out, fmt.Errorf("%s: %w", filepath.Base(path), err)
	}
	return out, nil
}

func shellScalar(value string) (string, error) {
	if value == "" {
		return "", nil
	}
	if strings.HasPrefix(value, `"`) {
		parsed, err := strconv.Unquote(value)
		if err != nil {
			return "", errors.New("invalid quoted value")
		}
		return parsed, nil
	}
	if strings.HasPrefix(value, "'") {
		if len(value) < 2 || !strings.HasSuffix(value, "'") || strings.Contains(value[1:len(value)-1], "'") {
			return "", errors.New("invalid single-quoted value")
		}
		return value[1 : len(value)-1], nil
	}
	if strings.ContainsAny(value, " \t\r\n\"'\\;$`&|<>(){}[]*?!") {
		return "", errors.New("unsafe unquoted value")
	}
	return value, nil
}

func summarize(current, proposed []target) diffSummary {
	a := map[string]target{}
	b := map[string]target{}
	for _, item := range current {
		a[item.Name] = item
	}
	for _, item := range proposed {
		b[item.Name] = item
	}
	result := diffSummary{Current: len(current), Proposed: len(proposed), Added: []string{}, Changed: []string{}, Removed: []string{}}
	for name, item := range b {
		old, ok := a[name]
		if !ok {
			result.Added = append(result.Added, name)
			continue
		}
		if old != item {
			result.Changed = append(result.Changed, name)
		}
	}
	for name := range a {
		if _, ok := b[name]; !ok {
			result.Removed = append(result.Removed, name)
		}
	}
	sort.Strings(result.Added)
	sort.Strings(result.Changed)
	sort.Strings(result.Removed)
	return result
}

func (rt runtime) applyTargets(records []target, source string) (map[string]any, error) {
	proposed, err := normalizeTargets(records)
	if err != nil {
		return nil, err
	}
	current, err := rt.loadTargets()
	if err != nil {
		return nil, err
	}
	diff := summarize(current, proposed)
	backup, err := rt.backupTargets()
	if err != nil {
		return nil, err
	}

	parent := filepath.Dir(rt.targetDir)
	next := filepath.Join(parent, fmt.Sprintf("targets.d.webui.new.%d", os.Getpid()))
	previous := filepath.Join(parent, fmt.Sprintf("targets.d.webui.previous.%d", os.Getpid()))
	_ = os.RemoveAll(next)
	_ = os.RemoveAll(previous)
	if err := os.Mkdir(next, 0700); err != nil {
		return nil, err
	}
	cleanupNext := true
	defer func() {
		if cleanupNext {
			_ = os.RemoveAll(next)
		}
	}()
	for _, item := range proposed {
		if err := writeTarget(filepath.Join(next, item.Name+".conf"), item); err != nil {
			return nil, err
		}
	}
	if err := os.Rename(rt.targetDir, previous); err != nil {
		return nil, err
	}
	if err := os.Rename(next, rt.targetDir); err != nil {
		_ = os.Rename(previous, rt.targetDir)
		return nil, err
	}
	cleanupNext = false
	rollback := func() {
		broken := filepath.Join(parent, fmt.Sprintf("targets.d.webui.failed.%d", os.Getpid()))
		_ = os.Rename(rt.targetDir, broken)
		_ = os.Rename(previous, rt.targetDir)
		_ = os.RemoveAll(broken)
	}
	if err := rt.lint(); err != nil {
		rollback()
		return nil, fmt.Errorf("post-apply lint failed; rollback restored previous targets: %w", err)
	}
	if err := os.RemoveAll(previous); err != nil {
		return nil, err
	}
	return map[string]any{"ok": true, "source": source, "backup": backup, "verify_state": "pass", "rollback_available": true, "changes": diff}, nil
}

func (rt runtime) backupTargets() (string, error) {
	stamp := time.Now().UTC().Format("20060102T150405.000000000Z")
	dir := filepath.Join(rt.stateDir, "backups", "webui-targets-"+stamp)
	if err := os.MkdirAll(dir, 0700); err != nil {
		return "", err
	}
	entries, err := os.ReadDir(rt.targetDir)
	if err != nil {
		return "", err
	}
	for _, entry := range entries {
		if entry.IsDir() || !strings.HasSuffix(entry.Name(), ".conf") {
			continue
		}
		data, err := os.ReadFile(filepath.Join(rt.targetDir, entry.Name()))
		if err != nil {
			return "", err
		}
		if err := os.WriteFile(filepath.Join(dir, entry.Name()), data, 0600); err != nil {
			return "", err
		}
	}
	return dir, nil
}

func writeTarget(path string, item target) error {
	enabled := "0"
	if item.Enabled {
		enabled = "1"
	}
	scp := ""
	if item.SCPMode == "legacy" {
		scp = "-O"
	}
	content := strings.Join([]string{
		`target_name="` + item.Name + `"`,
		`enabled="` + enabled + `"`,
		`aliases="` + item.Aliases + `"`,
		`ssh_user="` + item.SSHUser + `"`,
		`ssh_host="` + item.SSHAlias + `"`,
		`host="` + item.SSHAlias + `"`,
		`ssh_port="` + strconv.Itoa(item.SSHPort) + `"`,
		`remote_drop="` + item.RemoteDrop + `"`,
		`platform="` + item.Platform + `"`,
		`shell="` + item.Shell + `"`,
		`scp_flags="` + scp + `"`,
		`critical_role="` + item.Role + `"`,
		`role="` + item.Role + `"`,
		`allow_fallback="0"`,
		"",
	}, "\n")
	return os.WriteFile(path, []byte(content), 0600)
}

func (rt runtime) lint() error {
	if rt.configTool == "" {
		return errors.New("config lint tool is not configured")
	}
	info, err := os.Stat(rt.configTool)
	if err != nil || info.Mode()&0111 == 0 {
		return errors.New("config lint tool is not executable")
	}
	cmd := exec.Command(rt.configTool, "lint")
	cmd.Env = append(os.Environ(), "PIDD_STATE_DIR="+rt.stateDir)
	output, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("%s: %w", strings.TrimSpace(string(output)), err)
	}
	if !strings.Contains(string(output), "lint=ok") {
		return errors.New("config lint did not report lint=ok")
	}
	return nil
}
