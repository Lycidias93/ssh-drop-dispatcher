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
RC4_OVERLAY = ROOT / "source" / "rc4-webui"
RC5_OVERLAY = ROOT / "source" / "rc5-webui"
RC6_OVERLAY = ROOT / "source" / "rc6-webui"
TEMPLATE_COMMIT = "81678604122636ad87a0f6d48eac1262a67154a4"
CORE_VERSION = "0.3.0"
BASE_URL = f"https://raw.githubusercontent.com/Lycidias93/android-root-module-webui-template/{TEMPLATE_COMMIT}"

CORE_FILES = {
    "module/webroot/index.html": "5c5aea33780553da585d4d5b678a566fac5607c2",
    "module/webroot/app.js": "0fea0f39198cb2a6f854c78dd9a2f2de42ad1113",
    "module/webroot/app.css": "c610adaba1a0a839ac705e24549fd65d05de18af",
    "module/webroot/v03.js": "d6dfe510959e4dd7968134e81148302765cf90c7",
    "server/cmd/webui-server/main.go": "c12495e4acae7fade4b79017dd138dd320878718",
    "server/cmd/webui-server/v03.go": "8b5a824b95e44f8142c510b01177f91468fc63e5",
    "server/cmd/webui-server/v03_collection_digest.go": "022670c34a3f1aad25e64d41eb09b6b730d4f731",
}

BASE_PINS = {
    "service.sh": "c19b1dfb315cf53e4db9d43fe069d3d56d8f6337",
    "tools/sdd.sh": "a3334d1f30ea354ba27077588e1db9a278c40000",
    "tools/sdd-machine.sh": "879f09b8c3c10a39222e5c3afb5d6ae360e84f1f",
    "tools/sdd-workflow.sh": "e64fc6b4d151b7e0b51ba78fb05e395b605531ba",
}


def git_blob_sha(data: bytes) -> str:
    prefix = f"blob {len(data)}\0".encode()
    return hashlib.sha1(prefix + data).hexdigest()


def verify_blob(path: Path, expected: str) -> None:
    data = path.read_bytes()
    actual = git_blob_sha(data)
    if actual != expected:
        raise RuntimeError(f"blob_mismatch path={path} expected={expected} actual={actual}")


def fetch_core(work: Path) -> dict[str, Path]:
    fetched: dict[str, Path] = {}
    for rel, expected in CORE_FILES.items():
        url = f"{BASE_URL}/{rel}"
        dest = work / "core" / rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        with urllib.request.urlopen(url, timeout=30) as response:
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


def patch_webroot(webroot: Path) -> None:
    shutil.copy2(RC6_OVERLAY / "webroot" / "sdd-ui.js", webroot / "sdd-ui.js")
    shutil.copy2(RC4_OVERLAY / "webroot" / "sdd-ui.css", webroot / "sdd-ui.css")

    index = webroot / "index.html"
    html = index.read_text()

    css_anchor = '  <link rel="stylesheet" href="app.css">'
    if html.count(css_anchor) != 1:
        raise RuntimeError("webui_css_anchor_mismatch")
    html = html.replace(css_anchor, css_anchor + '\n  <link rel="stylesheet" href="sdd-ui.css">', 1)

    status_anchor = '      <div id="statusCards" class="cards"></div>'
    target_block = '''      <div id="statusCards" class="cards"></div>
      <section class="sdd-target-block" aria-labelledby="sddTargetsTitle">
        <div class="panel-heading">
          <div><h2 id="sddTargetsTitle">Target Matrix</h2><p>Secret-safe configured targets. Readiness tests run only on demand.</p></div>
          <button id="sddTargetRefresh" type="button">Refresh targets</button>
        </div>
        <div id="sddTargetCards" class="sdd-target-cards"></div>
      </section>'''
    if html.count(status_anchor) != 1:
        raise RuntimeError("webui_status_anchor_mismatch")
    html = html.replace(status_anchor, target_block, 1)

    script_anchor = '  <script src="app.js"></script>'
    if html.count(script_anchor) != 1 or html.count('  <script src="/v03.js"></script>') != 1:
        raise RuntimeError("webui_script_anchor_mismatch")
    html = html.replace(script_anchor, script_anchor + '\n  <script src="sdd-ui.js"></script>', 1)
    index.write_text(html)


def patch_support_tool(stage: Path) -> None:
    path = stage / "tools" / "dispatch-config.sh"
    text = path.read_text()
    old = "VERSION=4.12.6"
    new = "VERSION=$(sed -n 's/^version=//p' \"$MODDIR/module.prop\" 2>/dev/null | head -n 1)\n[ -n \"$VERSION\" ] || VERSION=unknown"
    if text.count(old) != 1:
        raise RuntimeError("dispatch_config_version_anchor_mismatch")
    path.write_text(text.replace(old, new, 1))


