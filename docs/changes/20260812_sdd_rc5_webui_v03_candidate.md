# SSH Drop Dispatcher RC5 WebUI v0.3 candidate

Date: 2026-08-12
Status: repository candidate built and CI-verified; installed-runtime verification pending

## Candidate identity

- Version: `4.13.0-verify-owner-rc5`
- VersionCode: `4130005`
- Branch: `rc5-webui-enhancements`
- Verified source head: `af578b14837f1403bcf98d91082aa5e4b1efdc33`
- GitHub Actions run: `31646319199`
- Inner module ZIP bytes: `3659732`
- Inner module ZIP SHA-256: `91a8d2b491353b1b1955550e49264bbeb4ffff94af6debacb3c138a187981410`
- Actions artifact ID: `9160856258`
- Actions artifact digest: `sha256:157c81e1bd63b1da05d9143677f9d399d65813cf42e04bfcdd161efab2b51d16`

The build is deterministic: two independent package passes produced the same module ZIP SHA-256.

## Shared WebUI foundation

RC5 pins the reusable foundation exactly:

- Core version: `0.3.0`
- Template repository: `Lycidias93/android-root-module-webui-template`
- Template commit: `3a8f614758d73eb2fb210baa782028c1c2030c5c`

RC5 consumes the v0.3 generic collection/import/export server and frontend while retaining SSH Drop Dispatcher domain logic in its module adapter.

## RC5 WebUI additions

- Typed target-profile collection editor.
- Preview-before-apply binding through the generic v0.3 preview token/digest contract.
- Exact confirmation `APPLY TARGETS` for collection mutation.
- Schema-bound target-profile JSON import with preview and exact confirmation `IMPORT TARGETS`.
- Secret-safe target-profile export with `secret_policy=reference`.
- Target changes create a timestamped backup before the directory swap.
- Target replacement is staged as a complete directory transaction.
- Post-apply `pidd-config.sh lint` verification is mandatory.
- Failed post-apply lint restores the previous target directory.
- `allow_fallback` remains fail-closed and is written as `0`.
- Existing target metadata needed by the dispatcher is normalized and preserved: target name, enabled state, aliases, SSH user/alias/port references, remote drop, platform, shell, SCP mode and role.
- Private-key bytes, tokens and arbitrary shell commands are not exposed by the editor or export.

## Preserved RC4 / delivery contracts

The delivery core is intentionally unchanged. The pinned `service.sh` Git blob remains:

`c19b1dfb315cf53e4db9d43fe069d3d56d8f6337`

The accepted RC4 adapter remains packaged as `bin/module-control-rc4`; the RC5 adapter delegates existing RC4 operations to it and owns only the v0.3 extension operations.

The hardened Android browser launcher remains based on the RC4 action layer and uses `/system/bin/am` on Android.

## CI evidence

Run `31646319199` completed successfully with:

- shell syntax and Go formatting guards;
- dispatcher identity fixtures;
- RC3 workflow-contract fixtures;
- unchanged deterministic RC4 candidate build;
- deterministic RC5 build;
- RC5 v0.3 capability-schema check;
- typed target collection get/preview/apply fixture;
- backup plus post-apply verification fixture;
- schema-bound export/import preview/apply fixture;
- module ZIP structure and metadata checks;
- clean checkout verification.

Build marker:

`RESULT: SDD_RC5_WEBUI_BUILD_DONE outcome=success delivery_core_changed=no workflow_exit_code=0`

## Acceptance boundary

This document is repository/build evidence only. It is not installed-runtime proof.

The currently accepted device Real-Ist remains RC4 until RC5 passes the project runtime preflight, controlled installation/activation and installed-runtime verification with:

`RESULT: CG_INSTALLED_RUNTIME_VERIFY_DONE outcome=success workflow_exit_code=0`

No public `update.json` promotion or release is implied by this candidate.

The separate historical scan-lock contention/follow-up amplification issue is not changed or claimed fixed by RC5.
