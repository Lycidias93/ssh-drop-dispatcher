<!-- telegram-release-channel:start -->
> Release updates: [@lycidias93](https://t.me/lycidias93)
<!-- telegram-release-channel:end -->

# SSH Drop Dispatcher

SSH Drop Dispatcher is an Android/Magisk file-drop dispatcher for rooted devices. It watches a local Android directory, detects explicit target markers in file names, and uploads complete artifacts to configured SSH drop targets.

The public package contains no private targets, no private IP addresses, no private hostnames, no private paths, no SSH keys, and no ntfy tokens.

## Current release

| Field | Value |
|---|---|
| Public release | `4.12.6` |
| Module ID | `ssh_drop_dispatcher` |
| Runtime SoT | `/data/adb/ssh-drop-dispatcher` |
| Magisk module path | `/data/adb/modules/ssh_drop_dispatcher` |
| Default scan directory | `/storage/emulated/0/Download` |
| Sortify marker policy | `v4115` |
| Update metadata | `update.json` |

## What changed in v4.12.6

This section follows the verified-release README style from the Pixel Thermal Polling Fix repository: plain problem statement, final fix, runtime evidence, operator steps, and explicit safety boundaries.

### Problem

On some Android/FUSE download paths, the event watcher can miss a newly completed `target-*__*` or `targets-*__*` file. Before this release, such files could wait for the long fallback rescan instead of being processed promptly.

A verified rc1 smoke showed the first mitigation was not enough: the fast watchdog did trigger, but it still launched the full Download scan and old completed/collision artifacts could delay the new productive target artifact.

### Final fix

`v4.12.6` promotes the rc2 target-only watchdog after post-reboot runtime verification and latency smoke.

The fast watchdog now processes only explicit dispatcher artifacts:

```text
target-*__*
targets-*__*
```

The trigger no longer depends on a full Download scan. Logs identify the path clearly:

```text
INFO fast_target_watchdog_trigger ... mode=target_only
START scan_dir=... reason=fast_target_watchdog mode=target_only
PROCESS pass=1 file=target-...__...
INFO delivery_latency ... latency_seconds=<n>
```

### Verified final behavior

Runtime evidence from the final rc2 smoke:

```text
version=4.12.6-low-latency-rc2
versionCode=4126002
fast_target_watchdog_enabled=yes
fast_target_interval_seconds=30
latency_warn_seconds=60
automatic_delivery=PASS
measured_latency_seconds=37
last_delivery_latency_seconds=28
target_only_trigger_gate=PASS
target_only_scan_log_gate=PASS
RESULT: SDD_V4126_RC2_LATENCY_SMOKE_DONE
```

The final release keeps the same delivery logic and promotes that verified behavior as:

```text
version=4.12.6
versionCode=4126003
```

## Safety invariants

`v4.12.6` does not change these boundaries:

- No host payload execution.
- No DNS, HA, VIP, default-route, static-route, MagicDNS, or subnet-route changes.
- No target drop-path changes.
- No bundled private runtime data.
- Sortify marker policy remains `v4115`.
- Public/private boundary remains strict.

## Filename contract

Only explicit target prefixes are routed by default.

Single target:

```text
target-alpha__file.txt
```

Multiple targets:

```text
targets-alpha-beta__file.txt
```

Examples:

```text
target-pi3__inventory.sh
target-pi4__report.txt
targets-pi3-pi4__bundle.tar.gz
```

Checksum sidecars such as `*.sha256`, `*.sha256sum`, `*.md5`, `*.sig`, and `*.asc` are ignored by the dispatcher.

## Quick install

1. Download the release ZIP:

```text
ssh-drop-dispatcher-magisk-v4.12.6.zip
```

2. Install it through Magisk.
3. Reboot Android.
4. Configure your own private targets under:

```text
/data/adb/ssh-drop-dispatcher/config/targets.d
```

5. Verify runtime status:

```text
su -c /data/adb/modules/ssh_drop_dispatcher/service.sh --runtime-status
```

Expected core state:

```text
version=4.12.6
versionCode=4126003
status=OK
main_pid_ok=yes
watcher_pid_ok=yes
watchdog_pid_ok=yes
event_pending=no
fast_target_watchdog_enabled=1
fast_target_interval_seconds=30
latency_warn_seconds=60
```

## Day-to-day operation

Primary setup command after flashing and rebooting:

```text
dispatch-config
```

Fallback if the Termux command is not available yet:

```text
su -c /data/adb/ssh-drop-dispatcher/bin/dispatch-config
```

Manual dispatch trigger:

```text
su -c /data/adb/modules/ssh_drop_dispatcher/service.sh --dispatch-now
```

Runtime status:

```text
su -c /data/adb/modules/ssh_drop_dispatcher/service.sh --runtime-status
```

WebUI status:

```text
su -c /data/adb/modules/ssh_drop_dispatcher/service.sh --webui-status
```

## Low-latency configuration

Defaults:

```text
DROP_DISPATCH_FAST_TARGET_WATCHDOG=1
DROP_DISPATCH_FAST_TARGET_INTERVAL_SECONDS=30
DROP_DISPATCH_LATENCY_WARN_SECONDS=60
```

WebUI/runtime status exposes:

```text
fast_target_watchdog_enabled=yes
fast_target_interval_seconds=30
latency_warn_seconds=60
last_delivery_latency_seconds=<seconds>
```

A latency warning is diagnostic. Delivery can still succeed:

```text
WARN delivery_latency_sla_breach ... latency_seconds=<n> warn_seconds=60
```

## Duplicate and already-present behavior

`v4.12.5` duplicate-alias protection remains active in `v4.12.6`.

Expected behavior:

- Original `target-*__*` and `targets-*__*` artifacts deliver normally and emit `PASS` ntfy events with `reason: delivered`.
- Android/browser suffix aliases with the same canonical name and digest are suppressed with `INFO duplicate_alias`.
- Alias-shaped files with the same canonical name but different content emit `WARN content_changed_same_canonical_name` and are not silently uploaded.
- Sortify markers retain canonical metadata such as `canonical_name` and `duplicate_alias_guard=1`.

WebUI status includes:

```text
duplicate_alias_guard_enabled=yes
duplicate_alias_notify_records=<count>
canonical_complete_records=<count>
```

## ntfy notifications

Optional ntfy notifications are disabled by default and configured only through private runtime config:

```text
NTFY_ENABLED=1
NTFY_TOPIC=<private topic>
```

or:

```text
NTFY_ENABLED=1
NTFY_URL=<private endpoint>
```

Optional token support uses a local private file:

```text
NTFY_TOKEN_FILE=/private/local/path
```

Token contents are never displayed by WebUI status. Delivery notifications include `host_run=no`.

Expected compact PASS body:

```text
<file>
reason: delivered
policy: v4115 · host_run: no
```

## Sortify marker contract

When all selected targets are complete, SDD writes a dispatcher-authoritative marker under:

```text
/data/adb/ssh-drop-dispatcher/integration/sortify-release
```

Required contract fields include:

```text
released=yes
authority=dispatcher
policy=v4115
reason='all_targets_done'
pending_targets=''
filename
canonical_name
sha256
size
rec
targets
done_targets
```

Sortify Dispatch can use this marker to release protected artifacts without becoming the dispatcher SoT.

## Public/private boundary

This repository is the public release channel for the generic SSH Drop Dispatcher package.

Private production runtimes, private target definitions, host aliases, device inventory, SSH keys, ntfy topics, ntfy endpoints, and local configuration are maintained outside this public repository.

Do not infer private runtime state from this public repository.

## Troubleshooting

### File did not deliver immediately

Check runtime status first:

```text
su -c /data/adb/modules/ssh_drop_dispatcher/service.sh --runtime-status
```

Then check whether the fast target watchdog triggered:

```text
su -c 'grep -E "fast_target_watchdog_trigger|mode=target_only|delivery_latency|PROCESS" /data/adb/ssh-drop-dispatcher/log/dispatch.log | tail -80'
```

Healthy low-latency fallback should show:

```text
fast_target_watchdog_trigger ... mode=target_only
PROCESS pass=1 file=target-...__...
```

### File already delivered before

Look for:

```text
INFO already_present_suppressed
INFO duplicate_alias
WARN content_changed_same_canonical_name
```

These are usually dedupe/protection outcomes, not upload failures.

### Need operator-only fallback

Break-glass SCP is explicit and never automatic:

```text
service.sh --breakglass-scp <file> <target>
service.sh --breakglass-status <file>
service.sh --breakglass-log-tail [lines]
```

Break-glass still requires a valid target prefix, space policy PASS, remote digest verification, and evidence in:

```text
/data/adb/ssh-drop-dispatcher/breakglass.log
```

## Documentation

- Installation: `docs/INSTALLATION.md`
- How it works: `docs/HOW_IT_WORKS.md`
- Configuration: `docs/CONFIGURATION.md`
- Features: `docs/FEATURES.md`
- ntfy runbook: `docs/NTFY_RUNBOOK.md`
- Changelog: `CHANGELOG.md`

## License

This project is licensed under the MIT License. See [LICENSE](./LICENSE).
