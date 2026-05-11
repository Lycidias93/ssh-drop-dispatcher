# Configuration

This document describes the public configuration model.

## Runtime directory

/data/adb/ssh-drop-dispatcher

## Target config directory

/data/adb/ssh-drop-dispatcher/config/targets.d

## Example target

File:

/data/adb/ssh-drop-dispatcher/config/targets.d/alpha.conf

Example content:

enabled=1
host=alpha
remote_drop=/tmp/ssh-drop-dispatcher-drop
platform=linux
shell=bash
verify=generic
role=example

## Field overview

enabled:
Set to 1 to enable the target.

host:
SSH host name as known to the Android SSH client.

remote_drop:
Remote directory where files should be uploaded.

platform:
Informational platform label.

shell:
Remote shell type. Use bash for Linux hosts with Bash, sh for POSIX shell targets.

verify:
Verification mode. Public default is generic.

role:
Informational role label.

## Filename examples

Single target:

target-alpha__file.txt

Multi target:

targets-alpha-beta__file.txt

## SSH configuration

You can use your normal SSH config.

Typical SSH config location in Termux:

~/.ssh/config

Example:

Host alpha
  HostName 192.0.2.10
  User example

Use your own host, user and key configuration.

## Remote directory

Create the remote drop directory before sending files:

mkdir -p /tmp/ssh-drop-dispatcher-drop

Use a persistent directory for real deployments.

## Recommended first test

1. Configure one target named alpha.
2. Verify SSH manually from Termux.
3. Create target-alpha__hello.txt in the watched drop directory.
4. Confirm that the file appears in the remote drop directory.
5. Check runtime status and dispatch logs.
