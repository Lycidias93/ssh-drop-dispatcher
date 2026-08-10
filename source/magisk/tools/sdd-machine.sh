#!/system/bin/sh

emit_version(){
  version=$(module_field version 2>/dev/null || true); [ -n "$version" ] || version=unknown
  version_code=$(module_field versionCode 2>/dev/null || true); [ -n "$version_code" ] || version_code=unknown
  if [ "$FORMAT" = json ]; then
    printf '{"schema":"sdd-cli-version-v2","version":'; json_string "$version"; printf ',"versionCode":'; json_string "$version_code"; printf ',"cliSchema":%s}\n' "$SDD_CLI_SCHEMA"
  else
    echo "schema=sdd-cli-version-v2"; echo "version=$version"; echo "versionCode=$version_code"; echo "cli_schema=$SDD_CLI_SCHEMA"
    echo "RESULT: SDD_CLI_DONE command=version outcome=success exit_code=0"
  fi
}

emit_capabilities(){
  commands='version capabilities status targets target-test dispatch delivery-status delivery-wait delivery-trace delivery-preflight trace inspect queue failures quarantine preflight dispatch-file incident requeue logs doctor chatgpt-context snapshot explain config install-termux bridge-status'
  if [ "$FORMAT" = json ]; then
    printf '{"schema":"sdd-cli-capabilities-v2","cliSchema":%s,"chatgptContextSchema":%s,"workflowSchema":%s,"deliveryReceiptSchema":%s,"incidentContextSchema":%s,"machineOutput":{"env":true,"json":true,"noPrompt":true},"workflow":{"derivedDeliveryId":true,"readOnlyTrace":true,"readOnlyQueueInspection":true,"preflightNoUpload":true,"dispatchFileWait":true,"automaticRequeue":false},"verifyOwnership":{"dispatcher":true,"remoteShaRequired":true,"bashFallback":"fail_closed","pythonDelivery":"unsupported"},"commands":' "$SDD_CLI_SCHEMA" "$SDD_CHATGPT_CONTEXT_SCHEMA" "$SDD_WORKFLOW_SCHEMA" "$SDD_DELIVERY_RECEIPT_SCHEMA" "$SDD_INCIDENT_CONTEXT_SCHEMA"; json_string "$commands"; printf '}\n'
  else
    echo "schema=sdd-cli-capabilities-v2"; echo "cli_schema=$SDD_CLI_SCHEMA"; echo "chatgpt_context_schema=$SDD_CHATGPT_CONTEXT_SCHEMA"; echo "workflow_schema=$SDD_WORKFLOW_SCHEMA"; echo "delivery_receipt_schema=$SDD_DELIVERY_RECEIPT_SCHEMA"; echo "incident_context_schema=$SDD_INCIDENT_CONTEXT_SCHEMA"
    echo "machine_env=yes"; echo "machine_json=yes"; echo "no_prompt=yes"; echo "derived_delivery_id=yes"; echo "preflight_no_upload=yes"; echo "dispatch_file_wait=yes"; echo "automatic_requeue=no"; echo "verify_owner=dispatcher"; echo "remote_sha_required=yes"
    echo "bash_missing_fallback=fail_closed"; echo "python_delivery=unsupported"; echo "commands=$commands"
    echo "RESULT: SDD_CLI_DONE command=capabilities outcome=success exit_code=0"
  fi
}

status_fields(){
  refresh_rc=0; refresh_runtime_status || refresh_rc=$?
  version=$(module_field version 2>/dev/null || true); [ -n "$version" ] || version=unknown
  version_code=$(module_field versionCode 2>/dev/null || true); [ -n "$version_code" ] || version_code=unknown
  health=$(env_field "$HEALTH_FILE" status unknown); detail=$(env_field "$HEALTH_FILE" detail unknown)
  main_ok=$(env_field "$HEALTH_FILE" main_pid_ok unknown); watcher_ok=$(env_field "$HEALTH_FILE" watcher_pid_ok unknown); watchdog_ok=$(env_field "$HEALTH_FILE" watchdog_pid_ok unknown)
  inflight=$(env_field "$HEALTH_FILE" inflight_bytes 0); event_pending=$(env_field "$HEALTH_FILE" event_pending unknown)
  verify_owner=$(env_field "$VERIFY_OWNER_FILE" verify_owner missing); external_wrapper=$(env_field "$VERIFY_OWNER_FILE" external_verify_wrapper missing)
  remote_sha=$(env_field "$VERIFY_OWNER_FILE" remote_sha_required missing); bash_fallback=$(env_field "$VERIFY_OWNER_FILE" bash_missing_fallback missing); python_delivery=$(env_field "$VERIFY_OWNER_FILE" python_delivery missing)
  [ -x "$TERMUX_BIN/sdd" ] && bridge=yes || bridge=no
  outcome=success; [ "$refresh_rc" -eq 0 ] || outcome=degraded; [ "$health" = OK ] || outcome=degraded
}

