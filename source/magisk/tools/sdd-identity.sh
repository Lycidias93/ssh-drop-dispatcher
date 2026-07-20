#!/system/bin/sh

# SDD vNext Milestone 1 identity helpers.
# Pure helpers only: no runtime state mutation, network access, or host execution.

SDD_IDENTITY_VERSION=${SDD_IDENTITY_VERSION:-2}
SDD_IDENTITY_POLICY=${SDD_IDENTITY_POLICY:-v4115}
SDD_IDENTITY_DASH_ALIAS=${SDD_IDENTITY_DASH_ALIAS:-0}
SDD_IDENTITY_SORT_BIN=${SDD_IDENTITY_SORT_BIN:-}

sdd_identity_sort_bin(){
  if [ -n "$SDD_IDENTITY_SORT_BIN" ] && [ -x "$SDD_IDENTITY_SORT_BIN" ]; then
    printf "%s" "$SDD_IDENTITY_SORT_BIN"
    return 0
  fi
  for candidate in /system/bin/sort /data/data/com.termux/files/usr/bin/sort /usr/bin/sort /bin/sort; do
    if [ -x "$candidate" ]; then
      printf "%s" "$candidate"
      return 0
    fi
  done
  command -v sort 2>/dev/null || return 1
}

sdd_identity_component_safe(){
  case "${1:-}" in
    ""|*"|"*|*'
'*|*'	'*) return 1 ;;
    *) return 0 ;;
  esac
}

sdd_identity_sha256_valid(){
  value="${1:-}"
  [ "${#value}" -eq 64 ] || return 1
  case "$value" in *[!0123456789abcdefABCDEF]*) return 1 ;; esac
  return 0
}

sdd_identity_target_valid(){
  case "${1:-}" in ""|*[!abcdefghijklmnopqrstuvwxyz0123456789_]*) return 1 ;; esac
  return 0
}

sdd_identity_normalize_targets(){
  sort_bin=$(sdd_identity_sort_bin) || return 1
  tmp_root="${TMPDIR:-/data/local/tmp}"
  tmp="$tmp_root/sdd-identity-targets.$$"
  : > "$tmp" 2>/dev/null || return 1
  for target in "$@"; do
    [ -n "$target" ] || continue
    target=$(printf "%s" "$target" | tr "[:upper:]" "[:lower:]")
    sdd_identity_target_valid "$target" || {
      rm -f "$tmp" >/dev/null 2>&1 || true
      return 1
    }
    printf "%s\n" "$target" >> "$tmp" || {
      rm -f "$tmp" >/dev/null 2>&1 || true
      return 1
    }
  done
  normalized=$("$sort_bin" -u "$tmp" 2>/dev/null | paste -sd, - 2>/dev/null)
  rm -f "$tmp" >/dev/null 2>&1 || true
  [ -n "$normalized" ] || return 1
  printf "%s" "$normalized"
}

sdd_identity_semantic_name(){
  requested="${1:-}"
  sdd_identity_component_safe "$requested" || return 1

  parenthesized=$(printf "%s\n" "$requested" | sed -E 's/^(.*) \(([1-9][0-9]*)\)(\.[^/]+)$/\1\3/')
  if [ "$parenthesized" != "$requested" ]; then
    printf "%s" "$parenthesized"
    return 0
  fi

  case "${SDD_IDENTITY_DASH_ALIAS:-0}" in
    1|yes|YES|true|TRUE|on|ON)
      dashed=$(printf "%s\n" "$requested" | sed -E 's/^(.*)-([1-9])(\.[^/]+)$/\1\3/')
      if [ "$dashed" != "$requested" ]; then
        printf "%s" "$dashed"
        return 0
      fi
      ;;
  esac

  printf "%s" "$requested"
}

sdd_identity_alias_kind(){
  requested="${1:-}"
  semantic=$(sdd_identity_semantic_name "$requested") || return 1
  if [ "$semantic" = "$requested" ]; then
    printf "exact"
    return 0
  fi
  case "$requested" in
    *" ("[1-9]*")".*) printf "browser_parenthesized" ;;
    *) printf "browser_dash_optin" ;;
  esac
}

sdd_identity_key(){
  semantic="${1:-}"
  sha256="${2:-}"
  targets="${3:-}"
  policy="${4:-$SDD_IDENTITY_POLICY}"

  sdd_identity_component_safe "$semantic" || return 1
  sdd_identity_sha256_valid "$sha256" || return 1
  sdd_identity_component_safe "$targets" || return 1
  sdd_identity_component_safe "$policy" || return 1

  printf "v%s|semantic=%s|sha256=%s|targets=%s|policy=%s" \
    "$SDD_IDENTITY_VERSION" "$semantic" "$(printf "%s" "$sha256" | tr "[:upper:]" "[:lower:]")" "$targets" "$policy"
}

sdd_identity_describe(){
  requested="${1:-}"
  sha256="${2:-}"
  shift 2 || return 1

  semantic=$(sdd_identity_semantic_name "$requested") || return 1
  alias_kind=$(sdd_identity_alias_kind "$requested") || return 1
  targets=$(sdd_identity_normalize_targets "$@") || return 1
  key=$(sdd_identity_key "$semantic" "$sha256" "$targets" "$SDD_IDENTITY_POLICY") || return 1

  if [ "$alias_kind" = "exact" ]; then is_alias=no; else is_alias=yes; fi

  printf "identity_version=%s\n" "$SDD_IDENTITY_VERSION"
  printf "requested_name=%s\n" "$requested"
  printf "semantic_name=%s\n" "$semantic"
  printf "effective_remote_name=%s\n" "$requested"
  printf "alias_kind=%s\n" "$alias_kind"
  printf "is_alias=%s\n" "$is_alias"
  printf "sha256=%s\n" "$(printf "%s" "$sha256" | tr "[:upper:]" "[:lower:]")"
  printf "targets=%s\n" "$targets"
  printf "policy=%s\n" "$SDD_IDENTITY_POLICY"
  printf "identity_key=%s\n" "$key"
}
