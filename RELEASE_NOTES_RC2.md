# SSH Drop Dispatcher v4.10.0-rc2

Public release candidate with interactive target setup.

## New in RC2

- Interactive SSH target setup wizard
- SSH key generation
- SSH config generation
- Optional public key installation on target host
- Remote drop directory creation
- Dispatcher target config creation
- SSH smoke test
- Updated installation and feature documentation

## Setup command

su -c "/data/adb/modules/ssh_drop_dispatcher/service.sh --setup-target"

## Important

This RC still does not include private target definitions. Users configure their own SSH targets.
