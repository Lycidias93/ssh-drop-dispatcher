# SDD Return Channel v1 additive delivery binding.
# This fragment is injected into the vNext candidate service only.
# It never changes outbound delivery success/failure semantics.

RETURN_BINDING_ROOT=$STATE_DIR/delivery-bindings

return_delivery_id_from_record(){
  return_rec=$1
  return_digest=$(printf "%s" "$return_rec" | $TOYBOX_BIN sha256sum 2>/dev/null | while read -r h rest; do printf "%s" "$h"; done)
  printf "%s" "$return_digest" | $GREP_BIN -Eq "^[0-9a-f]{64}$" || return 1
  printf "SDD-%s" "$(printf "%s" "$return_digest" | $SED_BIN 's/^\(.\{16\}\).*/\1/')"
}

record_delivery_binding(){
  return_rec=$1
  return_target=$2
  return_file=$3

  return_id=$(return_delivery_id_from_record "$return_rec" 2>/dev/null || true)
  return_sha=$(file_sha256_strict "$return_file" 2>/dev/null || true)
  return_epoch=$($DATE_BIN +%s 2>/dev/null || true)

  printf "%s" "$return_id" | $GREP_BIN -Eq "^SDD-[0-9a-f]{16}$" || return 1
  printf "%s" "$return_target" | $GREP_BIN -Eq "^[a-z0-9_-]{1,32}$" || return 1
  printf "%s" "$return_sha" | $GREP_BIN -Eq "^[0-9a-f]{64}$" || return 1
  case "$return_epoch" in ""|*[!0-9]*) return 1 ;; esac

  return_dir="$RETURN_BINDING_ROOT/$return_id"
  return_final="$return_dir/$return_target.json"
  return_tmp="$return_dir/.${return_target}.json.tmp.$$"
  $MKDIR_BIN -p "$return_dir" >/dev/null 2>&1 || return 1
  $CHMOD_BIN 700 "$RETURN_BINDING_ROOT" "$return_dir" >/dev/null 2>&1 || true

  {
    printf '{"schema":"SDD_DELIVERY_BINDING_V1","deliveryId":"%s","artifactSha256":"%s","target":"%s","completedEpoch":%s,"remoteShaVerified":true}\n' \
      "$return_id" "$return_sha" "$return_target" "$return_epoch"
  } > "$return_tmp" || { $RM_BIN -f "$return_tmp" >/dev/null 2>&1 || true; return 1; }
  $CHMOD_BIN 600 "$return_tmp" >/dev/null 2>&1 || true
  $MV_BIN -f "$return_tmp" "$return_final" >/dev/null 2>&1 || { $RM_BIN -f "$return_tmp" >/dev/null 2>&1 || true; return 1; }
  return 0
}
