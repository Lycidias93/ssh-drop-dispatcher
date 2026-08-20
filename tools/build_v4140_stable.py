#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import importlib.util
from pathlib import Path
import shutil
import sys
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
RC4_BUILDER = ROOT / "tools" / "build_vnext_return_rc4.py"
STABLE_PROP = ROOT / "source" / "stable-v4.14.0" / "module.prop"
ACCEPTED_RC4_SHA256 = "a0a82185dff60183dd95bbae01299a9a637836b008ede3a8f3a9da2f51e1b96d"
STABLE_VERSION = "4.14.0"
STABLE_VERSION_CODE = "4140005"

spec = importlib.util.spec_from_file_location("sdd_vnext_return_rc4_builder", RC4_BUILDER)
if spec is None or spec.loader is None:
    raise RuntimeError("rc4_builder_import_failed")
rc4 = importlib.util.module_from_spec(spec)
spec.loader.exec_module(rc4)


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def zip_payload(path: Path) -> dict[str, bytes]:
    with zipfile.ZipFile(path, "r") as archive:
        return {name: archive.read(name) for name in archive.namelist()}


def verify_stable_equivalence(rc4_zip: Path, stable_zip: Path) -> None:
    rc4_payload = zip_payload(rc4_zip)
    stable_payload = zip_payload(stable_zip)
    if set(rc4_payload) != set(stable_payload):
        missing = sorted(set(rc4_payload) - set(stable_payload))
        extra = sorted(set(stable_payload) - set(rc4_payload))
        raise RuntimeError(f"stable_file_set_mismatch missing={missing} extra={extra}")

    changed = [name for name in sorted(rc4_payload) if rc4_payload[name] != stable_payload[name]]
    if changed != ["module.prop"]:
        raise RuntimeError(f"stable_unexpected_payload_change changed={changed}")

    prop = stable_payload["module.prop"].decode("utf-8")
    if f"version={STABLE_VERSION}\n" not in prop:
        raise RuntimeError("stable_version_missing")
    if f"versionCode={STABLE_VERSION_CODE}\n" not in prop:
        raise RuntimeError("stable_version_code_missing")
    if "return-rc" in prop or "verify-owner" in prop:
        raise RuntimeError("stable_rc_label_present")


def build(output: Path) -> None:
    if not STABLE_PROP.is_file():
        raise RuntimeError("stable_module_prop_missing")
    if shutil.which("go") is None:
        raise RuntimeError("go_missing")

    with tempfile.TemporaryDirectory(prefix="sdd-v4140-stable-") as tmp:
        work = Path(tmp)
        fetched = rc4.rc3.rc1.fetch_core(work)
        stage = rc4.stage_module(work, fetched)
        rc4.verify_stage(stage, work)

        rc4_reference = work / "accepted-return-rc4-reference.zip"
        rc4.rc3.rc1.run([
            sys.executable,
            str(ROOT / "tools" / "build_magisk_zip.py"),
            str(stage),
            str(rc4_reference),
        ])
        reference_sha = sha256(rc4_reference)
        if reference_sha != ACCEPTED_RC4_SHA256:
            raise RuntimeError(
                f"accepted_rc4_rebuild_mismatch expected={ACCEPTED_RC4_SHA256} actual={reference_sha}"
            )

        shutil.copy2(STABLE_PROP, stage / "module.prop")

        first = work / "stable-first.zip"
        second = work / "stable-second.zip"
        for candidate in (first, second):
            rc4.rc3.rc1.run([
                sys.executable,
                str(ROOT / "tools" / "build_magisk_zip.py"),
                str(stage),
                str(candidate),
            ])
        if first.read_bytes() != second.read_bytes():
            raise RuntimeError("stable_package_not_reproducible")

        verify_stable_equivalence(rc4_reference, first)

        output.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(first, output)
        digest = sha256(output)
        print(f"stable_version={STABLE_VERSION}")
        print(f"stable_versionCode={STABLE_VERSION_CODE}")
        print(f"accepted_rc4_sha256={ACCEPTED_RC4_SHA256}")
        print("accepted_runtime=4.14.0-return-rc4")
        print("webui_core_version=0.6.0")
        print("stable_equivalence=only_module_prop_diff")
        print("return_channel_v1=enabled")
        print("named_delivery_scan_fairness=enabled")
        print("host_autoexecution_added=no")
        print("arbitrary_remote_command_added=no")
        print(f"artifact={output}")
        print(f"artifact_bytes={output.stat().st_size}")
        print(f"artifact_sha256={digest}")
        print("RESULT: SDD_V4140_STABLE_BUILD_DONE outcome=success workflow_exit_code=0")


def main() -> int:
    parser = argparse.ArgumentParser(description="Build stable SSH Drop Dispatcher v4.14.0 from the accepted Return RC4 payload")
    parser.add_argument(
        "--output",
        type=Path,
        default=ROOT / "dist" / "ssh-drop-dispatcher-magisk-v4.14.0.zip",
    )
    args = parser.parse_args()
    try:
        build(args.output.resolve())
    except Exception as exc:
        print(f"RESULT: SDD_V4140_STABLE_BUILD_DONE outcome=fail reason={exc} workflow_exit_code=1", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
