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
