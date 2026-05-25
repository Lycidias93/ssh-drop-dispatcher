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
