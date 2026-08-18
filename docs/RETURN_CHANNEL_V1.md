# SSH Drop Dispatcher Return Channel v1 Contract

Status: planning contract; no runtime implementation is implied by this document

Baseline:

- public stable: `4.13.0` / `4130007`
- CLI: v3
- runtime SoT: `/data/adb/ssh-drop-dispatcher`
- existing outbound engine remains `service.sh`
- dispatcher-owned remote SHA verification remains mandatory
- existing `SDD_DELIVERY_RECEIPT_V1` records remain valid and unchanged
- target payload autoexecution remains forbidden

## 1. Purpose

Return Channel v1 adds a generic verified data path from an already configured SSH target back to the Pixel.

It is a transport/receipt feature only.

SDD does **not** become:

- a remote execution engine;
- an RPC framework;
- a worker scheduler;
- a generic remote shell;
- a generic remote file browser.

The intended layering is:

```text
SDD outbound = data plane to target
external worker/control plane = optional execution outside SDD
SDD return = data plane back to Pixel
external coordinator = consumer of verified result
```

The Pixel initiates all SDD network operations.

## 2. Existing v4.13.0 contracts reused

Return Channel v1 reuses rather than replaces:

- configured target identity and SSH host mapping;
- existing SSH keys and known-host trust;
- dispatcher delivery records;
- CLI v3 opaque delivery ID format `SDD-<16 hex>`;
- dispatcher-owned SHA-256 implementation;
- ENV/JSON machine-output conventions;
- redaction rules;
- fail-closed shell/path policy.

The existing CLI v3 delivery ID is the correlation key for v1. The historical dispatcher record remains delivery truth. Return Channel v1 does not rewrite old `dispatch.done`, `dispatch.complete`, `dispatch.faildb`, `dispatch.inflight`, `dispatch.quarantined` or `delivery.receipts.jsonl` records.

## 3. Delivery-to-SHA binding prerequisite

### Problem

The current CLI v3 `SDD-*` delivery ID is derived from the existing dispatcher record:

```text
<basename>|<cksum-crc>:<bytes>
```

The stable delivery path separately verifies the real artifact SHA-256 remotely, but the existing delivery receipt does not provide a durable `deliveryId -> target -> artifactSha256` index for every normal delivery.

Return correlation must not infer that SHA from a filename, stale local file, log line or checksum collision.

### Contract

vNext adds additive delivery binding evidence after an existing target delivery has passed remote SHA verification.

Logical location:

```text
/data/adb/ssh-drop-dispatcher/delivery-bindings/<delivery-id>/<target>.json
```

Schema:

```text
SDD_DELIVERY_BINDING_V1
```

Required semantics:

- `schema`
- `deliveryId`
- `artifactSha256`
- `target`
- `completedEpoch`
- `remoteShaVerified=true`

Rules:

- one binding is target-specific so a completed target in a multi-target delivery can be correlated independently;
- the binding is written only after the existing remote SHA gate succeeds;
- a binding write failure never rewrites or invalidates an already successful outbound delivery;
- a return request requires a valid binding; it fails closed when the binding is absent or contradictory;
- v1 does not guess/backfill bindings for historical deliveries;
- legacy deliveries without a binding remain valid deliveries but are not return-capable unless a later explicitly designed migration can prove the binding without inference.

This is correlation evidence, not a second delivery state machine.

## 4. Return capability configuration

### Separate capability sidecar

Return configuration is intentionally separate from the existing target profile schema so v4.13.0 typed target editing and safe import/export do not become incompatible before WebUI support exists.

Logical directory:

```text
/data/adb/ssh-drop-dispatcher/config/returns.d/
```

Per-target file:

```text
<target>.conf
```

Required v1 fields:

```text
return_enabled="1"
remote_outbox="/absolute/clean/path"
```

Rules:

- absence of a sidecar means disabled;
- `return_enabled` defaults to `0`;
- the sidecar filename must resolve to an existing base target name;
- collection requires the base target to be enabled;
- SSH user/host/port/key/known-host identity comes only from the existing target/SSH configuration;
- no additional private key or incoming Pixel trust direction is introduced;
- `remote_outbox` must be an absolute normalized path from a strict allowlist and must not be `/`;
- remote outbox path values are never exposed by default status, ChatGPT context or public support output;
- public package defaults contain no real target or private outbox path.

