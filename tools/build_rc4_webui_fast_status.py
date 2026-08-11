#!/usr/bin/env python3
from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

import build_rc4_webui as base

ROOT = Path(__file__).resolve().parents[1]
WRAPPER = ROOT / "source" / "rc4-webui" / "module-control-fast-wrapper.sh"
ORIGINAL_VERIFY = base.verify_stage


def write_fixture(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")


def verify_stage_fast_status(stage: Path, work: Path) -> None:
    ORIGINAL_VERIFY(stage, work)

    control = stage / "bin" / "module-control"
    control_base = stage / "bin" / "module-control-base"
    if not WRAPPER.is_file() or WRAPPER.stat().st_size == 0:
        raise RuntimeError("fast_status_wrapper_missing")

    shutil.copy2(control, control_base)
    shutil.copy2(WRAPPER, control)
    control.chmod(0o755)
    control_base.chmod(0o755)

    wrapper_text = control.read_text(encoding="utf-8")
    if 'status_source":"local_snapshot' not in wrapper_text:
        raise RuntimeError("fast_status_marker_missing")
    if 'backend_refresh":"none' not in wrapper_text:
        raise RuntimeError("fast_status_refresh_contract_missing")
    if 'exec "$BASE" "$@"' not in wrapper_text:
        raise RuntimeError("fast_status_delegate_missing")
    if "chatgpt-context" in wrapper_text or "run_sdd" in wrapper_text:
        raise RuntimeError("fast_status_heavy_backend_reference")
    if "eval " in wrapper_text:
        raise RuntimeError("fast_status_eval_forbidden")

    subprocess.run(["sh", "-n", str(control)], check=True)
    subprocess.run(["sh", "-n", str(control_base)], check=True)

    state = work / "fast-status-state"
    runtime = work / "fast-status-runtime"
    target_dir = state / "config" / "targets.d"
    state.mkdir()
    runtime.mkdir()
    target_dir.mkdir(parents=True)

    write_fixture(
        state / "health.env",
        "status=OK\nmain_pid_ok=yes\nwatcher_pid_ok=yes\nwatchdog_pid_ok=yes\nevent_pending=no\n",
    )
    write_fixture(
        state / "config.env",
        "NTFY_ENABLED=1\nNTFY_PRIORITY=default\nNTFY_TAGS=package\nNTFY_TOPIC=fixture\nNTFY_URL=https://example.invalid\nNTFY_TOKEN_FILE=\n",
    )
    write_fixture(target_dir / "pi3.conf", "target_name=pi3\nenabled=1\nshell=bash\n")
    write_fixture(state / "dispatch.inflight", "")
    write_fixture(state / "dispatch.faildb", "")
    write_fixture(state / "dispatch.quarantined", "fixture|target=pi3|reason=test\n")
    write_fixture(
        state / "delivery.receipts.jsonl",
        '{"deliveryId":"fixture-id","file":"fixture.sh","state":"complete","scanScope":"fixture"}\n',
    )

    env = os.environ.copy()
    env.update(
        {
            "MODULE_DIR": str(stage),
            "MODULE_STATE_DIR": str(state),
            "WEBUI_RUNTIME_DIR": str(runtime),
            "SDD_WEBUI_CONFIG_FILE": str(state / "config.env"),
            "SDD_WEBUI_TARGET_DIR": str(target_dir),
            "SDD_WEBUI_HEALTH_FILE": str(state / "health.env"),
            "SDD_WEBUI_INFLIGHT_DB": str(state / "dispatch.inflight"),
            "SDD_WEBUI_FAIL_DB": str(state / "dispatch.faildb"),
            "SDD_WEBUI_QUAR_DB": str(state / "dispatch.quarantined"),
            "SDD_WEBUI_RECEIPT_DB": str(state / "delivery.receipts.jsonl"),
        }
    )

    capability_probe = subprocess.run(
        ["sh", str(control), "capabilities"],
        env=env,
        check=True,
        text=True,
        capture_output=True,
        timeout=2,
    )
    capabilities = json.loads(capability_probe.stdout)
    if capabilities.get("schema") != "root-module-webui.capabilities.v1":
        raise RuntimeError("delegated_capability_schema_mismatch")

    config_probe = subprocess.run(
        ["sh", str(control), "config-get"],
        env=env,
        check=True,
        text=True,
        capture_output=True,
        timeout=2,
    )
    config = json.loads(config_probe.stdout)
    if config.get("ntfy_enabled") is not True:
        raise RuntimeError("delegated_config_get_failed")

    status_probe = subprocess.run(
        ["sh", str(control), "status"],
        env=env,
        check=True,
        text=True,
        capture_output=True,
        timeout=2,
    )
    status = json.loads(status_probe.stdout)
    runtime_status = status.get("runtime", {})
    if status.get("ok") is not True or runtime_status.get("status_source") != "local_snapshot":
        raise RuntimeError("fast_status_fixture_failed")
    if runtime_status.get("backend_refresh") != "none":
        raise RuntimeError("fast_status_backend_refresh_regression")
    if runtime_status.get("event_pending") != "no":
        raise RuntimeError("fast_status_health_snapshot_failed")
    if runtime_status.get("last_delivery_id") != "fixture-id":
        raise RuntimeError("fast_status_receipt_snapshot_failed")

    print("rc4_webui_status_source=local_snapshot")
    print("rc4_webui_status_backend_refresh=none")
    print("rc4_webui_status_fixture_timeout_seconds=2")
    print("RESULT: SDD_RC4_WEBUI_FAST_STATUS_VERIFY_DONE outcome=success workflow_exit_code=0")


base.verify_stage = verify_stage_fast_status

if __name__ == "__main__":
    raise SystemExit(base.main())
