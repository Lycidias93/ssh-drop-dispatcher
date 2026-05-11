#!/system/bin/sh
SKIPMOUNT=false
PROPFILE=true
POSTFSDATA=false
LATESTARTSERVICE=true
ui_print "SSH Drop Dispatcher v4.10.0 RC2"
ui_print "Runtime SoT: /data/adb/ssh-drop-dispatcher"
ui_print "Targets: alpha beta edge router"
ui_print "Requires runtime bundle in /storage/emulated/0/PixelDropDispatch/main-bundle or existing runtime config."
mkdir -p /data/adb/ssh-drop-dispatcher/log /data/adb/ssh-drop-dispatcher/ssh
set_perm_recursive $MODPATH 0 0 0755 0644
set_perm $MODPATH/service.sh 0 0 0755
set_perm $MODPATH/manual-scan.sh 0 0 0755
[ -d "$MODPATH/tools" ] && set_perm_recursive $MODPATH/tools 0 0 0755 0755
[ -d "$MODPATH/config" ] && set_perm_recursive $MODPATH/config 0 0 0755 0644
ui_print "- v4.10.0 RC2 repairs runtime tool/default import and doctor routing"
ui_print "- Runtime status: su -c /data/adb/modules/ssh_drop_dispatcher/service.sh --runtime-status"
