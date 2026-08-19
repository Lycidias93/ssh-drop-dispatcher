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
VERSION = "4.14.0-return-rc3"
VERSION_CODE = "4140003"
TEMPLATE_COMMIT = "cb991dc8d7d982defbe5e34c5c0e0908efa9b236"
CORE_VERSION = "0.6.0"

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
    "module/webroot/index.html": "b6daebbfae9bf5d812cb16296d36457b95fe2a80",
    "module/webroot/app.js": "96d3925ad5220a92ebefa5924229074df7170893",
    "module/webroot/app.css": "81e6ad5962f006f5b00286f7a072dcc8328947dc",
    "module/webroot/observability.js": "29efbc7cf5f98d490557527a9d9b078e9a8ed616",
    "module/webroot/observability.css": "60b4c4f7db84c53dbe65b879eb108a552746306f",
    "server/cmd/webui-server/main.go": "a85315e5a44844ee1546481584c4e82b6e7db0c1",
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
            raise RuntimeError(f"core06_asset_missing:{asset}")
        if asset not in index:
            raise RuntimeError(f"core06_index_reference_missing:{asset}")
    observable = (webroot / "observability.js").read_text()
    for marker in ('const CORE_VERSION = "0.6.0"', "SENSITIVE_KEY", "dirtyScopes", "MAX_OPERATIONS"):
        if marker not in observable:
            raise RuntimeError(f"core06_observability_marker_missing:{marker}")
    app = (webroot / "app.js").read_text()
    for marker in ("actionStateSummary", "inventoryRefreshButton"):
        if marker not in app:
            raise RuntimeError(f"core06_ui_marker_missing:{marker}")
    for forbidden in ("eval(", "new Function", "window.ksu", "window.apatch"):
        if forbidden in observable or forbidden in app:
            raise RuntimeError(f"unsafe_core06_pattern:{forbidden}")


rc1.stage_module = stage_module
rc1.verify_stage = verify_stage


def build(output: Path) -> None:
    buffer = io.StringIO()
    with contextlib.redirect_stdout(buffer):
        rc1.build(output)
    rendered = buffer.getvalue().replace(
        "RESULT: SDD_VNEXT_RETURN_RC1_BUILD_DONE outcome=success workflow_exit_code=0",
        "RESULT: SDD_VNEXT_RETURN_RC3_BUILD_DONE outcome=success workflow_exit_code=0",
    )
    print(rendered, end="")


def main() -> int:
    parser = argparse.ArgumentParser(description="Build SSH Drop Dispatcher v4.14.0 Return Channel RC3 with WebUI Core 0.6")
    parser.add_argument("--output", type=Path, default=ROOT / "dist" / "ssh-drop-dispatcher-magisk-v4.14.0-return-rc3.zip")
    args = parser.parse_args()
    try:
        build(args.output.resolve())
    except Exception as exc:
        print(f"RESULT: SDD_VNEXT_RETURN_RC3_BUILD_DONE outcome=fail reason={exc} workflow_exit_code=1", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
