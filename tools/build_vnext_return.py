#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / "source" / "magisk"
RC4 = ROOT / "source" / "rc4-webui"
RC5 = ROOT / "source" / "rc5-webui"
RC6 = ROOT / "source" / "rc6-webui"
RETURN = ROOT / "source" / "vnext-return"

VERSION = "4.14.0-return-rc1"
VERSION_CODE = "4140001"
TEMPLATE_COMMIT = "73371fec0b5517df2d83d9796e1c79abe4484e6d"
CORE_VERSION = "0.4.0"
BASE_URL = f"https://raw.githubusercontent.com/Lycidias93/android-root-module-webui-template/{TEMPLATE_COMMIT}"

CORE_FILES = {
    "module/webroot/index.html": "3a7d9de60cfa6dd23b85e5b6fe24e5ffa5643b7a",
    "module/webroot/app.js": "0fea0f39198cb2a6f854c78dd9a2f2de42ad1113",
    "module/webroot/app.css": "c610adaba1a0a839ac705e24549fd65d05de18af",
    "module/webroot/race-guard.js": "7fb96452e663acdcc67ec7b0b1cea64db4985063",
    "module/webroot/race-guard.css": "ba9d473ee2873ffc583785115573c78917df285c",
    "module/webroot/v03.js": "d6dfe510959e4dd7968134e81148302765cf90c7",
    "module/webroot/v04.js": "df659077332cc47632ef9d347d6ff02565f29ded",
    "server/cmd/webui-server/main.go": "8f6f11c7c3239482d7c402773a5872e32a16badf",
    "server/cmd/webui-server/v03.go": "8b5a824b95e44f8142c510b01177f91468fc63e5",
    "server/cmd/webui-server/v03_collection_digest.go": "022670c34a3f1aad25e64d41eb09b6b730d4f731",
    "server/cmd/webui-server/v04.go": "b2bd85b7b3a5d8d07bd60f7624c4df9271fd83c1",
}

BASE_PINS = {
    "service.sh": "c19b1dfb315cf53e4db9d43fe069d3d56d8f6337",
    "tools/sdd.sh": "a3334d1f30ea354ba27077588e1db9a278c40000",
    "tools/sdd-machine.sh": "879f09b8c3c10a39222e5c3afb5d6ae360e84f1f",
    "tools/sdd-workflow.sh": "e64fc6b4d151b7e0b51ba78fb05e395b605531ba",
}


def git_blob_sha(data: bytes) -> str:
    return hashlib.sha1(f"blob {len(data)}\0".encode() + data).hexdigest()


def verify_blob(path: Path, expected: str) -> None:
    actual = git_blob_sha(path.read_bytes())
    if actual != expected:
        raise RuntimeError(f"blob_mismatch path={path} expected={expected} actual={actual}")


def fetch_core(work: Path) -> dict[str, Path]:
    fetched: dict[str, Path] = {}
    for rel, expected in CORE_FILES.items():
        dest = work / "core" / rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        with urllib.request.urlopen(f"{BASE_URL}/{rel}", timeout=30) as response:
            data = response.read()
        actual = git_blob_sha(data)
        if actual != expected:
            raise RuntimeError(f"core_blob_mismatch path={rel} expected={expected} actual={actual}")
        dest.write_bytes(data)
        fetched[rel] = dest
    return fetched


def run(cmd: list[str], *, cwd: Path | None = None, env: dict[str, str] | None = None, capture: bool = False) -> subprocess.CompletedProcess[str]:
    print("+", " ".join(cmd))
    return subprocess.run(cmd, cwd=cwd, env=env, check=True, text=True, capture_output=capture)


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"patch_anchor_mismatch label={label} count={count}")
    return text.replace(old, new, 1)


def patch_support_tool(stage: Path) -> None:
    path = stage / "tools" / "dispatch-config.sh"
    text = path.read_text()
    old = "VERSION=4.12.6"
    new = "VERSION=$(sed -n 's/^version=//p' \"$MODDIR/module.prop\" 2>/dev/null | head -n 1)\n[ -n \"$VERSION\" ] || VERSION=unknown"
    path.write_text(replace_once(text, old, new, "dispatch_config_version"))


