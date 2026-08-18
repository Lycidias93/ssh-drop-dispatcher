# Return Channel v1 — RC1 implementation status

Status: repository candidate implemented; Pixel runtime acceptance pending

Candidate:

- version: `4.14.0-return-rc1`
- versionCode: `4140001`
- public stable remains `4.13.0` / `4130007`
- shared WebUI Core: `0.4.0`
- exact Core commit: `73371fec0b5517df2d83d9796e1c79abe4484e6d`
- stable WebUI Core 0.3.0 lock remains unchanged

## Implemented transport contract

The RC1 candidate implements the generic pull-based data path defined in [`RETURN_CHANNEL_V1.md`](RETURN_CHANNEL_V1.md):

- optional target-specific return capability, disabled unless configured through `config/returns.d/<target>.conf`;
- target-specific delivery-to-artifact-SHA binding created only after the existing successful outbound remote-SHA gate;
- strict versioned Return request, receipt, acceptance and state documents;
- exact receipt path as remote commit marker;
- receipt-driven exact artifact pulls only;
- remote and local SHA-256 equality before local acceptance;
- dedicated persistent inbound store outside the dispatcher scan path;
- whole-return atomic staging/adoption;
- independent outbound delivery, return verification and producer-result state;
- bounded wait/size/count behavior;
- replay conflict detection;
- no automatic remote deletion.

## Correlation authority

A new Return request is accepted only when all of the following agree:

1. a valid `SDD_DELIVERY_BINDING_V1` exists for the requested delivery ID and source target;
2. that binding was created after dispatcher-owned remote SHA verification and contains the real outbound artifact SHA-256;
3. the corresponding target completion still resolves from the existing successful dispatcher delivery record;
4. the source target remains configured/enabled;
5. Return capability for that target is explicitly enabled.

The caller cannot supply an authoritative original artifact SHA.

## Return security boundary

RC1 does not add target payload execution, arbitrary remote commands, generic RPC, incoming SSH to the Pixel, remote directory crawling, wildcard/recursive SCP, a generic result browser or browser-selected device paths.

The remote adapter uses only a fixed internal command vocabulary for:

- exact regular-file/symlink checks;
- exact file byte size;
- exact SHA-256;
- exact SCP of the receipt or a receipt-declared artifact.

Result content, expected markers, opaque caller correlation and remote outbox paths are excluded from normal inventory/status surfaces.

## WebUI mapping

The candidate consumes the exact shared WebUI Core 0.4.0 commit above. SDD remains domain owner while Core supplies only reusable primitives:

- typed parameterized background jobs;
- active-job dedupe on declared identities;
- collection-backed target references;
- inventory-bound operations with stale-item re-resolution;
- bounded visibility-aware polling;
- honest queued/running/success/failed lifecycle without fake percentage progress.

SDD exposes typed Return request/probe/collect/wait jobs plus a secret-safe Return inventory. The browser never constructs SSH/SCP commands.

Return capability configuration itself remains domain-owned and is intentionally not exposed as an unrestricted browser path editor in RC1.

## Fixture acceptance

Repository fixtures cover:

- strict JSON including unknown/duplicate-key rejection;
- request/receipt correlation mismatch;
- path traversal and unsafe artifact names;
- symlink/special-file/config rejection;
- receipt/artifact/aggregate bounds;
- exact result-marker matching;
- atomic request/state/inbound behavior;
- dispatcher scan/inbound overlap rejection;
- stub SSH/SCP end-to-end collect;
- exact-path-only remote access and no outbox crawl;
- producer `failure` with independently verified return transport;
- idempotent unchanged recollect;
- changed-receipt replay conflict without destroying an already verified local result;
- binding without matching successful delivery record rejected;
- normal inventory redaction;
- deterministic candidate package build.

Required repository markers:

```text
RESULT: SDD_RETURN_CHANNEL_V1_FIXTURES_PASS
RESULT: SDD_VNEXT_RETURN_RC1_BUILD_DONE outcome=success workflow_exit_code=0
```

## Runtime gate

Repository PASS is not Pixel Real-Ist acceptance.

Before RC1 can be accepted on the Pixel:

1. preserve a complete rollback anchor for the accepted SDD runtime;
2. install the exact CI-produced candidate using the normal controlled Magisk lane;
3. reboot once;
4. verify exact installed runtime identity and Core 0.4 assets/binaries;
5. prove existing outbound delivery behavior remains green;
6. configure one bounded test Return sidecar without adding a new SSH trust direction;
7. run a real target Return smoke covering request → available → collect → verified and SHA/correlation evidence;
8. prove returned data never enters the dispatch scan path;
9. require the installed-runtime acceptance marker before any stable promotion.

No public stable release is authorized by this candidate status document.
