# Archived Heimnetz release: pixel-drop-dispatch-v4.10.0

- Source repo: Lycidias93/heimnetz-geraete
- Source release URL: https://github.com/Lycidias93/heimnetz-geraete/releases/tag/pixel-drop-dispatch-v4.10.0
- Source tag: pixel-drop-dispatch-v4.10.0
- Original name: Pixel Drop Dispatcher v4.10.0
- Published: 2026-05-01T14:49:42Z
- Created: 2026-05-01T14:49:38Z
- Draft: False
- Prerelease: False
- Latest flag at migration: False
- Proposed archive repo: Lycidias93/ssh-drop-dispatcher
- Migration note: archived before deleting the Heimnetz release object; source git tag intentionally kept.

## Original changelog

# Pixel Drop Dispatcher v4.10.0

Finaler Release-Stand für den produktiven Pixel Drop Dispatcher.

## Gates

- Runtime: `/data/adb/pixel-drop-dispatch`
- Version: `4.10.0`
- versionCode: `4102`
- Policy: `PIDD_POLICY_VERSION=v4102`
- `--runtime-status`: OK
- `--config-list`: OK
- `--doctor`: OK
- `health.env`: shell-sourcebar, `updated_at` quoted
- `dispatch.inflight`: 0
- `dispatch.faildb`: 0

## Ziele

- `pi3` → `/mnt/dietpi_userdata/BACKUP/_inbox/drop`
- `pi4` → `/mnt/dietpi_userdata/BACKUP/_inbox/drop`
- `berylax` → `/root/drop`
- `zeropi2` → `/opt/zeropi2/drop`

## Enthaltene Artefakte

- `pixel-drop-dispatch-magisk-main-v4.10.0.zip`
- `pixel-drop-dispatch-magisk-main-v4.10.0.zip.b64`
- `pixel-drop-dispatch-termux-setup-v4.10.0.zip`
- `pixel-drop-dispatch-termux-setup-v4.10.0.zip.b64`
- `pixel-drop-dispatch-abcd-interactive-v4.10.0.sh`
- `SHA256SUMS`
- `README_PIXEL_DROP_DISPATCH_V4.10.0.md`

## Root Cause / Fix

`health.env` war in RC2 wegen unquotiertem Timestamp nicht sauber sourcebar. In v4.10.0 final schreibt der Health-Writer `updated_at='YYYY-MM-DD HH:MM:SS'`.

## Original assets metadata

- pixel-drop-dispatch-abcd-interactive-v4.10.0.sh size=615
- pixel-drop-dispatch-magisk-main-v4.10.0.zip size=40431
- pixel-drop-dispatch-magisk-main-v4.10.0.zip.b64 size=54618
- pixel-drop-dispatch-termux-setup-v4.10.0.zip size=334
- pixel-drop-dispatch-termux-setup-v4.10.0.zip.b64 size=454
- README_PIXEL_DROP_DISPATCH_V4.10.0.md size=2574
- SHA256SUMS size=668
