## v4.12.4-already-present-rc1 - 2026-06-14

- Add ntfy INFO notification when an already delivered file reappears in the scan root with a newer mtime than its Sortify release marker.
- Debounce already-present notifications by record, targets and local mtime via runtime state `dispatch.already-present.ntfy`.
- Keep upload, host-run, Sortify marker policy v4115, WebUI ntfy settings and target routing unchanged.

## v4.12.3 - 2026-06-13

- Promote ntfy notification format rc1 to final v4.12.3 after runtime smoke passed.
- Final notification format uses minimal traffic-light status, concise target title, file line, reason, policy, and host_run status.
- `docs/NTFY_RUNBOOK.md` is part of the release. Delivery behavior, WebUI ntfy settings, BerylAX parser, break-glass SCP, and Sortify marker policy v4115 remain unchanged.

## v4.12.3-ntfy-format-rc1 - 2026-06-13

- Polish ntfy notification text with minimal traffic-light status emoji, concise title, file line, reason, policy, and host_run status.
- Add `docs/NTFY_RUNBOOK.md` with secret-safe status checks, test notification, message format, secret rules, and troubleshooting.
- Delivery behavior, WebUI ntfy settings, BerylAX parser, break-glass SCP, and Sortify marker policy v4115 remain unchanged.

## v4.12.2 - 2026-06-13

- Promote WebUI ntfy settings rc1 to final v4.12.2 after runtime smoke passed.
- WebUI can set secret-safe ntfy runtime config and send a test notification. Existing v4.12.1 delivery safety behavior and Sortify marker policy v4115 remain unchanged.

## v4.12.2-webui-rc1 - 2026-06-13

- Add secret-safe WebUI ntfy settings actions: set config, preserve token secrecy, backup config before changes, and send test notification.
- Keep v4.12.1 final delivery safety, BerylAX parser, break-glass SCP, delivery status/wait, and Sortify marker policy v4115 unchanged.

## v4.12.1 - 2026-06-12

- Promote delivery-safety rc5 to final v4.12.1 after post-reboot runtime smoke passed.
- Verified BerylAX/OpenWrt df parser fix, pi4 and BerylAX break-glass SCP, ntfy PASS hooks, dispatcher health, and unchanged Sortify marker policy v4115.

## v4.12.1-delivery-safety-rc5 - 2026-06-12

- Fix BerylAX/OpenWrt space probing by parsing remote df output locally after SSH instead of using nested remote awk quoting.
- Keep rc4 ntfy, delivery status/wait, break-glass SCP, retry behavior, and Sortify marker policy v4115 unchanged.

## v4.12.1-delivery-safety-rc4 - space probe retry candidate

- Hardened delivery space probes with bounded retry logging before declaring `space unreadable`.
- Preserves rc3 delivery-status/wait remote-first recovery and optional private ntfy notifications.
- No DNS, HA, VIP, route, Sortify marker policy or host-run changes.

## 4.12.1-delivery-safety-rc3

- Add `--delivery-status <file>` for remote-first delivery verification when the local source is already missing.
- Add `--wait-delivery <file> [timeout] [interval]` with heartbeat output for orchestrator/cgrun waits.
- Add optional ntfy delivery notifications for per-target PASS/FAIL events; disabled by default and configured only through private runtime config.
- Treat `local_missing + dispatcher done/complete + remote target exists` as a recoverable PASS state.
- Keep break-glass SCP, target-specific space gates, BerylAX `scp_flags=-O`, and Sortify marker policy `v4115` unchanged.
- No DNS, HA, VIP, route, host drop-path, or automatic host-run changes.

## 4.12.1-delivery-safety-rc2

- Add explicit manual `--breakglass-scp <file> <target>` for controlled Direct-SCP fallback.
- Add `--breakglass-status <file>` and `--breakglass-log-tail [lines]` evidence inspection.
- Gate break-glass with strict target prefix, sidecar/partial blocking, target-specific space policy, remote SHA-256 verification and evidence logging.
- Keep break-glass non-automatic and keep host execution out of scope.
- Keep Sortify marker policy `v4115` unchanged.
- Keep `update.json` on stable `4.12.0` during rc2 validation.

