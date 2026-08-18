#!/usr/bin/env python3
from __future__ import annotations

import argparse
import contextlib
import importlib.util
import io
from pathlib import Path
import shutil
import sys

ROOT = Path(__file__).resolve().parents[1]
RC1_BUILDER = ROOT / "tools" / "build_vnext_return.py"
VERSION = "4.14.0-return-rc2"
VERSION_CODE = "4140002"
TEMPLATE_COMMIT = "a365fea5049a1daa6e674eab27f81b0ebf4c878a"
CORE_VERSION = "0.5.0"

spec = importlib.util.spec_from_file_location("sdd_vnext_return_rc1_builder", RC1_BUILDER)
if spec is None or spec.loader is None:
    raise RuntimeError("rc1_builder_import_failed")
rc1 = importlib.util.module_from_spec(spec)
spec.loader.exec_module(rc1)

rc1.VERSION = VERSION
rc1.VERSION_CODE = VERSION_CODE
rc1.TEMPLATE_COMMIT = TEMPLATE_COMMIT
rc1.CORE_VERSION = CORE_VERSION
rc1.BASE_URL = f"https://raw.githubusercontent.com/Lycidias93/android-root-module-webui-template/{TEMPLATE_COMMIT}"
rc1.CORE_FILES = dict(rc1.CORE_FILES)
rc1.CORE_FILES.update({
    "module/webroot/index.html": "792d4c3038d3ccadf8212f7dc477b8b6c666cc59",
    "module/webroot/observability.js": "81d516c9d9a60431bce0ced7d1e173bc5831b4e0",
    "module/webroot/observability.css": "60b4c4f7db84c53dbe65b879eb108a552746306f",
})

_rc1_stage_module = rc1.stage_module
_rc1_verify_stage = rc1.verify_stage


def replace_line(text: str, prefix: str, replacement: str) -> str:
    lines = text.splitlines()
    matches = [i for i, line in enumerate(lines) if line.startswith(prefix)]
    if len(matches) != 1:
        raise RuntimeError(f"module_prop_anchor_mismatch prefix={prefix} count={len(matches)}")
    lines[matches[0]] = replacement
    return "\n".join(lines) + "\n"


def stage_module(work: Path, fetched: dict[str, Path]) -> Path:
    stage = _rc1_stage_module(work, fetched)
    prop = stage / "module.prop"
    text = prop.read_text()
    text = replace_line(text, "version=", f"version={VERSION}")
    text = replace_line(text, "versionCode=", f"versionCode={VERSION_CODE}")
    prop.write_text(text)

    webroot = stage / "webroot"
    for name in ("observability.js", "observability.css"):
        shutil.copy2(fetched[f"module/webroot/{name}"], webroot / name)
    return stage


def verify_stage(stage: Path, work: Path) -> None:
    _rc1_verify_stage(stage, work)
    webroot = stage / "webroot"
    index = (webroot / "index.html").read_text()
    for asset in ("observability.js", "observability.css"):
        path = webroot / asset
        if not path.is_file() or path.stat().st_size == 0:
            raise RuntimeError(f"core05_asset_missing:{asset}")
        if asset not in index:
            raise RuntimeError(f"core05_index_reference_missing:{asset}")
    observable = (webroot / "observability.js").read_text()
    for marker in ('const CORE_VERSION = "0.5.0"', "SENSITIVE_KEY", "dirtyScopes", "MAX_OPERATIONS"):
        if marker not in observable:
            raise RuntimeError(f"core05_observability_marker_missing:{marker}")
    for forbidden in ("eval(", "new Function", "window.ksu", "window.apatch"):
        if forbidden in observable:
            raise RuntimeError(f"unsafe_core05_pattern:{forbidden}")


rc1.stage_module = stage_module
rc1.verify_stage = verify_stage


def build(output: Path) -> None:
    buffer = io.StringIO()
    with contextlib.redirect_stdout(buffer):
        rc1.build(output)
    rendered = buffer.getvalue().replace(
        "RESULT: SDD_VNEXT_RETURN_RC1_BUILD_DONE outcome=success workflow_exit_code=0",
        "RESULT: SDD_VNEXT_RETURN_RC2_BUILD_DONE outcome=success workflow_exit_code=0",
    )
    print(rendered, end="")


def main() -> int:
    parser = argparse.ArgumentParser(description="Build SSH Drop Dispatcher v4.14.0 Return Channel RC2 with WebUI Core 0.5")
    parser.add_argument("--output", type=Path, default=ROOT / "dist" / "ssh-drop-dispatcher-magisk-v4.14.0-return-rc2.zip")
    args = parser.parse_args()
    try:
        build(args.output.resolve())
    except Exception as exc:
        print(f"RESULT: SDD_VNEXT_RETURN_RC2_BUILD_DONE outcome=fail reason={exc} workflow_exit_code=1", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
