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
OVERLAY = ROOT / "source" / "rc4-webui"
TEMPLATE_COMMIT = "5b8e412428cd04b1cf98a1fc0e03269580b60d71"
CORE_VERSION = "0.2.2"
BASE_URL = f"https://raw.githubusercontent.com/Lycidias93/android-root-module-webui-template/{TEMPLATE_COMMIT}"

CORE_FILES = {
    "module/webroot/index.html": "19ee3a07f5c4751f042c12b46f803800c4c2de71",
    "module/webroot/app.js": "6c83e4d1fa872e6afca1b2cca6a95efcd3c892b9",
    "module/webroot/app.css": "086437706de7aa68750f574d7f383df624c06a3a",
    "server/cmd/webui-server/main.go": "91be8656ffd0c5661a6770a27a8446d1a6ff306d",
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


def run(cmd: list[str], *, cwd: Path | None = None, env: dict[str, str] | None = None) -> None:
    print("+", " ".join(cmd))
    subprocess.run(cmd, cwd=cwd, env=env, check=True)


def patch_webroot(webroot: Path) -> None:
    for name in ("sdd-ui.js", "sdd-ui.css"):
        shutil.copy2(OVERLAY / "webroot" / name, webroot / name)

    index = webroot / "index.html"
    html = index.read_text()

    css_anchor = '  <link rel="stylesheet" href="app.css">'
    css_replacement = css_anchor + '\n  <link rel="stylesheet" href="sdd-ui.css">'
    if html.count(css_anchor) != 1:
        raise RuntimeError("webui_css_anchor_mismatch")
    html = html.replace(css_anchor, css_replacement, 1)

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
    script_replacement = script_anchor + '\n  <script src="sdd-ui.js"></script>'
    if html.count(script_anchor) != 1:
        raise RuntimeError("webui_script_anchor_mismatch")
    html = html.replace(script_anchor, script_replacement, 1)

    index.write_text(html)


def stage_module(work: Path, fetched: dict[str, Path]) -> Path:
    stage = work / "stage"
    shutil.copytree(BASE, stage)

    for rel, expected in BASE_PINS.items():
        verify_blob(stage / rel, expected)

    shutil.copy2(OVERLAY / "module.prop", stage / "module.prop")
    shutil.copy2(OVERLAY / "customize.sh", stage / "customize.sh")
    shutil.copy2(OVERLAY / "action.sh", stage / "action.sh")

    webroot = stage / "webroot"
    if webroot.exists():
        shutil.rmtree(webroot)
    webroot.mkdir(parents=True)
    for name in ("index.html", "app.js", "app.css"):
        shutil.copy2(fetched[f"module/webroot/{name}"], webroot / name)
    patch_webroot(webroot)

    bindir = stage / "bin"
    bindir.mkdir(parents=True, exist_ok=True)
    shutil.copy2(OVERLAY / "module-control", bindir / "module-control")

    go_source = fetched["server/cmd/webui-server/main.go"]
    output = bindir / "webui-server-arm64"
    env = os.environ.copy()
    env.update({"CGO_ENABLED": "0", "GOOS": "android", "GOARCH": "arm64"})
    run([
        "go", "build", "-buildvcs=false", "-trimpath",
        "-ldflags", f"-s -w -X main.version={CORE_VERSION}",
        "-o", str(output), str(go_source),
    ], cwd=ROOT, env=env)

    for path in (stage / "action.sh", stage / "customize.sh", stage / "service.sh", bindir / "module-control", output):
        path.chmod(0o755)

    return stage


def verify_stage(stage: Path, work: Path) -> None:
    required = [
        "module.prop", "customize.sh", "action.sh", "service.sh",
        "bin/module-control", "bin/webui-server-arm64",
        "webroot/index.html", "webroot/app.js", "webroot/app.css",
        "webroot/sdd-ui.js", "webroot/sdd-ui.css",
        "tools/sdd.sh", "tools/sdd-machine.sh", "tools/sdd-workflow.sh",
    ]
    for rel in required:
        path = stage / rel
        if not path.is_file() or path.stat().st_size == 0:
            raise RuntimeError(f"stage_file_missing:{rel}")

    module_prop = (stage / "module.prop").read_text()
    if "version=4.13.0-verify-owner-rc4" not in module_prop or "versionCode=4130004" not in module_prop:
        raise RuntimeError("rc4_metadata_missing")

    service_sha = git_blob_sha((stage / "service.sh").read_bytes())
    if service_sha != BASE_PINS["service.sh"]:
        raise RuntimeError("delivery_core_changed")

    action = (stage / "action.sh").read_text()
    control = (stage / "bin/module-control").read_text()
    index = (stage / "webroot/index.html").read_text()
    extension = (stage / "webroot/sdd-ui.js").read_text()
    if "127.0.0.1:0" not in action or "bootstrap.token" not in action:
        raise RuntimeError("loopback_bootstrap_contract_missing")
    if "AM_BIN=/system/bin/am" not in action or '"$AM_BIN" get-current-user' not in action or '"$AM_BIN" start' not in action:
        raise RuntimeError("android_framework_namespace_contract_missing")
    if "CURRENT_USER=$(am " in action or "if ! am start" in action:
        raise RuntimeError("unqualified_android_am_forbidden")
    if "window.ksu" in control or "eval " in control:
        raise RuntimeError("unsafe_webui_adapter_pattern")
    if "arbitrary_path_input_blocked" not in control:
        raise RuntimeError("adapter_safety_fact_missing")
    if "sddTargetCards" not in index or "sdd-ui.js" not in index or "sdd-ui.css" not in index:
        raise RuntimeError("target_card_extension_missing")
    if "exec(" in extension or "window.ksu" in extension or "window.apatch" in extension:
        raise RuntimeError("unsafe_webui_extension_pattern")
    if (stage / "bin/webui-server-arm64").read_bytes()[:4] != b"\x7fELF":
        raise RuntimeError("webui_server_not_elf")

    run(["sh", "-n", str(stage / "action.sh")])
    run(["sh", "-n", str(stage / "customize.sh")])
    run(["sh", "-n", str(stage / "bin/module-control")])

    adapter_runtime = work / "adapter-runtime"
    adapter_state = work / "adapter-state"
    adapter_runtime.mkdir()
    adapter_state.mkdir()
    env = os.environ.copy()
    env.update({
        "MODULE_DIR": str(stage),
        "MODULE_STATE_DIR": str(adapter_state),
        "WEBUI_RUNTIME_DIR": str(adapter_runtime),
        "SDD_WEBUI_CONFIG_FILE": str(adapter_state / "config.env"),
        "SDD_WEBUI_TARGET_DIR": str(adapter_state / "targets.d"),
        "SDD_WEBUI_QUAR_DB": str(adapter_state / "dispatch.quarantined"),
        "SDD_WEBUI_RECEIPT_DB": str(adapter_state / "delivery.receipts.jsonl"),
    })
    probe = subprocess.run(
        ["sh", str(stage / "bin/module-control"), "capabilities"],
        env=env,
        check=True,
        text=True,
        capture_output=True,
    )
    capabilities = json.loads(probe.stdout)
    if capabilities.get("schema") != "root-module-webui.capabilities.v1":
        raise RuntimeError("capability_schema_mismatch")
    names = {item.get("name") for item in capabilities.get("inventories", [])}
    if not {"queue", "targets", "quarantine", "failures", "receipts"}.issubset(names):
        raise RuntimeError("required_inventory_missing")


def build(output: Path) -> None:
    if shutil.which("go") is None:
        raise RuntimeError("go_missing")
    with tempfile.TemporaryDirectory(prefix="sdd-rc4-webui-") as tmp:
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
        print(f"rc4_webui_core_commit={TEMPLATE_COMMIT}")
        print(f"rc4_webui_core_version={CORE_VERSION}")
        print(f"delivery_core_service_blob={BASE_PINS['service.sh']}")
        print(f"artifact={output}")
        print(f"artifact_bytes={output.stat().st_size}")
        print(f"artifact_sha256={digest}")
        print("RESULT: SDD_RC4_WEBUI_BUILD_DONE outcome=success delivery_core_changed=no workflow_exit_code=0")


def main() -> int:
    parser = argparse.ArgumentParser(description="Build SSH Drop Dispatcher RC4 WebUI candidate")
    parser.add_argument(
        "--output",
        type=Path,
        default=ROOT / "dist" / "ssh-drop-dispatcher-magisk-v4.13.0-verify-owner-rc4.zip",
    )
    args = parser.parse_args()
    try:
        build(args.output.resolve())
    except Exception as exc:
        print(f"RESULT: SDD_RC4_WEBUI_BUILD_DONE outcome=fail reason={exc} workflow_exit_code=1", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
