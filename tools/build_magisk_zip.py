#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import os
from pathlib import Path
import stat
import sys
import zipfile

FIXED_TIME = (1980, 1, 1, 0, 0, 0)


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def mode_for(path: Path) -> int:
    mode = path.stat().st_mode
    if path.suffix == ".sh" or path.name in {"service.sh", "customize.sh", "action.sh", "manual-scan.sh"}:
        return 0o755
    if mode & stat.S_IXUSR:
        return 0o755
    return 0o644


def iter_files(root: Path):
    for path in sorted(root.rglob("*"), key=lambda p: p.as_posix()):
        if path.is_symlink():
            raise RuntimeError(f"symlink_not_supported:{path.relative_to(root)}")
        if path.is_file():
            yield path


def build(root: Path, output: Path) -> tuple[int, str]:
    if not root.is_dir():
        raise RuntimeError(f"module_root_missing:{root}")
    if not (root / "module.prop").is_file():
        raise RuntimeError("module_prop_missing")
    if not (root / "customize.sh").is_file():
        raise RuntimeError("customize_missing")
    if not (root / "service.sh").is_file():
        raise RuntimeError("service_missing")

    output.parent.mkdir(parents=True, exist_ok=True)
    tmp = output.with_suffix(output.suffix + ".tmp")
    tmp.unlink(missing_ok=True)

    count = 0
    with zipfile.ZipFile(tmp, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as zf:
        for path in iter_files(root):
            rel = path.relative_to(root).as_posix()
            data = path.read_bytes()
            info = zipfile.ZipInfo(rel, FIXED_TIME)
            info.create_system = 3
            info.external_attr = (mode_for(path) & 0xFFFF) << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            info.flag_bits |= 0x800
            zf.writestr(info, data, compress_type=zipfile.ZIP_DEFLATED, compresslevel=9)
            count += 1

    os.replace(tmp, output)
    digest = sha256(output)
    return count, digest


def main() -> int:
    parser = argparse.ArgumentParser(description="Build a deterministic SSH Drop Dispatcher Magisk ZIP")
    parser.add_argument("module_root", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()

    try:
        count, digest = build(args.module_root.resolve(), args.output.resolve())
    except Exception as exc:
        print(f"build_magisk_zip=FAIL reason={exc}", file=sys.stderr)
        return 1

    print("build_magisk_zip=PASS")
    print(f"file_count={count}")
    print(f"output={args.output.resolve()}")
    print(f"sha256={digest}")
    print("RESULT: SDD_MAGISK_ZIP_BUILD_DONE outcome=success exit_code=0")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
