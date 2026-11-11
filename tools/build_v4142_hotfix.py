#!/usr/bin/env python3
"""Deterministic source-only 4.14.2 hotfix overlay on frozen, verified 4.14.1."""
from __future__ import annotations

import argparse
import hashlib
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
VERSION = "4.14.2"
VERSION_CODE = "4140200"
STABLE = ROOT / "source/stable-v4.14.1/service.sh"
FIXED = ROOT / "source/vnext-issue69/service.sh"
COORDINATOR = ROOT / "source/vnext-issue69/tools/sdd-followup-coalesce.sh"
REQUIRED_BASE_SHA = "82e6ed97c61ad42c61a0d6d7653f60d3a520248dba1e1a57143ee3e8655b7556"
PUBLISHED_ASSET = "https://github.com/Lycidias93/ssh-drop-dispatcher/releases/download/v4.14.1/ssh-drop-dispatcher-magisk-v4.14.1.zip"
PUBLISHED_ASSET_SHA256 = "d8bc263937a20eea16625bf840f360889668fbff2c8f12a843a9d57f36ac6a9a"
PUBLISHED_ASSET_BYTES = 4849663
MARKER = "RESULT: SDD_V4142_HOTFIX_BUILD_DONE outcome=success workflow_exit_code=0"

def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()

def run(*args: object) -> None:
    subprocess.run([str(arg) for arg in args], cwd=ROOT, check=True)

def validate_source() -> None:
    if digest(STABLE) != REQUIRED_BASE_SHA:
        raise RuntimeError("v4141_frozen_source_changed")
    base = STABLE.read_text()
    hotfix = FIXED.read_text()
    if "bundle_ssh_atomic_refresh_failed" not in base or base == hotfix:
        raise RuntimeError("frozen_atomic_ssh_baseline_missing")
    if "bundle_ssh_atomic_refresh_failed" not in hotfix:
        raise RuntimeError("ssh_atomic_import_regressed")
    for token in (
        "FOLLOWUP_COORDINATOR=$MODULE_TOOLS_DIR/sdd-followup-coalesce.sh",
        '"$FOLLOWUP_COORDINATOR" request',
        '"$FOLLOWUP_COORDINATOR" reconcile',
        "scan_lock_release(){",
        "scan_lock_old_but_owner_alive",
        "followup_orphan_recovered",
    ):
        content = COORDINATOR.read_text() if token == "followup_orphan_recovered" else hotfix
        if token not in content:
            raise RuntimeError("missing_hotfix_contract:" + token)
    if "( $SLEEP_BIN 5; /data/adb/modules/ssh_drop_dispatcher/service.sh" in hotfix:
        raise RuntimeError("recursive_followup_still_present")
    run("sh", "-n", FIXED)
    run("sh", "-n", COORDINATOR)


def bundle_webui_assets(stage: Path) -> None:
    """Keep the pinned Core static-route allowlist unchanged.

    SDD CSS/JS are module-specific overlays, so compose them into the
    already-allowlisted app.css/app.js rather than serving extra paths.
    Both JS files are independent IIFEs; append SDD after Core app.js.
    """
    root = stage / "webroot"
    index_path = root / "index.html"
    index = index_path.read_text(encoding="utf-8")
    for entry in (
        '  <link rel="stylesheet" href="sdd-ui.css">\n',
        '  <script src="sdd-ui.js"></script>\n',
    ):
        if index.count(entry) != 1:
            raise RuntimeError("missing_or_duplicated_sdd_static_reference:" + entry.strip())
        index = index.replace(entry, "", 1)
    index_path.write_text(index, encoding="utf-8", newline="\n")
    for primary, overlay, label in (
        ("app.css", "sdd-ui.css", "SDD module styles"),
        ("app.js", "sdd-ui.js", "SDD module controls"),
    ):
        main = (root / primary).read_bytes()
        extra = (root / overlay).read_bytes()
        if not main or not extra:
            raise RuntimeError("missing_webui_bundle_source:" + overlay)
        if primary == "app.js":
            if not main.rstrip().endswith(b"})();") or not extra.lstrip().startswith(b"(() => {") or not extra.rstrip().endswith(b"})();"):
                raise RuntimeError("webui_iife_contract_changed")
        banner = ("\n/* " + label + " (bundled for pinned Core static routes) */\n").encode()
        (root / primary).write_bytes(main + banner + extra + b"\n")
    for forbidden in ("sdd-ui.css", "sdd-ui.js"):
        if ('href="' + forbidden + '"') in index or ('src="' + forbidden + '"') in index:
            raise RuntimeError("webui_unserved_static_reference:" + forbidden)

