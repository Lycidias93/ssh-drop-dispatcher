# RC4 WebUI fast-status Pixel preflight

Status: read-only device preflight PASS; corrected candidate is eligible for controlled install testing, but RC4 is not yet installed-runtime accepted.

## Root cause confirmed

The original RC4 WebUI status adapter called the full `sdd --json chatgpt-context` path. On Pixel this took about 13 seconds, while `module-control status` took about 17 seconds. The standalone WebUI server bounds a control call to 10 seconds, so its self-test terminated the status adapter and reported `module-control failed: signal: killed`.

This was a WebUI status-path latency failure, not a Dispatcher delivery-core failure.

## Fix

The candidate keeps the existing typed adapter as `bin/module-control-base` and installs a small `bin/module-control` front wrapper:

- only `status` is answered from local runtime snapshots (`health.env`, queue/failure/quarantine/receipt counters, configured target metadata and ntfy configured state);
- `status` performs no `chatgpt-context` or service runtime refresh;
- every non-status operation delegates to the existing typed adapter;
- Android delegation explicitly uses `/system/bin/sh` by default;
- secret/host/drop/network fields remain excluded from the status response;
- WebUI server, service/delivery core, CLI/workflow and frontend assets are unchanged.

Fast-status source head: `39c55abfb60e22b33ffd75c396265809372d85f1`
Fast-status wrapper blob: `cf7d9e1fd1e2871942b3ea885c5cb143cf3047d4`

Corrected deterministic candidate:

- bytes: `2592038`
- SHA-256: `270b9e1e07f6d0b7e536cafe1b0804a30f7e2121d65417ffd06f27966c7a7305`
- base candidate SHA-256: `d78511e289fa58ab3160e980ebd5f3b8a8474d18decce98868859413658eb201`
- delivery core blob remains `c19b1dfb315cf53e4db9d43fe069d3d56d8f6337`

## Bound Pixel preflight

Receipt:

- run_id: `20260811_103711_dispatcher-rc4-webui-fast-status-preflight_verify_pixel-dispatcher_12014_30557`
- command_exit_code: `0`
- finished_at: `2026-08-11T10:37:32+02:00`

Measured results:

- active RC4 health: OK
- candidate identity: PASS
- candidate status: 2 seconds, local snapshot
- capabilities: PASS
- config secret redaction: PASS
- Target Matrix: PASS for berylax/pi3/pi4/zeropi2 without private host/drop fields
- WebUI server self-test: PASS in 6 seconds
- isolated first run: PASS
- result-state verify: PASS
- no install/reboot/network mutation

Exact marker:

`RESULT: SDD_RC4_WEBUI_FAST_STATUS_CANDIDATE_PREFLIGHT_DONE outcome=success active=rc4 candidate=rc4 fast_status=pass status_source=local_snapshot status_elapsed_seconds=2 webui_selftest=pass target_matrix=pass delivery_core_changed=no workflow_exit_code=0`

## Remaining acceptance gate

The corrected candidate must still be installed through Magisk, rebooted/materialized, and pass the full installed-runtime verifier including WebUI action/self-test, typed inventories, target matrix, CLI/workflow/doctor/bridge and the project marker:

`RESULT: CG_INSTALLED_RUNTIME_VERIFY_DONE outcome=success workflow_exit_code=0`

Public update-channel promotion remains separate.
