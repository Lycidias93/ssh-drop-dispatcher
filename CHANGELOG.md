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
