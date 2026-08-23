# SSH Drop Dispatcher v4.14.1

## What changed

- Fixed intermittent SSH connection failures that could occur when an SSH key or SSH config bundle refresh overlapped a connection attempt.
- SSH bundle imports now avoid rewriting unchanged files and publish changed SSH files atomically, so consumers do not see a partially written key/config file.

## Updating

Install the v4.14.1 Magisk ZIP as a normal update over the existing SSH Drop Dispatcher installation. Existing dispatcher state, target configuration and SSH material remain in the persistent runtime state directory.