def build(output: Path) -> None:
    validate_source()
    with tempfile.TemporaryDirectory(prefix="sdd-v4142-hotfix-") as name:
        temp = Path(name)
        baseline_zip = temp / "frozen-v4.14.1.zip"
        run("curl", "--fail", "--location", "--silent", "--show-error",
            "--retry", "1", "--connect-timeout", "15", "--max-time", "240",
            "--output", baseline_zip, PUBLISHED_ASSET)
        if baseline_zip.stat().st_size != PUBLISHED_ASSET_BYTES or digest(baseline_zip) != PUBLISHED_ASSET_SHA256:
            raise RuntimeError("published_v4141_asset_identity_mismatch")
        stage = temp / "module"
        stage.mkdir()
        with zipfile.ZipFile(baseline_zip) as z:
            for member in z.infolist():
                parts = Path(member.filename).parts
                if member.filename.startswith("/") or ".." in parts:
                    raise RuntimeError("unsafe_base_package_path")
                z.extract(member, stage)
                if not member.is_dir():
                    extracted = stage / member.filename
                    original_mode = member.external_attr >> 16
                    extracted.chmod(0o755 if original_mode & 0o111 else 0o644)
        if (stage / "service.sh").read_bytes() != STABLE.read_bytes():
            raise RuntimeError("published_v4141_service_mismatch")
        original = {p.relative_to(stage).as_posix(): digest(p)
                    for p in stage.rglob("*") if p.is_file()}
        shutil.copyfile(FIXED, stage / "service.sh")
        prop = stage / "module.prop"
        content = prop.read_text()
        if content.count("version=4.14.1\n") != 1 or content.count("versionCode=4140100\n") != 1:
            raise RuntimeError("unexpected_base_module_version")
        content = content.replace("version=4.14.1\n", "version=4.14.2\n", 1)
        content = content.replace("versionCode=4140100\n", "versionCode=4140200\n", 1)
        prop.write_text(content)
        bundle_webui_assets(stage)
        shutil.copyfile(COORDINATOR, stage / "tools/sdd-followup-coalesce.sh")
        (stage / "tools/sdd-followup-coalesce.sh").chmod(0o755)
        current = {p.relative_to(stage).as_posix(): digest(p)
                   for p in stage.rglob("*") if p.is_file()}
        changed = {p for p in original if original[p] != current.get(p)}
        added = set(current) - set(original)
        if changed != {"service.sh", "module.prop", "webroot/index.html", "webroot/app.js", "webroot/app.css"} or added != {"tools/sdd-followup-coalesce.sh"}:
            raise RuntimeError(f"unexpected_hotfix_package_delta changed={changed} added={added}")
        first, second = temp / "first.zip", temp / "second.zip"
        for path in (first, second):
            run(sys.executable, ROOT / "tools/build_magisk_zip.py", stage, path)
        if first.read_bytes() != second.read_bytes():
            raise RuntimeError("hotfix_package_not_reproducible")
        with zipfile.ZipFile(first) as z:
            if b"version=4.14.2\n" not in z.read("module.prop"):
                raise RuntimeError("new_version_missing")
            if b"versionCode=4140200\n" not in z.read("module.prop"):
                raise RuntimeError("new_version_code_missing")
            if z.read("service.sh") != FIXED.read_bytes():
                raise RuntimeError("service_readback_mismatch")
            if z.read("tools/sdd-followup-coalesce.sh") != COORDINATOR.read_bytes():
                raise RuntimeError("coordinator_readback_mismatch")
            page = z.read("webroot/index.html")
            if b'sdd-ui.js"' in page or b'sdd-ui.css"' in page:
                raise RuntimeError("webui_unserved_assets_in_page")
            if not z.read("webroot/app.js").endswith((stage / "webroot/sdd-ui.js").read_bytes() + b"\n"):
                raise RuntimeError("webui_script_bundle_not_exact")
            if not z.read("webroot/app.css").endswith((stage / "webroot/sdd-ui.css").read_bytes() + b"\n"):
                raise RuntimeError("webui_style_bundle_not_exact")
        output.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(first, output)
        print(f"version={VERSION}")
        print(f"versionCode={VERSION_CODE}")
        print(f"artifact={output}")
        print(f"artifact_bytes={output.stat().st_size}")
        print(f"artifact_sha256={digest(output)}")
        print("package_delta=service.sh,module.prop,tools/sdd-followup-coalesce.sh,webroot/index.html,webroot/app.js,webroot/app.css")
        print("production_installed=no")
        print(MARKER)

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        build(args.output.resolve())
    except (OSError, RuntimeError, subprocess.CalledProcessError) as exc:
        print(f"RESULT: SDD_V4142_HOTFIX_BUILD_DONE outcome=fail reason={exc} workflow_exit_code=1",
              file=sys.stderr)
        raise SystemExit(1)
