#!/system/bin/sh
set -u

STATE_DIR=${SDD_STATE_DIR:-/data/adb/ssh-drop-dispatcher}
MODDIR=${SDD_MODDIR:-/data/adb/modules/ssh_drop_dispatcher}
TERMUX_BIN=${SDD_TERMUX_BIN:-/data/data/com.termux/files/usr/bin}
RUNTIME_BIN=$STATE_DIR/bin
RUNTIME_SDD=$RUNTIME_BIN/sdd
RUNTIME_CONFIG=$RUNTIME_BIN/dispatch-config
TERMUX_SDD=$TERMUX_BIN/sdd
TERMUX_CONFIG=$TERMUX_BIN/dispatch-config

write_runtime_sdd(){
  mkdir -p "$RUNTIME_BIN"
  cat > "$RUNTIME_SDD" <<'EOF_RUNTIME_SDD'
#!/system/bin/sh
STATE_DIR=/data/adb/ssh-drop-dispatcher
TOOL=$STATE_DIR/tools/sdd.sh
MODULE_TOOL=/data/adb/modules/ssh_drop_dispatcher/tools/sdd.sh
if [ -x "$TOOL" ]; then exec "$TOOL" "$@"; fi
if [ -x "$MODULE_TOOL" ]; then exec "$MODULE_TOOL" "$@"; fi
echo "sdd tool missing"
exit 69
EOF_RUNTIME_SDD
  chmod 755 "$RUNTIME_SDD" 2>/dev/null || true
}

write_runtime_config(){
  mkdir -p "$RUNTIME_BIN"
  cat > "$RUNTIME_CONFIG" <<'EOF_RUNTIME_CONFIG'
#!/system/bin/sh
STATE_DIR=/data/adb/ssh-drop-dispatcher
TOOL_V2=$STATE_DIR/tools/dispatch-config-v2.sh
MODULE_TOOL_V2=/data/adb/modules/ssh_drop_dispatcher/tools/dispatch-config-v2.sh
TOOL_LEGACY=$STATE_DIR/tools/dispatch-config.sh
MODULE_TOOL_LEGACY=/data/adb/modules/ssh_drop_dispatcher/tools/dispatch-config.sh
if [ -x "$TOOL_V2" ]; then exec "$TOOL_V2" "$@"; fi
if [ -x "$MODULE_TOOL_V2" ]; then exec "$MODULE_TOOL_V2" "$@"; fi
if [ -x "$TOOL_LEGACY" ]; then exec "$TOOL_LEGACY" "$@"; fi
if [ -x "$MODULE_TOOL_LEGACY" ]; then exec "$MODULE_TOOL_LEGACY" "$@"; fi
echo "dispatch-config tool missing"
exit 69
EOF_RUNTIME_CONFIG
  chmod 755 "$RUNTIME_CONFIG" 2>/dev/null || true
}

write_termux_sdd(){
  cat > "$TERMUX_SDD" <<'EOF_TERMUX_SDD'
#!/data/data/com.termux/files/usr/bin/sh
cmd=/data/adb/ssh-drop-dispatcher/bin/sdd
quote_arg(){
  printf "'"
  printf '%s' "$1" | sed "s/'/'\\\\''/g"
  printf "'"
}
if [ "$(id -u 2>/dev/null)" = "0" ]; then exec "$cmd" "$@"; fi
quoted=$(quote_arg "$cmd")
for arg in "$@"; do
  if printf '%s' "$arg" | grep -q '[[:cntrl:]]'; then
    echo "sdd bridge rejected control character in argument" >&2
    exit 64
  fi
  q=$(quote_arg "$arg")
  quoted="$quoted $q"
done
exec su -c "$quoted"
EOF_TERMUX_SDD
  chmod 755 "$TERMUX_SDD" 2>/dev/null || true
}

