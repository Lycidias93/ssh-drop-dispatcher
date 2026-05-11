# Installation Guide

This guide explains how to install SSH Drop Dispatcher on a rooted Android device.

## Status

Version: 4.10.0-rc1
Module ID: ssh_drop_dispatcher
Runtime directory: /data/adb/ssh-drop-dispatcher

This is a public release candidate. Test it on a non-critical setup first.

## Requirements

- Rooted Android device
- Magisk
- Termux
- SSH client available in Termux
- SSH access to your own target host
- A target directory on the remote host where files should be uploaded

## Files

Download the Magisk ZIP from the GitHub release:

- ssh-drop-dispatcher-magisk-v4.10.0-rc1.zip

Optional verification files:

- SHA256SUMS
- ssh-drop-dispatcher-magisk-v4.10.0-rc1.zip.b64

## Install with Magisk

1. Open Magisk.
2. Go to Modules.
3. Install from storage.
4. Select ssh-drop-dispatcher-magisk-v4.10.0-rc1.zip.
5. Reboot Android.

After reboot, the module runtime should exist at:

/data/adb/ssh-drop-dispatcher

## Termux preparation

Install an SSH client in Termux if needed:

pkg update
pkg install openssh

Verify SSH access to your target host before configuring the dispatcher:

ssh your-target-host

## Configure targets

The public RC does not include private targets.

Create target config files in:

/data/adb/ssh-drop-dispatcher/config/targets.d

Example target file:

/data/adb/ssh-drop-dispatcher/config/targets.d/alpha.conf

Recommended fields:

enabled=1
host=alpha
remote_drop=/tmp/ssh-drop-dispatcher-drop
platform=linux
shell=bash
verify=generic
role=example

Use your own host names and remote paths.

## Filename routing

Single target:

target-alpha__example.txt

Multi target:

targets-alpha-beta__example.txt

The target name in the filename must match the configured target name.

## Runtime checks

Run:

su -c "/data/adb/modules/ssh_drop_dispatcher/service.sh --runtime-status"

Run doctor:

su -c "/data/adb/modules/ssh_drop_dispatcher/service.sh --doctor"

List config:

su -c "/data/adb/modules/ssh_drop_dispatcher/service.sh --config-list"

## Basic smoke test

1. Create a test file in the watched Android drop directory.
2. Use a target marker in the filename.
3. Wait for the dispatcher to process it.
4. Check the remote drop directory on the target host.
5. Check runtime status and dispatch logs.

Example filename:

target-alpha__hello.txt

## Troubleshooting

If files are not uploaded:

- Check that the service is running.
- Check that the target name matches the filename marker.
- Check SSH access from Termux.
- Check that the remote directory exists.
- Check runtime status.
- Run doctor.
- Check dispatch logs.

Useful commands:

su -c "/data/adb/modules/ssh_drop_dispatcher/service.sh --runtime-status"
su -c "/data/adb/modules/ssh_drop_dispatcher/service.sh --doctor"
su -c "tail -n 120 /data/adb/ssh-drop-dispatcher/log/dispatch.log"

## Uninstall

Remove the module in Magisk and reboot.

After uninstall, manually remove runtime data only if you no longer need logs or state:

su -c "rm -rf /data/adb/ssh-drop-dispatcher"
