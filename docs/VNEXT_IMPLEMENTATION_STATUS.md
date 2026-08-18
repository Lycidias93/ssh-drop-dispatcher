# SSH Drop Dispatcher vNext Implementation Status

Roadmap: [`docs/VNEXT_ROADMAP.md`](VNEXT_ROADMAP.md)

Return Channel contract: [`docs/RETURN_CHANNEL_V1.md`](RETURN_CHANNEL_V1.md)

## Current baseline

- Public stable: `4.13.0` / `4130007`.
- Planning base: `main` at `60620215d368dc7cbd486a7302b32280c0190ce1`.
- CLI: v3.
- Persistent Pixel runtime SoT: `/data/adb/ssh-drop-dispatcher`.
- Existing outbound transport remains Pixel-initiated SSH/SCP through the single dispatcher delivery engine.
- Dispatcher-owned remote SHA-256 verification remains mandatory before target completion.
- Existing `SDD_DELIVERY_RECEIPT_V1` records remain valid.
- Target payload autoexecution remains forbidden.

The previous status document was based on the early `4.13.0-verify-owner-rc1` phase and is superseded by this reconciled stable baseline.

## Stable capabilities already implemented

The following work is already part of the `v4.13.0` line and is not pending vNext implementation:

- dispatcher-owned target verification;
- explicit `shell="bash|sh"` target policy with fail-closed missing-Bash behavior;
- remote SHA-256 parity before successful outbound completion;
- persistent done/complete/failure/inflight/quarantine delivery state;
- duplicate/browser-alias and canonical completion handling;
- CLI v3 delivery trace, inspect, queue/failure/quarantine inventory, preflight and `dispatch-file --wait`;
- opaque `SDD-*` delivery IDs derived from the existing dispatcher record;
- `SDD_DELIVERY_RECEIPT_V1` workflow receipts;
- redacted incident/ChatGPT context and ENV/JSON machine output;
- `python_delivery=unsupported` as an explicit policy decision;
- standalone WebUI Core 0.3.0 with typed target/profile administration, preview-before-apply, bounded import/export and target-readiness actions;
- secret-safe ntfy configured-state and read-only Sortify inventory.

## Roadmap reconciliation

The old roadmap baseline `4.12.6` is obsolete. `docs/VNEXT_ROADMAP.md` now distinguishes:

- capabilities already realized by `v4.13.0`;
- partially realized identity work that must not be rewritten casually;
- deferred retry/OMEN work;
- the **Return Channel v1** as the current active vNext milestone.

Two current identities must remain distinct:

1. the CLI v3 opaque delivery ID, derived from the existing dispatcher record;
2. the real artifact SHA-256 verified by the outbound dispatcher.

Return Channel v1 therefore adds explicit delivery-to-SHA binding evidence instead of pretending the current delivery ID is itself a cryptographic artifact identity.

## Return Channel v1 planning status

Planning contract: **defined; implementation not started**.

Fixed decisions in `RETURN_CHANNEL_V1.md`:

- pull-based return transport initiated by the Pixel;
- no incoming SSH requirement on the Pixel;
- no autoexecution, RPC or arbitrary remote-command surface;
- optional per-target return capability in separate `config/returns.d/<target>.conf` sidecars;
- return capability disabled by default;
- exact-path remote outbox model with receipt published last as the commit marker;
- dedicated Pixel inbound store under the persistent SDD runtime, never the normal dispatcher scan path;
- additive `SDD_DELIVERY_BINDING_V1` evidence for `deliveryId + target + artifactSha256` correlation;
- `SDD_RETURN_REQUEST_V1`, `SDD_RETURN_RECEIPT_V1`, `SDD_RETURN_ACCEPTANCE_V1` and versioned return-state semantics;
- strict origin, correlation, path, symlink, replay, size/count, SHA and optional result-marker validation;
- receipt-driven exact-file pull only; no recursive/list-all outbox collection;
- bounded polling and transfer sizes;
- atomic local staging/adoption;
- independent outbound-delivery, return-verification and producer-result state;
- producer `resultState` treated as metadata, not as SDD execution state;
- optional opaque caller correlation only; no Crosswork/Codex-specific fields in the public core;
- additive CLI v3 `sdd return ...` surface planned before any WebUI integration;
- migration/rollback behavior defined so `v4.13.0` can ignore new return state safely.

Planning acceptance target:

```text
RESULT: SDD_RETURN_CHANNEL_V1_CONTRACT_READY
```

## Required implementation order

The next phase is deliberately local and fixture-first:

1. strict return schema/parser fixtures;
2. local request/state/inbound atomicity fixtures;
3. replay/path/symlink/size/count/redaction fixtures;
4. outbound compatibility fixtures proving delivery completion remains independent;
5. additive delivery-binding implementation after the existing successful remote-SHA gate;
6. only then the exact-path SSH/SCP pull adapter;
7. additive CLI v3 return commands;
8. complete static/package guards;
9. prerelease/candidate build;
10. Pixel backup/install/reboot verification and one private configured-target return smoke.

No Pixel/runtime/network mutation belongs to the planning phase.

## Explicitly outside this milestone

- Codex worker implementation;
- Crosswork task or coordination schema;
- Crosswork SSH trigger;
- arbitrary remote commands;
- automatic target payload execution;
- private Heimnetz target/outbox configuration in the public repository;
- generic remote file browsing;
- automatic remote outbox deletion/acknowledgement;
- automatic retry/backoff engine;
- OMEN/Windows onboarding;
- WebUI return implementation before the CLI/schema contract is candidate-verified.

## Security boundaries

Return Channel development must remain fail-closed around:

- known delivery correlation;
- original artifact SHA-256 binding;
- exact source target/origin;
- remote and local path containment;
- symlink/special-file rejection;
- bounded receipt/artifact count and size;
- remote/local/receipt SHA parity;
- replay/stale-result conflicts;
- scan-path/inbound-path separation;
- result-content redaction;
- bounded polling/timeouts.

A missing, failed or timed-out return must never rewrite a successful outbound delivery into a delivery failure.

No DNS, HA, VIP, default/static route, MagicDNS or subnet-route change is part of this work.

## Current status

```text
stable_baseline=4.13.0
roadmap_reconciled=yes
return_channel_v1_contract=defined
implementation_started=no
runtime_mutation=no
release_authorized=no
```