## 4.12.1-delivery-safety-rc1

- Add target-specific delivery space policy gates before remote upload.
- Add `--verify-targets`, `--verify-target <target>`, and `--route-explain <file>` diagnostics.
- Harden ssh/scp binary resolution in the Magisk service context.
- Keep Sortify marker policy `v4115` unchanged.
- Keep `update.json` on stable `4.12.0` during rc validation.

## 4.12.0-webui-control-rc1 - WebUI control candidate

<!-- SDD_V4120_FINAL_CHANGELOG_START -->
## v4.12.0 - 2026-06-08

- Promotes the WebUI control release to stable `4.12.0` after rc2 runtime smoke passed on Pixel/Magisk.
- Adds WebUI/CLI pause-resume and dispatch-now control without changing DNS, HA, VIP, route, Sortify marker policy, or host drop paths.
- Enforces strict target-prefix routing so unprefixed handover/local files are ignored instead of routed by target-name tokens.
- Ignores sidecar artifacts such as `*.sha256` in the dispatcher queue.
- Adds per-target SCP flags and the BerylAX/OpenWrt Dropbear legacy-SCP fallback `-O`.
- Preserves Sortify release marker policy `v4115` and the dispatcher authority marker contract.

### Known verification notes

- Verify hosts through `/data/adb/ssh-drop-dispatcher/ssh/ssh-config.dispatch`; direct Termux SSH aliases may fall back to password auth.
- OpenSSH post-quantum warnings can precede command output; SHA parsers must select the first 64-hex digest line, not the first output line.
- `su -c` may have an empty or root-only `HOME`; scripts should set `HOME=/data/data/com.termux/files/home` or use explicit temp paths.
- BerylAX `scp_flags=-O` may come from the service fallback even when the persisted runtime target config omits it.
<!-- SDD_V4120_FINAL_CHANGELOG_END -->


## 4.12.0-webui-control-rc2 - WebUI control rc2

- Add strict target-prefix routing by default: only `target-*__*` and `targets-*__*` names are dispatched.
- Ignore sidecar checksum/signature files such as `*.sha256`.
- Add per-target `scp_flags` support with BerylAX legacy SCP fallback `-O`.
- Preserve Sortify `v4115` release-marker contract unchanged.
- No DNS/HA/VIP/route or host drop-path changes.


- Add WebUI control surface for runtime status, enable/disable, dispatch-now, doctor, target matrix, log tail, issue bundle and requeue.
- Add dispatcher enable flag `DROP_DISPATCH_ENABLED=0|1` with safe pause behavior.
- Add service commands `--enable`, `--disable`, `--dispatch-now`, `--webui-status` and `--webui-log-tail`.
- Keep Sortify marker policy unchanged at `v4115`.
- No DNS, HA, VIP, route, host drop-path or Sortify contract changes.

<!-- SDD_SORTIFY_CROSS_REPO_LINK_CHANGELOG_20260601_START -->
## 2026-06-01 - README cross-link to Sortify Dispatch

- Added a top-of-file README link from SSH Drop Dispatcher to Sortify Dispatch.
- Clarified that Sortify protects local download artifacts while this dispatcher owns target delivery and release markers.

<!-- SDD_SORTIFY_CROSS_REPO_LINK_CHANGELOG_20260601_END -->

## 4.11.0 - 2026-05-31

- Promotes the fully verified `4.11.0-rc7` line to the public final release.
- Keeps registry-based target routing, Sortify release markers with `policy=v4115`, prompt-safe private-runtime migration/export, backup/restore, WebUI and interactive setup support.
- Final update metadata is published through `update.json`; RC metadata remains separate in `update-rc.json`.
- Public defaults remain generic and contain no private targets, private IPs, private paths, host inventory or SSH keys.

## 4.11.0-rc7 - 2026-05-29

- Polishes the Magisk installer banner so flash logs, `module.prop`, and update metadata consistently show `4.11.0-rc7`.
- Carries forward the RC6 `load_target_registry()` return-code fix and RC5 registry routing + Sortify marker contract.
- No runtime migration, private target bundling, DNS, HA, VIP, or route changes.