### Global bounds

Implementation must expose bounded defaults in normal runtime configuration. Initial v1 contract defaults:

```text
RETURN_MAX_RECEIPT_BYTES=65536
RETURN_MAX_ARTIFACTS=8
RETURN_MAX_ARTIFACT_BYTES=268435456
RETURN_MAX_TOTAL_BYTES=536870912
RETURN_MAX_WAIT_SECONDS=3600
RETURN_POLL_INTERVAL_SECONDS=5
```

Validation rules:

- receipt: 1..64 KiB by default;
- artifact count: 1..8 by default;
- each artifact: non-empty and <=256 MiB by default;
- aggregate declared/pulled result data: <=512 MiB by default;
- user-requested wait is clamped to the configured maximum;
- polling interval is bounded; implementation must reject zero/tight busy loops.

Bounds may become configurable, but disabling all bounds is not allowed in v1.

## 5. Return request contract

A return is explicitly registered on the Pixel before it can be collected.

Schema:

```text
SDD_RETURN_REQUEST_V1
```

Logical location:

```text
/data/adb/ssh-drop-dispatcher/inbound/requests/<return-id>.json
```

Required fields:

```text
schema
returnId
deliveryId
artifactSha256
sourceTarget
expectedResultType
createdEpoch
```

Optional fields:

```text
expectedResultMarker
callerCorrelation
```

### Identifier rules

`returnId` is generated by SDD on the Pixel and is opaque:

```text
SDR-<32 lowercase hex>
```

It must be unique and derived from secure local randomness, not from a predictable counter.

The v1 request uses one canonical `returnId`; a second mandatory producer-defined receipt ID is intentionally not introduced. The accepted receipt SHA-256 becomes the local immutable receipt identity for replay/idempotency decisions.

### Correlation rules

Before a request can be created, SDD must prove:

1. `deliveryId` resolves to an existing dispatcher delivery;
2. `sourceTarget` is a configured target for that delivery;
3. that target has a successful delivery binding;
4. binding `artifactSha256` is a valid 64-hex SHA-256;
5. request `artifactSha256` is copied from that binding, never accepted from caller input as authority.

`callerCorrelation` is optional opaque consumer metadata. It is not interpreted by SDD, is not a Crosswork/Codex field, and must never be mandatory for the public transport contract.

If supplied, it is exact-match correlation metadata and is omitted from default status/ChatGPT context.

### Expected result contract

`expectedResultType` is a bounded opaque type identifier, not executable behavior.

`expectedResultMarker` is optional. If present:

- it is a bounded printable single-line literal;
- the remote receipt must report the same marker;
- after SHA verification, the primary textual result artifact must contain that exact line;
- the marker value itself is not printed by secret-safe summary/status surfaces.

No command, script or shell expression can be encoded as an expected result action.

## 6. Remote outbox publication contract

The producer/worker is external to SDD.

For a known return ID it publishes only inside:

```text
<remote_outbox>/<return-id>/
```

Final receipt path:

```text
<remote_outbox>/<return-id>/receipt.json
```

Payload examples:

```text
result.json
result.txt
diagnostics.tar.gz
```

### Producer publication order

A conforming producer must:

1. create result files under temporary names/paths;
2. finish writing each payload;
3. atomically rename each payload to its final receipt-referenced basename;
4. construct the final receipt referencing those immutable final files;
5. publish `receipt.json` **last** through an atomic rename;
6. leave receipt and referenced payloads immutable for the configured retention period.

The existence of final `receipt.json` is the remote commit marker.

SDD v1 does not delete or acknowledge remote files automatically.

## 7. Remote receipt schema

Remote receipt format is strict JSON.

Schema:

```text
SDD_RETURN_RECEIPT_V1
```

Required top-level fields:

```text
schema
returnId
deliveryId
artifactSha256
sourceTarget
resultType
resultState
primaryArtifact
artifacts
```

Optional top-level fields:

```text
resultMarker
callerCorrelation
producerStartedEpoch
producerEndedEpoch
```

