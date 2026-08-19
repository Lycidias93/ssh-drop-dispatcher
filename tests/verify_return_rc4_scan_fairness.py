#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
BUILDER = ROOT / "tools" / "build_vnext_return_rc4.py"

spec = importlib.util.spec_from_file_location("sdd_vnext_return_rc4_builder", BUILDER)
if spec is None or spec.loader is None:
    raise RuntimeError("rc4_builder_import_failed")
rc4 = importlib.util.module_from_spec(spec)
spec.loader.exec_module(rc4)

with tempfile.TemporaryDirectory(prefix="sdd-return-rc4-fairness-") as tmp:
    stage = Path(tmp)
    (stage / "tools").mkdir(parents=True)
    shutil.copy2(ROOT / "source" / "magisk" / "service.sh", stage / "service.sh")
    shutil.copy2(ROOT / "source" / "magisk" / "tools" / "sdd-workflow.sh", stage / "tools" / "sdd-workflow.sh")

    rc4.patch_dispatcher_fairness(stage)

    service = (stage / "service.sh").read_text()
    workflow = (stage / "tools" / "sdd-workflow.sh").read_text()

    required_service = (
        "EVENT_FOLLOWUP_WORKER_LOCKDIR=$STATE_DIR/event-followup.worker",
        "EVENT_FOLLOWUP_WORKER_TS=$STATE_DIR/event-followup.worker.ts",
        "stale_event_followup_worker_removed",
        "scan_file_once(){",
        "mode=named_file",
        "named_scan lock_timeout",
        "--scan-file)",
    )
    for marker in required_service:
        if marker not in service:
            raise RuntimeError(f"service_marker_missing:{marker}")

    forbidden_service = (
        "( $SLEEP_BIN 5; /data/adb/modules/ssh_drop_dispatcher/service.sh --scan-once event_followup )",
    )
    for marker in forbidden_service:
        if marker in service:
            raise RuntimeError(f"service_old_pattern_remaining:{marker}")

    required_workflow = (
        '"$SERVICE" --scan-file "$PREFLIGHT_FILE" "cli_dispatch_file_${PREFLIGHT_ID}" "$timeout"',
        "named_file true",
    )
    for marker in required_workflow:
        if marker not in workflow:
            raise RuntimeError(f"workflow_marker_missing:{marker}")
    if "existing_queue true" in workflow:
        raise RuntimeError("workflow_existing_queue_scope_remaining")

    subprocess.run(["sh", "-n", str(stage / "service.sh")], check=True)
    subprocess.run(["sh", "-n", str(stage / "tools" / "sdd-workflow.sh")], check=True)

print("RESULT: SDD_RETURN_RC4_SCAN_FAIRNESS_FIXTURE_PASS outcome=success workflow_exit_code=0")