emit_status(){
  status_fields
  if [ "$FORMAT" = json ]; then
    printf '{"schema":"sdd-cli-status-v2","version":'; json_string "$version"; printf ',"versionCode":'; json_string "$version_code"; printf ',"health":'; json_string "$health"; printf ',"detail":'; json_string "$detail"
    printf ',"mainPidOk":'; json_string "$main_ok"; printf ',"watcherPidOk":'; json_string "$watcher_ok"; printf ',"watchdogPidOk":'; json_string "$watchdog_ok"; printf ',"inflightBytes":'; json_string "$inflight"; printf ',"eventPending":'; json_string "$event_pending"
    printf ',"verifyOwner":'; json_string "$verify_owner"; printf ',"externalVerifyWrapper":'; json_string "$external_wrapper"; printf ',"remoteShaRequired":'; json_string "$remote_sha"; printf ',"bashMissingFallback":'; json_string "$bash_fallback"; printf ',"pythonDelivery":'; json_string "$python_delivery"; printf ',"termuxBridge":'; json_string "$bridge"; printf ',"outcome":'; json_string "$outcome"; printf '}\n'
  else
    echo "schema=sdd-cli-status-v2"; echo "version=$version"; echo "versionCode=$version_code"; echo "health=$health"; echo "detail=$detail"
    echo "main_pid_ok=$main_ok"; echo "watcher_pid_ok=$watcher_ok"; echo "watchdog_pid_ok=$watchdog_ok"; echo "inflight_bytes=$inflight"; echo "event_pending=$event_pending"
    echo "verify_owner=$verify_owner"; echo "external_verify_wrapper=$external_wrapper"; echo "remote_sha_required=$remote_sha"; echo "bash_missing_fallback=$bash_fallback"; echo "python_delivery=$python_delivery"; echo "termux_bridge_sdd=$bridge"
    echo "RESULT: SDD_CLI_DONE command=status outcome=$outcome exit_code=$refresh_rc"
  fi
  [ "$outcome" = success ]
}

emit_targets(){
  if [ "$FORMAT" = json ]; then
    printf '{"schema":"sdd-cli-targets-v2","targets":['; first=1
    if [ -d "$TARGET_DIR" ]; then for cf in "$TARGET_DIR"/*.conf; do [ -f "$cf" ] || continue; name=$(conf_field "$cf" target_name unknown); enabled=$(conf_field "$cf" enabled 1); shell=$(conf_field "$cf" shell missing); [ "$first" = 1 ] || printf ','; first=0; printf '{"name":'; json_string "$name"; printf ',"enabled":'; json_string "$enabled"; printf ',"shell":'; json_string "$shell"; printf '}'; done; fi
    printf ']}\n'
  else
    echo "schema=sdd-cli-targets-v2"; count=0
    if [ -d "$TARGET_DIR" ]; then for cf in "$TARGET_DIR"/*.conf; do [ -f "$cf" ] || continue; name=$(conf_field "$cf" target_name unknown); enabled=$(conf_field "$cf" enabled 1); shell=$(conf_field "$cf" shell missing); echo "target=$name enabled=$enabled shell=$shell"; count=$((count+1)); done; fi
    echo "target_count=$count"; echo "host_fields_exposed=no"; echo "remote_drop_fields_exposed=no"; echo "RESULT: SDD_CLI_DONE command=targets outcome=success exit_code=0"
  fi
}

receipt_summary_fields(){
  receipt_file="$STATE_DIR/delivery.receipts.jsonl"
  receipt_records=$(count_lines "$receipt_file")
  last_receipt_state=none
  last_delivery_id=none
  if [ -s "$receipt_file" ]; then
    last_line=$(tail -n 1 "$receipt_file" 2>/dev/null || true)
    last_receipt_state=$(printf '%s' "$last_line" | sed -n 's/.*"state":"\([^"]*\)".*/\1/p')
    last_delivery_id=$(printf '%s' "$last_line" | sed -n 's/.*"deliveryId":"\([^"]*\)".*/\1/p')
    [ -n "$last_receipt_state" ] || last_receipt_state=unknown
    [ -n "$last_delivery_id" ] || last_delivery_id=unknown
  fi
}