Example shape using public/generic values:

```json
{
  "schema": "SDD_RETURN_RECEIPT_V1",
  "returnId": "SDR-0123456789abcdef0123456789abcdef",
  "deliveryId": "SDD-0123456789abcdef",
  "artifactSha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  "sourceTarget": "alpha",
  "resultType": "example.result.v1",
  "resultState": "success",
  "primaryArtifact": "result.json",
  "artifacts": [
    {
      "name": "result.json",
      "sha256": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      "sizeBytes": 1234
    }
  ]
}
```

### `resultState`

Producer result state is metadata and is not SDD delivery state.

Allowed v1 values:

```text
success
failure
partial
cancelled
```

A receipt can therefore be transport-verified while reporting `resultState=failure`.

### Artifact entries

Every artifact entry requires:

```text
name
sha256
sizeBytes
```

Optional descriptive fields may be added only through a future schema version; v1 parsers reject unknown fields.

`primaryArtifact` must exactly name one item in `artifacts`.

### Strict JSON requirements

The parser must:

- reject unknown fields;
- reject duplicate object keys;
- reject extra JSON values/trailing documents;
- reject invalid UTF-8/control characters where applicable;
- never source, `eval` or execute receipt content;
- reject invalid field types instead of coercing them;
- validate all bounds before any payload SCP begins.

## 8. Path and filename rules

Remote receipt and artifact paths are constructed by SDD; they are never accepted as arbitrary full paths from the receipt.

Artifact `name` must be a plain basename and must reject at least:

- `/` or `\\`;
- `.` and `..` path segments;
- leading `.`;
- control characters/newlines/tabs;
- shell metacharacters outside the defined safe basename set;
- names longer than the v1 limit.

SDD constructs:

```text
<remote_outbox>/<return-id>/<artifact-name>
```

It never honors an absolute artifact path from a producer.

For the receipt and every payload, remote probes must reject:

- symlinks;
- directories;
- device/FIFO/socket/special files;
- paths escaping the configured outbox.

Local inbound staging similarly accepts only regular non-symlink files.

## 9. Pull and verification algorithm

Return collection is exact-path and receipt-driven. There is no `scp outbox/*`, recursive crawl or generic directory browser.

Required order:

1. load and validate the local `SDD_RETURN_REQUEST_V1`;
2. load the matching base target plus return sidecar;
3. validate that return capability is enabled and paths do not overlap the dispatcher scan path;
4. probe exact remote `receipt.json` path using the existing SSH identity;
5. reject symlink/non-regular receipt and enforce receipt byte limit;
6. SCP only the receipt into a local staging directory under the inbound root;
7. parse the receipt strictly without executing/sourcing it;
8. compare `returnId`, `deliveryId`, original `artifactSha256`, `sourceTarget`, `resultType`, optional marker and optional caller correlation against the local request/binding;
9. validate artifact count, basenames, declared sizes and aggregate bounds;
10. for each referenced artifact, probe the exact constructed remote path and reject symlink/non-regular files;
11. obtain the remote SHA-256 through a fixed dispatcher-owned verification command;
12. SCP the exact artifact to local staging;
13. compute local SHA-256 and require `receipt SHA == remote SHA == local SHA`;
14. require actual local byte size to equal the bounded declared size;
15. if an expected marker exists, verify the exact line in the primary artifact without printing artifact content;
16. create a local verification envelope;
17. atomically rename the complete staging directory to the verified inbound location;
18. atomically update return state and append a compact local receipt index.

A partial set is never promoted to verified state.

## 10. Pixel inbound store

Returned data is permanently separated from the outbound scan path.

Logical layout:

```text
/data/adb/ssh-drop-dispatcher/inbound/
  requests/
  state/
  .staging/
  verified/
  receipts.jsonl
```

Verified return layout:

```text
verified/<return-id>/
  receipt.json
  acceptance.json
  artifacts/
    <receipt-referenced-files>
```

Rules:

