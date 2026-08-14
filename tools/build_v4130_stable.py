#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
from pathlib import Path
import shutil
import sys
import tempfile
import zipfile

import build_rc6_webui as rc6

ROOT = Path(__file__).resolve().parents[1]
STABLE_PROP = ROOT / "source" / "stable-v4.13.0" / "module.prop"
ACCEPTED_RC6_SHA256 = "31ed930fc222d7879e12c8f3f83516b6e4793ae995991121dfb39b8610dccdae"
STABLE_VERSION = "4.13.0"
STABLE_VERSION_CODE = "4130007"


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def zip_payload(path: Path) -> dict[str, bytes]:
    with zipfile.ZipFile(path, "r") as archive:
        return {name: archive.read(name) for name in archive.namelist()}


def verify_stable_equivalence(rc6_zip: Path, stable_zip: Path) -> None:
    rc6_payload = zip_payload(rc6_zip)
    stable_payload = zip_payload(stable_zip)
    if set(rc6_payload) != set(stable_payload):
        missing = sorted(set(rc6_payload) - set(stable_payload))
        extra = sorted(set(stable_payload) - set(rc6_payload))
        raise RuntimeError(f"stable_file_set_mismatch missing={missing} extra={extra}")

    changed = []
    for name in sorted(rc6_payload):
        if rc6_payload[name] != stable_payload[name]:
            changed.append(name)
    if changed != ["module.prop"]:
        raise RuntimeError(f"stable_unexpected_payload_change changed={changed}")

    prop = stable_payload["module.prop"].decode("utf-8")
    if f"version={STABLE_VERSION}\n" not in prop:
        raise RuntimeError("stable_version_missing")
    if f"versionCode={STABLE_VERSION_CODE}\n" not in prop:
        raise RuntimeError("stable_version_code_missing")
    if "verify-owner" in prop:
        raise RuntimeError("stable_rc_label_present")


def build(output: Path) -> None:
    if not STABLE_PROP.is_file():
        raise RuntimeError("stable_module_prop_missing")
    if shutil.which("go") is None:
        raise RuntimeError("go_missing")

    with tempfile.TemporaryDirectory(prefix="sdd-v4130-stable-") as tmp:
        work = Path(tmp)
        fetched = rc6.fetch_core(work)
        stage = rc6.stage_module(work, fetched)
        rc6.verify_stage(stage, work)

        rc6_reference = work / "accepted-rc6-reference.zip"
        rc6.run([
            sys.executable,
            str(ROOT / "tools" / "build_magisk_zip.py"),
            str(stage),
            str(rc6_reference),
        ])
        reference_sha = sha256(rc6_reference)
        if reference_sha != ACCEPTED_RC6_SHA256:
            raise RuntimeError(
                f"accepted_rc6_rebuild_mismatch expected={ACCEPTED_RC6_SHA256} actual={reference_sha}"
            )

        shutil.copy2(STABLE_PROP, stage / "module.prop")

        first = work / "stable-first.zip"
        second = work / "stable-second.zip"
        for candidate in (first, second):
            rc6.run([
                sys.executable,
                str(ROOT / "tools" / "build_magisk_zip.py"),
                str(stage),
                str(candidate),
            ])
        if first.read_bytes() != second.read_bytes():
            raise RuntimeError("stable_package_not_reproducible")

        verify_stable_equivalence(rc6_reference, first)

        output.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(first, output)
        digest = sha256(output)
        print(f"stable_version={STABLE_VERSION}")
        print(f"stable_versionCode={STABLE_VERSION_CODE}")
        print(f"accepted_rc6_sha256={ACCEPTED_RC6_SHA256}")
        print(f"webui_core_commit={rc6.TEMPLATE_COMMIT}")
        print(f"webui_core_version={rc6.CORE_VERSION}")
        print("stable_equivalence=only_module_prop_diff")
        print("delivery_core_changed=no")
        print(f"artifact={output}")
        print(f"artifact_bytes={output.stat().st_size}")
        print(f"artifact_sha256={digest}")
        print("RESULT: SDD_V4130_STABLE_BUILD_DONE outcome=success workflow_exit_code=0")


def main() -> int:
    parser = argparse.ArgumentParser(description="Build stable SSH Drop Dispatcher v4.13.0 from the accepted RC6 payload")
    parser.add_argument(
        "--output",
        type=Path,
        default=ROOT / "dist" / "ssh-drop-dispatcher-magisk-v4.13.0.zip",
    )
    args = parser.parse_args()
    try:
        build(args.output.resolve())
    except Exception as exc:
        print(f"RESULT: SDD_V4130_STABLE_BUILD_DONE outcome=fail reason={exc} workflow_exit_code=1", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
