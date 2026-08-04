# SSH Drop Dispatcher vNext Implementation Status

Roadmap: `docs/VNEXT_ROADMAP.md`

## Program status

- Stable installed runtime baseline: `4.12.6` / `4126003`.
- Dispatcher-owned remote verification candidate: `4.13.0-verify-owner-rc1` / `4130001`.
- Candidate source and static fixtures: **implemented**.
- Pixel installed-runtime verification: **pending**.
- pi3/pi4/zeropi2/BerylAX target-wrapper retirement: **blocked until installed-runtime verification passes**.

## Dispatcher-owned remote verification candidate

The candidate removes the dispatcher dependency on target-local verification wrappers.

Implemented behavior:

- target profiles containing `verify`, `verify_cmd`, `verify_kind`, or `shell_kind` are migrated with timestamped backups;
- every enabled target receives an explicit `shell="bash|sh"` field;
- Bash targets use `bash -n` and fail closed when Bash is unavailable;
- POSIX-shell targets use `sh -n`;
- no Bash-to-`sh -n` fallback exists;
- local and remote SHA-256 must match before `record_done`;
- completion state, success notifications and Sortify markers remain downstream of the SHA gate;
- BerylAX retains `scp -O` compatibility;
- uploaded payloads are not executed;
- Python delivery remains intentionally unsupported.

Runtime ownership marker:

```text
/data/adb/ssh-drop-dispatcher/verification-owner.env
```

Required fields:

```text
verify_owner=dispatcher
external_verify_wrapper=no
remote_sha_required=yes
bash_missing_fallback=fail_closed
python_delivery=unsupported
```

Fixture marker:

```text
RESULT: SDD_VNEXT_DISPATCHER_VERIFY_OWNER_FIXTURES_PASS version=4.13.0-verify-owner-rc1
```

Candidate artifact:

```text
dist/ssh-drop-dispatcher-magisk-v4.13.0-verify-owner-rc1.zip
```

## Installation acceptance gate

The candidate is not accepted as live runtime until Pixel evidence shows all of the following:

- module version `4.13.0-verify-owner-rc1` / `4130001`;
- `verification_owner_marker_exists=yes`;
- exact ownership marker fields;
- `--config-lint` passes;
- pi3, pi4 and zeropi2 show `shell=bash`;
- BerylAX shows `shell=sh` and `scp_flags=-O`;
- no target config contains a legacy verify key;
- a delivery fixture records `remote_sha_match=yes` before `record_done`;
- a missing-Bash fixture fails without falling back to `sh -n`;
- no host payload execution occurs.

Only after this gate passes may the separate wrapper-retirement controller disable the target-local wrappers.

## Safety boundaries

- Existing target-local wrappers remain unchanged until the installed candidate proves ownership.
- Sortify marker policy remains `v4115`.
- No DNS, HA, VIP, default-route, static-route, MagicDNS or subnet-route change is part of this work.
- Stable update metadata is not promoted by this candidate step.
- No public release or final tag is implied by the RC artifact.
