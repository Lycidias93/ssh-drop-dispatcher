# SSH Drop Dispatcher vNext Roadmap

Status: active, reconciled after public stable `v4.13.0`

Reconciliation base:

- repository: `Lycidias93/ssh-drop-dispatcher`
- branch: `main`
- planning-base commit: `60620215d368dc7cbd486a7302b32280c0190ce1`
- public stable: `4.13.0` / `4130007`
- CLI: v3
- persistent runtime SoT: `/data/adb/ssh-drop-dispatcher`
- Sortify marker policy remains `v4115`
- Pixel remains the dispatcher control plane
- no automatic target payload execution
- no DNS, HA, VIP, default/static route, MagicDNS or subnet-route work belongs to this roadmap

The previous roadmap was written against `4.12.6` and is historical context only where it conflicts with the reconciled state below.

## Stable capabilities already realized

The following items must not be reimplemented as new vNext work:

- dispatcher-owned remote verification;
- explicit per-target `shell="bash|sh"` with fail-closed missing-Bash behavior;
- mandatory remote SHA-256 parity before target completion;
- BerylAX/OpenWrt legacy-SCP compatibility through target `scp_flags`;
- strict target-prefix routing and checksum/signature sidecar blocking;
- duplicate/browser-alias handling and canonical completion evidence;
- independent target free-space policy values;
- CLI v3 delivery trace, queue/failure/quarantine inspection, preflight, `dispatch-file --wait`, delivery receipts and incident context;
- machine-readable ENV/JSON output and secret-safe ChatGPT context;
- explicit `python_delivery=unsupported` policy;
- standalone WebUI Core 0.3.0, typed target/profile management, preview-before-apply, bounded safe import/export and target readiness actions;
- secret-safe ntfy configured-state and read-only Sortify inventory.

The existing outbound delivery engine remains authoritative. vNext must extend it rather than create another outbound uploader.

## Reconciliation of the old milestones

| Previous roadmap item | Reconciled state after v4.13.0 | vNext treatment |
|---|---|---|
| Delivery identity helper | Pure identity-v2 helpers and fixtures exist. CLI v3 also has an opaque `SDD-*` delivery ID derived from the existing dispatcher record. These are not one unified persisted identity contract. | Preserve the current CLI delivery ID. Add only the SHA-bound correlation evidence required by Return Channel v1; do not rewrite historical delivery state. |
| Narrow duplicate-alias recognition | Stable behavior exists. | Keep unchanged unless an independent regression is found. |
| Alias-aware inspection | CLI v3 trace/inspect and existing delivery status/wait provide current operator behavior. | Not a Return Channel prerequisite. |
| Mandatory normal-path remote SHA | Stable and dispatcher-owned. | Hard invariant; reuse the same SHA implementation for return verification where applicable. |
| Sortify marker identity | Canonical completion evidence already includes canonical name, SHA-256, target set and `v4115` policy. | Keep `v4115`; Return Channel must not change release-marker semantics. |
| Independent pi3/pi4 space policy | Stable target-specific configuration exists. | Complete; no new work. |
| Retry database/backoff | A fail database exists, but CLI capabilities explicitly keep automatic requeue disabled. | Deferred; not required for Return Channel v1. |
| Queue-aware health | CLI/WebUI inventories and health evidence are substantially richer than the old baseline, but no new automatic retry engine is implied. | Preserve current behavior; return state gets its own namespace. |
| Follow-up coalescing | Event-pending/watcher plumbing exists in the stable service. | Preserve. |
| Python policy | Resolved as unsupported. | Complete unless a future independent proposal changes it. |
| Canonical operator helper | `sdd dispatch-file <file> --wait` and delivery receipts implement the intended orchestration without a second uploader. | Preserve. |
| Structured operator view | CLI v3 and WebUI inventories/trace provide it. | Preserve; add return-specific views only after the return contract is stable. |
| OMEN onboarding | Not part of stable. | Deferred separate target project. |
| Optional two-way receipt channel | Not implemented. | **Current active vNext milestone: Return Channel v1.** |

