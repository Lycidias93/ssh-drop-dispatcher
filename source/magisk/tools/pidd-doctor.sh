#!/system/bin/sh
set -u

STATE_DIR=${PIDD_STATE_DIR:-/data/adb/ssh-drop-dispatcher}
MODULE_DIR=${PIDD_MODULE_DIR:-/data/adb/modules/ssh_drop_dispatcher}
TARGETS_DIR=$STATE_DIR/config/targets.d
CONFIG_TOOL=$STATE_DIR/tools/pidd-config.sh
REDACTED=0
ok=1

case "${1:-}" in
  --redacted|--chatgpt) REDACTED=1 ;;
  "") ;;
  *) echo "usage: pidd-doctor.sh [--redacted|--chatgpt]" >&2; exit 64 ;;
esac

check_file(){
  label="$1"; path="$2"
  if [ -e "$path" ]; then echo "$label=ok path=$path"; else echo "$label=missing path=$path"; ok=0; fi
}

pid_check(){
  label="$1"; file="$2"
  if [ ! -s "$file" ]; then echo "$label=missing_pid_file"; ok=0; return; fi
  pid=$(cat "$file" 2>/dev/null || true)
  if kill -0 "$pid" 2>/dev/null; then echo "$label=alive"; else echo "$label=dead"; ok=0; fi
}

conf_field(){
  file="$1"; key="$2"; default="${3:-}"
  value=$(sed -n "s/^${key}=//p" "$file" 2>/dev/null | sed -n '1p' | sed 's/^"//;s/"$//' || true)
  [ -n "$value" ] && printf '%s' "$value" || printf '%s' "$default"
}

echo "== pidd doctor =="
echo "doctor_schema=sdd-doctor-v2"
echo "redacted=$REDACTED"
check_file module_prop "$MODULE_DIR/module.prop"
check_file module_service "$MODULE_DIR/service.sh"
check_file runtime_dir "$STATE_DIR"
check_file config_env "$STATE_DIR/config.env"
check_file ssh_config "$STATE_DIR/ssh/ssh-config.dispatch"
check_file health_env "$STATE_DIR/health.env"

echo
echo "== module =="
if [ -f "$MODULE_DIR/module.prop" ]; then
  grep -E '^(id=|name=|version=|versionCode=|author=|description=|updateJson=)' "$MODULE_DIR/module.prop" 2>/dev/null || true
fi
[ -f "$MODULE_DIR/service.sh" ] && /system/bin/sh -n "$MODULE_DIR/service.sh" && echo "module_service_syntax=ok" || ok=0

echo
echo "== pids =="
pid_check main "$STATE_DIR/main.pid"
pid_check watcher "$STATE_DIR/inotifyd.pid"
pid_check watchdog "$STATE_DIR/watchdog.pid"

echo
echo "== health =="
[ -f "$STATE_DIR/health.env" ] && sed -n '1,120p' "$STATE_DIR/health.env" || true

echo
echo "== verification ownership =="
if [ -f "$STATE_DIR/verification-owner.env" ]; then
  grep -E '^(verify_owner|external_verify_wrapper|remote_sha_required|bash_missing_fallback|python_delivery|policy)=' "$STATE_DIR/verification-owner.env" 2>/dev/null || true
else
  echo "verification_owner_marker=missing"
  ok=0
fi

echo
echo "== config lint =="
if [ -x "$CONFIG_TOOL" ]; then
  "$CONFIG_TOOL" lint || ok=0
elif [ -x "$MODULE_DIR/tools/pidd-config.sh" ]; then
  "$MODULE_DIR/tools/pidd-config.sh" lint || ok=0
else
  echo "config_lint=missing"
  ok=0
fi

echo
echo "== state db sizes =="
for f in dispatch.inflight dispatch.done dispatch.complete dispatch.quarantined dispatch.faildb; do
  if [ -f "$STATE_DIR/$f" ]; then printf "%s_bytes=" "$f"; wc -c < "$STATE_DIR/$f"; else echo "$f=missing"; fi
done

echo
echo "== registry =="
count=0
if [ -d "$TARGETS_DIR" ]; then
  for cf in "$TARGETS_DIR"/*.conf; do
    [ -f "$cf" ] || continue
    target_name=$(conf_field "$cf" target_name unknown)
    enabled=$(conf_field "$cf" enabled 1)
    shell=$(conf_field "$cf" shell missing)
    role=$(conf_field "$cf" critical_role '')
    if [ "$REDACTED" = 1 ]; then
      echo "$target_name enabled=$enabled shell=$shell role=$role host=<redacted> remote_drop=<redacted>"
    else
      ssh_host=$(conf_field "$cf" ssh_host '')
      remote_drop=$(conf_field "$cf" remote_drop '')
      echo "$target_name enabled=$enabled host=$ssh_host remote_drop=$remote_drop shell=$shell role=$role"
    fi
    count=$((count + 1))
  done
else
  echo "registry=missing"
  ok=0
fi
echo "target_count=$count"

if [ "$REDACTED" = 1 ]; then
  echo "secret_content_read=no"
  echo "host_fields_redacted=yes"
  echo "remote_drop_fields_redacted=yes"
fi

echo
if [ "$ok" = 1 ]; then
  echo "doctor=ok"
  echo "RESULT: SDD_DOCTOR_DONE outcome=success redacted=$REDACTED exit_code=0"
else
  echo "doctor=degraded"
  echo "RESULT: SDD_DOCTOR_DONE outcome=degraded redacted=$REDACTED exit_code=1"
  exit 1
fi
