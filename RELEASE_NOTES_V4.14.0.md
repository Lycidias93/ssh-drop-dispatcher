# SSH Drop Dispatcher v4.14.0

## What changed since v4.13.0

- **Return Channel v1:** SDD can now pull verified result artifacts from an already configured SSH target back to Android. Return collection is explicitly requested, correlated to a completed outbound delivery and verified with SHA-256 before local acceptance.
- **Return CLI:** adds `sdd return` capability, request, status, probe, collect, wait and trace operations with machine-readable output and the existing redaction model.
- **Return WebUI:** adds a secret-safe Returns inventory and bounded manual Return operations without adding a generic remote file browser or remote shell.
- **WebUI Core 0.6:** improves mobile/state-aware UI behavior, Preview vs Apply wording, inventory caching with explicit live refresh, stale-response protection and responsive navigation.
- **More reliable named delivery:** `sdd dispatch-file` now uses a bounded named-file scan rather than triggering a full queue scan for that workflow, reducing lock contention when watcher/follow-up activity overlaps a user-requested delivery.
- **Follow-up coalescing:** event follow-up scans are single-flight/coalesced instead of being able to fan out into multiple concurrent follow-up processes.

## Upgrade

Install `ssh-drop-dispatcher-magisk-v4.14.0.zip` through Magisk and reboot normally. Existing persistent configuration under `/data/adb/ssh-drop-dispatcher` is preserved by the normal module update path.

Return Channel is opt-in per target. Existing targets continue to work as outbound-only targets unless a Return sidecar is configured.

## Safety model

Return Channel is a pull-based data path initiated by Android. It does not add target payload auto-execution, arbitrary remote commands, RPC, incoming SSH access to Android or a generic remote file browser.

## Current limitation

Python payload delivery remains unsupported by the dispatcher delivery policy.
