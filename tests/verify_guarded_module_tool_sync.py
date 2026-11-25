#!/usr/bin/env python3
"""Isolated regression tests for module-owned tool synchronization."""
import concurrent.futures
import os
from pathlib import Path
import subprocess
import tempfile
import threading
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "source/vnext-issue2516/service.sh"
HELPER = SOURCE.read_text().split("sync_module_tool(){", 1)[1].split("\n}\n", 1)[0]
SCRIPT = """set -eu
CP_BIN=cp
CMP_BIN=cmp
STAT_BIN=stat
CHMOD_BIN=chmod
MKTEMP_BIN=mktemp
MV_BIN=mv
RM_BIN=rm
sync_module_tool(){""" + HELPER + """
}
case "$1" in
  normal) ;;
  cmp_missing) CMP_BIN=/nonexistent ;;
  cp_fail) CP_BIN=false ;;
  mv_fail) MV_BIN=false ;;
esac
sync_module_tool "$2" "$3"
"""


class GuardedToolSync(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="sdd-sync-")
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.src = self.root / "module.sh"
        self.dst = self.root / "runtime.sh"
        self.src.write_bytes(b"new content\n" * 4096)
        self.runner = self.root / "helper.sh"
        self.runner.write_text(SCRIPT)

    def invoke(self, mode="normal"):
        return subprocess.run(["sh", str(self.runner), mode, str(self.src), str(self.dst)],
                              capture_output=True, timeout=15).returncode

    def assert_clean(self):
        self.assertEqual(list(self.root.glob("runtime.sh.sync.*")), [])

    def test_missing_identical_mode_drift_content_drift(self):
        self.assertEqual(self.invoke(), 0)
        self.assertEqual(self.dst.read_bytes(), self.src.read_bytes())
        self.assertEqual(self.dst.stat().st_mode & 0o777, 0o755)
        orig = self.dst.stat()
        self.assertEqual(self.invoke(), 0)
        self.assertEqual((orig.st_ino, orig.st_mtime_ns),
                         (self.dst.stat().st_ino, self.dst.stat().st_mtime_ns))
        self.dst.chmod(0o600)
        self.assertEqual(self.invoke(), 0)
        self.assertEqual(self.dst.stat().st_mode & 0o777, 0o755)
        self.dst.write_text("drift")
        self.assertEqual(self.invoke(), 0)
        self.assertEqual(self.dst.read_bytes(), self.src.read_bytes())
        self.assert_clean()

    def test_symlink_rejected_without_touching_referent(self):
        victim = self.root / "victim"
        victim.write_text("preserve")
        self.dst.symlink_to(victim)
        self.assertNotEqual(self.invoke(), 0)
        self.assertTrue(self.dst.is_symlink())
        self.assertEqual(victim.read_text(), "preserve")
        self.assert_clean()

    def test_directory_rejected(self):
        self.dst.mkdir()
        self.assertNotEqual(self.invoke(), 0)
        self.assertTrue(self.dst.is_dir())
        self.assert_clean()

    def test_copy_failure_and_rename_failure_preserve_old(self):
        self.dst.write_text("old")
        for mode in ("cp_fail", "mv_fail"):
            self.assertNotEqual(self.invoke(mode), 0)
            self.assertEqual(self.dst.read_text(), "old")
            self.assert_clean()

    def test_unavailable_comparator_falls_back(self):
        self.dst.write_text("old")
        self.assertEqual(self.invoke("cmp_missing"), 0)
        self.assertEqual(self.dst.read_bytes(), self.src.read_bytes())
        self.assert_clean()

    def test_concurrent_readers_and_writers(self):
        old = b"old content\n" * 4096
        new = self.src.read_bytes()
        self.dst.write_bytes(old)
        stop = threading.Event()
        unexpected = []
        def reader():
            while not stop.is_set():
                try:
                    content = self.dst.read_bytes()
                    if content not in (old, new):
                        unexpected.append(len(content))
                        break
                except FileNotFoundError:
                    unexpected.append("missing")
                    break
        t = threading.Thread(target=reader)
        t.start()
        try:
            with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
                self.assertEqual(list(pool.map(lambda _: self.invoke(), range(24))), [0]*24)
        finally:
            stop.set()
            t.join()
        self.assertEqual(unexpected, [])
        self.assertEqual(self.dst.read_bytes(), new)
        self.assert_clean()

if __name__ == "__main__":
    unittest.main()