def stage_module(work: Path, fetched: dict[str, Path]) -> Path:
    stage = work / "stage"
    shutil.copytree(BASE, stage)

    for rel, expected in BASE_PINS.items():
        verify_blob(stage / rel, expected)

    patch_support_tool(stage)
    shutil.copy2(RC6_OVERLAY / "module.prop", stage / "module.prop")
    shutil.copy2(RC4_OVERLAY / "customize.sh", stage / "customize.sh")
    shutil.copy2(RC4_OVERLAY / "action.sh", stage / "action.sh")

    webroot = stage / "webroot"
    if webroot.exists():
        shutil.rmtree(webroot)
    webroot.mkdir(parents=True)
    for name in ("index.html", "app.js", "app.css", "v03.js"):
        shutil.copy2(fetched[f"module/webroot/{name}"], webroot / name)
    patch_webroot(webroot)

    bindir = stage / "bin"
    bindir.mkdir(parents=True, exist_ok=True)
    # Keep the runtime-proven RC5 v0.3 typed wrapper/helper and replace only the
    # module-specific base/status composition for the RC6 UX follow-up.
    shutil.copy2(RC6_OVERLAY / "module-control-base", bindir / "module-control-base")
    shutil.copy2(RC6_OVERLAY / "module-control-fast-wrapper.sh", bindir / "module-control-rc4")
    shutil.copy2(RC5_OVERLAY / "module-control", bindir / "module-control")

    server_dir = work / "server"
    server_dir.mkdir()
    for name in ("main.go", "v03.go", "v03_collection_digest.go"):
        shutil.copy2(fetched[f"server/cmd/webui-server/{name}"], server_dir / name)
    output = bindir / "webui-server-arm64"
    env = os.environ.copy()
    env.update({"CGO_ENABLED": "0", "GOOS": "android", "GOARCH": "arm64"})
    run([
        "go", "build", "-buildvcs=false", "-trimpath",
        "-ldflags", f"-s -w -X main.version={CORE_VERSION}",
        "-o", str(output), "main.go", "v03.go", "v03_collection_digest.go",
    ], cwd=server_dir, env=env)

    helper = bindir / "sdd-webui-v03-helper-arm64"
    run([
        "go", "build", "-buildvcs=false", "-trimpath", "-ldflags", "-s -w",
        "-o", str(helper), str(RC5_OVERLAY / "v03-helper.go"),
    ], cwd=ROOT, env=env)

    for path in (
        stage / "action.sh", stage / "customize.sh", stage / "service.sh",
        stage / "tools" / "dispatch-config.sh",
        bindir / "module-control", bindir / "module-control-rc4",
        bindir / "module-control-base", output, helper,
    ):
        path.chmod(0o755)

    return stage