## Current active milestone — Return Channel v1

Contract: [`RETURN_CHANNEL_V1.md`](RETURN_CHANNEL_V1.md)

Objective:

> Add a generic, pull-based, SHA-verified result/receipt path from an already configured target back to the Pixel without turning SDD into an execution, RPC or remote-shell orchestration system.

Architecture:

```text
Pixel / SDD outbound  --SSH/SCP-->  target inbox
external control plane             target worker
Pixel / SDD return    <--SSH/SCP--  target outbox
```

The Pixel remains the initiator of every SDD network operation.

### Hard boundaries

Return Channel v1 must preserve all of these:

- no target payload autoexecution;
- no arbitrary remote command transport or generic RPC endpoint;
- no incoming SSH requirement on the Pixel;
- no write of returned data into the configured dispatcher scan directory;
- no result acceptance without a known delivery correlation and original artifact SHA-256;
- no change to successful outbound delivery state because a later result is missing, failed or timed out;
- no new SSH key or trust direction;
- no private target, host, path, key, token or Crosswork/Codex protocol in the public repository;
- no DNS/HA/VIP/route/MagicDNS/subnet-route change.

### Implementation order

1. Freeze the versioned request, remote receipt and local state schemas in `RETURN_CHANNEL_V1.md`.
2. Add strict parser/validator fixtures before any network code.
3. Add local return request/state storage and atomic inbound staging fixtures; still no network access.
4. Add durable delivery-to-SHA binding evidence after successful existing remote-SHA delivery, without changing delivery completion semantics.
5. Add the bounded, exact-path SSH/SCP pull adapter using existing target identity and SSH configuration; no remote directory crawling.
6. Wire additive `sdd return ...` commands into CLI v3 with ENV/JSON output and redaction.
7. Run compatibility fixtures proving existing delivery, receipts, target profiles, WebUI target editing and Sortify behavior are unchanged.
8. Build a prerelease/candidate only; stable update metadata remains untouched.
9. Verify candidate package/static guards and preserve a complete Pixel rollback anchor before installation.
10. Run controlled Pixel candidate verification, then a configured target return smoke. No public stable promotion is implied by this roadmap.

### WebUI order

Do not design a second WebUI transport stack. WebUI integration starts only after the CLI/schema contract has survived candidate verification. It may expose return state and a bounded manual collect action, but never a generic file browser or remote shell.

## Deferred work outside Return Channel v1

These remain separate proposals and must not expand the first return-channel candidate:

- automatic retry/backoff engine;
- OMEN/Windows onboarding;
- automatic target execution;
- worker lifecycle management;
- Crosswork/Codex coordination or task protocols;
- arbitrary remote commands;
- generic remote file browsing;
- automatic remote outbox cleanup.

## Release discipline

- Do not patch active Pixel runtime from an unverified worktree.
- Do not change stable `update.json` during candidate development.
- Fixtures and static guards precede Pixel mutation.
- Build a complete candidate artifact before installation.
- Back up active runtime and preserve a visible rollback anchor.
- Post-reboot runtime verification is mandatory before acceptance.
- Public release notes/changelog contain only user-relevant changes; internal hashes, CI/run IDs, RC provenance and acceptance evidence remain internal evidence.
- No release, tag or publish is authorized by this planning document alone.

## Definition of done for Return Channel v1 planning

Planning is complete when:

- the current `4.13.0` stable baseline and CLI v3 behavior are the source of truth;
- stale `4.12.6` roadmap assumptions are explicitly reconciled;
- request, receipt and state schemas are versioned;
- remote outbox and local inbound layout are fixed;
- delivery, return and producer execution/result states are independent;
- correlation binds a known delivery ID, original artifact SHA-256 and source target;
- path, symlink, traversal, size, count, timeout, replay and redaction invariants are documented;
- the fixture matrix is defined before implementation;
- migration/rollback behavior is defined;
- no target autoexecution or arbitrary remote command surface is introduced;
- consumer-specific coordination remains outside the public SDD contract.
