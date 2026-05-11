# SSH Drop Dispatcher

SSH Drop Dispatcher is an Android/Magisk file-drop dispatcher that routes files to configured SSH targets based on filename markers.

Status:
Public release candidate: 4.10.0-rc1

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
## Documentation

- Installation: docs/INSTALLATION.md
- How it works: docs/HOW_IT_WORKS.md
- Configuration: docs/CONFIGURATION.md
- Features: docs/FEATURES.md
- XDA draft: XDA_PUBLIC_RC_DRAFT.md
## Quick install

1. Download ssh-drop-dispatcher-magisk-v4.10.0-rc1.zip from the release.
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
