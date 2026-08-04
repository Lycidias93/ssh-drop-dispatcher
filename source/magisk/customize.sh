#!/system/bin/sh
SKIPMOUNT=false
PROPFILE=true
POSTFSDATA=false
LATESTARTSERVICE=true

STATE_DIR=/data/adb/ssh-drop-dispatcher
TERMUX_BIN=/data/data/com.termux/files/usr/bin
TERMUX_CMD=$TERMUX_BIN/dispatch-config
RUNTIME_BIN=$STATE_DIR/bin
RUNTIME_CMD=$RUNTIME_BIN/dispatch-config

ui_print "SSH Drop Dispatcher 4.13.0-verify-owner-rc1"
ui_print "Runtime SoT: $STATE_DIR"
ui_print "Author: Lycidias93
Dispatcher-owned remote syntax verification + strict shell profiles + fail-closed Bash + normal-path SHA-256 parity + delivery safety + break-glass SCP + ntfy + Sortify marker contract
Prompt-safe private runtime export: final"
ui_print "Public defaults only: no bundled private targets or keys"
ui_print "Command: dispatch-config"

mkdir -p "$STATE_DIR/log" "$STATE_DIR/ssh" "$STATE_DIR/config/targets.d" "$STATE_DIR/tools" "$RUNTIME_BIN" "$STATE_DIR/backups"

set_perm_recursive $MODPATH 0 0 0755 0644
set_perm $MODPATH/service.sh 0 0 0755
[ -f "$MODPATH/action.sh" ] && set_perm $MODPATH/action.sh 0 0 0755
[ -f "$MODPATH/manual-scan.sh" ] && set_perm $MODPATH/manual-scan.sh 0 0 0755
[ -d "$MODPATH/tools" ] && set_perm_recursive $MODPATH/tools 0 0 0755 0755
[ -d "$MODPATH/config" ] && set_perm_recursive $MODPATH/config 0 0 0755 0644
[ -d "$MODPATH/webroot" ] && set_perm_recursive $MODPATH/webroot 0 0 0755 0644

if [ -d "$MODPATH/tools" ]; then
  for x in "$MODPATH"/tools/*.sh; do
    [ -f "$x" ] || continue
    bn=${x##*/}
    cp -f "$x" "$STATE_DIR/tools/$bn" 2>/dev/null || true
    chmod 755 "$STATE_DIR/tools/$bn" 2>/dev/null || true
  done
fi

cat > "$RUNTIME_CMD" <<'EOF_CMD'
#!/system/bin/sh
STATE_DIR=/data/adb/ssh-drop-dispatcher
TOOL=$STATE_DIR/tools/dispatch-config.sh
MODULE_TOOL=/data/adb/modules/ssh_drop_dispatcher/tools/dispatch-config.sh
if [ -x "$TOOL" ]; then
  exec "$TOOL" "$@"
fi
if [ -x "$MODULE_TOOL" ]; then
  exec "$MODULE_TOOL" "$@"
fi
echo "dispatch-config tool missing"
exit 1
EOF_CMD
chmod 755 "$RUNTIME_CMD" 2>/dev/null || true

if [ -d "$TERMUX_BIN" ]; then
  cat > "$TERMUX_CMD" <<'EOF_TERMUX'
#!/data/data/com.termux/files/usr/bin/sh
cmd="/data/adb/ssh-drop-dispatcher/bin/dispatch-config"
if [ "$(id -u 2>/dev/null)" = "0" ]; then
  exec "$cmd" "$@"
fi
quoted="$cmd"
for arg in "$@"; do
  safe=$(printf "%s" "$arg" | sed "s/'/'\\''/g")
  quoted="$quoted '$safe'"
done
exec su -c "$quoted"
EOF_TERMUX
  chmod 755 "$TERMUX_CMD" 2>/dev/null || true
  ui_print "- Termux command installed: dispatch-config"
else
  ui_print "- Termux not found yet; install command later with dispatch-config"
fi

ui_print "- After reboot run: dispatch-config"
ui_print "- Fallback: su -c $RUNTIME_CMD"
ui_print "- Runtime status: su -c /data/adb/modules/ssh_drop_dispatcher/service.sh --runtime-status"

ui_print "- Private runtime export: dispatch-config -> Export existing private runtime ZIP"

ui_print "- Private runtime export prompt fix: final"
