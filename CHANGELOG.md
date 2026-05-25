<!-- SDD_V4110_RC1_WIZARD_WEBUI_START -->
## 4.11.0-rc1 - public vNext RC

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
