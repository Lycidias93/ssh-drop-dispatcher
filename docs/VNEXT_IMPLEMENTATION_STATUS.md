# SSH Drop Dispatcher vNext Implementation Status

Roadmap: [`docs/VNEXT_ROADMAP.md`](VNEXT_ROADMAP.md)  
Stable Return guide: [`docs/RETURN_CHANNEL_V1_STABLE.md`](RETURN_CHANNEL_V1_STABLE.md)  
Frozen Return contract: [`docs/RETURN_CHANNEL_V1.md`](RETURN_CHANNEL_V1.md)

## Current baseline

- Public stable target: `4.14.0` / `4140005`.
- Accepted runtime basis: `4.14.0-return-rc4`.
- CLI remains v3.
- Persistent Android runtime SoT remains `/data/adb/ssh-drop-dispatcher`.
- Outbound dispatcher, dispatcher-owned remote SHA-256 verification and delivery state remain authoritative.
- Target payload autoexecution, arbitrary remote-command transport and RPC remain forbidden.

## Return Channel v1

Return Channel v1 is implemented and accepted for stable promotion. The public generic layer includes:

- target-specific `SDD_DELIVERY_BINDING_V1` evidence after successful outbound remote-SHA verification;
- versioned Return request, receipt, acceptance and state contracts;
- optional per-target Return capability sidecars;
- exact-path pull-based SSH/SCP collection initiated by Android;
- dedicated inbound storage outside the outbound dispatch scan path;
- strict origin, correlation, path, symlink, size, count, SHA and replay checks;
- atomic local adoption;
- independent outbound-delivery, Return-transport and producer-result semantics;
- additive CLI v3 `sdd return ...` commands;
- read-only Returns inventory and bounded typed operations in WebUI Core 0.6.

## RC4 acceptance

The accepted RC4 line adds bounded named-delivery scan fairness on top of the Return/Core-0.6 candidate:

- `dispatch-file` uses a named-file scan rather than a full queue scan;
- named-file lock acquisition is bounded;
- event follow-up work is single-flight/coalesced;
- the real outbound-delivery + Return round trip completed successfully with remote SHA verification, Return request/probe/collect, correlation and marker verification.

Stable `v4.14.0` is a deterministic promotion of that accepted payload. The functional package must reproduce the accepted RC4 archive exactly before stable metadata is applied, and only `module.prop` may differ in the stable ZIP.

## Security boundaries

- no host autoexecution;
- no arbitrary remote command endpoint;
- no incoming SSH requirement on Android;
- no returned data in the outbound scan directory;
- no Return acceptance without delivery correlation, source-target validation and SHA-256 parity;
- no recursive/list-all remote outbox pull;
- bounded polling, counts and sizes;
- no secret result content in normal status/WebUI output;
- no private target/path/key material in the public repository.

## Current machine status

```text
stable_target=4.14.0
stable_versionCode=4140005
accepted_runtime=4.14.0-return-rc4
return_channel_v1_contract=defined
return_channel_v1_implementation=accepted
return_channel_v1_stable_promotion=authorized
webui_core=0.6.0
webui_core_commit=cb991dc8d7d982defbe5e34c5c0e0908efa9b236
named_delivery_scan_fairness=accepted
host_autoexecution_added=no
arbitrary_remote_command_added=no
```
