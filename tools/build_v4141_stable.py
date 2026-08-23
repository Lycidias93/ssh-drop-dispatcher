#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import importlib.util
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
RC4_BUILDER = ROOT / "tools" / "build_vnext_return_rc4.py"
BASE_SERVICE = ROOT / "source" / "magisk" / "service.sh"
HOTFIX_SERVICE = ROOT / "source" / "stable-v4.14.1" / "service.sh"
BASE_PROP = ROOT / "source" / "stable-v4.14.0" / "module.prop"
HOTFIX_PROP = ROOT / "source" / "stable-v4.14.1" / "module.prop"
BASELINE_SHA256 = "868e9735e89bc55cdc43d207fed7a07d7ca92fb5852a975f8ebd8ef8c4c989fd"
STABLE_VERSION = "4.14.1"
STABLE_VERSION_CODE = "4140100"
VULNERABLE_LINE = '      [ -f "$BUNDLE_DIR/ssh/$x" ] && $CP_BIN -f "$BUNDLE_DIR/ssh/$x" "$SSH_DIR/$x" >/dev/null 2>&1 || true'
FIXED_LINE = '      [ -f "$BUNDLE_DIR/ssh/$x" ] && { src_sig=$($CKSUM_BIN "$BUNDLE_DIR/ssh/$x" 2>/dev/null); dst_sig=""; [ -f "$SSH_DIR/$x" ] && dst_sig=$($CKSUM_BIN "$SSH_DIR/$x" 2>/dev/null); if [ -n "$src_sig" ] && [ "$src_sig" != "$dst_sig" ]; then tmp="$SSH_DIR/.$x.import.$$"; if $CP_BIN -f "$BUNDLE_DIR/ssh/$x" "$tmp" >/dev/null 2>&1 && $CHMOD_BIN 600 "$tmp" >/dev/null 2>&1 && $MV_BIN -f "$tmp" "$SSH_DIR/$x" >/dev/null 2>&1; then :; else $RM_BIN -f "$tmp" >/dev/null 2>&1 || true; log "WARN bundle_ssh_atomic_refresh_failed file=$x"; fi; fi; } || true'

spec = importlib.util.spec_from_file_location("sdd_vnext_return_rc4_builder", RC4_BUILDER)
if spec is None or spec.loader is None:
    raise RuntimeError("rc4_builder_import_failed")
rc4 = importlib.util.module_from_spec(spec)
spec.loader.exec_module(rc4)


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def payload(path: Path) -> dict[str, bytes]:
    with zipfile.ZipFile(path, "r") as archive:
        return {name: archive.read(name) for name in archive.namelist()}


def verify_source_overlay() -> None:
    base = BASE_SERVICE.read_text()
    fixed = HOTFIX_SERVICE.read_text()
    if base.count(VULNERABLE_LINE) != 1:
        raise RuntimeError("base_vulnerable_anchor_mismatch")
    if base.count("bundle_ssh_atomic_refresh_failed") != 0:
        raise RuntimeError("base_unexpected_hotfix_marker")
    expected = base.replace(VULNERABLE_LINE, FIXED_LINE, 1)
    if fixed != expected:
        raise RuntimeError("hotfix_service_delta_not_exact")
    if VULNERABLE_LINE in fixed:
        raise RuntimeError("hotfix_vulnerable_line_remaining")
    for marker in (
        'src_sig=$($CKSUM_BIN',
        'tmp="$SSH_DIR/.$x.import.$$"',
        '$CHMOD_BIN 600 "$tmp"',
        '$MV_BIN -f "$tmp" "$SSH_DIR/$x"',
        'bundle_ssh_atomic_refresh_failed',
    ):
        if marker not in fixed:
            raise RuntimeError(f"hotfix_marker_missing:{marker}")
    subprocess.run(["sh", "-n", str(HOTFIX_SERVICE)], check=True)


