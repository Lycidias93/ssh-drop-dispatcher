# SSH Drop Dispatcher vNext Implementation Status

Roadmap: `docs/VNEXT_ROADMAP.md`

## Program status

- Planning baseline: merged through PR #51.
- Milestone 1 — Identity and integrity: **in progress** through issue #53.
- Milestone 1 foundation: pure delivery-identity helper and fixture suite implemented on the current feature branch.
- Milestone 2 — Retry, health and maintenance: approved through issue #54, blocked on Milestone 1 runtime acceptance.
- Milestone 3 — Workflow and target expansion: approved through issue #55, blocked on Milestones 1 and 2.

## Current Milestone 1 proof

The foundation helper defines:

- identity schema version `2`;
- semantic name, SHA-256, normalized target set and policy identity key;
- exact versus parenthesized-browser-alias classification;
- intentional numeric/date suffix preservation;
- dash-alias handling only through explicit opt-in;
- machine-readable identity description.

Fixture marker:

`RESULT: SDD_VNEXT_M1_IDENTITY_HELPER_FIXTURES_PASS`

This foundation is not wired into the active dispatcher service yet. Normal-path remote SHA enforcement, marker identity v2, alias-aware status/wait and pi3 threshold integration remain open in issue #53.

## Current boundaries

- Stable runtime remains `4.12.6` / `4126003`.
- Sortify marker policy remains `v4115`.
- No host execution is added.
- No active Pixel runtime or stable update metadata is changed.
- No release, tag or publish action is authorized by this implementation step.
- No DNS, HA, VIP, default-route, static-route, MagicDNS or subnet-route changes.

## Milestone 1 final gate

Milestone 1 is complete only after service integration and the full fixture matrix finish with:

`RESULT: SDD_VNEXT_M1_IDENTITY_INTEGRITY_FIXTURES_PASS`

Runtime installation and RC publication remain separate later gates.
