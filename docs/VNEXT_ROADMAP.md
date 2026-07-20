# SSH Drop Dispatcher vNext Roadmap

Status: approved planning baseline

Baseline:

- repository base: `e552c0274d318dce90b7d6129774d1f6e691322c`
- active public runtime: `4.12.6` / `4126003`
- Sortify marker policy remains `v4115`
- no host execution is added to the dispatcher
- no DNS, HA, VIP, default-route, static-route, MagicDNS or subnet-route change belongs to this roadmap

## Objective

Make delivery identity, alias handling, content integrity, retry state and operator visibility deterministic without weakening the existing strict target-prefix, Sortify-release-marker or no-host-run contracts.

The central invariant is:

> A delivery is identified by semantic artifact name, resolved target set and content SHA-256. Requested filename, browser/download alias and effective remote filename are metadata of that identity, not independent delivery records.

## Milestone 1 — Identity and integrity

This is the first implementation and release-candidate scope.

### 1. Delivery identity contract

Introduce a versioned identity record containing at least:

- `identity_version`
- `requested_name`
- `semantic_name`
- `effective_remote_name`
- `sha256`
- normalized resolved target set
- Sortify policy
- identity state

The target set must be normalized deterministically before identity comparison.

### 2. Narrow duplicate-alias recognition

Current alias handling must no longer treat every trailing numeric dash suffix as a browser duplicate.

Required behavior:

- recognize known browser/download aliases such as `name (1).ext` and narrowly defined duplicate forms;
- preserve intentional names such as date, build and version suffixes;
- never reuse an alias result when SHA-256 or target set differs;
- log the requested, semantic and effective names explicitly.

### 3. Alias-aware status and wait

`--delivery-status` and `--wait-delivery` must resolve by delivery identity rather than exact requested basename only.

Terminal outcomes:

- `PASS_EXACT`
- `PASS_ALIAS_REUSED`
- `FAIL_SHA_CONFLICT`
- `FAIL_TARGET_CONFLICT`
- `FAIL_QUARANTINED`
- `FAIL_TERMINAL_DELIVERY`
- bounded timeout only while the identity remains genuinely pending

The command output must remain machine-readable and include `host_run=no`.

### 4. Mandatory normal-path remote SHA verification

The regular SCP path must verify remote SHA-256 before recording target completion.

Required order:

1. local preflight and local SHA-256;
2. upload to temporary remote path;
3. atomic remote rename;
4. remote existence and syntax/basic verification;
5. remote SHA-256 readback;
6. exact local/remote digest comparison;
7. only then write done/complete state and Sortify release marker.

A missing or mismatched digest is a delivery failure and must not produce `released=yes`.

### 5. Sortify marker identity v2

Keep `policy=v4115`, but harden marker identity and validation.

Requirements:

- explicit marker schema/version field;
- canonical/semantic name passed explicitly, never inherited from ambient shell state;
- marker content validates SHA-256, semantic name and normalized target set before reuse;
- marker reuse with matching SHA but conflicting name or targets is rejected;
- partial delivery remains `released=no` with accurate done and pending target sets.

### 6. pi3 space-policy variable fix

Read pi3 and pi4 free-space thresholds independently:

- pi3 uses `REMOTE_MIN_FREE_KB_pi3` and `REMOTE_WARN_FREE_KB_pi3`;
- pi4 uses `REMOTE_MIN_FREE_KB_pi4` and `REMOTE_WARN_FREE_KB_pi4`.

Add a regression fixture proving distinct values are honored.

### 7. Milestone 1 fixture matrix

Static fixtures must cover at least:

- exact single-target delivery;
- exact multi-target delivery;
- browser alias with identical SHA and targets;
- intentional numeric/date suffix not classified as alias;
- alias with changed SHA;
- alias with changed target set;
- stale marker with matching SHA but wrong semantic name;
- stale marker with matching SHA but wrong target set;
- regular-path remote SHA match;
- regular-path remote SHA mismatch;
- missing remote SHA implementation;
- partial multi-target delivery;
- pi3/pi4 distinct space thresholds;
- BerylAX `scp -O` regression;
- strict target-prefix and sidecar blocking regression.

Acceptance marker:

`RESULT: SDD_VNEXT_M1_IDENTITY_INTEGRITY_FIXTURES_PASS`

## Milestone 2 — Retry, health and maintenance

Start only after Milestone 1 fixtures and Pixel candidate smoke are green.

