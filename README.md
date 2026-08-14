<!-- telegram-release-channel:start -->
> Release updates: [@lycidias93](https://t.me/lycidias93)
<!-- telegram-release-channel:end -->

# SSH Drop Dispatcher

SSH Drop Dispatcher is an Android/Magisk file-drop dispatcher for rooted devices. It watches a local Android directory, routes explicitly named artifacts to configured SSH targets, verifies delivery, and exposes the same runtime through a hardened CLI and standalone browser WebUI.

The public package contains **no private targets, private IP addresses, private hostnames, private paths, SSH keys, or ntfy tokens**.

## Current stable release

| Field | Value |
|---|---|
| Public release | `4.13.0` |
| versionCode | `4130007` |
| Module ID | `ssh_drop_dispatcher` |
| Runtime SoT | `/data/adb/ssh-drop-dispatcher` |
| Magisk module path | `/data/adb/modules/ssh_drop_dispatcher` |
| Default scan directory | `/storage/emulated/0/Download` |
| Shared WebUI Core | `0.3.0` @ `81678604122636ad87a0f6d48eac1262a67154a4` |
| Sortify marker policy | `v4115` |
| Update metadata | `update.json` |

`v4.13.0` is the stable promotion of the Pixel-installed and post-boot verified `4.13.0-verify-owner-rc6` runtime. The stable build is deterministic and CI requires it to differ from the accepted RC6 package **only in `module.prop`**.

## Highlights since v4.12.6

### Dispatcher-owned verification and CLI v3

The dispatcher now has a versioned identity/workflow layer around the existing delivery engine:

- delivery tracing and opaque delivery IDs;
- queue, failure and quarantine inspection;
- read-only per-file preflight;
- `dispatch-file --wait` orchestration using the existing dispatcher scan path;
- delivery receipts and incident context;
- secret-safe ChatGPT context and doctor output;
- hardened Termux bridge;
- explicit target readiness and SHA-256 parity evidence.

See [CLI v3](docs/CLI_V3.md) and [configuration](docs/CONFIGURATION.md).

### Standalone WebUI Core 0.3.0

The Magisk Action button opens a local standalone browser UI backed by the shared Android Root Module WebUI Core `0.3.0`:

- loopback-only native server on a dynamic port;
- one-time bootstrap token exchanged for an HttpOnly session cookie;
- typed and allowlisted operations only;
- no JavaScript shell execution;
- typed repeated-record/profile editor;
- preview-bound whole-collection apply;
- bounded schema-declared import/export;
- secret/reference/credential export policy metadata;
- bounded inventories, logs and background jobs.

The consumer lock is pinned to the current shared template commit; floating `main` is never consumed silently.

### Faster, clearer operation

- Fast local WebUI status with runtime latency checks.
- Typed profile aliases are canonicalized before apply/export.
- Add-record, focus/scroll, confirmation and result-summary UX is improved.
- Support bundles derive their version from module metadata.
- ntfy is shown only as secret-safe configured/not-configured state.
- Sortify companion status is read-only; Sortify remains authoritative for its writable settings.

### Aggregate target readiness

`Test all enabled targets` checks enabled targets sequentially and non-fail-fast without delivering artifacts.

Required targets remain hard failures. Explicitly intermittent targets such as ZeroPi2 may be reported as:

```text
SKIP reason=intermittent_unavailable
```

only when the failure is the allowed SSH availability boundary. Reachable targets with readiness/content/storage failures still fail.

## Install / update

1. Download `ssh-drop-dispatcher-magisk-v4.13.0.zip` from the `v4.13.0` GitHub release.
2. Install the ZIP through Magisk.
3. Reboot Android normally.
4. Open the module Action button for the WebUI, or use the CLI.

Persistent configuration lives under:

```text
/data/adb/ssh-drop-dispatcher
```

and is preserved across normal module updates.

## Filename routing

Only explicit target prefixes are routed by default.

Single target:

```text
target-alpha__file.txt
```

Multiple targets:

```text
targets-alpha-beta__file.txt
```

Checksum/signature sidecars such as `*.sha256`, `*.sha256sum`, `*.md5`, `*.sig`, and `*.asc` are ignored by the dispatcher.

## CLI quick start

After installation, the Termux bridge exposes `sdd` when the bridge is installed/current.

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

A controlled delivery workflow uses:

```text
sdd dispatch-file <file> --wait
```

It does not create a second uploader: preflight feeds the existing dispatcher scan path and then waits on the resulting delivery state.

## WebUI

Open the Magisk module Action button. The WebUI provides:

- Overview and health;
- secret-safe ntfy state;
- target matrix and explicit readiness tests;
- queue/failure/quarantine/receipt inventories;
- typed profile editing;
- preview-first import and collection apply;
- safe export;
- bounded actions and background jobs;
- read-only Sortify companion inventory.

The WebUI is not a boot dependency. A WebUI failure cannot prevent the normal dispatcher service from starting.

## Safety invariants

- No automatic host payload execution.
- No DNS, HA, VIP, default/static route, MagicDNS, or subnet-route changes.
- No target drop-path changes as part of the v4.13.0 stable promotion.
- No bundled private runtime data.
- Sortify release-marker policy remains `v4115`.
- Stable publication changes only release metadata relative to the accepted RC6 payload; the delivery core is unchanged.

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

The stable builder first reproduces that exact RC6 digest, then replaces only `module.prop` with `version=4.13.0` / `versionCode=4130007`, rebuilds deterministically twice, and rejects any other payload difference.

## Documentation

- [v4.13.0 release notes](RELEASE_NOTES_V4.13.0.md)
- [CLI v3](docs/CLI_V3.md)
- [Configuration](docs/CONFIGURATION.md)
- [vNext implementation status](docs/VNEXT_IMPLEMENTATION_STATUS.md)
- [Changelog](CHANGELOG.md)

## License

See [LICENSE](LICENSE).
