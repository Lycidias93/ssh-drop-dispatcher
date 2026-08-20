# SSH Drop Dispatcher vNext Roadmap

Status: reconciled for the `v4.14.0` stable line.

## Stable baseline

- stable: `4.14.0` / `4140005`;
- CLI: v3;
- WebUI Core: 0.6;
- persistent runtime SoT: `/data/adb/ssh-drop-dispatcher`;
- Sortify marker policy: `v4115`;
- Android remains the dispatcher control plane;
- no automatic target payload execution;
- no arbitrary remote-command/RPC surface.

## Completed in v4.14.0

Return Channel v1 is no longer an active roadmap milestone. It is part of the stable product and includes:

- target-specific delivery-to-SHA binding after verified outbound delivery;
- explicit Return request/state contracts;
- opt-in per-target Return capability sidecars;
- exact-path, pull-based SSH/SCP collection initiated by Android;
- dedicated inbound storage separated from the outbound scan directory;
- origin/path/bounds/SHA/replay validation and atomic local adoption;
- CLI v3 `sdd return ...` operations;
- WebUI Returns inventory and bounded typed operations;
- bounded named-file dispatch for `sdd dispatch-file`;
- single-flight/coalesced event follow-up scans.

The frozen design contract remains at [`RETURN_CHANNEL_V1.md`](RETURN_CHANNEL_V1.md); the stable user guide is [`RETURN_CHANNEL_V1_STABLE.md`](RETURN_CHANNEL_V1_STABLE.md).

## Stable invariants to preserve

Future work must preserve:

- explicit `target-*__*` / `targets-*__*` routing;
- dispatcher-owned remote verification and mandatory SHA-256 parity;
- fail-closed target shell policy;
- duplicate/browser-alias suppression;
- CLI v3 receipts, trace, preflight and incident context;
- secret-safe machine/WebUI output;
- no returned data in the outbound scan directory;
- no Return acceptance without a known delivery correlation and SHA identity;
- no incoming SSH requirement on Android;
- no hidden automatic requeue or target execution;
- no private target, path, key or token data in public packages.

## Candidate future work

These are separate proposals and are not implied by the v4.14.0 release:

1. **Retry/backoff policy** — a bounded, inspectable retry design without silently changing the current no-auto-requeue default.
2. **Additional target platforms** — onboarding and compatibility work must remain target-specific rather than weakening the core shell/verification contract.
3. **Return lifecycle UX** — optional retention/cleanup tooling may be considered, but automatic remote outbox deletion remains out of scope until explicitly designed.
4. **Broader device compatibility evidence** — expand the Android/root-device support matrix without weakening the reference-device acceptance gates.
5. **WebUI/CLI observability** — continue improving inventories and troubleshooting while preserving redaction and typed operations.

## Explicitly out of scope without a separate design

- automatic target payload execution;
- arbitrary remote commands;
- worker lifecycle management;
- generic remote file browsing;
- RPC/task-protocol transport;
- automatic remote Return outbox deletion;
- unrelated network/DNS/HA/routing changes.

## Release discipline

A future stable release must be based on accepted runtime evidence, use a reproducible package build, keep public changelogs user-facing, preserve existing configuration on normal update and publish stable update metadata only with an available release asset.