emit_chatgpt_context(){
  status_fields
  lint_rc=0; config_lint_rc || lint_rc=$?; [ "$lint_rc" -eq 0 ] || outcome=degraded
  inflight_records=$(count_lines "$STATE_DIR/dispatch.inflight"); fail_records=$(count_lines "$STATE_DIR/dispatch.faildb"); quarantine_records=$(count_lines "$STATE_DIR/dispatch.quarantined")
  recent_fail=$(count_log_token FAIL); recent_warn=$(count_log_token WARN); target_count=0
  receipt_summary_fields
  if [ -d "$TARGET_DIR" ]; then for cf in "$TARGET_DIR"/*.conf; do [ -f "$cf" ] || continue; target_count=$((target_count+1)); done; fi
  if [ "$FORMAT" = json ]; then
    printf '{"schema":"SDD_CHATGPT_CONTEXT_V1","version":'; json_string "$version"; printf ',"versionCode":'; json_string "$version_code"; printf ',"health":'; json_string "$health"
    printf ',"mainPidOk":'; json_string "$main_ok"; printf ',"watcherPidOk":'; json_string "$watcher_ok"; printf ',"watchdogPidOk":'; json_string "$watchdog_ok"; printf ',"inflightBytes":'; json_string "$inflight"; printf ',"eventPending":'; json_string "$event_pending"
    printf ',"verifyOwner":'; json_string "$verify_owner"; printf ',"externalVerifyWrapper":'; json_string "$external_wrapper"; printf ',"remoteShaRequired":'; json_string "$remote_sha"; printf ',"bashMissingFallback":'; json_string "$bash_fallback"; printf ',"pythonDelivery":'; json_string "$python_delivery"
    printf ',"configLint":'; [ "$lint_rc" -eq 0 ] && json_string ok || json_string fail
    printf ',"workflowSchema":%s,"deliveryReceiptRecords":%s,"lastDeliveryId":' "$SDD_WORKFLOW_SCHEMA" "$receipt_records"; json_string "$last_delivery_id"; printf ',"lastReceiptState":'; json_string "$last_receipt_state"
    printf ',"targetCount":%s,"inflightRecords":%s,"failRecords":%s,"quarantineRecords":%s,"recentFailLines":%s,"recentWarnLines":%s,"redaction":{"secretContentRead":false,"hostFieldsExposed":false,"remoteDropFieldsExposed":false,"networkAddressesExposed":false},"targets":[' "$target_count" "$inflight_records" "$fail_records" "$quarantine_records" "$recent_fail" "$recent_warn"
    first=1; if [ -d "$TARGET_DIR" ]; then for cf in "$TARGET_DIR"/*.conf; do [ -f "$cf" ] || continue; name=$(conf_field "$cf" target_name unknown); enabled=$(conf_field "$cf" enabled 1); shell=$(conf_field "$cf" shell missing); [ "$first" = 1 ] || printf ','; first=0; printf '{"name":'; json_string "$name"; printf ',"enabled":'; json_string "$enabled"; printf ',"shell":'; json_string "$shell"; printf '}'; done; fi
    printf '],"outcome":'; json_string "$outcome"; printf '}\n'
  else
    echo "schema=SDD_CHATGPT_CONTEXT_V1"; echo "cli_schema=$SDD_CLI_SCHEMA"; echo "workflow_schema=$SDD_WORKFLOW_SCHEMA"; echo "version=$version"; echo "versionCode=$version_code"; echo "health=$health"
    echo "main_pid_ok=$main_ok"; echo "watcher_pid_ok=$watcher_ok"; echo "watchdog_pid_ok=$watchdog_ok"; echo "inflight_bytes=$inflight"; echo "event_pending=$event_pending"
    echo "verify_owner=$verify_owner"; echo "external_verify_wrapper=$external_wrapper"; echo "remote_sha_required=$remote_sha"; echo "bash_missing_fallback=$bash_fallback"; echo "python_delivery=$python_delivery"; [ "$lint_rc" -eq 0 ] && echo "config_lint=ok" || echo "config_lint=fail"
    echo "target_count=$target_count"; if [ -d "$TARGET_DIR" ]; then for cf in "$TARGET_DIR"/*.conf; do [ -f "$cf" ] || continue; name=$(conf_field "$cf" target_name unknown); enabled=$(conf_field "$cf" enabled 1); shell=$(conf_field "$cf" shell missing); echo "target=$name enabled=$enabled shell=$shell"; done; fi
    echo "inflight_records=$inflight_records"; echo "fail_records=$fail_records"; echo "quarantine_records=$quarantine_records"; echo "recent_fail_lines=$recent_fail"; echo "recent_warn_lines=$recent_warn"; echo "delivery_receipt_records=$receipt_records"; echo "last_delivery_id=$last_delivery_id"; echo "last_receipt_state=$last_receipt_state"
    echo "secret_content_read=no"; echo "host_fields_exposed=no"; echo "remote_drop_fields_exposed=no"; echo "network_addresses_exposed=no"
    echo "RESULT: SDD_CHATGPT_CONTEXT_DONE outcome=$outcome schema=$SDD_CHATGPT_CONTEXT_SCHEMA runtime_exit_code=$refresh_rc lint_exit_code=$lint_rc"
  fi
  [ "$outcome" = success ]
}

emit_explain(){
  code="$1"
  case "$code" in
    REMOTE_SHA_MISMATCH|remote_sha_mismatch) reason='Remote digest differs from the local artifact.'; action='Do not complete delivery; inspect the transfer path and retry only after the mismatch cause is known.' ;;
    BASH_MISSING|bash_missing) reason='Target requires Bash but Bash is unavailable.'; action='Restore Bash or intentionally change the target shell profile; no sh fallback is allowed.' ;;
    TARGET_SPACE_LOW|target_space_low|SPACE_POLICY|space_policy) reason='Remote free-space policy blocked delivery.'; action='Free space or review the explicit target policy; do not bypass the gate silently.' ;;
    LEGACY_VERIFY_KEY|legacy_verify_key) reason='A target still contains a retired verify/shell selector.'; action='Run config lint/migration and remove legacy keys.' ;;
    SSH_UNREACHABLE|ssh_unreachable) reason='Required SSH connection failed.'; action='Check reachability, host config and credentials without implicit DNS/route changes.' ;;
    DELIVERY_TIMEOUT|delivery_timeout) reason='Delivery did not reach verified complete state in time.'; action='Run sdd trace <file|delivery-id> before any requeue.' ;;
    DISPATCHER_DISABLED|dispatcher_disabled) reason='Dispatcher is disabled.'; action='Enable it only if that is the intended operational state, then verify status.' ;;
    LOCAL_PREFLIGHT|local_preflight) reason='Local shell validation blocked delivery before upload.'; action='Run sdd preflight <file> and correct the local syntax issue.' ;;
    CANONICAL_COLLISION|canonical_collision) reason='The canonical artifact name already exists with different content.'; action='Inspect sdd trace and quarantine evidence before choosing a new artifact name or retry strategy.' ;;
    *) reason='Unknown or unmapped result code.'; action='Run sdd incident --chatgpt and sdd trace <file|delivery-id>.' ;;
  esac
  if [ "$FORMAT" = json ]; then printf '{"schema":"sdd-cli-explain-v2","code":'; json_string "$code"; printf ',"reason":'; json_string "$reason"; printf ',"safeNextAction":'; json_string "$action"; printf '}\n'; else echo "schema=sdd-cli-explain-v2"; echo "code=$code"; echo "reason=$reason"; echo "safe_next_action=$action"; echo "RESULT: SDD_CLI_DONE command=explain outcome=success exit_code=0"; fi
}
