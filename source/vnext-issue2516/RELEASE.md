# V4.14.3 guarded tool synchronization

- Avoids rewriting identical executable runtime tools on every watchdog cycle.
- Publishes changed regular tools atomically and preserves prior content on copy or rename failure.

Build from the exact V4.14.2 released ZIP using `tools/build_v4143_guarded_tools.py --base BASE.zip --output CANDIDATE.zip`. The builder verifies both input hashes, all 42 ZIP entries and permissions, the exact two-file delta and deterministic output. The V4.14.2 release is the rollback package. No automatic promotion of the update channel. Magisk staging, device acceptance after owner reboot, actual delivery and WebUI audit remain required before public release.

The scoped stage controller verifies the exact old and new ZIPs, all 41 installed payload files, existing bridges and runtime tools. It saves a private rollback anchor before using Magisk staging; it neither stops the dispatcher nor resets queue/inflight state. Failed staging attempts restore touched baseline files and retain evidence. Android exact-baseline preflight and controller lint passed. Owner-manual reboot and postboot delivery acceptance remain separate.
