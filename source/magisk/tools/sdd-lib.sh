#!/system/bin/sh

module_field(){
  key="$1"
  [ -f "$MODULE_PROP" ] || return 1
  sed -n "s/^${key}=//p" "$MODULE_PROP" 2>/dev/null | sed -n '1p'
}

env_field(){
  file="$1"; key="$2"; default="${3:-}"
  value=""
  [ -f "$file" ] && value=$(sed -n "s/^${key}=//p" "$file" 2>/dev/null | sed -n '1p') || true
  [ -n "$value" ] && printf '%s' "$value" || printf '%s' "$default"
}

conf_field(){
  file="$1"; key="$2"; default="${3:-}"
  value=""
  [ -f "$file" ] && value=$(sed -n "s/^${key}=//p" "$file" 2>/dev/null | sed -n '1p' | sed 's/^"//;s/"$//') || true
  [ -n "$value" ] && printf '%s' "$value" || printf '%s' "$default"
}

json_escape(){ printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\r/\\r/g; s/\t/\\t/g'; }
json_string(){ printf '"%s"' "$(json_escape "$1")"; }

count_lines(){
  file="$1"
  if [ -f "$file" ]; then value=$(wc -l < "$file" 2>/dev/null | tr -d ' ' || true); else value=0; fi
  [ -n "$value" ] || value=0
  printf '%s' "$value"
}

count_log_token(){
  token="$1"
  if [ -f "$LOG_FILE" ]; then value=$(tail -n 200 "$LOG_FILE" 2>/dev/null | grep -c "$token" 2>/dev/null || true); else value=0; fi
  [ -n "$value" ] || value=0
  printf '%s' "$value"
}

refresh_runtime_status(){
  [ -x "$SERVICE" ] || return 69
  "$SERVICE" --runtime-status >/dev/null 2>&1
}

config_lint_rc(){
  tool="$STATE_DIR/tools/pidd-config.sh"
  [ -x "$tool" ] || tool="$MODDIR/tools/pidd-config.sh"
  [ -x "$tool" ] || return 69
  "$tool" lint >/dev/null 2>&1
}

run_service(){
  label="$1"; shift
  if [ ! -x "$SERVICE" ]; then
    echo "sdd_cli=FAIL command=$label reason=service_missing path=$SERVICE" >&2
    echo "RESULT: SDD_CLI_DONE command=$label outcome=unavailable exit_code=69" >&2
    return 69
  fi
  "$SERVICE" "$@"
  rc=$?
  [ "$rc" -eq 0 ] && outcome=success || outcome=fail
  echo "RESULT: SDD_CLI_DONE command=$label outcome=$outcome exit_code=$rc"
  return "$rc"
}

usage_error(){
  echo "sdd_cli=FAIL reason=$1" >&2
  echo "RESULT: SDD_CLI_DONE outcome=usage_error exit_code=64" >&2
  return 64
}
