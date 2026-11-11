# SSH Drop Dispatcher v4.14.2

## What changed
- Fixed heavy slowdown when many Download events arrived during an active scan. The dispatcher now groups follow-up events instead of starting overlapping scan processes.
- Prevented a long-running, healthy scan from being treated as a stale lock and interrupted.
- Improved recovery of pending events when a scan is temporarily busy or a worker needs to restart.
- Fixed standalone WebUI notification settings not saving correctly on Android.

## Updating
Install the v4.14.2 Magisk ZIP as a normal update over an existing SSH Drop Dispatcher installation and restart Android to activate the updated module scripts. Back up your current module and persistent configuration before updating.

Existing target configuration, delivery records and SSH settings are preserved. Previously quarantined transfers remain quarantined; they are not automatically resent.

## Compatibility
Target filename routing, remote SHA-256 verification, CLI v3, WebUI Core 0.6, Sortify integration and Return Channel v1 retain their existing user-facing behavior.