### Retry database

Use `dispatch.faildb` as an actual versioned state store with:

- identity key;
- target;
- attempt count;
- first and last failure timestamps;
- next retry timestamp;
- failure reason;
- terminal/nonterminal state.

Retry must be bounded and use deterministic backoff. Repeated notifications must remain debounced.

### Queue-aware health

Health and WebUI status should expose:

- pending count;
- retrying count;
- terminal-failure count;
- oldest pending age;
- last delivery result and reason;
- scan-lock age;
- follow-up pending state.

Alive processes alone must not force `status=OK` when delivery state is degraded.

### Follow-up coalescing

At most one delayed follow-up scan may be pending. Additional events set a flag instead of starting more background sleepers.

### State and log maintenance

Add read-only dry-run first, then separately gated apply support for:

- stale inflight entries;
- obsolete debounce records;
- superseded legacy state records;
- bounded log rotation;
- backup and rollback evidence before compaction.

Acceptance marker:

`RESULT: SDD_VNEXT_M2_RETRY_OBSERVABILITY_FIXTURES_PASS`

## Milestone 3 — Workflow and target expansion

### Python policy decision

Resolve the current documentation/runtime mismatch explicitly:

- either implement `.py` support with local AST validation and target-aware remote validation;
- or remove `.py` from active workflow claims.

No implicit partial support is accepted.

### Canonical operator helper

Provide one caller-facing helper that creates a target artifact, records expected identity, waits through alias resolution, verifies final remote SHA and prints a copyable next Termux block when a follow-up action remains.

This helper does not execute the remote artifact.

### Structured operator view

Expose a compact identity-centric queue view for CLI and WebUI:

- requested and effective names;
- semantic identity;
- targets;
- state;
- retry timing;
- remote SHA status;
- last failure;
- lock/watcher state.

### OMEN onboarding

Treat OMEN as a separate target project after Linux/BerylAX identity and integrity behavior is stable.

Windows/OpenSSH verification must not inherit Bash, systemd, SFTP or Linux path assumptions.

### Optional two-way receipt channel

Design a distinct receipt path for later host execution results.

Rules:

- dispatcher delivery and host execution remain separate states;
- no automatic host execution;
- receipt binds to delivery identity and artifact SHA-256;
- receipt origin and expected result marker are verified;
- missing receipt never rewrites a successful delivery as an upload failure.

Acceptance marker:

`RESULT: SDD_VNEXT_M3_WORKFLOW_TARGET_FIXTURES_PASS`

## Implementation order

1. Add identity helpers and pure fixtures.
2. Correct alias classification.
3. Introduce identity-aware marker validation.
4. Enforce remote SHA on the normal upload path.
5. Upgrade status/wait terminal-state handling.
6. Fix pi3 space variables.
7. Run static guards and candidate-package verification.
8. Build a prerelease candidate without changing stable update metadata.
9. Run Pixel install, reboot verify and exact/alias/conflict delivery smokes.
10. Promote only after all Milestone 1 acceptance gates pass.

## File matrix for Milestone 1

Expected code and test scope:

- `source/magisk/service.sh`
- new identity/fixture helpers under `source/magisk/tools/` or `tests/`
- `docs/FEATURES.md`
- `docs/HOW_IT_WORKS.md`
- `docs/DELIVERY_SAFETY_V4121.md` or a superseding vNext document
- `README.md`
- `CHANGELOG.md`
- release-candidate notes and metadata only after implementation verification

Unexpected private target, key, host inventory, route or runtime files are out of scope.

## Release discipline

- Do not patch the active Pixel runtime from an unverified worktree.
- Do not change stable `update.json` during RC development.
- Build a complete candidate artifact first.
- Verify package contents, shell syntax, fixtures and public/private guards.
- Back up active runtime before installation.
- Preserve the visible rollback anchor.
- Require post-reboot runtime status and identity-specific delivery smokes.
- No release, tag or publish is authorized by this planning document alone.

## Definition of done

The vNext program is complete only when:

- Milestone 1 identity and integrity behavior is final and runtime verified;
- Milestone 2 retry and health state is bounded and runtime verified;
- Milestone 3 workflow claims match implemented behavior;
- active documentation contains one current dispatcher baseline;
- Sortify policy compatibility remains verified;
- `host_run=no` remains true for dispatcher delivery;
- no DNS/HA/VIP/route behavior changed;
- no private data entered public repository history.