- mode is private/root-owned (`0700` directories, `0600` data where applicable);
- `.staging` and `verified` are on the same filesystem so final directory rename is atomic;
- staging residue never counts as verified;
- existing verified content is never overwritten;
- identical re-collection is idempotent;
- same return ID with different receipt/result identity is a replay conflict;
- inbound files are never automatically dispatched or executed;
- inbound artifact content is never included in ordinary logs, status, WebUI summary or ChatGPT context.

### Scan-path overlap guard

Return Channel v1 must fail closed if the configured dispatcher scan path and the fixed inbound root overlap in either direction.

In particular, inbound data must never be written to `/storage/emulated/0/Download` or another active dispatcher scan root.

## 11. Local acceptance envelope and receipt index

The remote receipt is preserved byte-for-byte as `receipt.json` after verification.

SDD additionally writes local verification evidence:

```text
acceptance.json
```

Schema:

```text
SDD_RETURN_ACCEPTANCE_V1
```

It records only verification metadata, including:

- `returnId`
- `deliveryId`
- `sourceTarget`
- remote receipt SHA-256
- artifact count and verified aggregate bytes
- correlation verification result
- origin verification result
- SHA verification result
- marker verification result when applicable
- verified epoch
- local state `verified`

It does not copy result content into the envelope.

A compact append-only `inbound/receipts.jsonl` may index accepted return IDs and verification outcomes. The per-return request/state/acceptance files remain reconstructable truth; the JSONL index is not allowed to become the only copy of state.

## 12. State separation

Outbound delivery state is immutable with respect to later return outcomes.

Examples:

```text
delivery=done
return=pending
producer_result=unknown
```

```text
delivery=done
return=verified
producer_result=failure
```

```text
delivery=done
return=timeout
producer_result=unknown
```

A missing or invalid return never changes `dispatch.done` or `dispatch.complete` into a delivery failure.

### SDD return states

Public v1 states:

```text
not_requested
pending
available
verified
failed
timeout
```

`collecting` may be an internal transient state but is not required as a durable public state.

State semantics:

- `not_requested`: no local return request exists;
- `pending`: request exists; no verified receipt is available yet;
- `available`: exact remote receipt commit marker has been observed;
- `verified`: receipt, correlation, origin and all referenced artifacts passed validation and atomic local adoption completed;
- `failed`: an observed receipt/result violated a non-transient contract such as correlation, path, replay, size, marker or SHA integrity;
- `timeout`: a bounded wait expired; this is **not** proof of producer failure and may later transition to `available`/`verified` on an explicit retry.

Transient target unavailability or transport interruption does not retroactively fail delivery and should remain retryable without inventing execution state.

### Producer execution/result state

SDD does not own execution state.

The receipt `resultState` is stored as producer metadata only. SDD verifies transport/correlation integrity, not whether the producer's computation was logically successful.

## 13. Origin, replay and stale-result rules

Origin trust is the existing outbound target SSH trust:

- exact configured target;
- existing SSH identity;
- existing known-host verification;
- Pixel initiates the connection.

No new target-to-Pixel authentication path is created.

Replay handling:

- first successful verified adoption fixes the accepted remote receipt SHA and result set for that `returnId`;
- a repeated collection with identical verified identities is idempotent;
- same `returnId` with different receipt or artifact identity is `RETURN_REPLAY_CONFLICT` and never overwrites local verified data;
- a receipt with a different delivery ID, original artifact SHA or source target is rejected even if all result payload hashes are internally consistent.

The producer may include timestamps, but wall-clock time alone is never used as correlation authority.

## 14. CLI v3 additive surface

CLI v3 is extended; `cli_schema=3` may remain because the change is additive. Capabilities advertise dedicated return schema versions.

Planned commands:

```text
sdd return capability [target]
sdd return request <delivery-id> --target <target> --type <result-type> [--marker <literal>] [--correlation <opaque>]
sdd return status <return-id>
sdd return probe <return-id>
sdd return collect <return-id>
sdd return wait <return-id> [timeout_seconds] [interval_seconds]
sdd return trace <return-id>
```

Semantics:

- `capability`: local config/capability inspection; no network;
- `request`: creates immutable local correlation expectation; no network and no host execution;
- `status`: local state only;
- `probe`: exact remote receipt existence/type probe only; no payload collection;
- `collect`: receipt-driven bounded pull and verification;
- `wait`: bounded polling for receipt availability only; it does not execute the target payload and does not implicitly crawl/download the outbox;
- `trace`: local redacted request/state/verification metadata, never result content.

