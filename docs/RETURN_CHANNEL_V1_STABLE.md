# Return Channel v1 — stable user guide

Return Channel v1 is available in SSH Drop Dispatcher `v4.14.0`.

It adds a verified pull path from an already configured SSH target back to the Android dispatcher. Android remains the initiator of every SDD network operation.

## What it is

A normal outbound SDD delivery can record a target-specific SHA-256 binding after the remote upload has been verified. A later Return request can use that binding to accept result artifacts from the same configured target.

The Return path is intentionally separate from outbound delivery state: an outbound delivery can remain successful even if a later Return is missing, delayed or fails validation.

## What it is not

Return Channel does not add:

- target payload auto-execution;
- arbitrary remote commands or RPC;
- incoming SSH access to Android;
- recursive remote browsing;
- automatic remote outbox deletion.

Any worker that produces a result on the target remains external to SDD.

## Enable Return for a target

Return configuration is opt-in and stored separately from the normal target profile:

```text
/data/adb/ssh-drop-dispatcher/config/returns.d/<target>.conf
```

Minimal shape:

```text
return_enabled="1"
remote_outbox="/absolute/path/to/outbox"
```

The target must already exist in the normal SDD target registry. SSH identity, keys, known-host trust and host mapping are reused from the existing target configuration.

## CLI

The Return command family is available through the normal `sdd` CLI:

```text
sdd return capability <target>
sdd return request <delivery-id> --target <target> --type <result-type>
sdd return status <return-id>
sdd return probe <return-id>
sdd return collect <return-id>
sdd return wait <return-id>
sdd return trace <return-id>
```

Use `sdd help` and the command output for the exact accepted arguments on the installed version.

## Verification model

A Return is accepted only when its request, source target, original delivery binding and returned data agree. Result artifacts are checked for path safety, bounds and SHA-256 identity before atomic local adoption.

Returned data is stored under the dedicated inbound runtime namespace and is kept outside the normal outbound scan directory.

## WebUI

WebUI Core 0.6 exposes a secret-safe Returns inventory and bounded typed operations. It does not expose arbitrary remote paths or shell commands.

## Retention

Return data is not silently deleted by the v1 transport. Review and remove retained result data according to your own workflow and storage policy.

For the frozen schema/design detail, see [`RETURN_CHANNEL_V1.md`](RETURN_CHANNEL_V1.md).