write_termux_config(){
  cat > "$TERMUX_CONFIG" <<'EOF_TERMUX_CONFIG'
#!/data/data/com.termux/files/usr/bin/sh
cmd=/data/adb/ssh-drop-dispatcher/bin/dispatch-config
quote_arg(){
  printf "'"
  printf '%s' "$1" | sed "s/'/'\\\\''/g"
  printf "'"
}
if [ "$(id -u 2>/dev/null)" = "0" ]; then exec "$cmd" "$@"; fi
quoted=$(quote_arg "$cmd")
for arg in "$@"; do
  if printf '%s' "$arg" | grep -q '[[:cntrl:]]'; then
    echo "dispatch-config bridge rejected control character in argument" >&2
    exit 64
  fi
  q=$(quote_arg "$arg")
  quoted="$quoted $q"
done
exec su -c "$quoted"
EOF_TERMUX_CONFIG
  chmod 755 "$TERMUX_CONFIG" 2>/dev/null || true
}

install_all(){
  write_runtime_sdd
  write_runtime_config
  if [ ! -d "$TERMUX_BIN" ]; then
    echo "termux_bridge=deferred"
    echo "termux_bin=$TERMUX_BIN"
    echo "runtime_sdd=$RUNTIME_SDD"
    echo "runtime_dispatch_config=$RUNTIME_CONFIG"
    echo "RESULT: SDD_TERMUX_BRIDGE_INSTALL_DONE outcome=deferred exit_code=0"
    return 0
  fi
  write_termux_sdd
  write_termux_config
  echo "termux_bridge=installed"
  echo "termux_sdd=$TERMUX_SDD"
  echo "termux_dispatch_config=$TERMUX_CONFIG"
  echo "runtime_sdd=$RUNTIME_SDD"
  echo "runtime_dispatch_config=$RUNTIME_CONFIG"
  echo "bridge_contract=sdd-termux-v2"
  echo "dispatch_config_frontend=v2"
  echo "RESULT: SDD_TERMUX_BRIDGE_INSTALL_DONE outcome=success exit_code=0"
}

remove_termux(){
  if [ -f "$TERMUX_SDD" ]; then rm -f "$TERMUX_SDD"; echo "removed=$TERMUX_SDD"; else echo "already_absent=$TERMUX_SDD"; fi
  if [ -f "$TERMUX_CONFIG" ]; then rm -f "$TERMUX_CONFIG"; echo "removed=$TERMUX_CONFIG"; else echo "already_absent=$TERMUX_CONFIG"; fi
  echo "RESULT: SDD_TERMUX_BRIDGE_REMOVE_DONE outcome=success exit_code=0"
}

bridge_status(){
  [ -x "$RUNTIME_SDD" ] && runtime_sdd=yes || runtime_sdd=no
  [ -x "$RUNTIME_CONFIG" ] && runtime_dispatch_config=yes || runtime_dispatch_config=no
  [ -x "$TERMUX_SDD" ] && termux_sdd=yes || termux_sdd=no
  [ -x "$TERMUX_CONFIG" ] && termux_dispatch_config=yes || termux_dispatch_config=no
  echo "schema=sdd-termux-bridge-status-v2"
  echo "bridge_contract=sdd-termux-v2"
  echo "dispatch_config_frontend=v2"
  echo "runtime_sdd=$runtime_sdd"
  echo "runtime_dispatch_config=$runtime_dispatch_config"
  echo "termux_sdd=$termux_sdd"
  echo "termux_dispatch_config=$termux_dispatch_config"
  if [ "$runtime_sdd" = yes ] && [ "$runtime_dispatch_config" = yes ]; then
    echo "RESULT: SDD_TERMUX_BRIDGE_STATUS outcome=ready exit_code=0"
    return 0
  fi
  echo "RESULT: SDD_TERMUX_BRIDGE_STATUS outcome=degraded exit_code=1"
  return 1
}

case "${1:-install}" in
  install) install_all ;;
  remove) remove_termux ;;
  status|self-test) bridge_status ;;
  *) echo "usage: sdd-termux-install.sh install|remove|status" >&2; exit 64 ;;
esac
