# SSH Drop Dispatcher CLI v2

CLI v2 is the non-interactive control surface introduced with `4.13.0-verify-owner-rc2`.
It sits above the existing dispatcher service API and does not replace the delivery engine.

## Primary command

```text
sdd
```

`dispatch-config` remains available as the legacy interactive configuration UI.

## Design contract

- Non-interactive by default.
- Unknown commands/options fail with exit `64`; they never fall into an interactive menu.
- Machine-readable `--env` and `--json` output for status/capability/context commands.
- `--no-prompt` blocks the legacy interactive config flow.
- Module version is read from the installed `module.prop`; CLI v2 does not hard-code the runtime version.
- ChatGPT context output omits SSH host fields, remote drop paths, network addresses and secret content.
- Dispatcher-owned remote verification and SHA-256 parity semantics are unchanged from RC1.

## Commands

```text
sdd version
sdd capabilities
sdd status
sdd targets
sdd target test <name>
sdd dispatch
sdd delivery status <file>
sdd delivery wait <file> [timeout_seconds] [interval_seconds]
sdd requeue <file>
sdd logs [lines]
sdd doctor
sdd doctor --chatgpt
sdd chatgpt-context
sdd snapshot
sdd explain <result-code>
sdd config
sdd install-termux
sdd bridge-status
```

Output flags can be placed before or after the command where the command supports machine output:

```text
sdd --json status
sdd status --json
sdd chatgpt-context --env
```

## ChatGPT context contract

The stable schema marker is:

```text
schema=SDD_CHATGPT_CONTEXT_V1
```

The context contains:

- installed version and versionCode;
- runtime health and process health booleans;
- verification-owner policy fields;
- config-lint result;
- target names, enabled state and explicit shell only;
- inflight/failure/quarantine counts;
- recent WARN/FAIL line counts;
- explicit redaction markers.

It does not expose SSH hosts, remote drop paths, keys, tokens or network addresses.

Expected successful tail marker:

```text
RESULT: SDD_CHATGPT_CONTEXT_DONE outcome=success schema=1 runtime_exit_code=0 lint_exit_code=0
```

## Termux bridge v2

The canonical bridge installer is:

```text
/data/adb/ssh-drop-dispatcher/tools/sdd-termux-install.sh
```

It creates:

```text
/data/adb/ssh-drop-dispatcher/bin/sdd
/data/adb/ssh-drop-dispatcher/bin/dispatch-config
/data/data/com.termux/files/usr/bin/sdd
/data/data/com.termux/files/usr/bin/dispatch-config
```

The Termux wrappers use one fixed root command and shell-quote each argument before `su -c`.
Arguments containing control characters are rejected. The bridge does not use `eval`.

Bridge contract:

```text
bridge_contract=sdd-termux-v2
```

## Stable result behavior

CLI wrapper operations end with a stable `RESULT:` marker where practical:

```text
RESULT: SDD_CLI_DONE command=<command> outcome=<success|fail|degraded|blocked|usage_error> exit_code=<n>
```

The underlying service keeps its existing delivery-specific markers; CLI v2 does not alter them.

## Exit codes

- `0`: command completed successfully.
- `1`: runtime/health/doctor result is degraded or a service operation failed.
- `64`: CLI usage error or an interactive flow was blocked by `--no-prompt`.
- `69`: required runtime/tool is unavailable.
- Other service exit codes are propagated by service-backed commands.

## Compatibility

RC2 intentionally does not alter:

- filename routing contract;
- target drop paths;
- dispatcher-owned remote syntax verification;
- fail-closed Bash behavior;
- normal-path remote SHA-256 parity gate;
- host payload non-execution policy;
- DNS, HA, VIP, route, MagicDNS or subnet-route state.
