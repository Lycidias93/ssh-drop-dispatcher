# [Magisk][Termux] SSH Drop Dispatcher - Route dropped files to SSH targets by filename

## Overview

SSH Drop Dispatcher is an Android/Magisk file-drop dispatcher for routing files to configured SSH targets based on filename markers.

It is intended for homelab, admin and automation workflows where an Android device acts as a small control-plane node.

## Features

- Filename-based target routing
- Single-target and multi-target dispatch
- SSH-based upload
- Runtime health status
- Target registry support
- Manual scan support
- Dispatch state tracking
- Sourceable health environment
- No bundled private target configuration

## Filename examples

Single target:
target-alpha__file.txt

Multi target:
targets-alpha-beta__file.txt

## Requirements

- Rooted Android device
- Magisk
- Termux
- SSH client
- Configured SSH access to your own target hosts

## Privacy

The public package does not include private hostnames, private device names, home-network configuration, SSH keys, or private target definitions.

## Release

Version: 4.10.0-rc1
versionCode: 4100001

GitHub:
- Repo: ssh-drop-dispatcher
- Latest release: ssh-drop-dispatcher-v4.10.0-rc1

## Credits

- SSH Drop Dispatcher Contributors
- Android, Magisk, Termux and XDA communities

## Changelog

### 4.10.0-rc1

- Initial public release candidate.
- Neutralized module metadata.
- Added online update metadata.
- Removed bundled private target configuration.
## Installation summary

1. Install the Magisk ZIP.
2. Reboot.
3. Configure your own SSH target files.
4. Test SSH from Termux.
5. Drop a file named target-alpha__example.txt into the watched directory.
6. Check the remote drop directory and runtime status.

## How it works summary

The module watches a local Android drop directory. File names contain target markers. The dispatcher resolves configured targets and uploads matching files to their remote drop directories over SSH/SCP. Processing is tracked in runtime state files and can be checked with runtime-status and doctor commands.
## Feature details

- Android/Magisk based service
- Filename based routing
- Single target dispatch
- Multi target dispatch
- SSH/SCP upload to configured targets
- Runtime health checks
- Doctor command
- Config list command
- Target registry files
- Dispatch state tracking
- In-flight, done, complete, quarantine and failure records
- Manual scan support
- Event based scan support
- Watchdog supported runtime supervision
- No bundled private target definitions

## Interactive setup wizard

RC2 adds a setup wizard:

su -c "/data/adb/modules/ssh_drop_dispatcher/service.sh --setup-target"

The wizard walks the user through SSH target setup, SSH key generation, SSH config creation, optional authorized_keys installation, remote drop directory creation and a smoke test.

## RC3 adds initial scan directory setup

RC3 adds the initial setup command:

su -c "/data/adb/modules/ssh_drop_dispatcher/service.sh --setup"

The wizard lets the user choose the local scan directory. The default remains /storage/emulated/0/Download. After that it can continue into SSH target setup.
