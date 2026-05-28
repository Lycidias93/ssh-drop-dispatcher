# Backup, restore and private-runtime migration

`dispatch-config` can export and import a ZIP backup.

Default export includes:

- `manifest.env`
- `config.env`
- `config/targets.d/*.conf`
- `ssh/ssh-config.dispatch`
- `ssh/known_hosts`
- public SSH keys

Private SSH keys are excluded by default. Exporting or importing private SSH keys requires an explicit typed confirmation.

The wizard also provides a local-only migration helper for an existing private runtime. This migration is for the device owner only and must not be committed to the public repository or release ZIP.

## Export an existing private runtime

Run `dispatch-config` and choose `Export existing private runtime ZIP`, or run:

```sh
dispatch-config export-private-runtime
```

This creates a ZIP in the Android Download directory using the public SSH Drop Dispatcher backup format. Private SSH keys are excluded by default and require typing `INCLUDE-PRIVATE-KEYS`.

Use this before replacing a private Pixel Drop Dispatcher runtime with the public SSH Drop Dispatcher module.

## Non-interactive export with private keys

The `export-private-runtime` command can be driven non-interactively for migration tests:

```sh
SDD_EXPORT_INCLUDE_PRIVATE_KEYS=yes SDD_EXPORT_PRIVATE_KEYS_CONFIRM=INCLUDE-PRIVATE-KEYS dispatch-config export-private-runtime
```

Only use this for local migration or local backups. Do not upload the resulting ZIP to public releases or issue reports.

## Sortify release marker contract
The dispatcher creates `integration/sortify-release` and writes per-file completion markers after all selected targets are done.