## 4.11.0-rc6 - 2026-05-28

- Fixes the RC5 runtime abort where `load_target_registry()` could return a failing status when enabled target configs omit optional `verify=`.
- Keeps registry routing and Sortify release-marker contract from RC5.
- RC5 remains a prerelease only; use RC6 for fresh installs and reset/restore workflows.

## 4.11.0-rc5 - Registry routing and Sortify marker contract
- Routes file names through the imported target registry instead of hard-coded sample targets.
- Adds a Sortify release marker directory and writes completion markers after all selected targets finish.
- Keeps prompt-safe private-runtime export behavior from rc4.
- Public defaults remain generic and contain no private targets, paths, IPs or keys.

## 4.11.0-rc4 - Prompt-safe private runtime export
- Routes `dispatch-config` prompts to stderr so command substitution captures only answers.
- Fixes confirmed private SSH key inclusion in private-runtime export ZIPs.
- Keeps public defaults free of private targets, paths, keys and legacy author metadata.

## 4.11.0-rc4
- Fixed dispatch-config interactive prompts so command substitutions capture only answers, not prompt text.
- Fixed private-runtime ZIP export with confirmed private SSH key inclusion.
- Public metadata remains Lycidias93-only; no bundled private targets or keys.

## 4.11.0-rc4 - ask-prompt private export fix
- Fix `dispatch-config` prompts so command substitution captures only the answer, not the prompt text.
- Restores confirmed private-key inclusion for `export-private-runtime` and backup/export flows.
- Keeps public defaults only; no private targets, IPs, paths, keys, or Lycidias93 metadata are bundled.

## 4.11.0-rc4 - public RC3

- Fix private runtime export with private SSH keys for non-interactive `su -c` usage.
- Add explicit environment-gated export confirmation for `export-private-runtime`.
- Keep public package free of bundled private targets, private paths and private keys.

## 4.11.0-rc4 - public RC2

- Add non-destructive export of an existing private Pixel Drop Dispatcher runtime into an SSH Drop Dispatcher backup ZIP.
- Include legacy private key name `id_drop_dispatch_ed25519` in backup/export and private-runtime migration flows.
- Accept `id_drop_dispatch_ed25519`, `id_ed25519` or `id_rsa` as dispatcher private-key presence checks.
- Keep public author metadata as `Lycidias93` and retain public/private guard.

<!-- SDD_V4110_RC1_WIZARD_WEBUI_START -->
## 4.11.0-rc4 - public vNext RC

- Switches public vNext ownership metadata to `Lycidias93`.
- Adds `dispatch-config` interactive wizard as the primary setup entrypoint.
- Installs/removes the Termux command `dispatch-config`.
- Adds backup/export ZIP and restore/import ZIP support with optional private SSH keys behind explicit confirmation.
- Adds local private-runtime migration into the public runtime.
- Adds reset-to-default config support.
- Adds redacted xda/GitHub issue file export.
- Adds WebUI assets and Magisk action fallback.
- Adds Magisk online RC update metadata through `update-rc.json`.
- Keeps public release free of private targets, private IPs, private paths and private keys.
<!-- SDD_V4110_RC1_WIZARD_WEBUI_END -->

# Changelog

## 4.10.0-rc1

- Initial public release candidate.
- Neutral module name and ID.
- Public runtime path.
- No bundled private targets.
- Online update metadata added.
- Sourceable health environment retained.

## 4.10.0-rc2

- Added interactive SSH target setup wizard.
- Added SSH key generation for dispatcher use.
- Added SSH config generation.
- Added optional public key installation on target hosts.
- Added remote drop directory creation.
- Added target config generation.
- Added setup smoke test.
- Updated installation, feature and XDA documentation.

## 4.10.0-rc3

- Added interactive initial setup wizard.
- Added local scan directory selection.
- Kept /storage/emulated/0/Download as the default scan directory.
- Writes SCAN_DIR to runtime config.env.
- Initial setup can continue into SSH target setup.
- Updated README, installation, configuration, features and XDA documentation.
