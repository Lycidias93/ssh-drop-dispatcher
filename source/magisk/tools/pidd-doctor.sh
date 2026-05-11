#!/system/bin/sh
set -u

STATE_DIR=${PIDD_STATE_DIR:-/data/adb/ssh-drop-dispatcher}
MODULE_DIR=${PIDD_MODULE_DIR:-/data/adb/modules/ssh_drop_dispatcher}
TARGETS_DIR=$STATE_DIR/config/targets.d
ok=1

check_file(){
  label="$1"; path="$2"
  if [ -e "$path" ]; then echo "$label=ok path=$path"; else echo "$label=missing path=$path"; ok=0; fi
}

pid_check(){
  label="$1"; file="$2"
  if [ ! -s "$file" ]; then echo "$label=missing_pid_file"; ok=0; return; fi
  pid=$(cat "$file" 2>/dev/null || true)
  if kill -0 "$pid" 2>/dev/null; then echo "$label=alive pid=$pid"; else echo "$label=dead pid=$pid"; ok=0; fi
}

echo "== pidd doctor =="
check_file module_prop "$MODULE_DIR/module.prop"
check_file module_service "$MODULE_DIR/service.sh"
check_file runtime_dir "$STATE_DIR"
check_file config_env "$STATE_DIR/config.env"
check_file ssh_config "$STATE_DIR/ssh/ssh-config.dispatch"
check_file health_env "$STATE_DIR/health.env"

echo
echo "== module =="
[ -f "$MODULE_DIR/module.prop" ] && sed -n "1,80p" "$MODULE_DIR/module.prop"
[ -f "$MODULE_DIR/service.sh" ] && /system/bin/sh -n "$MODULE_DIR/service.sh" && echo "module_service_syntax=ok" || ok=0

echo
echo "== pids =="
pid_check main "$STATE_DIR/main.pid"
pid_check watcher "$STATE_DIR/inotifyd.pid"
pid_check watchdog "$STATE_DIR/watchdog.pid"

echo
echo "== health =="
[ -f "$STATE_DIR/health.env" ] && sed -n "1,120p" "$STATE_DIR/health.env" || true

echo
echo "== state db sizes =="
for f in dispatch.inflight dispatch.done dispatch.complete dispatch.quarantined dispatch.faildb; do
  if [ -f "$STATE_DIR/$f" ]; then printf "%s_bytes=" "$f"; wc -c < "$STATE_DIR/$f"; else echo "$f=missing"; fi
done

echo
echo "== registry =="
if [ -d "$TARGETS_DIR" ]; then
  for cf in "$TARGETS_DIR"/*.conf; do
    [ -f "$cf" ] || continue
    target_name= enabled=1 ssh_host= remote_drop= shell_kind= critical_role=
    . "$cf"
    echo "$target_name enabled=$enabled host=$ssh_host remote_drop=$remote_drop shell=$shell_kind role=$critical_role"
  done
else
  echo "registry=missing"
fi

echo
if [ "$ok" = "1" ]; then echo "doctor=ok"; else echo "doctor=degraded"; exit 1; fi