def patch_webroot(webroot: Path) -> None:
    shutil.copy2(RETURN.parent / "rc6-webui" / "webroot" / "sdd-ui.js", webroot / "sdd-ui.js")
    shutil.copy2(RC4 / "webroot" / "sdd-ui.css", webroot / "sdd-ui.css")
    index = webroot / "index.html"
    html = index.read_text()
    css_anchor = '  <link rel="stylesheet" href="app.css">'
    html = replace_once(html, css_anchor, css_anchor + '\n  <link rel="stylesheet" href="sdd-ui.css">', "webui_css")
    status_anchor = '      <div id="statusCards" class="cards"></div>'
    target_block = '''      <div id="statusCards" class="cards"></div>
      <section class="sdd-target-block" aria-labelledby="sddTargetsTitle">
        <div class="panel-heading">
          <div><h2 id="sddTargetsTitle">Target Matrix</h2><p>Secret-safe configured targets. Readiness tests run only on demand.</p></div>
          <button id="sddTargetRefresh" type="button">Refresh targets</button>
        </div>
        <div id="sddTargetCards" class="sdd-target-cards"></div>
      </section>'''
    html = replace_once(html, status_anchor, target_block, "webui_target_matrix")
    script_anchor = '  <script src="app.js"></script>'
    html = replace_once(html, script_anchor, script_anchor + '\n  <script src="sdd-ui.js"></script>', "webui_sdd_script")
    index.write_text(html)


def patch_service(stage: Path) -> None:
    path = stage / "service.sh"
    text = path.read_text()
    fragment = (RETURN / "service-binding.inc.sh").read_text().rstrip() + "\n\n"
    text = replace_once(text, "already_done(){", fragment + "already_done(){", "service_binding_functions")
    old = '    record_done "$rec" "$t"\n    clear_inflight "$rec" "$t"'
    new = '    record_done "$rec" "$t"\n    record_delivery_binding "$rec" "$t" "$f" || log "WARN return_binding write_failed file=$base target=$t delivery_state=unchanged"\n    clear_inflight "$rec" "$t"'
    text = replace_once(text, old, new, "service_binding_call")
    path.write_text(text)


def patch_sdd_cli(stage: Path) -> None:
    path = stage / "tools" / "sdd.sh"
    text = path.read_text()
    usage_old = '  bridge-status, help\nEOF_USAGE'
    usage_new = '  bridge-status, return capability|request|status|probe|collect|wait|trace, help\nEOF_USAGE'
    text = replace_once(text, usage_old, usage_new, "sdd_usage_return")
    anchor = 'cmd=${1:-help}; [ "$#" -gt 0 ] && shift || true\nfor arg in "$@"; do'
    injection = '''cmd=${1:-help}; [ "$#" -gt 0 ] && shift || true
if [ "$cmd" = return ]; then
  return_tool="$STATE_DIR/tools/sdd-return.sh"
  [ -x "$return_tool" ] || return_tool="$MODDIR/tools/sdd-return.sh"
  [ -x "$return_tool" ] || { echo "sdd_cli=FAIL reason=return_tool_missing" >&2; echo "RESULT: SDD_CLI_DONE command=return outcome=unavailable exit_code=69" >&2; exit 69; }
  SDD_FORMAT="$FORMAT" "$return_tool" "$@"
  exit $?
fi
for arg in "$@"; do'''
    text = replace_once(text, anchor, injection, "sdd_return_dispatch")
    path.write_text(text)


def patch_machine_capabilities(stage: Path) -> None:
    path = stage / "tools" / "sdd-machine.sh"
    text = path.read_text()
    old_commands = "commands='version capabilities status targets target-test dispatch delivery-status delivery-wait delivery-trace delivery-preflight trace inspect queue failures quarantine preflight dispatch-file incident requeue logs doctor chatgpt-context snapshot explain config install-termux bridge-status'"
    new_commands = "commands='version capabilities status targets target-test dispatch delivery-status delivery-wait delivery-trace delivery-preflight trace inspect queue failures quarantine preflight dispatch-file incident requeue logs doctor chatgpt-context snapshot explain config install-termux bridge-status return'"
    text = replace_once(text, old_commands, new_commands, "machine_return_command")
    old_json = "printf ',\"verifyOwnership\":{\"dispatcher\":true,\"remoteShaRequired\":true,\"bashFallback\":\"fail_closed\",\"pythonDelivery\":\"unsupported\"},\"commands\":'"
    new_json = "printf ',\"verifyOwnership\":{\"dispatcher\":true,\"remoteShaRequired\":true,\"bashFallback\":\"fail_closed\",\"pythonDelivery\":\"unsupported\"},\"returnChannel\":{\"bindingSchema\":1,\"requestSchema\":1,\"receiptSchema\":1,\"acceptanceSchema\":1,\"pullBased\":true,\"autoExecution\":false},\"commands\":'"
    text = replace_once(text, old_json, new_json, "machine_return_json")
    old_env = '    echo "bash_missing_fallback=fail_closed"; echo "python_delivery=unsupported"; echo "commands=$commands"'
    new_env = '    echo "bash_missing_fallback=fail_closed"; echo "python_delivery=unsupported"; echo "return_binding_schema=1"; echo "return_request_schema=1"; echo "return_receipt_schema=1"; echo "return_acceptance_schema=1"; echo "return_pull_based=yes"; echo "return_auto_execution=no"; echo "commands=$commands"'
    text = replace_once(text, old_env, new_env, "machine_return_env")
    path.write_text(text)


