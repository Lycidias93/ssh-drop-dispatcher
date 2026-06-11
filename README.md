<!-- SDD_V4120_WEBUI_CONTROL_START -->
## SSH Drop Dispatcher 4.12.0-webui-control-rc1 - WebUI control candidate

This vNext candidate adds a small public control surface for day-to-day operation:

- Enable/disable dispatcher from WebUI using `DROP_DISPATCH_ENABLED=0|1`.
- Trigger `Dispatch now` without waiting for inotify/fallback scan.
- Show runtime status, target matrix, Sortify marker state and bounded log tail.
- Run doctor, create redacted issue bundle and requeue a selected file.
- Keep the stable Sortify marker contract unchanged: `policy=v4115`, `authority=dispatcher`, `released=yes`, matching SHA/size and empty `pending_targets`.

Scope guard:

- No DNS, HA, VIP or route changes.
- No host drop-path changes.
- No Sortify Dispatch contract change.
- No automatic private key export.

<!-- SDD_V4120_WEBUI_CONTROL_END -->

<!-- SDD_SORTIFY_CROSS_REPO_LINK_20260601_START -->
## Companion: Sortify Dispatch

SSH Drop Dispatcher pairs with [Sortify Dispatch](https://github.com/Lycidias93/Sortify-Dispatch), the optional local sorter/protection module for Android downloads.

- SSH Drop Dispatcher routes `target-*__*` and `targets-*__*` artifacts to SSH targets.
- Sortify Dispatch keeps those artifacts in `/sdcard/Download` until this dispatcher writes a valid `policy=v4115` release marker.
- Pixel-local, Termux and repo helper artifacts are intentionally outside the dispatcher release marker contract.

<!-- SDD_SORTIFY_CROSS_REPO_LINK_20260601_END -->

<!-- SDD_V4110_FINAL_PUBLIC_RELEASE_20260531_START -->
## v4.11.0 final public release

SSH Drop Dispatcher v4.11.0 is the public final release promoted from the fully verified rc7 line.

Primary setup command after flashing and rebooting:

```sh
dispatch-config
```

Fallback if the Termux command is not available yet:

```sh
su -c /data/adb/ssh-drop-dispatcher/bin/dispatch-config
```

Included in this release:

- `dispatch-config` interactive wizard
- Termux command install/remove/repair support
- config backup/export ZIP and restore/import ZIP
- optional private SSH key export/import with explicit confirmation
- import helper for an existing private runtime into the public runtime
- registry-based filename routing
- Sortify release marker contract with `policy=v4115`
- reset to public default config
- redacted support export
- WebUI files for WebUI-capable managers plus Magisk action button fallback
- Magisk online update metadata through `update.json`

Public/private boundary:

- Public release contains no private targets, no private IPs, no private paths and no private SSH keys.
- Private configs may be imported locally by the owner through the wizard, but are never bundled in the public ZIP.
<!-- SDD_V4110_FINAL_PUBLIC_RELEASE_20260531_END -->

<!-- SDD_V4110_RC1_WIZARD_WEBUI_START -->
## HISTORICAL - v4.11.0 public RC notes

SSH Drop Dispatcher v4.11.0 RC notes are retained for history.

Primary setup command after flashing and rebooting:

```sh
dispatch-config
```

Fallback if the Termux command is not available yet:

```sh
su -c /data/adb/ssh-drop-dispatcher/bin/dispatch-config
```

Included in this RC line:

- `dispatch-config` interactive wizard
- Termux command install/remove/repair support
- config backup/export ZIP and restore/import ZIP
- optional private SSH key export/import with explicit confirmation
- import helper for an existing private runtime into the public runtime
- reset to public default config
- redacted `xda/GitHub issue.txt` support export
- WebUI files for WebUI-capable managers plus Magisk action button fallback
- Magisk online RC update metadata through `update-rc.json`

Public/private boundary:

- Public release contains no private targets, no private IPs, no private paths and no private SSH keys.
- Private configs may be imported locally by the owner through the wizard, but are never bundled in the public ZIP.
<!-- SDD_V4110_RC1_WIZARD_WEBUI_END -->

# SSH Drop Dispatcher

SSH Drop Dispatcher is an Android/Magisk file-drop dispatcher that routes files to configured SSH targets based on filename markers.

Status:
Public release: 4.11.0

What it does:
- Watches a local Android drop directory
- Detects target markers in filenames
- Uploads files to configured SSH targets
- Tracks dispatch state
- Provides runtime health checks
- Supports manual scans and config listing

Filename format:
- Single target: target-alpha__file.txt
- Multi target: targets-alpha-beta__file.txt

Requirements:
- Rooted Android device
- Magisk
- Termux
- SSH client
- SSH access to your own target hosts

Configuration:
This public release does not include private target definitions.
Add your own SSH targets before use.
Keep private hostnames, IP addresses and SSH keys outside public releases.

Online update channel:
https://raw.githubusercontent.com/Lycidias93/ssh-drop-dispatcher/main/update.json

Privacy:
The public package must not include personal hostnames, private IPs, private paths, SSH keys, or device inventory.

Credits:
- SSH Drop Dispatcher Contributors
- Android, Magisk, Termux and XDA communities

## Public/private boundary

This repository is the public release channel for the generic SSH Drop Dispatcher package.
Private production runtimes, private target definitions, host aliases, device inventory and local configuration are maintained outside this public repository.
Do not infer private runtime state from this public repository.

## Documentation

- Installation: docs/INSTALLATION.md
- How it works: docs/HOW_IT_WORKS.md
- Configuration: docs/CONFIGURATION.md
- Features: docs/FEATURES.md
- XDA draft: XDA_PUBLIC_RC_DRAFT.md
## Quick install

1. Download ssh-drop-dispatcher-magisk-v4.11.0.zip from the release.
2. Install it through Magisk.
3. Reboot Android.
4. Configure your own target files under /data/adb/ssh-drop-dispatcher/config/targets.d.
5. Verify with service.sh --runtime-status and service.sh --doctor.
## Features

- Filename-based SSH target routing
- Single-target and multi-target dispatch
- Magisk boot service
- Runtime health status
- Doctor and config-list commands
- Target registry through config files
- Dispatch state tracking
- Duplicate processing protection
- Manual and event-based scans
- No bundled private target definitions


## Factory reset and private-runtime migration

The public package does not ship private targets, private paths or SSH keys.
For an existing private Pixel Drop Dispatcher installation, use `dispatch-config` and choose `Export existing private runtime ZIP` before replacing the private module.
The export can include public SSH material by default and private SSH keys only after an explicit typed confirmation.

## Interactive setup

After installing and rebooting, run:

su -c "/data/adb/modules/ssh_drop_dispatcher/service.sh --setup-target"

The wizard creates an SSH key, configures an SSH alias, creates a dispatcher target config, prepares the remote drop directory and runs a smoke test.

## Initial setup

After installing and rebooting, run:

su -c "/data/adb/modules/ssh_drop_dispatcher/service.sh --setup"

The initial setup wizard asks for the local scan directory. The default is:

/storage/emulated/0/Download

You can keep the default or choose a different local directory. The wizard writes the selected path to:

/data/adb/ssh-drop-dispatcher/config.env

After that, the wizard can start the SSH target setup.

## Non-interactive private runtime export

For scripted migration from a private Pixel Drop Dispatcher runtime, the public wizard supports an explicit environment-gated export:

```sh
SDD_EXPORT_INCLUDE_PRIVATE_KEYS=yes SDD_EXPORT_PRIVATE_KEYS_CONFIRM=INCLUDE-PRIVATE-KEYS dispatch-config export-private-runtime
```

The resulting ZIP must be treated as sensitive when private keys are included.

## v4.11.0-rc4
- Fixes prompt-safe private-runtime export so confirmed private SSH keys are included in export ZIPs.

## 4.11.0-rc7 - Registry routing and Sortify marker contract
- Routes file names through the imported target registry instead of hard-coded sample targets.
- Adds a Sortify release marker directory and writes completion markers after all selected targets finish.
- Keeps prompt-safe private-runtime export behavior from rc4.
- Public defaults remain generic and contain no private targets, paths, IPs or keys.

## License

This project is licensed under the MIT License. See [LICENSE](./LICENSE).

### v4.12.0 WebUI control rc2

The rc2 candidate keeps the WebUI control work and adds stricter dispatch safety: only `target-*__*` and `targets-*__*` names are routed by default, checksum sidecars such as `*.sha256` are ignored, and target configs can set `scp_flags`. BerylAX uses legacy SCP mode (`-O`) for Dropbear/OpenWrt compatibility. Sortify marker policy remains `v4115`; DNS/HA/VIP/route and host drop paths are unchanged.

<!-- SDD_V4120_FINAL_README_START -->
## SSH Drop Dispatcher v4.12.0 final

`v4.12.0` promotes the WebUI control candidate after rc2 runtime smoke passed on Pixel/Magisk.

Included:

- WebUI and CLI enable/disable controls.
- Bounded `dispatch-now` / `scan-now` trigger.
- Strict `target-*__` / `targets-*__` routing; unprefixed handover/local files are ignored.
- Queue ignore for sidecars such as `*.sha256`.
- Per-target SCP flags with BerylAX/OpenWrt Dropbear legacy-SCP fallback `-O`.
- Sortify marker contract remains dispatcher-authoritative with policy `v4115`.

Known verification notes:

- Use the dispatcher SSH config for validation: `/data/adb/ssh-drop-dispatcher/ssh/ssh-config.dispatch`.
- Do not validate dispatcher delivery with plain Termux `ssh pi4` / `ssh berylax` unless that exact key context is known.
- OpenSSH post-quantum warnings can appear before command output; log parsers must filter for digest lines.
- Root `su -c` may not provide a writable `HOME`; use explicit temp paths.
<!-- SDD_V4120_FINAL_README_END -->

## v4.12.1 delivery safety candidate

The v4.12.1 candidate adds target-specific delivery safety checks and on-device diagnostics:

- `--verify-targets` / `--verify-target <target>` for SSH, drop path and space policy checks.
- `--route-explain <file>` for prefix, target and dispatch-state diagnostics.
- Remote free-space gates before upload.
- BerylAX-specific defaults: 50 MiB minimum free space, 100 MiB warning, 20 MiB max artifact size.
- Sortify marker policy remains `v4115`.

### v4.12.1 rc2 break-glass Direct-SCP

The rc2 candidate adds an explicit operator-only fallback command:

```text
service.sh --breakglass-scp <file> <target>
service.sh --breakglass-status <file>
service.sh --breakglass-log-tail [lines]
```

Break-glass is never automatic. It requires a valid target prefix, target-specific space policy PASS, remote SHA-256 match and evidence in `/data/adb/ssh-drop-dispatcher/breakglass.log`. Host execution remains a separate gated step.

## v4.12.1 rc3 delivery status/wait diagnostics

The rc3 candidate adds remote-first delivery diagnostics and optional ntfy delivery notifications for orchestrators that need to continue after the local Download source has already disappeared but dispatcher state and remote drops prove delivery completion.

Commands:

```text
service.sh --delivery-status <file>
service.sh --wait-delivery <file> [timeout_seconds] [interval_seconds]
```

`--delivery-status` reports local existence, route targets, dispatcher done/complete records, Sortify marker references, remote target existence/digests, `recovery_mode`, `final_gate`, and `host_run=no`.

`--wait-delivery` repeats that status with heartbeat output until `final_gate=PASS` or timeout. It does not execute remote host payloads and does not change DNS, HA, VIP, routes, or target drop paths.

Optional ntfy notifications are disabled by default and configured only through private runtime config: `NTFY_ENABLED=1` plus `NTFY_URL` or `NTFY_TOPIC`; optional `NTFY_TOKEN_FILE` may point at a local private token file. Notifications are emitted per target for `PASS` or `FAIL` delivery events and include `host_run=no`.