def verify_stage(stage: Path, work: Path) -> None:
    required = [
        "module.prop", "customize.sh", "action.sh", "service.sh",
        "bin/module-control", "bin/module-control-rc4", "bin/module-control-base",
        "bin/webui-server-arm64", "bin/sdd-webui-v03-helper-arm64",
        "webroot/index.html", "webroot/app.js", "webroot/app.css", "webroot/v03.js",
        "webroot/sdd-ui.js", "webroot/sdd-ui.css", "tools/sdd.sh",
        "tools/sdd-machine.sh", "tools/sdd-workflow.sh", "tools/pidd-config.sh",
        "tools/dispatch-config.sh",
    ]
    for rel in required:
        path = stage / rel
        if not path.is_file() or path.stat().st_size == 0:
            raise RuntimeError(f"stage_file_missing:{rel}")

    module_prop = (stage / "module.prop").read_text()
    if "version=4.13.0-verify-owner-rc6" not in module_prop or "versionCode=4130006" not in module_prop:
        raise RuntimeError("rc6_metadata_missing")

    service_sha = git_blob_sha((stage / "service.sh").read_bytes())
    if service_sha != BASE_PINS["service.sh"]:
        raise RuntimeError("delivery_core_changed")

    action = (stage / "action.sh").read_text()
    wrapper = (stage / "bin/module-control").read_text()
    fast_wrapper = (stage / "bin/module-control-rc4").read_text()
    base = (stage / "bin/module-control-base").read_text()
    index = (stage / "webroot/index.html").read_text()
    app = (stage / "webroot/app.js").read_text()
    v03_ui = (stage / "webroot/v03.js").read_text()
    extension = (stage / "webroot/sdd-ui.js").read_text()
    support_tool = (stage / "tools/dispatch-config.sh").read_text()

    if "127.0.0.1:0" not in action or "bootstrap.token" not in action:
        raise RuntimeError("loopback_bootstrap_contract_missing")
    if "AM_BIN=/system/bin/am" not in action or '"$AM_BIN" get-current-user' not in action or '"$AM_BIN" start' not in action:
        raise RuntimeError("android_framework_namespace_contract_missing")
    if "CURRENT_USER=$(am " in action or "if ! am start" in action:
        raise RuntimeError("unqualified_android_am_forbidden")
    if "capabilities-v03" not in wrapper or "APPLY TARGETS" not in wrapper or "IMPORT TARGETS" not in wrapper:
        raise RuntimeError("rc6_v03_adapter_contract_missing")
    for marker in (
        'status_source":"local_snapshot',
        'ntfy_topic_configured',
        'ntfy_url_configured',
        'ntfy_token_file_configured',
    ):
        if marker not in fast_wrapper:
            raise RuntimeError(f"rc6_fast_status_marker_missing:{marker}")
    for marker in ("target-test-all-enabled", "inventory_sortify()", "sortify) inventory_sortify"):
        if marker not in base:
            raise RuntimeError(f"rc6_base_adapter_marker_missing:{marker}")
    for marker in ("Configured · leave blank to preserve.", "scrollIntoView", "syncRunState"):
        if marker not in app:
            raise RuntimeError(f"template_ux_marker_missing:{marker}")
    for marker in ("recordCount", "syncApplyState", "syncImportApply", "resultSummary"):
        if marker not in v03_ui:
            raise RuntimeError(f"template_v03_ux_marker_missing:{marker}")
    for marker in ("Test all enabled targets", "target-test-all-enabled", "Sortify companion", "name=sortify"):
        if marker not in extension:
            raise RuntimeError(f"rc6_webui_extension_marker_missing:{marker}")
    if "sddTargetCards" not in index or "sdd-ui.js" not in index or "v03.js" not in index:
        raise RuntimeError("rc6_webui_extension_missing")
    if "VERSION=4.12.6" in support_tool or "s/^version=//p" not in support_tool:
        raise RuntimeError("support_bundle_version_not_module_derived")
    for source in (app, v03_ui, extension):
        if "window.ksu" in source or "window.apatch" in source or "eval(" in source or "new Function" in source:
            raise RuntimeError("unsafe_webui_extension_pattern")
    for rel in ("bin/webui-server-arm64", "bin/sdd-webui-v03-helper-arm64"):
        if (stage / rel).read_bytes()[:4] != b"\x7fELF":
            raise RuntimeError(f"not_elf:{rel}")

    run(["sh", "-n", str(stage / "action.sh")])
    run(["sh", "-n", str(stage / "customize.sh")])
    run(["sh", "-n", str(stage / "tools" / "dispatch-config.sh")])
    run(["sh", "-n", str(stage / "bin/module-control")])
    run(["sh", "-n", str(stage / "bin/module-control-rc4")])
    run(["sh", "-n", str(stage / "bin/module-control-base")])

    native_helper = work / "sdd-webui-v03-helper-native"
    native_env = os.environ.copy()
    native_env.pop("GOOS", None)
    native_env.pop("GOARCH", None)
    native_env["CGO_ENABLED"] = "0"
    run(["go", "build", "-buildvcs=false", "-trimpath", "-o", str(native_helper), str(RC5_OVERLAY / "v03-helper.go")], cwd=ROOT, env=native_env)

    adapter_runtime = work / "adapter-runtime"
    requests = adapter_runtime / "requests"
    uploads = adapter_runtime / "uploads"
    adapter_state = work / "adapter-state"
    target_dir = adapter_state / "config" / "targets.d"
    sortify_dir = work / "sortify-module"
    for path in (requests, uploads, target_dir, sortify_dir):
        path.mkdir(parents=True, exist_ok=True)
    (adapter_state / "health.env").write_text(
        "status=OK\nevent_pending=no\nmain_pid_ok=yes\nwatcher_pid_ok=yes\nwatchdog_pid_ok=yes\n"
    )
    (adapter_state / "config.env").write_text(
        "NTFY_ENABLED=1\nNTFY_PRIORITY=default\nNTFY_TAGS=package\n"
        "NTFY_TOPIC=fixture-secret-topic\nNTFY_URL=https://ntfy.example.invalid\n"
        "NTFY_TOKEN_FILE=/data/adb/ssh-drop-dispatcher/ntfy.token\n"
    )
    (target_dir / "pi3.conf").write_text('target_name="pi3"\nenabled="1"\nssh_host="pi3"\nremote_drop="/tmp/drop"\nplatform="linux"\nshell="bash"\nscp_flags=""\nrole="primary"\n')
    (target_dir / "berylax.conf").write_text('target_name="berylax"\nenabled="1"\nssh_host="berylax"\nremote_drop="/tmp/drop"\nplatform="openwrt"\nshell="sh"\nscp_flags="-O"\nrole="router"\n')
    (sortify_dir / "module.prop").write_text("id=sortify\nname=Sortify Dispatch\nversion=4.7.1-webui-cleanup-hotfix\nversionCode=25\n")
    (sortify_dir / "sortify.conf").write_text(
        "INTERVAL=300\nSORTIFY_NORMAL_SORT=1\nSORTIFY_SORT_MODE=interval\n"
        "SORTIFY_HOLD_PROTECTED=1\nSORTIFY_DISPATCHER_INTEGRATION=auto\n"
        "SORTIFY_DUPLICATE_MODE=filename\n"
    )
    lint_tool = work / "lint-ok.sh"
    lint_tool.write_text("#!/bin/sh\necho 'lint=ok verify_owner=dispatcher external_verify_wrapper=no'\n")
    lint_tool.chmod(0o755)
    fake_sdd = work / "fake-sdd.sh"
    fake_sdd.write_text(
        "#!/bin/sh\n"
        "if [ \"${1:-}\" = target ] && [ \"${2:-}\" = test ] && [ -n \"${3:-}\" ]; then\n"
        "  echo \"target=${3} readiness=PASS\"\n"
        "  exit 0\n"
        "fi\n"
        "echo \"unsupported fake sdd invocation\" >&2\n"
        "exit 2\n"
    )
    fake_sdd.chmod(0o755)

    env = os.environ.copy()
    env.update({
        "MODULE_DIR": str(stage),
        "MODULE_STATE_DIR": str(adapter_state),
        "WEBUI_RUNTIME_DIR": str(adapter_runtime),
        "SDD_WEBUI_TARGET_DIR": str(target_dir),
        "SDD_WEBUI_V03_HELPER": str(native_helper),
        "SDD_WEBUI_V03_CONFIG_TOOL": str(lint_tool),
        "SDD_WEBUI_CONFIG_FILE": str(adapter_state / "config.env"),
        "SDD_WEBUI_QUAR_DB": str(adapter_state / "dispatch.quarantined"),
        "SDD_WEBUI_RECEIPT_DB": str(adapter_state / "delivery.receipts.jsonl"),
        "SDD_WEBUI_SH_BIN": shutil.which("sh") or "/bin/sh",
        "SDD_WEBUI_SDD": str(fake_sdd),
        "SDD_WEBUI_SORTIFY_MODULE_DIR": str(sortify_dir),
        "SDD_WEBUI_SORTIFY_PROP": str(sortify_dir / "module.prop"),
        "SDD_WEBUI_SORTIFY_CONFIG": str(sortify_dir / "sortify.conf"),
    })
    control = ["sh", str(stage / "bin/module-control")]

    status_raw = run(control + ["status"], env=env, capture=True).stdout
    status = json.loads(status_raw)
    runtime = status.get("runtime", {})
    if runtime.get("status_source") != "local_snapshot" or runtime.get("backend_refresh") != "none":
        raise RuntimeError("rc6_fast_status_runtime_fixture_mismatch")
    for key in ("ntfy_topic_configured", "ntfy_url_configured", "ntfy_token_file_configured"):
        if runtime.get(key) != "yes":
            raise RuntimeError(f"rc6_ntfy_configured_state_mismatch:{key}")
    if "fixture-secret-topic" in status_raw or "ntfy.example.invalid" in status_raw or "ntfy.token" in status_raw:
        raise RuntimeError("rc6_ntfy_secret_leak")

    config = json.loads(run(control + ["config-get"], env=env, capture=True).stdout)
    if any(config.get(key) for key in ("ntfy_topic", "ntfy_url", "ntfy_token_file")):
        raise RuntimeError("rc6_ntfy_write_only_contract_mismatch")

    base_doc = json.loads(run(control + ["capabilities"], env=env, capture=True).stdout)
    if base_doc.get("schema") != "root-module-webui.capabilities.v1":
        raise RuntimeError("base_capability_schema_mismatch")
    job_names = {item.get("name") for item in base_doc.get("jobs", [])}
    inventory_names = {item.get("name") for item in base_doc.get("inventories", [])}
    if "target-test-all-enabled" not in job_names or "sortify" not in inventory_names:
        raise RuntimeError("rc6_capability_additions_missing")

    smoke = run(control + ["job-run", "target-test-all-enabled"], env=env, capture=True).stdout
    if "target=pi3 result=PASS" not in smoke or "target=berylax result=PASS" not in smoke or "outcome=success tested=2 failed=0" not in smoke:
        raise RuntimeError("rc6_all_enabled_smoke_fixture_mismatch")

    sortify = json.loads(run(control + ["inventory", "sortify"], env=env, capture=True).stdout)
    sortify_item = sortify.get("items", [{}])[0]
    if sortify_item.get("version") != "4.7.1-webui-cleanup-hotfix" or sortify_item.get("dispatcher_integration") != "auto" or sortify_item.get("sort_mode") != "interval":
        raise RuntimeError("rc6_sortify_inventory_fixture_mismatch")

    v03 = run(control + ["capabilities-v03"], env=env, capture=True)
    v03_doc = json.loads(v03.stdout)
    if v03_doc.get("schema") != "root-module-webui.extensions.v1" or not v03_doc.get("features", {}).get("collections"):
        raise RuntimeError("v03_capability_schema_mismatch")
    current = json.loads(run(control + ["collection-get", "targets"], env=env, capture=True).stdout)
    if len(current.get("records", [])) != 2:
        raise RuntimeError("v03_collection_get_mismatch")

    records = current["records"]
    for item in records:
        if item["name"] == "pi3":
            item["role"] = "primary_updated"
    preview_request = requests / "collection-preview.json"
    preview_request.write_text(json.dumps({"name": "targets", "mode": "preview", "records": records}, separators=(",", ":")))
    preview = json.loads(run(control + ["collection-preview", "targets", str(preview_request)], env=env, capture=True).stdout)
    if preview.get("validation") != "pass" or preview.get("changes", {}).get("changed") != ["pi3"]:
        raise RuntimeError("v03_collection_preview_mismatch")
    apply_request = requests / "collection-apply.json"
    apply_request.write_text(json.dumps({"name": "targets", "mode": "apply", "records": records, "preview_token": "server-owned", "confirmation": "APPLY TARGETS"}, separators=(",", ":")))
    applied = json.loads(run(control + ["collection-apply", "targets", str(apply_request)], env=env, capture=True).stdout)
    if applied.get("verify_state") != "pass" or not applied.get("backup"):
        raise RuntimeError("v03_collection_apply_mismatch")

    exported = run(control + ["export", "target-profiles"], env=env, capture=True).stdout
    export_doc = json.loads(exported)
    if export_doc.get("schema") != "sdd-target-profiles-backup-v1" or len(export_doc.get("targets", [])) != 2:
        raise RuntimeError("v03_export_mismatch")
    upload = uploads / "target-profiles.json"
    upload.write_text(exported)
    imported_preview = json.loads(run(control + ["import-preview", "target-profiles", str(upload)], env=env, capture=True).stdout)
    if imported_preview.get("validation") != "pass":
        raise RuntimeError("v03_import_preview_mismatch")
    import_request = requests / "import-apply.json"
    import_request.write_text('{"name":"target-profiles"}')
    imported = json.loads(run(control + ["import-apply", "target-profiles", str(upload), str(import_request)], env=env, capture=True).stdout)
    if imported.get("verify_state") != "pass":
        raise RuntimeError("v03_import_apply_mismatch")


