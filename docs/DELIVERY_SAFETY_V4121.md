# SSH Drop Dispatcher v4.12.1 delivery safety

Status: release candidate scope; rc2 adds explicit break-glass Direct-SCP.

## Purpose

`v4.12.1` is a maintenance release for delivery robustness. It does not change DNS, routes, HA/VIP, target drop paths, or the Sortify marker contract.

## Target space policy defaults

| Target | Min free | Warn free | Max artifact |
|---|---:|---:|---:|
| pi3 | 3 GiB | 5 GiB | unset |
| pi4 | 3 GiB | 5 GiB | unset |
| zeropi2 | 512 MiB | 1 GiB | 512 MiB |
| berylax | 50 MiB | 100 MiB | 20 MiB |

Upload gate:

```text
remote_available_kb >= min_free_kb + artifact_size_kb
artifact_size_kb <= max_artifact_kb if max_artifact_kb > 0
```

## New diagnostics

```text
service.sh --verify-targets
service.sh --verify-target pi4
service.sh --route-explain /storage/emulated/0/Download/target-pi4__example.txt
```

## Known delivery failure patterns

- Direct Termux SSH is not Dispatcher SSH; verification must use `ssh-config.dispatch`.
- OpenSSH post-quantum warnings must not be parsed as data.
- `su -c` may have `HOME=/` or an empty home; scripts should use fixed runtime/cache paths.
- BerylAX/OpenWrt requires legacy SCP mode through `scp_flags=-O`.
- BerylAX has a small overlay; large artifacts are blocked by target policy.
- Unprefixed handover files must not route. Remote dispatch requires `target-*__` or `targets-*__`.
- Direct SCP is break-glass only and requires explicit operator approval plus evidence.
## Break-glass Direct-SCP

`v4.12.1-delivery-safety-rc2` adds a manual break-glass upload command for cases where normal dispatcher delivery is blocked but the operator explicitly approves a controlled fallback:

```text
service.sh --breakglass-scp <file> <target>
service.sh --breakglass-status <file>
service.sh --breakglass-log-tail [lines]
```

Rules:

- Break-glass is never automatic.
- The file must be supported and must not be partial or a checksum/signature sidecar.
- The file name must use a valid `target-*__` or `targets-*__` prefix and include the explicit target.
- Target-specific space policy must pass before upload.
- Upload uses the configured dispatcher SSH config and target `scp_flags`; BerylAX keeps `-O`.
- Upload writes a temporary remote file and then performs an atomic rename.
- Remote SHA-256 must match local SHA-256.
- Evidence is appended to `/data/adb/ssh-drop-dispatcher/breakglass.log`.
- Host execution is not part of break-glass and remains a separate verify/run gate.

## rc3 delivery status/wait addendum

Portal v1.6.5 delivery anomaly handling requires a remote-first PASS path: if the local source is missing later, but dispatcher state shows done/complete and each target remote drop contains the file, orchestrators must continue instead of failing on the missing local file.

New commands:

```text
service.sh --delivery-status <file>
service.sh --wait-delivery <file> [timeout_seconds] [interval_seconds]
```

Expected recovery PASS shape:

```text
local_exists=no
dispatch_complete=yes
remote_all=yes
final_gate=PASS
recovery_mode=remote_first
host_run=no
```

This does not alter the Sortify marker policy (`v4115`), remote drop paths, DNS, HA, VIP, or routes. Optional ntfy notifications are private-runtime-only, disabled by default, and report per-target PASS/FAIL delivery outcomes without bundling secrets.
