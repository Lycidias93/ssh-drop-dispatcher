# Archived Heimnetz release: pixel-drop-dispatch-v4.11.0

- Source repo: Lycidias93/heimnetz-geraete
- Source release URL: https://github.com/Lycidias93/heimnetz-geraete/releases/tag/pixel-drop-dispatch-v4.11.0
- Source tag: pixel-drop-dispatch-v4.11.0
- Original name: Pixel Drop Dispatcher v4.11.0 Magisk
- Published: 2026-05-25T14:37:20Z
- Created: 2026-05-25T14:30:11Z
- Draft: False
- Prerelease: False
- Latest flag at migration: False
- Proposed archive repo: Lycidias93/ssh-drop-dispatcher
- Migration note: archived before deleting the Heimnetz release object; source git tag intentionally kept.

## Original changelog

# Pixel Drop Dispatcher v4.11.0

Final Magisk release for the private Pixel Drop Dispatcher runtime.

## Release

- Version: `4.11.0`
- versionCode: `4115`
- Policy: `PIDD_POLICY_VERSION=v4115`
- Magisk module id: `pixel_drop_dispatch`
- Runtime SoT: `/data/adb/pixel-drop-dispatch`

## Verified final gates

- Runtime after reboot: `status=OK`
- PIDs alive: main, watcher, watchdog
- Queue clean: `inflight_bytes=0`, `event_pending=no`
- Python dispatch: enabled for `pi3,pi4`
- ZeroPi2/BerylAX Python dispatch: default guarded
- ntfy backend: present, default disabled, runtime redacted
- Sortify Dispatch integration: `v4.3-pidd-v4115-contract` / `versionCode=14`
- Sortify contract: `policy=v4115`, `dispatcher_integration_state=active`

## Assets

- `pixel-drop-dispatch-magisk-main-4.11.0.zip`
  - SHA256: `b4c9d436878637e567b9038ed636ff3941bcee39a9edc69a9ea5194f42d42945`
- `SHA256SUMS`
- `README_PIXEL_DROP_DISPATCH_4.11.0.md`

## Safety

No DNS, HA, VIP, route, ntfy secret, or host runtime changes are part of this GitHub release publication.

## Original assets metadata

- pixel-drop-dispatch-magisk-main-4.11.0.zip size=56507
- README_PIXEL_DROP_DISPATCH_4.11.0.md size=2379
- SHA256SUMS size=325
