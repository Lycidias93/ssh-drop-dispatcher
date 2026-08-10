# SSH Drop Dispatcher CLI v3

CLI v3 is the workflow/observability layer introduced with `4.13.0-verify-owner-rc3`.

It extends CLI v2 without replacing the verified delivery engine. Routing, upload, remote syntax verification, SHA-256 parity, quarantine policy and completion semantics remain owned by `service.sh`.

## Versioned contracts

```text
cli_schema=3
workflow_schema=1
delivery_receipt_schema=1
incident_context_schema=1
chatgpt_context_schema=1
```

Existing status/version/target output schemas remain compatible; `cli_schema=3` advertises the expanded command surface.

## Delivery identity

RC3 derives a stable workflow identity from the dispatcher's existing record contract instead of introducing a second transport identity.

Existing dispatcher record:

```text
<basename>|<cksum-crc>:<bytes>
```

Derived workflow ID:

```text
SDD-<cksum-crc>-<bytes>
```

The derived ID can be resolved back through the existing done/complete/inflight/quarantine state or, while the local artifact remains present, from the scan directory.

This means RC3 tracing can cover records created before RC3 without rewriting historical dispatcher state.

## New commands

```text
sdd trace <file|delivery-id>
sdd delivery trace <file|delivery-id>
sdd inspect <file|delivery-id>
sdd queue [limit]
sdd failures [limit]
sdd quarantine [limit]
sdd preflight <file>
sdd delivery preflight <file>
sdd dispatch-file <file> --wait [timeout_seconds] [interval_seconds]
sdd incident [file|delivery-id]
sdd incident --chatgpt [file|delivery-id]
```

All workflow inspection commands support the existing `--env` and `--json` output modes.

## Delivery trace

Schema:

```text
SDD_DELIVERY_TRACE_V1
```

Trace resolves:

- delivery ID;
- file basename;
- local-presence state;
- existing dispatcher record;
- target list;
- overall state;
- per-target state (`pending`, `inflight`, `done`, `quarantined`);
- quarantine reason where present.

Trace is local-state inspection and reports:

```text
host_run=no
```

The env form may include a short redacted log excerpt. The JSON form stays compact and structured.

## Queue/failure/quarantine inspection

Schemas:

```text
SDD_QUEUE_V1
SDD_FAILURES_V1
SDD_QUARANTINE_V1
```

These commands are local-state inspection only. They do not upload, retry, requeue, delete or repair anything.

`failures` redacts host values and network addresses before returning recent failure log evidence.

## Read-only delivery preflight

Schema:

```text
SDD_PREFLIGHT_V1
```

Preflight checks, without uploading the artifact:

1. local file exists;
2. file is complete/supported and not a checksum sidecar;
3. config lint passes;
4. filename resolves to active target(s);
5. dispatcher is enabled;
6. shell artifacts pass the explicit per-target local shell syntax check;
7. each target passes the existing target readiness check (SSH authentication, remote drop writability and free-space policy).

The target-readiness part performs read-only remote probes, so successful remote probing reports:

```text
host_run=yes
```

Preflight never invokes SCP and never calls the delivery scan path.

Outcomes are intentionally simple:

```text
READY
BLOCKED
```

## Orchestrated delivery workflow

Command:

```text
sdd dispatch-file <file> --wait [timeout] [interval]
```

RC3 deliberately does **not** duplicate `process_file()` or create a second upload engine.

The workflow is:

```text
preflight -> existing dispatcher scan -> wait-delivery -> receipt
```

The normal scan processes the existing ready dispatcher queue. Therefore the receipt explicitly reports:

```text
scan_scope=existing_queue
automatic_requeue=no
```

The named file is the item RC3 waits on and receipts, but other already-pending dispatcher artifacts may be processed by the normal scan at the same time. This preserves the existing single dispatcher engine and its ordering/safety rules.

No automatic requeue occurs after failure or timeout.

## Delivery receipt

Schema:

```text
SDD_DELIVERY_RECEIPT_V1
```

Receipts contain:

- delivery ID;
- file basename;
- dispatcher record;
- targets;
- start/end epochs;
- final workflow state;
- preflight result;
- dispatch/wait exit codes;
- explicit `scanScope=existing_queue`;
- explicit `automaticRequeue=false`;
- `remoteShaRequired=true`;
- `hostRun=true`.

Receipts are appended as JSONL to:

```text
/data/adb/ssh-drop-dispatcher/delivery.receipts.jsonl
```

The receipt file is workflow evidence only. It does not replace `dispatch.done`, `dispatch.complete`, quarantine state or remote SHA verification as delivery truth.

## Incident context

Schema:

```text
SDD_INCIDENT_CONTEXT_V1
```

Incident context is designed for ChatGPT/Codex troubleshooting. It includes:

- runtime health;
- config-lint state;
- optional delivery ID/file state;
- quarantine/failure/inflight counts;
- recent WARN/FAIL counts;
- a safe next action;
- explicit redaction markers.

It does not expose host fields, remote drop paths, network addresses or secret content and reports:

```text
host_run=no
```

## ChatGPT context additions

`SDD_CHATGPT_CONTEXT_V1` remains the stable context schema. RC3 adds optional workflow summary fields:

```text
workflow_schema=1
delivery_receipt_records=<n>
last_delivery_id=<id|none>
last_receipt_state=<state|none>
```

No file names, host fields, remote paths or network addresses are added to the compact ChatGPT context.

## Safety boundaries

RC3 does not change:

- dispatcher-owned remote verification;
- normal-path remote SHA parity;
- fail-closed Bash behavior;
- explicit `sh` profile for BerylAX;
- BerylAX `scp -O` policy;
- target drop directories;
- filename routing contract;
- host payload non-execution policy;
- Python delivery policy;
- DNS, HA, VIP, default/static route, MagicDNS or subnet-route state.

RC3 adds no automatic self-healing, automatic requeue, quarantine deletion or network repair.
