# V4.14.3 guarded tool synchronization

- Avoids rewriting identical executable runtime tools on every watchdog cycle.
- Publishes changed regular tools atomically and preserves prior content on copy or rename failure.

Build from the exact V4.14.2 released ZIP using `tools/build_v4143_guarded_tools.py --base BASE.zip --output CANDIDATE.zip`. The builder verifies both input hashes, all 42 ZIP entries and permissions, the exact two-file delta and deterministic output. The V4.14.2 release is the rollback package. No automatic promotion of the update channel. Magisk staging, device acceptance after owner reboot, actual delivery and WebUI audit remain required before public release.
