#!/usr/bin/env python3
"""Reproducible, hash-bound V4.14.3 guarded-tool overlay; no publishing."""
import argparse
from copy import copy
import hashlib
from pathlib import Path
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "source/vnext-issue2516/service.sh"
BASE_SHA = "d81ce09f53e1372c0d03e60561ccf1f8b691a8fcd563a7ce5150b3840ef15778"
OLD_SHA = "c1a54cd7fb0ceafc973adccc195494b41ae577131e04a9ee406424f58165b583"
NEW_SHA = "76fcdf95da041170f746b7d4c0bf690988538b6407017a0c649e8962e4e73e1c"
ASSET_SHA = "1567c65101d6c55c2fdcb26b3b2cfe30d6b12c767ab35c1c26352d1d1e32465a"

def digest(data):
    return hashlib.sha256(data).hexdigest()

def require(condition, reason):
    if not condition:
        raise RuntimeError(reason)

def build(base, output):
    source = SOURCE.read_bytes()
    require(digest(source) == NEW_SHA, "candidate_source_drift")
    require(digest(base.read_bytes()) == BASE_SHA, "base_asset_drift")
    require(not output.exists(), "output_already_exists")
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=output.parent) as temp:
        first = Path(temp) / "first.zip"
        second = Path(temp) / "second.zip"
        with zipfile.ZipFile(base) as old:
            names = old.namelist()
            require(len(names) == 42 and len(set(names)) == 42 and old.testzip() is None, "baseline_integrity")
            require(digest(old.read("service.sh")) == OLD_SHA, "baseline_service")
            prop = old.read("module.prop")
            require(prop.count(b"version=4.14.2\n") == 1 and prop.count(b"versionCode=4140200\n") == 1, "baseline_version")
            prop = prop.replace(b"version=4.14.2\n", b"version=4.14.3-guarded-tools-v1\n").replace(b"versionCode=4140200\n", b"versionCode=4140300\n")
            for target in (first, second):
                with zipfile.ZipFile(target, "w") as z:
                    z.comment = old.comment
                    for info in old.infolist():
                        data = source if info.filename == "service.sh" else prop if info.filename == "module.prop" else old.read(info)
                        z.writestr(copy(info), data)
                with zipfile.ZipFile(target) as z:
                    require(z.namelist() == names and z.testzip() is None, "candidate_integrity")
                    require({n for n in names if z.read(n) != old.read(n)} == {"module.prop", "service.sh"}, "package_delta")
                    require(all(z.getinfo(n).external_attr == old.getinfo(n).external_attr for n in names), "package_modes")
        require(first.read_bytes() == second.read_bytes(), "rebuild_mismatch")
        require(digest(first.read_bytes()) == ASSET_SHA, "candidate_asset_drift")
        first.replace(output)
    print("RESULT: SDD_V4143_BUILD_PASS members=42 changed=module.prop,service.sh sha256=" + ASSET_SHA)

if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--base", required=True, type=Path)
    p.add_argument("--output", required=True, type=Path)
    args = p.parse_args()
    build(args.base, args.output)
