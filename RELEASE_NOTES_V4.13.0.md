# SSH Drop Dispatcher v4.13.0

Stable promotion of the fully verified `4.13.0-verify-owner-rc6` runtime.

## What changed since the last public release, v4.12.6

- **Dispatcher-owned verification and identity:** adds the vNext identity layer, explicit target verification/preflight, SHA-256 parity evidence, quarantine-aware state, and safer config sanitization without introducing a second delivery engine.
- **CLI v3 workflow and observability:** adds delivery tracing, queue/failure/quarantine inspection, read-only preflight, orchestrated `dispatch-file --wait`, delivery receipts, incident context, ChatGPT context, doctor output, and the hardened Termux bridge.
- **Secure standalone WebUI:** moves the public UI onto the shared Android Root Module WebUI Core `0.3.0` with loopback-only serving, one-time bootstrap tokens, HttpOnly sessions, typed/allowlisted operations, and no JavaScript shell execution.
- **Typed profiles and safe transfer:** adds typed repeated-record editing, preview-bound whole-collection apply, bounded schema-declared import/export, secret-safe export policy metadata, alias canonicalization, and explicit no-op preview flows.
- **Operational WebUI improvements:** adds fast local status, bounded inventory views, long-running job handling, stronger apply/confirmation gating, record-count/focus feedback, and clearer result summaries.
- **Target readiness UX:** adds `Test all enabled targets` as a sequential, non-fail-fast readiness check with no artifact delivery. Required targets remain hard failures; explicitly intermittent targets such as ZeroPi2 may be reported as `SKIP reason=intermittent_unavailable` only at the SSH availability boundary.
- **ntfy and Sortify integration:** exposes only secret-safe configured/not-configured ntfy state and adds read-only Sortify companion inventory while Sortify remains authoritative for its writable settings.
- **Support and reliability:** support bundles derive their version from module metadata; Android framework commands are namespace-bound; WebUI inventory and fast-status paths gained runtime/latency acceptance coverage; deterministic build and release-equivalence checks were added.

## Stable promotion identity

- Stable version: `4.13.0`
- Stable versionCode: `4130007`
- Stable ZIP SHA-256: `d9a59f65f67981fdc397aeab793607910431fc444a06eceac7dae84719a5580a`
- Accepted runtime: `4.13.0-verify-owner-rc6`
- Accepted RC6 ZIP SHA-256: `31ed930fc222d7879e12c8f3f83516b6e4793ae995991121dfb39b8610dccdae`
- Accepted source commit: `dc78829e5e3e4be8794ff7441730d8b843a25932`
- Accepted Pixel runtime marker: `RESULT: CG_INSTALLED_RUNTIME_VERIFY_DONE outcome=success workflow_exit_code=0`
- Shared WebUI Core: `0.3.0` at `81678604122636ad87a0f6d48eac1262a67154a4`
- Stable promotion CI: workflow run `31850598193` PASS

The stable build is generated deterministically from the accepted RC6 payload. CI first rebuilds the RC6 package and requires the exact accepted RC6 SHA-256, then requires the stable ZIP to differ from that package only in `module.prop`. The versionCode is incremented from RC6 (`4130006`) to stable (`4130007`) so installed RC builds can upgrade normally.

## Verified runtime state

Pixel post-boot acceptance passed with module identity, all 31 runtime payload files, services/PIDs, CLI, redaction, Termux bridge, WebUI fast status, ntfy configured-state, Sortify inventory, typed profiles, safe export/import preview, WebUI actions, and enabled-target readiness all green. BerylAX, pi3 and pi4 passed; ZeroPi2 was correctly classified as intermittent/unavailable. No target artifact delivery occurred during acceptance.

## Safety boundaries

- No host payload execution is added by the release promotion.
- No DNS, HA, VIP, default/static route, MagicDNS, or subnet-route changes.
- No bundled private targets, private IPs, private paths, SSH keys, or ntfy tokens.
- Sortify release-marker policy remains `v4115`.
- Stable promotion does not alter the accepted delivery core.

## Upgrade

Flash `ssh-drop-dispatcher-magisk-v4.13.0.zip` through Magisk and reboot normally. Existing persistent configuration under `/data/adb/ssh-drop-dispatcher` is preserved by the module update model.
