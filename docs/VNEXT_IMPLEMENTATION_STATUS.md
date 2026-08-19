# SSH Drop Dispatcher vNext Implementation Status

Roadmap: [`docs/VNEXT_ROADMAP.md`](VNEXT_ROADMAP.md)  
Return Channel contract: [`docs/RETURN_CHANNEL_V1.md`](RETURN_CHANNEL_V1.md)

## Baseline

- Public stable remains `4.13.0` / `4130007`.
- CLI remains v3.
- Persistent Pixel runtime SoT remains `/data/adb/ssh-drop-dispatcher`.
- Existing outbound dispatcher, dispatcher-owned remote SHA-256 verification and delivery state remain authoritative.
- Target payload autoexecution, arbitrary remote-command transport and RPC remain forbidden.

## Return Channel v1 implementation

Return Channel v1 is implemented as an additive vNext candidate. The public generic layer includes:

- `SDD_DELIVERY_BINDING_V1` after successful outbound remote-SHA verification;
- versioned Return request/receipt/acceptance/state contracts;
- per-target optional return capability sidecars;
- exact-path pull-based SSH/SCP collection initiated by the Pixel;
- dedicated persistent inbound storage outside the normal dispatch scan path;
- strict origin/correlation/path/symlink/size/count/SHA/replay checks;
- atomic local adoption;
- independent delivery, return and producer-result semantics;
- additive CLI v3 `sdd return ...` commands;
- read-only Return inventory and bounded manual operations in the WebUI adapter;
- no Crosswork/Codex-specific schema or private Heimnetz target configuration in the public core.

## Candidate history

- RC1 introduced the generic Return Channel and WebUI Core 0.4 consumer primitives.
- RC2 synchronized the candidate to WebUI Core 0.5 and validated the browser-session observability layer.
- RC3 synchronizes to the current shared WebUI Core 0.6 at `cb991dc8d7d982defbe5e34c5c0e0908efa9b236`.

RC3 keeps Return transport and receipt semantics unchanged. Core 0.6 is API-compatible with the existing adapter and adds generic state-aware/mobile base-UI behavior: optional active/blocked action state, explicit Preview vs Apply wording, session-cached inventory switching with explicit live refresh, stale-response protection, and responsive inventory/navigation rendering.

## Runtime acceptance status

Pixel RC2 postboot evidence established exact candidate payload identity, services, CLI version/capabilities, Return capability/retention, WebUI Core 0.5, Returns inventory, Sortify inventory, typed targets, ntfy preservation and standard-surface redaction. The only failing gate was `sdd --env status` being killed at exactly 10 seconds immediately after reboot.

That failure is verifier timing, not evidence of runtime drift: `sdd status` invokes `service.sh --runtime-status`, whose service entrypoint performs `wait_boot` before emitting status. Boot-readiness delay must therefore be isolated from the command-level status SLO. The repo-owned acceptance verifier is being revised accordingly.

Because the shared template advanced from Core 0.5 to Core 0.6 after RC2 was built, RC2 is not promoted to final accepted vNext runtime. The next device candidate is RC3/Core 0.6, avoiding an unnecessary RC2 acceptance/reboot cycle.

## Security boundaries unchanged

- no host autoexecution;
- no arbitrary remote command endpoint;
- no inbound files in the outbound scan directory;
- no acceptance without delivery correlation, source-target validation and SHA-256 parity;
- no recursive/list-all remote outbox pull;
- bounded polling, counts and sizes;
- no secret result content in normal status/WebUI output;
- no private target/path/key material in the public repository;
- no DNS/HA/VIP/default/static route/MagicDNS/subnet-route changes.

## Current machine status

```text
stable_baseline=4.13.0
return_channel_v1_contract=defined
return_channel_v1_implementation=implemented_candidate
current_candidate=4.14.0-return-rc3
current_candidate_versionCode=4140003
webui_core=0.6.0
webui_core_commit=cb991dc8d7d982defbe5e34c5c0e0908efa9b236
pixel_rc2_payload_identity=verified
pixel_rc2_final_acceptance=superseded_by_core06_sync
host_autoexecution_added=no
stable_release_authorized=no
```
