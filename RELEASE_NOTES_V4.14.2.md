# SSH Drop Dispatcher v4.14.2 — Hotfix

## Changes
- Prevented a process storm when a large number of Download events arrive while a scan is busy.
- Combined pending follow-up events into a single bounded worker, with watchdog recovery rather than recursive process creation.
- Protected an active slow scan against mistaken stale-lock cleanup.
- Retained pending work across bounded retries and recoverable scan errors.

## Compatibility and behavior
- Existing SSH/SCP target configuration, target/multitarget filenames, verified SHA-256 delivery, CLI v3, WebUI Core 0.6, Sortify integration and Return Channel v1 remain unchanged.
- No new target hosts, routes, SSH trust or remote-execution features.
- v4.14.2 does not install automatically. The running Magisk module remains unchanged until an explicitly approved installation.

## Updating
Back up the current module and persistent runtime configuration before any separately approved update. The persistent state is expected to remain at `/data/adb/ssh-drop-dispatcher`. Restore the prior verified module package and configuration backup if the canary fails; do not delete queued files or transfer state.

## Verification
Publication requires an exact package hash, current CI, source-fixture and security passes, approved device smoke, package/host identity and rollback verification. Do not treat local fixture tests or candidate packaging alone as production installation acceptance.
