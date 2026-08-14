# SSH Drop Dispatcher RC5 WebUI v0.3 candidate

Date: 2026-08-13
Status: repository candidate rebuilt and CI-verified after fast-status packaging correction; Pixel runtime preflight pending

## Candidate identity

- Version: `4.13.0-verify-owner-rc5`
- VersionCode: `4130005`
- Branch: `rc5-webui-enhancements`
- Verified implementation head: `518323b5113c2fe5d99e08a85471cf7eb2282038`
- GitHub Actions run: `31649348576`
- GitHub Actions job: `94290038108`
- Inner module ZIP bytes: `3661719`
- Inner module ZIP SHA-256: `6739900be9cd6886ca5745e7cc1b16d21133e6fa10721539045e22ba6a2c3401`
- Actions artifact ID: `9161974295`
- Actions artifact size: `3662544`
- Actions artifact digest: `sha256:64709623f063ace937ca3abda8e280e633caa94f84493f8c5d449823d73a0949`

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

## Fast-status packaging correction

The first RC5 CI candidate at head `272f4535228cb7b190de4556e815c593f215653d` incorrectly packaged the legacy RC4 typed adapter directly as `bin/module-control-rc4`.

A read-only Pixel diagnostic showed the consequence:

- RC5 v0.3 capabilities path completed successfully;
- accepted active RC4 `module-control status` completed through its local-snapshot fast-status path;
- direct `sdd --json chatgpt-context` exceeded the bounded diagnostic window;
- the original RC5 candidate RC4/RC5 status paths also exceeded that window because they had lost the accepted RC4 fast-status front wrapper.

This was a candidate composition regression, not a delivery-core change and not a failure of the generic v0.3 collection/import/export core.

Head `518323b5113c2fe5d99e08a85471cf7eb2282038` corrects the composition to:

1. `bin/module-control` — RC5 v0.3 extension adapter;
2. `bin/module-control-rc4` — accepted RC4 fast-status wrapper;
3. `bin/module-control-base` — preserved legacy typed RC4 adapter for non-status operations.

The builder now verifies that the RC4 wrapper advertises `status_source=local_snapshot` and `backend_refresh=none`, syntax-checks all three adapters and executes a status fixture through the complete RC5-to-RC4 chain. The fixture must observe the local-snapshot status path before the build can pass.

This correction is `module_specific` under the shared WebUI sync policy: it preserves SSH Drop Dispatcher runtime/adaptor composition and does not change the generic WebUI v0.3 schema/server/frontend primitives.

## Preserved RC4 / delivery contracts

The delivery core is intentionally unchanged. The pinned `service.sh` Git blob remains:

`c19b1dfb315cf53e4db9d43fe069d3d56d8f6337`

The RC5 package preserves the accepted RC4 fast-status behavior while retaining the full RC4 typed adapter behind it for all non-status operations.

The hardened Android browser launcher remains based on the RC4 action layer and uses `/system/bin/am` on Android.

## CI evidence

Run `31649348576` completed successfully with:

- shell syntax and Go formatting guards;
- dispatcher identity fixtures;
- RC3 workflow-contract fixtures;
- unchanged deterministic RC4 candidate build;
- deterministic corrected RC5 build;
- explicit three-adapter fast-status composition checks;
- RC5 fast-status local-snapshot runtime fixture;
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

The currently accepted device Real-Ist remains RC4 until the corrected RC5 candidate passes the project Pixel runtime preflight, controlled installation/activation and installed-runtime verification with:

`RESULT: CG_INSTALLED_RUNTIME_VERIFY_DONE outcome=success workflow_exit_code=0`

No public `update.json` promotion or release is implied by this candidate.

The separate historical scan-lock contention/follow-up amplification issue is not changed or claimed fixed by RC5.