def patch_webui_base(stage: Path) -> None:
    path = stage / "bin" / "module-control-base"
    text = path.read_text()
    old = "  printf '{\\\"name\\\":\\\"receipts\\\",\\\"label\\\":\\\"Delivery receipts\\\",\\\"description\\\":\\\"Recent RC3 workflow delivery receipts.\\\"}'"
    if old not in text:
        old = "  printf '{\"name\":\"receipts\",\"label\":\"Delivery receipts\",\"description\":\"Recent RC3 workflow delivery receipts.\"}'"
    new = "  printf '{\"name\":\"returns\",\"label\":\"Returns\",\"description\":\"Secret-safe Return Channel state and correlation metadata.\"},'\n" + old
    text = replace_once(text, old, new, "webui_returns_inventory")
    path.write_text(text)


def stage_module(work: Path, fetched: dict[str, Path]) -> Path:
    stage = work / "stage"
    shutil.copytree(BASE, stage)
    for rel, expected in BASE_PINS.items():
        verify_blob(stage / rel, expected)

    shutil.copy2(RETURN / "module.prop", stage / "module.prop")
    shutil.copy2(RC4 / "customize.sh", stage / "customize.sh")
    shutil.copy2(RC4 / "action.sh", stage / "action.sh")
    patch_support_tool(stage)
    patch_service(stage)
    patch_sdd_cli(stage)
    patch_machine_capabilities(stage)

    webroot = stage / "webroot"
    if webroot.exists():
        shutil.rmtree(webroot)
    webroot.mkdir(parents=True)
    for name in ("index.html", "app.js", "app.css", "race-guard.js", "race-guard.css", "v03.js", "v04.js"):
        shutil.copy2(fetched[f"module/webroot/{name}"], webroot / name)
    patch_webroot(webroot)

    bindir = stage / "bin"
    bindir.mkdir(parents=True, exist_ok=True)
    shutil.copy2(RETURN / "module-control", bindir / "module-control")
    shutil.copy2(RC5 / "module-control", bindir / "module-control-v03")
    shutil.copy2(RC6 / "module-control-fast-wrapper.sh", bindir / "module-control-rc4")
    shutil.copy2(RC6 / "module-control-base", bindir / "module-control-base")
    patch_webui_base(stage)

    tools = stage / "tools"
    shutil.copy2(RETURN / "sdd-return.sh", tools / "sdd-return.sh")

    server_dir = work / "server"
    server_dir.mkdir()
    for name in ("main.go", "v03.go", "v03_collection_digest.go", "v04.go"):
        shutil.copy2(fetched[f"server/cmd/webui-server/{name}"], server_dir / name)

    env = os.environ.copy()
    env.update({"CGO_ENABLED": "0", "GOOS": "android", "GOARCH": "arm64"})
    server = bindir / "webui-server-arm64"
    run(["go", "build", "-buildvcs=false", "-trimpath", "-ldflags", f"-s -w -X main.version={CORE_VERSION}", "-o", str(server), "main.go", "v03.go", "v03_collection_digest.go", "v04.go"], cwd=server_dir, env=env)
    helper = bindir / "sdd-webui-v03-helper-arm64"
    run(["go", "build", "-buildvcs=false", "-trimpath", "-ldflags", "-s -w", "-o", str(helper), str(RC5 / "v03-helper.go")], cwd=ROOT, env=env)
    return_helper = bindir / "sdd-return-helper-arm64"
    run(["go", "build", "-buildvcs=false", "-trimpath", "-ldflags", "-s -w", "-o", str(return_helper), str(RETURN / "sdd-return-helper.go")], cwd=ROOT, env=env)

    for path in (
        stage / "action.sh", stage / "customize.sh", stage / "service.sh",
        bindir / "module-control", bindir / "module-control-v03", bindir / "module-control-rc4", bindir / "module-control-base",
        server, helper, return_helper, tools / "sdd-return.sh", tools / "sdd.sh",
    ):
        path.chmod(0o755)
    return stage


