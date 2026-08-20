# Changelog

This changelog tracks public, user-relevant stable changes. Historical RC/build/verification bookkeeping remains available in Git history but is intentionally omitted here.

## v4.14.0 - 2026-08-20

### What changed since v4.13.0

- Added Return Channel v1: verified pull-based result transfer from an already configured SSH target back to Android, correlated to a completed outbound delivery and checked with SHA-256 before acceptance.
- Added `sdd return` capability, request, status, probe, collect, wait and trace operations with machine-readable output and existing redaction rules.
- Added a secret-safe Returns inventory and bounded Return operations to the standalone WebUI.
- Updated the WebUI to Core 0.6 with state-aware actions, clearer Preview vs Apply behavior, explicit live inventory refresh, stale-response protection and improved responsive/mobile navigation.
- Changed `sdd dispatch-file` to use a bounded named-file scan instead of starting a full queue scan for that workflow, reducing contention when watcher or follow-up activity overlaps a requested delivery.
- Coalesced event follow-up scans into a single-flight worker to avoid concurrent follow-up fan-out.

## v4.13.0 - 2026-08-15

### What changed since v4.12.6

- Added dispatcher-owned target verification and preflight, including remote shell checks and remote SHA-256 parity before a delivery is marked complete.
- Added CLI v3 delivery tracing, queue/failure/quarantine inspection, read-only preflight, `dispatch-file --wait`, delivery receipts, incident context and secret-safe ChatGPT context.
- Reworked the standalone WebUI on WebUI Core 0.3.0 with local-only access, typed/allowlisted operations and stronger session handling.
- Added typed target/profile editing, alias canonicalization, preview-before-apply, bounded import/export and secret-aware export handling.
- Improved WebUI responsiveness and usability with faster local status, bounded inventories/background jobs, clearer result summaries, stronger confirmation gating and better mobile record focus/navigation.
- Added `Test all enabled targets` for sequential readiness checks without sending an artifact, with intermittent availability reported separately from real readiness failures.
- Added secret-safe ntfy configured/not-configured status and read-only Sortify companion inventory.
- Improved support bundle version reporting and Android command handling in the Magisk/Termux environment.

## v4.12.6 - 2026-07-04

- Added a fast target-only watchdog so productive target drops do not have to wait for the long fallback scan when Android/FUSE watcher events are missed.
- Added delivery-latency telemetry and reduced repeated canonical-collision warning noise.

## v4.12.5 - 2026-06-16

- Added duplicate-alias handling for Android/browser download suffixes such as `name-1.ext` and `name (1).ext`.
- Identical aliases are suppressed instead of being uploaded a second time; changed-content canonical collisions are reported separately.

## v4.12.4 - 2026-06-14

- Added secret-safe ntfy information for already-delivered files that reappear with a newer local timestamp.
- Added debounce behavior so repeated scans do not emit duplicate already-present notifications.

## v4.12.3 - 2026-06-13

- Improved ntfy delivery notification formatting with concise status, target, file, reason and host-run information.
- Added the ntfy integration runbook.

## v4.12.2 - 2026-06-13

- Added secret-safe WebUI ntfy configuration and test-notification actions.

## v4.12.1 - 2026-06-12

- Added delivery status/wait diagnostics and controlled break-glass SCP support.
- Added target-specific free-space gates and hardened BerylAX/OpenWrt compatibility.
- Added optional per-target delivery notifications while keeping automatic requeue disabled.

## v4.12.0 - 2026-06-08

- Added WebUI/CLI pause, resume and dispatch-now controls.
- Enforced strict `target-*__*` / `targets-*__*` routing and ignored checksum/signature sidecars.
- Added per-target SCP flags including legacy SCP compatibility for Dropbear/OpenWrt targets.

## v4.11.0 - 2026-05-31

- Added registry-based target routing and Sortify completion markers.
- Added `dispatch-config`, setup/migration, backup/restore and public-format export workflows.
- Added the initial public WebUI and update metadata while keeping private target/key data out of public packages.

## v4.10.0 - 2026-05

- Initial public SSH Drop Dispatcher release line.
- Added generic target setup, SSH configuration, local scan-directory setup and public update metadata.