All commands support the existing ENV/JSON machine-output model where applicable.

New advertised schemas:

```text
return_request_schema=1
return_receipt_schema=1
return_acceptance_schema=1
return_state_schema=1
```

No CLI command accepts an arbitrary remote command string.

## 15. Failure taxonomy

Machine-readable failures must distinguish at least:

```text
RETURN_DISABLED
RETURN_TARGET_UNKNOWN
RETURN_BINDING_MISSING
RETURN_RECEIPT_MISSING
RETURN_TRANSPORT_UNAVAILABLE
RETURN_RECEIPT_INVALID
RETURN_CORRELATION_MISMATCH
RETURN_ORIGIN_MISMATCH
RETURN_PATH_INVALID
RETURN_SYMLINK_REJECTED
RETURN_SIZE_LIMIT
RETURN_SHA_MISMATCH
RETURN_MARKER_MISMATCH
RETURN_REPLAY_CONFLICT
RETURN_TIMEOUT
```

Suggested CLI exit conventions follow existing SDD behavior:

- `64`: usage/schema-invalid caller request;
- `69`: unavailable capability/dependency;
- `124`: bounded wait timeout;
- `1`: observed verification/contract failure;
- `0`: requested operation completed successfully.

Transport-unavailable and receipt-missing conditions must not be converted into outbound delivery failures.

## 16. Redaction and secret handling

Default status/ChatGPT/WebUI summary surfaces may expose:

- return capability enabled yes/no;
- return ID;
- delivery ID;
- source target name if already allowed by that surface;
- return state;
- result state after verified receipt;
- artifact count/aggregate size;
- verification booleans;
- safe next action.

They must not expose by default:

- remote outbox path;
- SSH key or secret material;
- result artifact content;
- raw receipt body;
- expected/actual result marker text;
- opaque caller correlation value;
- arbitrary producer diagnostic text.

Issue/support bundles must follow the same redaction boundary.

## 17. Compatibility and migration

Return Channel v1 is additive.

On upgrade from v4.13.0:

- existing target profiles remain valid and unchanged;
- absence of `config/returns.d/<target>.conf` means return disabled;
- existing delivery receipts remain valid and are not migrated or rewritten;
- existing outbound state databases remain authoritative and untouched;
- new delivery bindings are created only for new successfully verified deliveries after the vNext implementation is active;
- legacy deliveries without a binding fail closed for return requests instead of being guessed/backfilled;
- normal config backup/export should include return capability sidecars when implemented;
- inbound result payloads are excluded from normal config backups by default because they may be large or sensitive;
- WebUI target-profile import/export remains on its current schema until a later WebUI-specific return-capability design.

A rollback to v4.13.0 leaves new return sidecars/bindings/inbound data inert. Rollback automation must never delete verified inbound result data automatically.

## 18. Fixture matrix required before device mutation

### Schema/parser fixtures

- valid single-artifact receipt;
- valid multi-artifact receipt;
- unknown field rejected;
- duplicate JSON key rejected;
- wrong field type rejected;
- trailing second JSON value rejected;
- invalid `returnId`, `deliveryId` and SHA rejected;
- invalid timestamps/order rejected when timestamps are present;
- invalid result state/type rejected;
- primary artifact missing from artifact list rejected.

### Correlation fixtures

- exact request/receipt match;
- wrong delivery ID;
- wrong original artifact SHA;
- wrong source target;
- wrong result type;
- wrong optional marker;
- wrong optional caller correlation;
- missing delivery binding;
- binding for another target.

### Path/filesystem fixtures

- `../` traversal rejected;
- slash/backslash artifact path rejected;
- leading-dot artifact rejected;
- remote receipt symlink rejected;
- remote artifact symlink rejected;
- directory/FIFO/special file rejected;
- outbox path outside strict allowlist rejected;
- scan-root/inbound overlap rejected;
- local staging symlink/non-regular file rejected.

### Size/count fixtures

