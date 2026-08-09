#!/system/bin/sh
SKIPMOUNT=false
PROPFILE=true
POSTFSDATA=false
LATESTARTSERVICE=true

STATE_DIR=/data/adb/ssh-drop-dispatcher
RUNTIME_BIN=$STATE_DIR/bin
TERMUX_INSTALLER=$STATE_DIR/tools/sdd-termux-install.sh

ui_print "SSH Drop Dispatcher 4.13.0-verify-owner-rc2"
ui_print "Runtime SoT: $STATE_DIR"
ui_print "Author: Lycidias93"
ui_print "Dispatcher-owned remote verification + CLI v2 + hardened Termux bridge + ChatGPT machine context"
ui_print "Public defaults only: no bundled private targets or keys"

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

if [ -x "$TERMUX_INSTALLER" ]; then
  "$TERMUX_INSTALLER" install >/dev/null 2>&1 || true
else
  ui_print "- WARN: Termux bridge installer missing; runtime tools remain available through module paths"
fi

ui_print "- Primary Termux command: sdd"
ui_print "- Legacy interactive config command: dispatch-config"
ui_print "- Machine status: sdd status --env"
ui_print "- JSON status: sdd status --json"
ui_print "- ChatGPT context: sdd chatgpt-context"
ui_print "- ChatGPT doctor: sdd doctor --chatgpt"
ui_print "- Runtime fallback: su -c $RUNTIME_BIN/sdd"
ui_print "- Private runtime export remains available through dispatch-config"
