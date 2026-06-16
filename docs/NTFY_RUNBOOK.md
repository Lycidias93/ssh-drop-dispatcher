<!-- SDD_V4125_NTFY_RUNBOOK_START -->
## Duplicate-alias guard final

`v4.12.5` uses ntfy to make duplicate and collision decisions visible:

- `INFO duplicate_alias`: a download-suffix alias has the same canonical name and digest as an already completed artifact; no second upload is expected.
- `WARN content_changed_same_canonical_name`: an alias-shaped filename has a different digest from the completed canonical artifact; the dispatcher must not silently upload it.
- Expected WebUI field: `duplicate_alias_guard_enabled=yes`.
- Expected invariant: `policy: v4115 · host_run: no` remains visible.

No ntfy topic, token, URL or token-file contents belong in repository files.
<!-- SDD_V4125_NTFY_RUNBOOK_END -->

# SDD ntfy Runbook

## Status checks

Run:

```sh
su -c '/data/adb/modules/ssh_drop_dispatcher/service.sh --webui-status' | grep -E 'version=|ntfy_'
```

Expected secret-safe fields:

```text
ntfy_enabled=1
ntfy_endpoint_configured=yes
ntfy_token_file_configured=no
```

## Test notification

```sh
su -c '/data/adb/modules/ssh_drop_dispatcher/service.sh --webui-ntfy-test'
```

Expected log evidence:

```text
NTFY_SENT status=PASS target=webui file=webui-ntfy-test reason=manual-test
```

## Message format

```text
🟢 SDD PASS · pi4
target-pi4__example.sh
reason: delivered
policy: v4115 · host_run: no
```

Emoji: 🟢 PASS, 🟡 WARN/SKIP, 🔴 FAIL/ERROR, 🔵 INFO/TEST/other.

## Secret rules

- Never commit ntfy topic, token, or token file content.
- WebUI status may show configured yes/no only.
- Runtime config changes must create a config backup first.
- Keep host_run=no and Sortify marker policy v4115 visible in notifications.

## Troubleshooting

```sh
su -c 'grep -E "NTFY_|BREAKGLASS|PASS space|FAIL space" /data/adb/ssh-drop-dispatcher/log/dispatch.log | tail -80'
```

## Final v4.12.3 verification

Runtime smoke passed with secret-safe status, ntfy test push, BerylAX verify, BerylAX breakglass proof, ntfy log evidence, runtime health OK, `host_run=no`, and Sortify marker policy `v4115` unchanged.

## Already-present ntfy info

When a fully delivered file reappears in the scan root with the same record and a newer local mtime than its Sortify release marker, SDD sends one debounced INFO notification: `reason: already_present`. This indicates dedupe/no-upload, not a delivery failure.

## Already-present rc2 notes

`v4.12.4-already-present-rc2` sends `reason: already_present` only when the delivered local file is newer than its Sortify release marker. The mtime probe tries Termux stat, system stat and toybox stat. WebUI status exposes `already_present_notify_enabled=yes|no`.

## v4.12.4 final verification

- PASS notification remains `reason: delivered`.
- Already-present notification is `status=INFO`, target-specific, and uses `reason: already_present`.
- Repeated dispatch without another mtime change is debounced.
- WebUI status field: `already_present_notify_enabled=yes|no`.
- Sortify marker policy remains `v4115`; host_run remains `no`.

## Duplicate-alias guard rc1

- `INFO duplicate_alias`: the raw filename is a download-suffix alias for an already completed canonical artifact with the same digest; no second upload is expected.
- `WARN content_changed_same_canonical_name`: the raw filename looks like an alias but has a different digest from an already completed canonical artifact; the dispatcher must not silently upload it.
- WebUI status should show `duplicate_alias_guard_enabled=yes` when the guard is active.
