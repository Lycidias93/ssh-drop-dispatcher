# Return Channel v1 RC3

RC3 is the WebUI Core 0.6 synchronization candidate for the already implemented Return Channel v1.

## Candidate identity

- version: `4.14.0-return-rc3`
- versionCode: `4140003`
- shared WebUI Core: `0.6.0`
- pinned template commit: `cb991dc8d7d982defbe5e34c5c0e0908efa9b236`

## Scope

RC3 keeps the Return Channel transport, receipt, correlation, inbound-store and security contracts unchanged from RC2. It updates only the shared WebUI Core consumer layer to the current Core 0.6 contract and rebuilds the candidate against that exact pin.

Core 0.6 remains API-compatible with existing SDD adapters and adds generic state-aware/mobile base-UI behavior: optional active/blocked action state, clearer Preview vs Apply wording, session-cached inventory switching with explicit live refresh, stale-response protection, and responsive inventory/navigation rendering.

The public SDD core still does not gain remote execution, arbitrary shell input, a generic file browser, private Crosswork/Codex fields, or automatic host payload execution.

Stable `4.13.0` remains unchanged.
