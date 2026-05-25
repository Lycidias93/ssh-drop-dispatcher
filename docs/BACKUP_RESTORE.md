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