def build(output: Path) -> None:
    if shutil.which("go") is None:
        raise RuntimeError("go_missing")
    with tempfile.TemporaryDirectory(prefix="sdd-rc6-webui-") as tmp:
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
        print(f"rc6_webui_core_commit={TEMPLATE_COMMIT}")
        print(f"rc6_webui_core_version={CORE_VERSION}")
        print(f"delivery_core_service_blob={BASE_PINS['service.sh']}")
        print(f"artifact={output}")
        print(f"artifact_bytes={output.stat().st_size}")
        print(f"artifact_sha256={digest}")
        print("RESULT: SDD_RC6_WEBUI_BUILD_DONE outcome=success delivery_core_changed=no workflow_exit_code=0")


def main() -> int:
    parser = argparse.ArgumentParser(description="Build SSH Drop Dispatcher RC6 WebUI candidate")
    parser.add_argument(
        "--output",
        type=Path,
        default=ROOT / "dist" / "ssh-drop-dispatcher-magisk-v4.13.0-verify-owner-rc6.zip",
    )
    args = parser.parse_args()
    try:
        build(args.output.resolve())
    except Exception as exc:
        print(f"RESULT: SDD_RC6_WEBUI_BUILD_DONE outcome=fail reason={exc} workflow_exit_code=1", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
