#!/system/bin/sh
MODDIR=${0%/*}
RUNTIME_CMD=/data/adb/ssh-drop-dispatcher/bin/dispatch-config
MODULE_TOOL=$MODDIR/tools/dispatch-config.sh
if [ -x "$RUNTIME_CMD" ]; then
  exec "$RUNTIME_CMD"
fi
if [ -x "$MODULE_TOOL" ]; then
  exec "$MODULE_TOOL"
fi
echo "dispatch-config is not installed yet. Reboot once, then run dispatch-config from Termux."
exit 1
