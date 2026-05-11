# How SSH Drop Dispatcher Works

SSH Drop Dispatcher turns an Android device into a small file routing node.

It watches a local drop directory, detects target markers in filenames, and uploads matching files to configured SSH targets.

## Main idea

A file name contains the target.

Example:

target-alpha__backup.txt

The dispatcher sees target-alpha, resolves the configured target alpha, and uploads the file to the remote drop directory of that target.

## Components

## Magisk module

The Magisk module starts the dispatcher during boot.

Module path:

/data/adb/modules/ssh_drop_dispatcher

Runtime path:

/data/adb/ssh-drop-dispatcher

## Service script

The service script is the main control entrypoint.

It provides:

- runtime status
- doctor checks
- config listing
- event watching
- fallback scans
- dispatch processing

Typical commands:

su -c "/data/adb/modules/ssh_drop_dispatcher/service.sh --runtime-status"
su -c "/data/adb/modules/ssh_drop_dispatcher/service.sh --doctor"
su -c "/data/adb/modules/ssh_drop_dispatcher/service.sh --config-list"

## Runtime state

The runtime directory stores state, logs, config and PID files.

Important files:

- health.env
- dispatch.inflight
- dispatch.done
- dispatch.complete
- dispatch.quarantined
- dispatch.faildb
- log/dispatch.log
- log/health.log
- config/targets.d

## Target registry

Each target has a config file.

Example:

config/targets.d/alpha.conf

A target describes:

- whether it is enabled
- SSH host name
- remote drop directory
- platform
- shell type
- verification mode
- role label

## Routing

Routing is filename based.

Single target:

target-alpha__file.txt

Multi target:

targets-alpha-beta__file.txt

A target token must match a configured target name.

## Dispatch flow

1. A file appears in the local drop directory.
2. The dispatcher scans the filename.
3. It extracts target names.
4. It checks target config.
5. It uploads the file over SSH/SCP.
6. It records success or failure in state files.
7. It keeps logs for later inspection.

## Dedupe and state

The dispatcher records processed files.

Typical state files:

- dispatch.inflight: currently processing
- dispatch.done: successful target upload records
- dispatch.complete: completed file records
- dispatch.quarantined: files held back
- dispatch.faildb: failed dispatch records

This prevents repeated upload loops and makes processing auditable.

## Health

health.env is written in a shell-sourceable format.

Example fields:

status=OK
main_pid_ok=yes
watcher_pid_ok=yes
watchdog_pid_ok=yes
inflight_bytes=0
event_pending=no

The quoted timestamp format is intentional so health.env can be sourced by shell scripts.

## Watcher and watchdog

The dispatcher uses a watcher to detect file events and a watchdog to keep the runtime healthy.

If event watching misses something, fallback scans can still process files.

## What the public RC does not include

The public RC does not include private targets, private hostnames, private IPs, SSH keys, personal device names or home-network paths.

You must configure your own targets.
