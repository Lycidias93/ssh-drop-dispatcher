# Configuration

This document describes the public configuration model for SSH Drop Dispatcher.

## Runtime directory

```text
/data/adb/ssh-drop-dispatcher
```

## Target config directory

```text
/data/adb/ssh-drop-dispatcher/config/targets.d
```

## Example target

File:

```text
/data/adb/ssh-drop-dispatcher/config/targets.d/alpha.conf
```

Example content:

```text
target_name="alpha"
enabled="1"
ssh_host="alpha"
remote_drop="/tmp/ssh-drop-dispatcher-drop"
platform="linux"
shell="bash"
role="example"
```

## Required verification model

Remote syntax verification is owned by the dispatcher. Target-local verification wrappers are not part of the configuration model.

These keys are rejected:

```text
verify=
verify_cmd=
verify_kind=
shell_kind=
```

Every enabled target must declare one explicit shell:

```text
shell="bash"
```

or:

```text
shell="sh"
```

Use `bash` for pi3, pi4, zeropi2 and other Linux targets whose delivered scripts use `#!/usr/bin/env bash`. Use `sh` for BerylAX/OpenWrt and other POSIX-shell targets.

For Bash targets, a missing remote `bash` interpreter is a hard failure. The dispatcher never falls back from `bash -n` to `sh -n`.

After upload, the dispatcher requires remote SHA-256 parity before it records delivery completion, sends a success notification, or emits a Sortify release marker.

Python files are intentionally unsupported by this candidate.

## Field overview

`target_name`
: Stable lowercase dispatcher target name.

`enabled`
: Set to `1` to enable the target.

`ssh_host`
: SSH host name as known to the Android dispatcher SSH configuration.

`remote_drop`
: Remote directory where files are uploaded.

`platform`
: Informational platform label.

`shell`
: Required remote syntax checker: `bash` or `sh`.

`scp_flags`
: Optional target-specific SCP flags. BerylAX retains legacy SCP mode `-O`.

`role`
: Informational role label.

## Upgrade migration

The `4.13.0-verify-owner-rc1` candidate migrates existing target profiles before loading them:

- creates timestamped backups under `/data/adb/ssh-drop-dispatcher/backups/verify-owner-*`;
- removes `verify`, `verify_cmd`, `verify_kind`, and `shell_kind`;
- writes an explicit `shell="bash|sh"` field;
- writes `/data/adb/ssh-drop-dispatcher/verification-owner.env` only after every target profile passes migration validation.

The marker contains:

```text
verify_owner=dispatcher
external_verify_wrapper=no
remote_sha_required=yes
bash_missing_fallback=fail_closed
python_delivery=unsupported
```

## Filename examples

Single target:

```text
target-alpha__file.txt
```

Multiple targets:

```text
targets-alpha-beta__file.txt
```

## SSH configuration

The dispatcher uses its runtime SSH configuration and keys under:

```text
/data/adb/ssh-drop-dispatcher/ssh
```

Use your own host, user and key configuration. Do not bundle private target data in the public module.

## Remote directory

Create the remote drop directory before sending files:

```text
mkdir -p /tmp/ssh-drop-dispatcher-drop
```

Use a persistent directory for real deployments.

## Recommended first test

1. Configure one target with an explicit `shell`.
2. Run `--config-lint` and `--verify-target`.
3. Create `target-alpha__hello.txt` in the watched directory.
4. Confirm that the file appears in the remote drop directory.
5. Confirm the dispatch log contains `verify_owner=dispatcher`, `external_verify_wrapper=no`, and `remote_sha_match=yes`.
6. Check runtime status and the verification-owner marker.

## Local scan directory

Default:

```text
/storage/emulated/0/Download
```

The selected value is stored in:

```text
/data/adb/ssh-drop-dispatcher/config.env
```

The scan directory is global. Remote drop directories and shell profiles are configured per target.
