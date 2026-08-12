# SSH Drop Dispatcher RC5 WebUI v0.3 candidate

Date: 2026-08-12
Status: repository candidate built and CI-verified; installed-runtime verification pending

## Candidate identity

- Version: `4.13.0-verify-owner-rc5`
- VersionCode: `4130005`
- Branch: `rc5-webui-enhancements`
- Verified implementation head: `272f4535228cb7b190de4556e815c593f215653d`
- GitHub Actions run: `31646893673`
- GitHub Actions job: `94282460361`
- Inner module ZIP bytes: `3659733`
- Inner module ZIP SHA-256: `618c43535a1b0c7e89c9646bc73bcbe59b8e8579a9702883c654e33f5f10ec63`
- Actions artifact ID: `9161073241`
- Actions artifact size: `3660558`
- Actions artifact digest: `sha256:ae7678e9559e390aec3fa05e5df6246f8c69879c03357ae5708b8ec058b8db59`

The build is deterministic: two independent package passes produced the same inner module ZIP SHA-256.

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
- Target-name validation is aligned with the canonical Dispatcher lint contract (`[a-z0-9_]+`).
- Private-key bytes, tokens and arbitrary shell commands are not exposed by the editor or export.

## Preserved RC4 / delivery contracts

The delivery core is intentionally unchanged. The pinned `service.sh` Git blob remains:

`c19b1dfb315cf53e4db9d43fe069d3d56d8f6337`

The accepted RC4 adapter remains packaged as `bin/module-control-rc4`; the RC5 adapter delegates existing RC4 operations to it and owns only the v0.3 extension operations.

The hardened Android browser launcher remains based on the RC4 action layer and uses `/system/bin/am` on Android.

## CI evidence

Run `31646893673` completed successfully with:

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
