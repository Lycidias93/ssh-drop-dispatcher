# SSH Drop Dispatcher v4.12.1 delivery safety

Status: release candidate scope.

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