def verify_delta(base_zip: Path, hotfix_zip: Path) -> None:
    base = payload(base_zip)
    hotfix = payload(hotfix_zip)
    if set(base) != set(hotfix):
        raise RuntimeError("hotfix_file_set_changed")
    changed = [name for name in sorted(base) if base[name] != hotfix[name]]
    if changed != ["module.prop", "service.sh"]:
        raise RuntimeError(f"hotfix_unexpected_payload_change changed={changed}")
    service = hotfix["service.sh"].decode("utf-8")
    if VULNERABLE_LINE in service or "bundle_ssh_atomic_refresh_failed" not in service:
        raise RuntimeError("hotfix_service_contract_missing")
    prop = hotfix["module.prop"].decode("utf-8")
    if f"version={STABLE_VERSION}\n" not in prop:
        raise RuntimeError("hotfix_version_missing")
    if f"versionCode={STABLE_VERSION_CODE}\n" not in prop:
        raise RuntimeError("hotfix_version_code_missing")
    if "return-rc" in prop or "verify-owner" in prop:
        raise RuntimeError("hotfix_rc_label_present")


def build(output: Path) -> None:
    for path in (BASE_SERVICE, HOTFIX_SERVICE, BASE_PROP, HOTFIX_PROP):
        if not path.is_file():
            raise RuntimeError(f"required_file_missing:{path.relative_to(ROOT)}")
    if shutil.which("go") is None:
        raise RuntimeError("go_missing")
    verify_source_overlay()

    with tempfile.TemporaryDirectory(prefix="sdd-v4141-stable-") as tmp:
        work = Path(tmp)
        fetched = rc4.rc3.rc1.fetch_core(work)
        stage = rc4.stage_module(work, fetched)
        rc4.verify_stage(stage, work)

        shutil.copy2(BASE_PROP, stage / "module.prop")
        baseline = work / "stable-v4.14.0-reference.zip"
        rc4.rc3.rc1.run([
            sys.executable,
            str(ROOT / "tools" / "build_magisk_zip.py"),
            str(stage),
            str(baseline),
        ])
        baseline_sha = sha256(baseline)
        if baseline_sha != BASELINE_SHA256:
            raise RuntimeError(
                f"published_v4140_rebuild_mismatch expected={BASELINE_SHA256} actual={baseline_sha}"
            )

        shutil.copy2(HOTFIX_SERVICE, stage / "service.sh")
        shutil.copy2(HOTFIX_PROP, stage / "module.prop")
        (stage / "service.sh").chmod(0o755)

        first = work / "stable-v4.14.1-first.zip"
        second = work / "stable-v4.14.1-second.zip"
        for candidate in (first, second):
            rc4.rc3.rc1.run([
                sys.executable,
                str(ROOT / "tools" / "build_magisk_zip.py"),
                str(stage),
                str(candidate),
            ])
        if first.read_bytes() != second.read_bytes():
            raise RuntimeError("hotfix_package_not_reproducible")

        verify_delta(baseline, first)
        output.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(first, output)
        digest = sha256(output)
        print(f"stable_version={STABLE_VERSION}")
        print(f"stable_versionCode={STABLE_VERSION_CODE}")
        print(f"published_v4140_sha256={BASELINE_SHA256}")
        print("stable_delta=module.prop,service.sh")
        print("ssh_bundle_import_unchanged_rewrite=no")
        print("ssh_bundle_import_atomic_publish=yes")
        print("host_autoexecution_added=no")
        print("arbitrary_remote_command_added=no")
        print(f"artifact={output}")
        print(f"artifact_bytes={output.stat().st_size}")
        print(f"artifact_sha256={digest}")
        print("RESULT: SDD_V4141_STABLE_BUILD_DONE outcome=success workflow_exit_code=0")


def main() -> int:
    parser = argparse.ArgumentParser(description="Build SSH Drop Dispatcher v4.14.1 stable atomic SSH import hotfix")
    parser.add_argument(
        "--output",
        type=Path,
        default=ROOT / "dist" / "ssh-drop-dispatcher-magisk-v4.14.1.zip",
    )
    args = parser.parse_args()
    try:
        build(args.output.resolve())
    except Exception as exc:
        print(
            f"RESULT: SDD_V4141_STABLE_BUILD_DONE outcome=fail reason={exc} workflow_exit_code=1",
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
