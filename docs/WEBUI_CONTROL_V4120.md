# SSH Drop Dispatcher 4.12.0-webui-control-rc1 WebUI Control Candidate

<!-- SDD_V4120_FINAL_DOC_START -->
## Final v4.12.0 release notes

`v4.12.0` keeps the rc2 runtime-proven behavior as stable:

- Strict target-prefix routing is enabled.
- Sidecar files such as `*.sha256` are ignored by the dispatcher queue.
- BerylAX/OpenWrt Dropbear delivery uses the legacy SCP fallback `-O` when target config omits explicit `scp_flags`.
- Sortify marker policy remains `v4115`.
- No DNS/HA/VIP/route or host drop-path changes are part of this release.

Verification gotchas captured from rc2 smoke:

- Use the dispatcher SSH config, not normal Termux aliases, for host validation.
- Ignore OpenSSH post-quantum warning lines when extracting SHA256 output.
- Avoid `$HOME/.cache` in root-run scripts unless `HOME` is explicitly set.
<!-- SDD_V4120_FINAL_DOC_END -->


Status: candidate source patch.

## Goals

- Public WebUI controls for safe runtime operations.
- `DROP_DISPATCH_ENABLED=0|1` as persistent pause/resume flag.
- `Dispatch now` command for immediate bounded scan.
- Runtime status, doctor, target matrix, log tail, issue bundle and requeue from WebUI.
- Preserve the Sortify `v4115` marker contract unchanged.

## Commands

```sh
su -c /data/adb/modules/ssh_drop_dispatcher/service.sh --webui-status
su -c /data/adb/modules/ssh_drop_dispatcher/service.sh --enable
su -c /data/adb/modules/ssh_drop_dispatcher/service.sh --disable
su -c /data/adb/modules/ssh_drop_dispatcher/service.sh --dispatch-now
su -c /data/adb/modules/ssh_drop_dispatcher/service.sh --webui-log-tail 180
```

## Safety

`--disable` writes `DROP_DISPATCH_ENABLED=0`, stops runtime PIDs and marks health as disabled.
`--enable` writes `DROP_DISPATCH_ENABLED=1` and requests service start if no main PID is alive.
`--dispatch-now` refuses to run while disabled.

No DNS/HA/VIP/route or target drop-path changes are included.

## RC2 strict routing / legacy SCP notes

`4.12.0-webui-control-rc2` keeps the WebUI control surface from rc1 and tightens dispatch safety:

- Strict target-prefix routing is enabled by default with `DROP_DISPATCH_STRICT_TARGET_PREFIX=1`.
- Unprefixed files such as `berylax_config_snapshot_handover_*.md` are not dispatched just because a target token appears in the filename.
- Sidecar files such as `*.sha256` are ignored by the dispatcher queue.
- Target configs may set `scp_flags`; the effective default for `berylax` is `-O` for Dropbear/OpenWrt legacy SCP compatibility.
- Sortify marker policy remains `v4115`; no DNS/HA/VIP/route or host drop-path changes are included.
