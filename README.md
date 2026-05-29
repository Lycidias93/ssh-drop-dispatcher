<!-- SDD_V4110_RC1_WIZARD_WEBUI_START -->
## v4.11.0-rc4 public vNext

SSH Drop Dispatcher v4.11.0-rc4 is the public-safe vNext line maintained by Lycidias93.

Primary setup command after flashing and rebooting:

```sh
dispatch-config
```

Fallback if the Termux command is not available yet:

```sh
su -c /data/adb/ssh-drop-dispatcher/bin/dispatch-config
```

Included in this RC:

- `dispatch-config` interactive wizard
- Termux command install/remove/repair support
- config backup/export ZIP and restore/import ZIP
- optional private SSH key export/import with explicit confirmation
- import helper for an existing private runtime into the public runtime
- reset to public default config
- redacted `xda/GitHub issue.txt` support export
- WebUI files for WebUI-capable managers plus Magisk action button fallback
- Magisk online update metadata through `update-rc.json`

Public/private boundary:

- Public release contains no private targets, no private IPs, no private paths and no private SSH keys.
- Private configs may be imported locally by the owner through the wizard, but are never bundled in the public ZIP.
<!-- SDD_V4110_RC1_WIZARD_WEBUI_END -->

# SSH Drop Dispatcher

SSH Drop Dispatcher is an Android/Magisk file-drop dispatcher that routes files to configured SSH targets based on filename markers.

Status:
Public release candidate: 4.11.0-rc4

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
This public RC does not include private target definitions.
Add your own SSH targets before use.
Keep private hostnames, IP addresses and SSH keys outside public releases.

Online update channel:
https://raw.githubusercontent.com/Lycidias93/ssh-drop-dispatcher/main/update-rc.json

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

1. Download ssh-drop-dispatcher-magisk-v4.10.0-rc3.zip from the release.
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
