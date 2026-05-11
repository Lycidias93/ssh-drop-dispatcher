# SSH Drop Dispatcher v4.10.0-rc3

Public release candidate with interactive initial scan directory setup.

## New in RC3

- Added initial setup command.
- Added interactive local scan directory selection.
- Kept /storage/emulated/0/Download as the default scan directory.
- Writes SCAN_DIR to /data/adb/ssh-drop-dispatcher/config.env.
- Initial setup can continue into SSH target setup.
- Updated README and documentation.

## Setup command

su -c "/data/adb/modules/ssh_drop_dispatcher/service.sh --setup"

## Target setup command

su -c "/data/adb/modules/ssh_drop_dispatcher/service.sh --setup-target"

## Important

The local scan directory is global. Remote drop directories are configured per target.
