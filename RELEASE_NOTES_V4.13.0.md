# SSH Drop Dispatcher v4.13.0

## What changed since v4.12.6

- **Dispatcher-owned target verification:** target readiness, remote shell verification and remote SHA-256 parity are now owned by the dispatcher before a delivery is marked complete.
- **CLI v3 workflow:** adds delivery tracing, queue/failure/quarantine inspection, read-only preflight, `dispatch-file --wait`, delivery receipts, incident context and secret-safe ChatGPT context.
- **New standalone WebUI:** moves administration to WebUI Core 0.3.0 with local-only access, typed/allowlisted operations and stronger session handling.
- **Safer target/profile editing:** adds typed repeated-record editing, alias canonicalization, preview-before-apply, bounded import/export and secret-aware export handling.
- **Better WebUI usability:** adds faster local status, bounded inventory views, background jobs, clearer result summaries, stronger confirmation gating and improved mobile record focus/navigation.
- **Target readiness UX:** adds `Test all enabled targets`, which checks configured targets sequentially without delivering an artifact and reports intermittent-unavailable targets separately from real readiness failures.
- **ntfy and Sortify visibility:** adds secret-safe ntfy configured/not-configured status and a read-only Sortify companion inventory.
- **Support improvements:** support bundles now derive their version from module metadata and Android command handling is more robust in the Magisk/Termux environment.

## Upgrade

Install `ssh-drop-dispatcher-magisk-v4.13.0.zip` through Magisk and reboot normally. Existing persistent configuration under `/data/adb/ssh-drop-dispatcher` is preserved by the normal module update path.

## Current limitation

Python payload delivery remains unsupported by the dispatcher delivery policy.