def verify_stage(stage: Path, work: Path) -> None:
    required = [
        "module.prop", "service.sh", "tools/sdd.sh", "tools/sdd-return.sh", "tools/sdd-machine.sh",
        "bin/module-control", "bin/module-control-v03", "bin/module-control-rc4", "bin/module-control-base",
        "bin/webui-server-arm64", "bin/sdd-webui-v03-helper-arm64", "bin/sdd-return-helper-arm64",
        "webroot/index.html", "webroot/app.js", "webroot/app.css", "webroot/race-guard.js", "webroot/race-guard.css", "webroot/v03.js", "webroot/v04.js", "webroot/sdd-ui.js", "webroot/sdd-ui.css",
    ]
    for rel in required:
        path = stage / rel
        if not path.is_file() or path.stat().st_size == 0:
            raise RuntimeError(f"stage_file_missing:{rel}")

    prop = (stage / "module.prop").read_text()
    if f"version={VERSION}" not in prop or f"versionCode={VERSION_CODE}" not in prop:
        raise RuntimeError("candidate_metadata_missing")
    service = (stage / "service.sh").read_text()
    for marker in ("SDD_DELIVERY_BINDING_V1", "record_delivery_binding", 'delivery_state=unchanged'):
        if marker not in service:
            raise RuntimeError(f"delivery_binding_marker_missing:{marker}")
    if service.count('record_delivery_binding "$rec" "$t" "$f"') != 1:
        raise RuntimeError("delivery_binding_hook_count_invalid")
    sdd = (stage / "tools" / "sdd.sh").read_text()
    if 'if [ "$cmd" = return ]' not in sdd or 'SDD_FORMAT="$FORMAT" "$return_tool" "$@"' not in sdd:
        raise RuntimeError("return_cli_dispatch_missing")
    machine = (stage / "tools" / "sdd-machine.sh").read_text()
    for marker in ("return_binding_schema=1", '"returnChannel"', "return_auto_execution=no"):
        if marker not in machine:
            raise RuntimeError(f"return_capability_marker_missing:{marker}")
    base = (stage / "bin" / "module-control-base").read_text()
    if '"name":"returns"' not in base:
        raise RuntimeError("returns_inventory_not_declared")
    wrapper = (stage / "bin" / "module-control").read_text()
    for marker in ("root-module-webui.extensions.v2", "return-collect", "inventory_operations", "job-run-file"):
        if marker not in wrapper:
            raise RuntimeError(f"return_webui_adapter_marker_missing:{marker}")
    index = (stage / "webroot" / "index.html").read_text()
    if "/v04.js" not in index or "race-guard.js" not in index or "sdd-ui.js" not in index:
        raise RuntimeError("webui_v04_assets_missing")
    v04 = (stage / "webroot" / "v04.js").read_text()
    if "document.hidden" not in v04 or "/api/v1/v04/inventory-operation" not in v04:
        raise RuntimeError("webui_v04_contract_missing")
    for source in ((stage / "webroot" / "app.js").read_text(), v04, (stage / "webroot" / "sdd-ui.js").read_text()):
        for forbidden in ("window.ksu", "window.apatch", "eval(", "new Function"):
            if forbidden in source:
                raise RuntimeError(f"unsafe_webui_pattern:{forbidden}")

    for rel in ("action.sh", "customize.sh", "service.sh", "tools/sdd.sh", "tools/sdd-return.sh", "tools/sdd-machine.sh", "bin/module-control", "bin/module-control-v03", "bin/module-control-rc4", "bin/module-control-base"):
        run(["sh", "-n", str(stage / rel)])
    for rel in ("bin/webui-server-arm64", "bin/sdd-webui-v03-helper-arm64", "bin/sdd-return-helper-arm64"):
        if (stage / rel).read_bytes()[:4] != b"\x7fELF":
            raise RuntimeError(f"not_elf:{rel}")

    native = work / "sdd-return-helper-native"
    native_env = os.environ.copy()
    native_env.pop("GOOS", None); native_env.pop("GOARCH", None); native_env["CGO_ENABLED"] = "0"
    run(["go", "build", "-buildvcs=false", "-trimpath", "-o", str(native), str(RETURN / "sdd-return-helper.go")], cwd=ROOT, env=native_env)

    fixture_state = work / "fixture-state"
    (fixture_state / "config" / "targets.d").mkdir(parents=True)
    (fixture_state / "config" / "returns.d").mkdir(parents=True)
    (fixture_state / "ssh").mkdir(parents=True)
    (fixture_state / "config.env").write_text("DROP_DISPATCH_SCAN_DIR=/tmp/sdd-fixture-scan\n")
    (fixture_state / "config" / "targets.d" / "alpha.conf").write_text('target_name="alpha"\nenabled="1"\nssh_host="alpha"\nremote_drop="/tmp/drop"\nplatform="linux"\nshell="bash"\nscp_flags=""\nrole="fixture"\n')
    (fixture_state / "config" / "returns.d" / "alpha.conf").write_text('return_enabled="1"\nremote_outbox="/tmp/sdd-return-outbox"\n')
    binding_dir = fixture_state / "delivery-bindings" / "SDD-0123456789abcdef"
    binding_dir.mkdir(parents=True)
    binding_dir.joinpath("alpha.json").write_text(json.dumps({"schema":"SDD_DELIVERY_BINDING_V1","deliveryId":"SDD-0123456789abcdef","artifactSha256":"a"*64,"target":"alpha","completedEpoch":1700000000,"remoteShaVerified":True}, separators=(",", ":")) + "\n")
    env = os.environ.copy()
    env.update({"SDD_STATE_DIR": str(fixture_state), "SDD_FORMAT": "json"})
    created = json.loads(run([str(native), "request", "SDD-0123456789abcdef", "--target", "alpha", "--type", "example.result.v1"], env=env, capture=True).stdout)
    if created.get("state") != "pending" or not created.get("returnId", "").startswith("SDR-"):
        raise RuntimeError("return_request_fixture_failed")
    inventory = json.loads(run([str(native), "inventory"], env=env, capture=True).stdout)
    if not inventory.get("items") or inventory["items"][0].get("state") != "pending":
        raise RuntimeError("return_inventory_fixture_failed")
    retention = json.loads(run([str(native), "cleanup-preview"], env=env, capture=True).stdout)
    if retention.get("automaticDeletion") is not False or retention.get("applySupported") is not False:
        raise RuntimeError("return_retention_safety_fixture_failed")


