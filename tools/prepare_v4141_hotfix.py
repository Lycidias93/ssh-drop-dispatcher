#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[1]
BASE_SERVICE = ROOT / "source" / "magisk" / "service.sh"
STABLE_DIR = ROOT / "source" / "stable-v4.14.1"
STABLE_SERVICE = STABLE_DIR / "service.sh"
CHANGELOG = ROOT / "CHANGELOG.md"

VULNERABLE_LINE = '      [ -f "$BUNDLE_DIR/ssh/$x" ] && $CP_BIN -f "$BUNDLE_DIR/ssh/$x" "$SSH_DIR/$x" >/dev/null 2>&1 || true'
FIXED_LINE = '      [ -f "$BUNDLE_DIR/ssh/$x" ] && { src_sig=$($CKSUM_BIN "$BUNDLE_DIR/ssh/$x" 2>/dev/null); dst_sig=""; [ -f "$SSH_DIR/$x" ] && dst_sig=$($CKSUM_BIN "$SSH_DIR/$x" 2>/dev/null); if [ -n "$src_sig" ] && [ "$src_sig" != "$dst_sig" ]; then tmp="$SSH_DIR/.$x.import.$$"; if $CP_BIN -f "$BUNDLE_DIR/ssh/$x" "$tmp" >/dev/null 2>&1 && $CHMOD_BIN 600 "$tmp" >/dev/null 2>&1 && $MV_BIN -f "$tmp" "$SSH_DIR/$x" >/dev/null 2>&1; then :; else $RM_BIN -f "$tmp" >/dev/null 2>&1 || true; log "WARN bundle_ssh_atomic_refresh_failed file=$x"; fi; fi; } || true'

CHANGELOG_ENTRY = """## v4.14.1 - 2026-08-23\n\n- Fixed intermittent SSH failures that could occur when an SSH key/config bundle refresh overlapped a connection attempt. Bundle imports now avoid rewriting unchanged files and publish changed SSH files atomically.\n\n"""


def main() -> int:
    source = BASE_SERVICE.read_text()
    vulnerable_count = source.count(VULNERABLE_LINE)
    fixed_count = source.count('bundle_ssh_atomic_refresh_failed')
    if vulnerable_count != 1 or fixed_count != 0:
        raise SystemExit(
            f"unexpected_base_service_prestate vulnerable_count={vulnerable_count} fixed_count={fixed_count}"
        )

    fixed = source.replace(VULNERABLE_LINE, FIXED_LINE, 1)
    if VULNERABLE_LINE in fixed:
        raise SystemExit("vulnerable_line_remains")
    for marker in (
        'src_sig=$($CKSUM_BIN',
        'tmp="$SSH_DIR/.$x.import.$$"',
        '$MV_BIN -f "$tmp" "$SSH_DIR/$x"',
        'bundle_ssh_atomic_refresh_failed',
    ):
        if marker not in fixed:
            raise SystemExit(f"fixed_marker_missing:{marker}")

    STABLE_DIR.mkdir(parents=True, exist_ok=True)
    STABLE_SERVICE.write_text(fixed)
    shutil.copymode(BASE_SERVICE, STABLE_SERVICE)

    changelog = CHANGELOG.read_text()
    if "## v4.14.1 - 2026-08-23" not in changelog:
        anchor = "## v4.14.0 - 2026-08-20\n"
        if changelog.count(anchor) != 1:
            raise SystemExit("changelog_anchor_mismatch")
        changelog = changelog.replace(anchor, CHANGELOG_ENTRY + anchor, 1)
        CHANGELOG.write_text(changelog)

    print("stable_service=source/stable-v4.14.1/service.sh")
    print("hotfix_delta=atomic_ssh_bundle_import")
    print("changelog=v4.14.1")
    print("RESULT: SDD_V4141_HOTFIX_PREPARE_DONE outcome=success workflow_exit_code=0")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
