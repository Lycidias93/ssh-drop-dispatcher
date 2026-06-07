# SSH Drop Dispatcher 4.12.0-webui-control-rc1 WebUI Control Candidate

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
