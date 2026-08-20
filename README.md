<!-- telegram-release-channel:start -->
> Release updates: [@lycidias93](https://t.me/lycidias93)
<!-- telegram-release-channel:end -->

# SSH Drop Dispatcher

SSH Drop Dispatcher is an Android/Magisk file-drop dispatcher for rooted devices. It watches a local Android directory, resolves explicit target markers from filenames, transfers matching files over SSH/SCP, verifies the remote result with SHA-256 and records delivery state.

`v4.14.0` adds **Return Channel v1**, a verified pull path for result artifacts from an already configured SSH target back to Android. SDD remains a transport layer: it does not become a remote execution engine, RPC service or generic remote shell.

The runtime is available through **CLI v3** and a loopback-only standalone **WebUI Core 0.6**. Public packages contain no private targets, private IP addresses, private hostnames, private paths, SSH private keys or ntfy tokens.

## Current stable release

| Field | Value |
|---|---|
| Public release | `4.14.0` |
| versionCode | `4140005` |
| Release asset | `ssh-drop-dispatcher-magisk-v4.14.0.zip` |
| Module ID | `ssh_drop_dispatcher` |
| Runtime SoT | `/data/adb/ssh-drop-dispatcher` |
| Magisk module path | `/data/adb/modules/ssh_drop_dispatcher` |
| Default scan directory | `/storage/emulated/0/Download` |
| WebUI Core | `0.6.0` |
| Return Channel | `v1` |
| Sortify marker policy | `v4115` |
| Update metadata | `update.json` |

Download the package and checksum file from the [v4.14.0 GitHub release](https://github.com/Lycidias93/ssh-drop-dispatcher/releases/tag/v4.14.0).

## Highlights

- explicit single-target and multi-target filename routing;
- SSH/SCP delivery to user-configured hosts;
- dispatcher-owned remote shell verification;
- mandatory remote SHA-256 parity before successful completion;
- duplicate/in-flight/completed/failure/quarantine state;
- event-driven watching with fallback scans and watchdog supervision;
- bounded named-file dispatch for `sdd dispatch-file`;
- single-flight/coalesced event follow-up scans;
- CLI v3 tracing, preflight, receipts and incident context;
- **Return Channel v1** with delivery binding, request/probe/collect/wait/trace and SHA-verified result adoption;
- standalone WebUI Core 0.6 with typed/allowlisted actions and a Returns inventory;
- optional secret-safe ntfy state;
- read-only Sortify companion status and completion markers.

There is one outbound delivery engine. CLI and WebUI operations delegate to the dispatcher runtime rather than implementing a second uploader.

## Compatibility

The public package requires:

- a rooted Android device;
- a Magisk-compatible module manager;
- Termux for the normal user-facing CLI workflow;
- Termux `openssh` and working SSH authentication to your own targets.

The project does not publish a broad device/Android-version support matrix. Devices outside the reference environment should be treated as compatible-by-design rather than individually certified.

Each enabled SSH target declares its remote shell explicitly:

```text
shell="bash"
```

or:

```text
shell="sh"
```

A missing required Bash interpreter is fail-closed. Python payload delivery remains unsupported by the current delivery policy.

## Install / update

1. Download `ssh-drop-dispatcher-magisk-v4.14.0.zip` from the [v4.14.0 release](https://github.com/Lycidias93/ssh-drop-dispatcher/releases/tag/v4.14.0).
2. Optionally verify the archive against the release `SHA256SUMS` asset.
3. Install the ZIP through Magisk.
4. Reboot Android normally.
5. Open Termux and run `sdd status`.
6. Open the Magisk module Action button for the WebUI when desired.

Existing persistent configuration under `/data/adb/ssh-drop-dispatcher` is preserved across normal module updates.

The installer attempts to install or update the Termux bridge automatically. The persistent runtime entrypoint remains available when the bridge is unavailable.

## Filename routing

Only explicit target prefixes are routed.

Single target:

```text
target-alpha__file.txt
```

Multiple targets:

```text
targets-alpha-beta__file.txt
```

The target token must match an enabled configured target. Checksum/signature sidecars such as `*.sha256`, `*.sha256sum`, `*.md5`, `*.sig` and `*.asc` are ignored by the dispatcher.

Android/browser duplicate aliases such as numeric filename suffixes are canonicalized and suppressed when they refer to already completed identical content.

## Target configuration

Target profiles live under:

```text
/data/adb/ssh-drop-dispatcher/config/targets.d
```

Minimal example:

```text
target_name="alpha"
enabled="1"
ssh_host="alpha"
remote_drop="/srv/drop"
platform="linux"
shell="bash"
role="example"
```

Important rules:

- `target_name` is the stable routing token;
- `ssh_host` resolves through the dispatcher's SSH configuration;
- `remote_drop` must already be writable on the target;
- every enabled target must declare `shell="bash"` or `shell="sh"`;
- private host/key/path data belongs only in the local runtime.

See [Configuration](docs/CONFIGURATION.md) for the complete field and migration model.

## CLI v3 quick start

The primary Termux command is `sdd`.

```text
sdd version
sdd status
sdd queue
sdd failures
sdd quarantine
sdd preflight <file>
sdd trace <file|delivery-id>
sdd incident --chatgpt <file|delivery-id>
sdd dispatch-file <file> --wait
```

### Read-only preflight

```text
sdd preflight <file>
```

Preflight checks local file eligibility, configuration, filename routing, dispatcher state, local shell syntax and target readiness. It may perform read-only SSH probes, but it does not upload the artifact.

### Controlled delivery

```text
sdd dispatch-file <file> --wait
```

The v4.14 flow is:

```text
preflight -> bounded named-file scan -> wait-delivery -> verified receipt
```

The named-file path avoids triggering a full queue scan for a user-requested delivery and reports `scan_scope=named_file` in its receipt. Automatic requeue is not performed after a failure or timeout.

Delivery receipts are appended under the persistent runtime and can be inspected through CLI/WebUI inventory surfaces.

## Return Channel v1

Return Channel is opt-in per target. It reuses the target's existing SSH identity and adds a separate Return sidecar:

```text
/data/adb/ssh-drop-dispatcher/config/returns.d/<target>.conf
```

Minimal shape:

```text
return_enabled="1"
remote_outbox="/absolute/path/to/outbox"
```

The command family is exposed through the normal CLI:

```text
sdd return capability <target>
sdd return request <delivery-id> --target <target> --type <result-type>
sdd return status <return-id>
sdd return probe <return-id>
sdd return collect <return-id>
sdd return wait <return-id>
sdd return trace <return-id>
```

A Return request must correlate to a completed outbound delivery and its target-specific SHA-256 binding. Returned data is pulled by Android, validated for origin/path/bounds/SHA identity and adopted atomically under the dedicated inbound runtime namespace.

Returned data is kept outside the outbound scan directory. A later Return failure does not rewrite an already successful outbound delivery.

See the [stable Return Channel v1 guide](docs/RETURN_CHANNEL_V1_STABLE.md).

## WebUI Core 0.6

Open the module's **Action** button in Magisk. The WebUI is a local standalone browser interface and is not a boot dependency.

Security model:

- loopback-only native server on a dynamic local port;
- one-time bootstrap token exchanged for an HttpOnly session cookie;
- typed and allowlisted operations only;
- no JavaScript shell execution;
- no arbitrary generic filesystem-path input;
- no secret-value reconstruction or display.

Current UI capabilities include:

- overview and health state;
- target matrix and explicit readiness tests;
- queue, failure, quarantine and receipt inventories;
- typed target/profile editing and preview-before-apply;
- bounded import/export with secret-aware handling;
- Returns inventory and bounded Return operations;
- secret-safe ntfy configured/not-configured state;
- read-only Sortify companion inventory;
- state-aware actions, explicit live inventory refresh and stale-response protection;
- mobile-focused responsive navigation and record views.

## ntfy integration

ntfy configuration remains local. Public runtime and WebUI surfaces expose only secret-safe configured/not-configured state; token contents are not returned in status, WebUI data, exports or incident context.

See [ntfy runbook](docs/NTFY_RUNBOOK.md).

## Sortify integration

Sortify remains authoritative for its writable settings. SSH Drop Dispatcher exposes a read-only companion view and writes its documented per-file completion/release markers after the selected target set has completed successfully.

The Sortify marker policy remains `v4115`.

## Backup, restore and migration

`dispatch-config` supports ZIP-based backup/import workflows. The normal public-format backup includes configuration, target profiles, SSH configuration, known hosts and public keys.

Private SSH keys are excluded by default and require explicit confirmation when intentionally included. Backups containing private environment data must never be attached to public issues or releases.

See [Backup and restore](docs/BACKUP_RESTORE.md).

## Troubleshooting

Useful first checks:

```text
sdd status
sdd failures
sdd quarantine
sdd incident --chatgpt
```

Incident/ChatGPT context redacts host fields, remote paths, network addresses and secret content while preserving bounded runtime evidence.

## Safety boundaries

SSH Drop Dispatcher intentionally does **not**:

- execute delivered payloads automatically on targets;
- expose an arbitrary remote-command or RPC endpoint;
- require incoming SSH access to Android for Return Channel;
- automatically requeue failed or timed-out deliveries;
- recursively browse arbitrary remote Return paths;
- automatically delete remote Return outbox data;
- expose private targets, private hostnames/IPs, private paths, SSH private keys or ntfy token contents in public packages;
- fall back from required Bash verification to `sh`;
- treat Python artifacts as supported delivery payloads.

## Changes in v4.14.0

The user-facing delta since `v4.13.0` is:

- verified pull-based Return Channel v1;
- CLI and WebUI Return operations;
- WebUI Core 0.6 state/mobile/refresh improvements;
- bounded named-file dispatch for `dispatch-file`;
- single-flight/coalesced event follow-up scans to reduce lock contention.

See [v4.14.0 release notes](RELEASE_NOTES_V4.14.0.md) and the [Changelog](CHANGELOG.md).

## Documentation

- [v4.14.0 release notes](RELEASE_NOTES_V4.14.0.md)
- [Return Channel v1 stable guide](docs/RETURN_CHANNEL_V1_STABLE.md)
- [Return Channel v1 contract](docs/RETURN_CHANNEL_V1.md)
- [CLI v3](docs/CLI_V3.md)
- [Configuration](docs/CONFIGURATION.md)
- [How it works](docs/HOW_IT_WORKS.md)
- [Features](docs/FEATURES.md)
- [Backup and restore](docs/BACKUP_RESTORE.md)
- [ntfy runbook](docs/NTFY_RUNBOOK.md)
- [vNext implementation status](docs/VNEXT_IMPLEMENTATION_STATUS.md)
- [vNext roadmap](docs/VNEXT_ROADMAP.md)
- [Changelog](CHANGELOG.md)

## Source layout

`source/magisk` remains the frozen v4.13 baseline used by the deterministic Return builders. The public v4.14.0 package is built from that baseline plus the versioned Return/WebUI overlays and is promoted only when it reproduces the accepted `4.14.0-return-rc4` payload with `module.prop` as the sole stable-promotion difference.

## License

See [LICENSE](LICENSE).
