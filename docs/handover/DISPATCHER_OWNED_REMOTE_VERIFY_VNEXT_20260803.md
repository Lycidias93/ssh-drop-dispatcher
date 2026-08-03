# Dispatcher vNext handover: dispatcher-owned remote verification

Date: 2026-08-03
Status: implementation gate for host-wrapper retirement
Risk: medium
Source: `Lycidias93/heimnetz-geraete@main:docs/handover/dispatcher_remote_verify_wrapper_retirement_20260803.md`

## Required vNext runtime contract

The host retirement package must remain blocked until the installed runtime exposes a root-owned marker at exactly one active runtime root:

- `/data/adb/pixel-drop-dispatch/verification-owner.env`, or
- `/data/adb/ssh-drop-dispatcher/verification-owner.env` during the runtime-path migration.

Required exact fields:

```text
verify_owner=dispatcher
external_verify_wrapper=no
remote_sha_required=yes
bash_missing_fallback=fail_closed
```

The marker is installation/runtime evidence, not repository evidence. It must be generated from installed code only after runtime configuration has been migrated and linted.

## Mandatory source behavior

1. Ignore and reject legacy `verify`, `verify_cmd` and `verify_kind` keys as active wrapper selectors.
2. Declare target shells explicitly: pi3/pi4/zeropi2=`bash`, berylax=`sh`.
3. For Bash targets, missing `bash` is a hard failure; never fall back to `sh -n`.
4. For POSIX-sh targets, use `sh -n`.
5. Add interpreter-aware Python handling or remove Python delivery claims. Python must never enter shell verification.
6. After atomic rename, verify existence/non-empty, interpreter syntax and exact remote SHA-256.
7. Write done/complete/Sortify release state only after exact SHA parity.
8. Emit delivery evidence:
   - `verify_owner=dispatcher`
   - `verify_mode=bash-n|sh-n|python3|basic`
   - `external_verify_wrapper=no`
   - `remote_sha_match=yes`
   - `host_run=no`
9. Config doctor, lint, setup, migration, examples and WebUI must not require host-local wrapper paths.
10. Preserve BerylAX legacy SCP `-O`, BusyBox/POSIX constraints and no-SFTP behavior.

## Regression acceptance

Required marker:

```text
RESULT: SDD_VNEXT_DISPATCHER_VERIFY_OWNER_FIXTURES_PASS
```

Fixture matrix:

- valid/invalid Bash for pi3, pi4 and zeropi2;
- missing remote Bash fails closed;
- valid/invalid POSIX sh for berylax;
- CRLF and wrong shebang fail locally;
- mixed Bash/sh multi-target artifact fails locally;
- permitted valid/invalid Python is interpreter-aware;
- non-script existence and SHA verification;
- simulated remote SHA mismatch produces no done/complete/release marker;
- stale legacy wrapper keys cannot reactivate an external verifier;
- normal path and break-glass path produce the same verification ownership evidence.

## Host rollout package

The operational package is maintained in `Lycidias93/heimnetz-geraete`:

- `tools/dispatcher/targets-pi3-pi4-zeropi2__dispatcher-remote-verify-wrapper-retirement-v1.sh`
- `tools/dispatcher/target-berylax__dispatcher-remote-verify-wrapper-retirement-v1.sh`
- `tools/dispatcher/pixel_local__dispatcher-remote-verify-wrapper-retirement-pi3-pi4-zeropi2-berylax-v1.sh`

The controller fails closed unless the runtime marker proves all four required fields. It then performs dispatcher delivery, host preflight, root-only backup, reversible rename, remote verify, and before/after network-state comparison. Any apply failure triggers reverse-order rollback.

## Completion gate

Do not mark host retirement complete until installed runtime verification and the controller result both show:

```text
RESULT: DISPATCHER_REMOTE_VERIFY_WRAPPER_RETIREMENT_CONTROL_PASS workflow_exit_code=0
```

No DNS, HA, VIP, default route, static route, MagicDNS, subnet route, table-52 or firewall mutation is part of this change.
