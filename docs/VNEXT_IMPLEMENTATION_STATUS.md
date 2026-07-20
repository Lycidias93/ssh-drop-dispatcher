# SSH Drop Dispatcher vNext Implementation Status

Roadmap: `docs/VNEXT_ROADMAP.md`

## Program status

- Planning baseline: merged through PR #51.
- Milestone 1 — Identity and integrity: approved, implementation pending.
- Milestone 2 — Retry, health and maintenance: approved, blocked on Milestone 1 runtime acceptance.
- Milestone 3 — Workflow and target expansion: approved, blocked on Milestones 1 and 2.

## Current boundaries

- Stable runtime remains `4.12.6` / `4126003`.
- Sortify marker policy remains `v4115`.
- No host execution is added.
- No stable update metadata, release, tag or publish action is authorized by the planning merge.
- No DNS, HA, VIP, default-route, static-route, MagicDNS or subnet-route changes.

## Next implementation gate

Milestone 1 must start from a fresh branch at current `main` and finish with:

`RESULT: SDD_VNEXT_M1_IDENTITY_INTEGRITY_FIXTURES_PASS`

Runtime installation and RC publication remain separate later gates.
