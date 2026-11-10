# SDD v4.14.2: Pixel activation and Pi4 smoke verification (2026-11-10)

## Evidence and scope

Pixel 10 Pro XL (`mustang`, Android 17) has successfully activated Magisk module v4.14.2. The on-device postboot verifier confirmed exact installed service and coalescer SHA-256 values. The isolated 12-event singleflight canary returned one worker and one scan.

The owner explicitly authorized production activation and smoke tests. The first controlled production canary successfully delivered the 54-byte `target-pi4__sdd-v4142-smoke-20261110114858.txt` to Pi4. The dispatcher delivery log showed `remote_sha_match=yes`, and independent Pi4 root-level SHA-256 readback confirmed the same file digest `b75b24c6874910c1e04a9effd2f82330572cc797a271b4af784d5f8a86b2422e`. A separate ad-hoc controller erroneously treated a secondary remote read-permission failure as a digest mismatch, invoked its designed fail-closed rollback and disabled the dispatcher. The v4.14.2 module was not rolled back.

## Recovery controller

`tools/pixel_local__sdd_v4142_finalize_activation_v1.sh` is a narrowly scoped, fully linted Workflowfit controller. It validates device/build/boot and exact module source hashes, battery, disabled starting state, original backup, safe backlog and isolated Pi4 canary provenance. The downloaded files were audited: six older target-directed files (four already completed, two quarantined) plus the completed Pi4 canary, seven total. The Pixel source/dispatcher ledger identifies this canary by `target-pi4__sdd-v4142-smoke-20261110114858-12669.txt`, whereas Pi4 currently holds its byte-identical canonical alias `target-pi4__sdd-v4142-smoke-20261110114858.txt`. Both exact file SHA-256 values were read independently and match the fixed canary digest. Bind these separately in the controller; searching the wrong local basename is a fail-closed readback error, not evidence that the dispatcher failed to deliver. Neither blocked older artifact is requeued.

It independently reads the existing Pi4 canary using the configured dispatcher SSH identity (remote root) and accepts only a strict 64-character lowercase hexadecimal SHA-256 field. It separately rejects missing files or permission errors. It then deletes only the verified, exact Pi4 canary and its optional matching Pixel-local copy, enables v4.14.2, verifies main/watcher/watchdog processes, observes short-term worker counts and retains a new exact configuration backup. On failure, the controller calls the module's `--disable` path and restores the verified disabled configuration. It does not issue a reboot, install a new module, publish a release, change routing or touch any user download aside from the known canary.

`tests/verify_followup_singleflight.py` covers positive and negative hash-output parsing and source guard invariants. CI and live Workflowfit verify must pass before executing the controller. After execution, inspect actual enabled state, process health, any new scan locks, CPU pressure and delivery records independently.

## Rollback and incomplete gates

The original Magisk v4.14.1 rollback and pre-v4.14.2 runtime snapshot remain in `/data/adb/ssh-drop-dispatcher/backups/v4142-manual-Ewiikz`. The v4.14.2 production activation controller creates its own disabled-state backup before mutation. Quarantined legacy artifacts remain untouched.

This change does **not** authorize public v4.14.2 release/tag/publishing or Cloud1 integration. Any further production-data transfer requires its own scoped integrity/safety checks.