- receipt over limit rejected before payload pull;
- zero artifact rejected;
- artifact count over limit rejected;
- artifact declared size over limit rejected;
- aggregate declared size over limit rejected;
- actual size differs from declared size;
- local/remote/receipt SHA mismatch permutations.

### State/replay fixtures

- request creates `pending` without host access;
- receipt probe transitions to `available` only;
- verified collection becomes `verified` atomically;
- staging residue never appears verified;
- identical recollect is idempotent;
- changed receipt under same return ID is replay conflict;
- timeout leaves outbound delivery unchanged and can later become verified;
- producer `resultState=failure` with valid payload yields `return=verified`, not delivery failure;
- return validation failure leaves outbound delivery `done/complete` unchanged.

### Transport fixtures with stubs

- receipt absent;
- target unreachable;
- SSH authentication failure;
- SCP receipt failure;
- SCP payload failure mid-set;
- remote SHA utility unavailable;
- remote SHA mismatch;
- exact happy path;
- no recursive/list-all outbox command is invoked;
- no target artifact write or execution command is invoked.

### Redaction fixtures

- result content absent from CLI status;
- raw receipt absent from ChatGPT context;
- remote outbox path absent from secret-safe output;
- caller correlation and marker text absent from default summaries;
- support bundle contains only approved metadata.

### Compatibility fixtures

- v4.13 target profile without return sidecar behaves unchanged;
- existing `SDD_DELIVERY_RECEIPT_V1` fixtures remain green;
- current CLI v3 trace/preflight/dispatch-file fixtures remain green;
- existing WebUI typed target profile parser remains green without new keys;
- Sortify `v4115` marker behavior is byte/semantic compatible;
- outbound dispatcher completion does not depend on return state.

Planning acceptance marker:

```text
RESULT: SDD_RETURN_CHANNEL_V1_CONTRACT_READY
```

Future implementation fixture markers should be separated by layer rather than one monolithic test:

```text
RESULT: SDD_RETURN_V1_SCHEMA_FIXTURES_PASS
RESULT: SDD_RETURN_V1_LOCAL_STATE_FIXTURES_PASS
RESULT: SDD_RETURN_V1_TRANSPORT_FIXTURES_PASS
RESULT: SDD_RETURN_V1_COMPAT_FIXTURES_PASS
```

## 19. Candidate and Pixel verification order

After fixtures are green:

1. candidate/prerelease build only;
2. package identity, shell/native-helper syntax and public/private guards;
3. full Pixel runtime backup/rollback anchor;
4. candidate install;
5. normal reboot;
6. installed-runtime verify proving existing outbound service remains green;
7. return capability disabled-by-default verify;
8. enable one local private target sidecar outside the public repo;
9. perform a fresh verified outbound delivery that creates a delivery binding;
10. external producer creates a conforming remote outbox receipt/result;
11. run `probe`, `wait`, `collect`, idempotent recollect and one bounded negative case;
12. verify existing outbound delivery state is unchanged throughout;
13. only then accept the candidate runtime.

No stable release is part of the planning-phase definition of done.

## 20. Explicit non-goals for v1

Not included:

- Codex worker implementation;
- Crosswork task schema;
- Crosswork SSH trigger;
- arbitrary command execution;
- host autoexecution;
- remote worker management;
- private target configuration in the public repository;
- target-specific private protocols;
- generic outbox browsing/listing;
- remote deletion/cleanup/acknowledgement;
- background unbounded polling daemon;
- WebUI implementation before CLI/schema acceptance.

## 21. Planning definition of done

The planning contract is complete when this document and the reconciled roadmap are merged with:

- current v4.13.0 baseline recorded;
- old roadmap drift explicitly resolved;
- versioned request/receipt/acceptance/state contracts fixed;
- separate optional return capability config fixed;
- exact-path remote outbox and local atomic inbound layout fixed;
- delivery SHA binding prerequisite defined;
- delivery/return/producer-result state separation defined;
- origin/correlation/SHA/marker/replay validation defined;
- bounded path/count/size/polling policy defined;
- complete fixture matrix defined before implementation;
- migration/rollback behavior defined;
- no autoexecution or arbitrary remote command surface;
- consumer-specific coordination excluded from public SDD.
