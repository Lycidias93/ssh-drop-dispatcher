<!-- telegram-release-channel:start -->
> Release updates: [@lycidias93](https://t.me/lycidias93)
<!-- telegram-release-channel:end -->

# SSH Drop Dispatcher

SSH Drop Dispatcher is an Android/Magisk file-drop dispatcher for rooted devices. It watches one local Android directory, resolves explicit target markers from filenames, transfers matching artifacts over SSH/SCP, verifies the remote result, and records auditable delivery state.

The same runtime is exposed through a hardened **CLI v3** and a loopback-only standalone **WebUI Core 0.3.0**. The public package contains **no private targets, private IP addresses, private hostnames, private paths, SSH keys, or ntfy tokens**.

## Current stable release

| Field | Value |
|---|---|
| Public release | `4.13.0` |
| versionCode | `4130007` |
| Release asset | `ssh-drop-dispatcher-magisk-v4.13.0.zip` |
| Asset size | `3,667,734` bytes |
| Stable ZIP SHA-256 | `d9a59f65f67981fdc397aeab793607910431fc444a06eceac7dae84719a5580a` |
| Module ID | `ssh_drop_dispatcher` |
| Runtime SoT | `/data/adb/ssh-drop-dispatcher` |
| Magisk module path | `/data/adb/modules/ssh_drop_dispatcher` |
| Default scan directory | `/storage/emulated/0/Download` |
| Shared WebUI Core | `0.3.0` @ `81678604122636ad87a0f6d48eac1262a67154a4` |
| Sortify marker policy | `v4115` |
| Update metadata | `update.json` |

Download the current stable package from the [v4.13.0 GitHub release](https://github.com/Lycidias93/ssh-drop-dispatcher/releases/tag/v4.13.0).

`v4.13.0` is the stable promotion of the post-boot accepted `4.13.0-verify-owner-rc6` runtime. The stable builder first reproduces the accepted RC6 ZIP exactly, then changes only `module.prop` to the public stable version metadata. CI rejects any other payload difference.

## What the module does

A file is routed by an explicit target marker in its filename. The dispatcher resolves that marker against its target registry, performs readiness and syntax checks, uploads through the existing delivery engine, requires remote SHA-256 parity before completion, and records the result in persistent state.

Core behavior includes:

- single-target and multi-target filename routing;
- SSH/SCP delivery to user-configured hosts;
- dispatcher-owned remote shell verification;
- mandatory remote SHA-256 parity before successful completion;
- duplicate/in-flight/completed/failure/quarantine state;
- event-driven watching with fallback scans and watchdog supervision;
- explicit target readiness checks without artifact delivery;
- CLI v3 tracing, preflight, receipts and incident context;
- standalone WebUI for health, targets, profiles, inventories and bounded actions;
- optional secret-safe ntfy state;
- read-only Sortify companion status and release-marker integration.

There is still one delivery engine: CLI and WebUI operations delegate to the dispatcher runtime rather than implementing a second uploader.

## Compatibility and verified scope

### Android host

The public package requires:

- a rooted Android device;
- a Magisk-compatible module manager;
- Termux for the normal user-facing CLI workflow;
- Termux `openssh` and working SSH authentication to your own targets.

The `v4.13.0` stable claim is backed by post-boot acceptance on the project Pixel reference device. The repository does **not** currently publish a broad device/Android-version support matrix, so other rooted Android devices should be treated as compatible-by-design rather than individually verified unless separate evidence exists.

### SSH targets

Each enabled target declares its remote shell explicitly:

- `shell="bash"` for Bash targets;
- `shell="sh"` for POSIX-shell targets such as OpenWrt/BerylAX.

A missing required Bash interpreter is fail-closed; the dispatcher does not silently fall back from `bash -n` to `sh -n`.

The stable acceptance run verified required target readiness for BerylAX, pi3 and pi4. ZeroPi2 was explicitly classified as intermittent/unavailable at the allowed SSH availability boundary. These names are validation fixtures, not bundled public target definitions.

Python delivery remains unsupported by the current delivery policy.

## Architecture

The runtime separates persistent state from the Magisk module payload:

```text
Magisk module
  /data/adb/modules/ssh_drop_dispatcher
        |
        +-- service.sh / boot integration
        +-- Action -> standalone WebUI
        |
        v
Persistent runtime SoT
  /data/adb/ssh-drop-dispatcher
        |
        +-- config / targets / SSH material
        +-- runtime binaries and tools
        +-- logs / state / receipts / backups
        |
        v
Existing dispatcher delivery engine
        |
        +-- filename -> target resolution
        +-- readiness + local shell syntax checks
        +-- SCP upload
        +-- dispatcher-owned remote syntax verification
        +-- remote SHA-256 parity
        +-- done / complete / failure / quarantine state
```

Persistent configuration under `/data/adb/ssh-drop-dispatcher` is preserved across normal module updates.

## Install / update

1. Download `ssh-drop-dispatcher-magisk-v4.13.0.zip` from the [v4.13.0 release](https://github.com/Lycidias93/ssh-drop-dispatcher/releases/tag/v4.13.0).
2. Verify the SHA-256 if you want an independent package identity check.
3. Install the ZIP through Magisk.
4. Reboot Android normally.
5. Open Termux and check the runtime with `sdd status`.
6. Open the Magisk module Action button for the WebUI when desired.

The installer attempts to install/update the Termux bridge automatically. The runtime fallback remains available through the persistent runtime path when the bridge is unavailable.

For legacy interactive configuration, `dispatch-config` remains available.

## Filename routing contract

Only explicit target prefixes are routed.

Single target:

```text
target-alpha__file.txt
```

Multiple targets:

```text
targets-alpha-beta__file.txt
```

The target token must match an enabled configured target. Checksum/signature sidecars such as `*.sha256`, `*.sha256sum`, `*.md5`, `*.sig`, and `*.asc` are ignored by the dispatcher.

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

- `target_name` is the stable dispatcher routing token;
- `ssh_host` resolves through the dispatcher's SSH configuration;
- `remote_drop` must already be writable on the target;
- every enabled target must declare `shell="bash"` or `shell="sh"`;
- legacy target-local verification wrapper fields are rejected;
- private host/key/path data belongs only in the local runtime, never in the public repository.

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
```

### Read-only preflight

```text
sdd preflight <file>
```

Preflight checks local file eligibility, configuration, filename routing, dispatcher state, local shell syntax and target readiness. Target readiness may perform read-only SSH probes, but preflight never invokes SCP and never starts the delivery scan path.

Expected high-level outcomes are `READY` or `BLOCKED`.

### Controlled delivery workflow

```text
sdd dispatch-file <file> --wait
```

The flow is:

```text
preflight -> existing dispatcher scan -> wait-delivery -> receipt
```

This does not create a second upload engine. The existing dispatcher queue is processed under the normal ordering and safety rules. Automatic requeue is not performed after failure or timeout.

### Delivery tracing and receipts

CLI v3 derives an opaque delivery ID from the existing dispatcher record, so historical state can be inspected without rewriting it.

Receipts are appended to:

```text
/data/adb/ssh-drop-dispatcher/delivery.receipts.jsonl
```

Receipts are workflow evidence; the dispatcher state files and remote verification remain the delivery truth.

See [CLI v3](docs/CLI_V3.md) for schemas and the complete command surface.

## WebUI Core 0.3.0

Open the module's **Action** button in Magisk. The WebUI is a local standalone browser interface and is **not a boot dependency**.

Security and transport model:

- loopback-only native server on a dynamic local port;
- one-time bootstrap token exchanged for an HttpOnly session cookie;
- typed and allowlisted operations only;
- no JavaScript shell execution;
- no arbitrary generic filesystem-path input;
- no secret-value reconstruction or display.

Current UI capabilities include:

- overview and health state;
- secret-safe ntfy configured/not-configured state;
- target matrix and explicit readiness tests;
- `Test all enabled targets` aggregate smoke without artifact delivery;
- queue, failure, quarantine and receipt inventories;
- typed repeated-record/profile editing;
- alias canonicalization;
- preview-bound whole-collection apply;
- schema-versioned bounded import/export;
- secret/reference/credential-aware export policy;
- long-running jobs and bounded actions;
- read-only Sortify companion inventory;
- mobile-focused record, confirmation and result-summary UX.

The consumer is pinned to `Lycidias93/android-root-module-webui-template` Core `0.3.0` at commit `81678604122636ad87a0f6d48eac1262a67154a4`. That commit is also the current canonical template `main`; floating `main` is never consumed silently by the dispatcher build.

## Target readiness semantics

`Test all enabled targets` checks enabled targets sequentially and non-fail-fast without delivering artifacts.

Required targets remain hard failures. A target explicitly classified as intermittent may be reported as:

```text
SKIP reason=intermittent_unavailable
```

only when the failure is the allowed SSH availability boundary. A reachable target with readiness, content or storage failures still fails.

## ntfy integration

ntfy configuration remains local. The public runtime and WebUI expose only secret-safe configured/not-configured state; token contents are not returned in status, WebUI data, exports or ChatGPT context.

See [ntfy runbook](docs/NTFY_RUNBOOK.md) for the detailed integration model.

## Sortify integration

Sortify remains authoritative for its writable settings. SSH Drop Dispatcher only exposes a read-only companion view and writes its documented per-file completion/release markers after the selected target set has completed successfully.

The current Sortify release-marker policy remains `v4115`.

## Backup, restore and migration

`dispatch-config` supports ZIP-based backup/import workflows. The normal public-format backup includes configuration, target profiles, SSH configuration, known hosts and public keys.

Private SSH keys are excluded by default and require explicit typed confirmation when intentionally included.

For migration from an older private runtime, `dispatch-config export-private-runtime` creates a public-format migration ZIP. Such backups may contain private environment data and must never be attached to public issues or releases.

See [Backup and restore](docs/BACKUP_RESTORE.md).

## Runtime state and troubleshooting

Important persistent paths include:

```text
/data/adb/ssh-drop-dispatcher/config.env
/data/adb/ssh-drop-dispatcher/config/targets.d/
/data/adb/ssh-drop-dispatcher/ssh/
/data/adb/ssh-drop-dispatcher/log/
/data/adb/ssh-drop-dispatcher/delivery.receipts.jsonl
```

Useful first checks:

```text
sdd status
sdd failures
sdd quarantine
sdd incident --chatgpt
```

The incident/ChatGPT context is designed to redact host fields, remote paths, network addresses and secret content while still exposing runtime health and a bounded next action.

The legacy service entrypoint also retains runtime-status, doctor and config-list diagnostics for recovery/debugging.

## Safety boundaries

SSH Drop Dispatcher intentionally does **not**:

- execute delivered payloads automatically on target hosts;
- silently repair DNS, HA, VIP, default/static routes, MagicDNS or subnet routes;
- automatically requeue failed or timed-out deliveries;
- delete quarantine state automatically;
- expose private targets, private hostnames/IPs, private paths, SSH private keys or ntfy token contents in the public package;
- fall back from required Bash verification to `sh`;
- treat Python artifacts as supported delivery payloads under the current policy.

The WebUI is not a boot dependency. A WebUI failure cannot prevent the normal dispatcher service from starting.

## Verification provenance

The accepted Pixel RC6 runtime passed post-boot installed-runtime verification with:

```text
RESULT: SDD_V4130_VERIFY_OWNER_RC6_RUNTIME_VERIFY_PASS workflow_exit_code=0
RESULT: CG_INSTALLED_RUNTIME_VERIFY_DONE outcome=success workflow_exit_code=0
```

Accepted RC6 package SHA-256:

```text
31ed930fc222d7879e12c8f3f83516b6e4793ae995991121dfb39b8610dccdae
```

Public stable package SHA-256:

```text
d9a59f65f67981fdc397aeab793607910431fc444a06eceac7dae84719a5580a
```

The stable promotion is deterministic and changes only `module.prop` relative to the accepted RC6 package. The public release workflow then verified the published tag, non-draft/non-prerelease state, asset size and asset digest.

This means the functional runtime payload of `v4.13.0` is the device-accepted RC6 payload while the public package carries the clean stable version metadata.

## Changes in v4.13.0

`v4.13.0` contains the complete user-relevant delta since the previous public stable `v4.12.6`, including:

- dispatcher-owned verification/identity and SHA parity;
- CLI v3 workflow tracing, receipts, preflight and incident context;
- secure standalone WebUI Core 0.3.0;
- typed target/profile administration and safe import/export;
- aggregate target readiness UX;
- ntfy secret-state and Sortify read-only integration;
- fast-status, inventory and mobile WebUI UX improvements;
- deterministic stable-promotion and publication verification.

See [v4.13.0 release notes](RELEASE_NOTES_V4.13.0.md) and the [Changelog](CHANGELOG.md) for the full release history.

## Documentation

- [v4.13.0 release notes](RELEASE_NOTES_V4.13.0.md)
- [CLI v3](docs/CLI_V3.md)
- [Configuration](docs/CONFIGURATION.md)
- [How it works](docs/HOW_IT_WORKS.md)
- [Features](docs/FEATURES.md)
- [Backup and restore](docs/BACKUP_RESTORE.md)
- [ntfy runbook](docs/NTFY_RUNBOOK.md)
- [vNext implementation status](docs/VNEXT_IMPLEMENTATION_STATUS.md)
- [vNext roadmap](docs/VNEXT_ROADMAP.md)
- [Changelog](CHANGELOG.md)

## License

See [LICENSE](LICENSE).
