#!/usr/bin/env python3
"""Regression for SDD issue #69: bounded, coalesced follow-up scheduling."""
import concurrent.futures
import os
from pathlib import Path
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
COORD = ROOT / "source/vnext-issue69/tools/sdd-followup-coalesce.sh"
SERVICE = ROOT / "source/vnext-issue69/service.sh"


class FollowupSingleflight(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="sdd-followup-")
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.state = self.root / "state"
        (self.state / "log").mkdir(parents=True)
        self.calls = self.root / "calls"
        self.fake = self.root / "fake-service.sh"
        self.fake.write_text("""#!/bin/sh
printf 'scan\\n' >> "$SDD_TEST_CALLS"
if [ -d "$SDD_FOLLOWUP_STATE_DIR/scan.lock" ]; then
  printf '1\\n' > "$SDD_FOLLOWUP_STATE_DIR/.event.pending"
  exit 0
fi
rm -f "$SDD_FOLLOWUP_STATE_DIR/.event.pending"
if [ -n "${SDD_TEST_FAIL_ONCE_FILE:-}" ] && [ -f "$SDD_TEST_FAIL_ONCE_FILE" ]; then
  rm -f "$SDD_TEST_FAIL_ONCE_FILE"
  exit 23
fi
sleep "${SDD_TEST_SCAN_DELAY:-0}"
exit 0
""")
        self.fake.chmod(0o755)
        self.env = dict(os.environ,
                        SDD_FOLLOWUP_STATE_DIR=str(self.state),
                        SDD_FOLLOWUP_SERVICE=str(self.fake),
                        SDD_FOLLOWUP_DELAY_SECONDS="1",
                        SDD_FOLLOWUP_MAX_ATTEMPTS="8",
                        SDD_TEST_CALLS=str(self.calls),
                        SDD_TEST_SCAN_DELAY="0")

    def invoke(self, mode, env=None):
        result = subprocess.run(["sh", str(COORD), mode], env=env or self.env,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                timeout=12, check=False)
        self.assertEqual(result.returncode, 0, (result.stdout, result.stderr))

    def await_condition(self, predicate, deadline=12):
        until = time.monotonic() + deadline
        while time.monotonic() < until:
            if predicate():
                return
            time.sleep(0.05)
        self.fail("timed out waiting for follow-up condition")

    def call_count(self):
        return self.calls.read_text().count("scan") if self.calls.exists() else 0

    def slot(self):
        return self.state / ".followup.worker.lock"

    def pending(self):
        return self.state / ".event.pending"

    def test_220_simultaneous_requests_single_worker(self):
        (self.state / "scan.lock").mkdir()
        with concurrent.futures.ThreadPoolExecutor(max_workers=32) as pool:
            list(pool.map(self.invoke, ["request"] * 220))
        self.assertTrue(self.pending().exists())
        self.assertTrue(self.slot().exists())
        log = (self.state / "log/dispatch.log").read_text()
        self.assertEqual(log.count("followup_reserved"), 1, log)
        (self.state / "scan.lock").rmdir()
        self.await_condition(lambda: self.call_count() == 1 and not self.slot().exists())
        self.assertFalse(self.pending().exists())
        self.assertEqual(self.call_count(), 1)

    def test_bounded_retry_keeps_pending_until_watchdog(self):
        env = dict(self.env, SDD_FOLLOWUP_MAX_ATTEMPTS="2")
        (self.state / "scan.lock").mkdir()
        self.invoke("request", env)
        self.await_condition(lambda: not self.slot().exists(), deadline=5)
        self.assertTrue(self.pending().exists())
        self.assertEqual(self.call_count(), 0)
        (self.state / "scan.lock").rmdir()
        self.invoke("reconcile", env)
        self.await_condition(lambda: self.call_count() == 1 and not self.slot().exists())
        self.assertFalse(self.pending().exists())

    def test_stale_slot_recovery(self):
        self.pending().write_text("1\\n")
        self.slot().mkdir()
        (self.slot() / "pid").write_text("99999999\\n")
        (self.slot() / "created_at").write_text(str(int(time.time()) - 130))
        self.invoke("reconcile")
        self.await_condition(lambda: self.call_count() == 1 and not self.slot().exists())
        self.assertFalse(self.pending().exists())
        self.assertIn("followup_orphan_recovered",
                      (self.state / "log/dispatch.log").read_text())

    def test_event_arrives_while_followup_scan_running(self):
        env = dict(self.env, SDD_TEST_SCAN_DELAY="2")
        self.invoke("request", env)
        self.await_condition(lambda: self.call_count() >= 1)
        self.invoke("request", env)
        self.await_condition(lambda: self.call_count() >= 2, deadline=8)
        self.await_condition(lambda: not self.slot().exists(), deadline=8)
        self.assertFalse(self.pending().exists())
        self.assertEqual(self.call_count(), 2)

    def test_nonzero_scan_retries_without_lost_wakeup(self):
        fail_marker = self.root / "fail_once"
        fail_marker.write_text("1")
        env = dict(self.env, SDD_TEST_FAIL_ONCE_FILE=str(fail_marker))
        self.invoke("request", env)
        self.await_condition(lambda: self.call_count() >= 2, deadline=8)
        self.await_condition(lambda: not self.slot().exists(), deadline=8)
        self.assertEqual(self.call_count(), 2)
        self.assertFalse(self.pending().exists())
        self.assertIn("retry_preserved=yes", (self.state / "log/dispatch.log").read_text())

    def test_scan_lock_stale_guard_preserves_live_owner(self):
        import time as _time
        lock = self.state / "scan.lock"
        lock.mkdir()
        timestamp = self.state / "scan.lock.ts"
        timestamp.write_text(str(int(_time.time()) - 3600))
        owner = lock / "owner.pid"
        owner.write_text(str(os.getpid()))
        inflight = self.state / "dispatch.inflight"
        inflight.write_text("orphaned|target\\n")
        source = SERVICE.read_text()
        guard = "stale_lock_guard(){" + source.split("stale_lock_guard(){", 1)[1].split("\n}\n", 1)[0] + "\n}"
        script = "\n".join((
            "SCAN_LOCKDIR=$SDD_TEST_SCAN_LOCKDIR",
            "SCAN_LOCK_TS=$SDD_TEST_SCAN_LOCK_TS",
            "INFLIGHT_DB=$SDD_TEST_INFLIGHT_DB",
            "DATE_BIN=date; CAT_BIN=cat; MV_BIN=mv; RM_BIN=rm",
            "log(){ :; }",
            "pid_alive(){ kill -0 \"$1\" 2>/dev/null; }",
            guard,
            "stale_lock_guard",
        ))
        env = dict(self.env, SDD_TEST_SCAN_LOCKDIR=str(lock),
                   SDD_TEST_SCAN_LOCK_TS=str(timestamp),
                   SDD_TEST_INFLIGHT_DB=str(inflight),
                   DROP_DISPATCH_STALE_LOCK_SECONDS="10")
        subprocess.run(["sh", "-c", script], env=env, check=True, timeout=5)
        self.assertTrue(lock.exists(), "live scan owner must not be evicted")
        self.assertEqual(inflight.read_text(), "orphaned|target\\n",
                         "active scan inflight must remain untouched")
        owner.write_text("99999999")
        blocked_env = dict(env, SDD_TEST_INFLIGHT_DB=str(self.root / "missing" / "dispatch.inflight"))
        blocked = subprocess.run(["sh", "-c", script], env=blocked_env,
                                 check=False, timeout=5, capture_output=True)
        self.assertNotEqual(blocked.returncode, 0)
        self.assertTrue(lock.exists(), "failed inflight recovery must retain the stale lock")
        subprocess.run(["sh", "-c", script], env=env, check=True, timeout=5)
        self.assertFalse(lock.exists(), "orphaned scan lock should be released")
        self.assertFalse(timestamp.exists())
        self.assertEqual(inflight.read_text(), "",
                         "dead scanner reservations must be reconciled for retry")

    def test_hotfix_ci_checks_extracted_files_without_sigpipe(self):
        workflow = (ROOT / '.github/workflows/v4142-hotfix.yml').read_text()
        self.assertNotIn('unzip -p "$zip" service.sh | grep', workflow)
        self.assertNotIn('unzip -Z1 "$zip" | grep', workflow)
        self.assertIn('unzip -p "$zip" service.sh > /tmp/sdd-v4142-verify/service.sh', workflow)
        self.assertIn("grep -Fq 'scan_lock_old_but_owner_alive' /tmp/sdd-v4142-verify/service.sh", workflow)

    def test_production_integration(self):
        source = SERVICE.read_text()
        self.assertIn("sdd-followup-coalesce.sh", source)
        self.assertIn('"$FOLLOWUP_COORDINATOR" reconcile', source)
        self.assertIn('/tools/sdd-followup-coalesce.sh request >/dev/null 2>&1 &', source)
        self.assertNotIn('--scan-once inotify_event', source)
        self.assertEqual(source.count('> "$SCAN_LOCKDIR/owner.pid"'), 2)
        self.assertEqual(source.count("trap 'scan_lock_release' 0"), 2)
        self.assertNotIn("( $SLEEP_BIN 5; /data/adb/modules/ssh_drop_dispatcher/service.sh", source)


if __name__ == "__main__":
    unittest.main(verbosity=2)
