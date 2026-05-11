# Features

SSH Drop Dispatcher is an Android/Magisk file-drop dispatcher for routing files to configured SSH targets by filename markers.

## Core features

- Interactive initial setup wizard

- Local scan directory selection

- Default scan directory remains /storage/emulated/0/Download

- Interactive SSH target setup wizard
- SSH key generation
- SSH config generation
- Optional public key installation on target host
- Remote drop directory creation

- Android/Magisk based dispatcher service
- Filename-based routing
- Single-target dispatch
- Multi-target dispatch
- SSH/SCP based upload
- Runtime health status
- Doctor checks
- Config listing
- Target registry via config files
- Dispatch state tracking
- Duplicate processing protection
- In-flight state tracking
- Completed dispatch records
- Failure database
- Quarantine state
- Manual scan support
- Event based scan support
- Watchdog supported runtime supervision
- Sourceable health environment
- Public update metadata support
- No bundled private target definitions

## Filename based routing

Files are routed by target markers in their filename.

Single target example:

target-alpha__file.txt

Multi target example:

targets-alpha-beta__file.txt

The target token must match a configured target name.

## Target registry

Targets are configured through files in:

/data/adb/ssh-drop-dispatcher/config/targets.d

Each target can define:

- enabled state
- SSH host
- remote drop directory
- platform label
- shell type
- verification mode
- role label

## Runtime status and doctor

The module exposes runtime checks through service.sh.

Runtime status:

su -c "/data/adb/modules/ssh_drop_dispatcher/service.sh --runtime-status"

Doctor:

su -c "/data/adb/modules/ssh_drop_dispatcher/service.sh --doctor"

Config list:

su -c "/data/adb/modules/ssh_drop_dispatcher/service.sh --config-list"

## Dispatch state

The runtime tracks dispatch state using files such as:

- dispatch.inflight
- dispatch.done
- dispatch.complete
- dispatch.quarantined
- dispatch.faildb

This makes file processing auditable and helps avoid repeated upload loops.

## Public RC privacy model

The public RC does not include:

- private target definitions
- private hostnames
- private IP addresses
- SSH keys
- personal device names
- home-network paths

Users must configure their own SSH targets.

## Typical use cases

- Android device as a small homelab control-plane node
- File handoff from Android to Linux targets
- Admin dropbox for scripts or archives
- Multi-target distribution by filename
- Auditable file transfer workflows
- Local automation with SSH based delivery

## Current RC limitations

- Requires rooted Android and Magisk
- Requires working SSH access from Android or Termux
- Requires user-created target configs
- Public RC should be tested on non-critical systems first
- No private target profiles are bundled