def build(output: Path) -> None:
    if shutil.which("go") is None:
        raise RuntimeError("go_missing")
    with tempfile.TemporaryDirectory(prefix="sdd-vnext-return-") as tmp:
        work = Path(tmp)
        fetched = fetch_core(work)
        stage = stage_module(work, fetched)
        verify_stage(stage, work)
        first = work / "first.zip"
        second = work / "second.zip"
        run([sys.executable, str(ROOT / "tools" / "build_magisk_zip.py"), str(stage), str(first)])
        run([sys.executable, str(ROOT / "tools" / "build_magisk_zip.py"), str(stage), str(second)])
        if first.read_bytes() != second.read_bytes():
            raise RuntimeError("package_not_reproducible")
        output.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(first, output)
        digest = hashlib.sha256(output.read_bytes()).hexdigest()
        print(f"candidate_version={VERSION}")
        print(f"candidate_versionCode={VERSION_CODE}")
        print(f"webui_core_version={CORE_VERSION}")
        print(f"webui_core_commit={TEMPLATE_COMMIT}")
        print(f"stable_service_blob={BASE_PINS['service.sh']}")
        print("delivery_core_changed=yes_additive_return_binding_only")
        print("host_autoexecution_added=no")
        print("arbitrary_remote_command_added=no")
        print(f"artifact={output}")
        print(f"artifact_bytes={output.stat().st_size}")
        print(f"artifact_sha256={digest}")
        print("RESULT: SDD_VNEXT_RETURN_RC1_BUILD_DONE outcome=success workflow_exit_code=0")


def main() -> int:
    parser = argparse.ArgumentParser(description="Build SSH Drop Dispatcher v4.14.0 Return Channel RC1 candidate")
    parser.add_argument("--output", type=Path, default=ROOT / "dist" / "ssh-drop-dispatcher-magisk-v4.14.0-return-rc1.zip")
    args = parser.parse_args()
    try:
        build(args.output.resolve())
    except Exception as exc:
        print(f"RESULT: SDD_VNEXT_RETURN_RC1_BUILD_DONE outcome=fail reason={exc} workflow_exit_code=1", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
