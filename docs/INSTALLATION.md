# Installation

## Requirements

- Rooted Android device
- Magisk-compatible module manager
- Termux
- Termux package `openssh`
- SSH access to your own target host

## Install

1. Download `ssh-drop-dispatcher-magisk-v4.11.0-rc1.zip` from the GitHub release.
2. Flash it in Magisk.
3. Reboot Android.
4. Open Termux and run:

```sh
dispatch-config
```

Fallback:

```sh
su -c /data/adb/ssh-drop-dispatcher/bin/dispatch-config
```

## Online updates

The RC channel uses:

```text
https://raw.githubusercontent.com/Lycidias93/ssh-drop-dispatcher/main/update-rc.json
```

Stable releases use `update.json`.

## Before replacing a private runtime

Do not disable or remove the private dispatcher until a public-format backup ZIP has been created and verified.
Use `dispatch-config export-private-runtime` to create the ZIP, then import it into the public runtime only when you are ready to switch over.
