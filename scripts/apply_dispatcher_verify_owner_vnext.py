#!/usr/bin/env python3
from __future__ import annotations

import re
import subprocess
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SERVICE = ROOT / "source/magisk/service.sh"
MODULE_PROP = ROOT / "source/magisk/module.prop"
CUSTOMIZE = ROOT / "source/magisk/customize.sh"
PIDD_CONFIG = ROOT / "source/magisk/tools/pidd-config.sh"
DIST = ROOT / "dist/ssh-drop-dispatcher-magisk-v4.13.0-verify-owner-rc1.zip"

VERSION = "4.13.0-verify-owner-rc1"
VERSION_CODE = "4130001"
POLICY = "sdd-v4.13.0-verify-owner-v1"


class TransformError(RuntimeError):
    pass


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise TransformError(f"{label}: expected exactly one literal anchor, found {count}")
    return text.replace(old, new, 1)


def regex_once(text: str, pattern: str, replacement: str, label: str) -> str:
    new_text, count = re.subn(pattern, replacement, text, count=1, flags=re.S)
    if count != 1:
        raise TransformError(f"{label}: expected exactly one regex anchor, found {count}")
    return new_text


def patch_service(text: str) -> str:
    text = replace_once(
        text,
        "HEALTH_FILE=$STATE_DIR/health.env\n",
        "HEALTH_FILE=$STATE_DIR/health.env\n"
        "VERIFY_OWNER_FILE=$STATE_DIR/verification-owner.env\n"
        "VERIFY_OWNER_POLICY=" + POLICY + "\n",
        "service constants",
    )

    new_registry = r'''load_target_registry(){
  ACTIVE_TARGETS=""
  [ -d "$TARGETS_DIR" ] || return 0
  for cf in "$TARGETS_DIR"/*.conf; do
    [ -f "$cf" ] || continue
    if $GREP_BIN -Eq "^(verify|verify_cmd|verify_kind)=" "$cf" 2>/dev/null; then
      log "FAIL target_registry legacy_verify_key file=$cf verify_owner=dispatcher external_verify_wrapper=no"
      return 1
    fi
    target_name=
    enabled=1
    ssh_host=
    remote_drop=
    platform=
    shell=
    scp_flags=
    . "$cf"
    target_name=$(lower_name "$target_name")
    case "$target_name" in
      "") log "FAIL target_registry missing_name file=$cf"; return 1 ;;
      *[!a-z0-9_]*) log "FAIL target_registry invalid_name file=$cf"; return 1 ;;
    esac
    [ "${enabled:-1}" = "1" ] || continue
    case "${shell:-}" in
      sh|bash) ;;
      "") log "FAIL target_registry missing_explicit_shell target=$target_name file=$cf"; return 1 ;;
      *) log "FAIL target_registry invalid_shell target=$target_name shell=${shell:-} file=$cf"; return 1 ;;
    esac
    append_active_target "$target_name"
    [ -n "${ssh_host:-}" ] && set_dynamic_var "HOST_$target_name" "$ssh_host"
    [ -n "${remote_drop:-}" ] && set_dynamic_var "REMOTE_DIR_$target_name" "$remote_drop"
    set_dynamic_var "SHELL_$target_name" "$shell"
    if [ -z "${scp_flags:-}" ] && [ "$target_name" = "berylax" ]; then
      scp_flags="-O"
    fi
    if [ -n "${scp_flags:-}" ]; then
      printf "%s" "$scp_flags" | $GREP_BIN -Eq "^[A-Za-z0-9_ .:=,/@+-]*$" || { log "FAIL target_registry invalid_scp_flags target=$target_name"; return 1; }
    fi
    [ -n "${scp_flags:-}" ] && set_dynamic_var "SCP_FLAGS_$target_name" "$scp_flags"
  done
  return 0
}

registry_summary(){'''
    text = regex_once(
        text,
        r'load_target_registry\(\)\{\n.*?\n\}\n\nregistry_summary\(\)\{',
        new_registry,
        "load_target_registry",
    )

    text = replace_once(
        text,
        '      scp_flags=\n      . "$cf"\n      t_l=$(lower_name "${target_name:-}")\n'
        '      [ -z "${scp_flags:-}" ] && [ "$t_l" = "berylax" ] && scp_flags="-O"\n'
        '      printf "%s enabled=%s host=%s remote_drop=%s scp_flags=%s\\n" "$target_name" "${enabled:-1}" "${ssh_host:-}" "${remote_drop:-}" "${scp_flags:-}"\n',
        '      shell=\n      scp_flags=\n      . "$cf"\n      t_l=$(lower_name "${target_name:-}")\n'
        '      [ -z "${scp_flags:-}" ] && [ "$t_l" = "berylax" ] && scp_flags="-O"\n'
        '      printf "%s enabled=%s host=%s remote_drop=%s shell=%s scp_flags=%s verify_owner=dispatcher external_verify_wrapper=no\\n" "$target_name" "${enabled:-1}" "${ssh_host:-}" "${remote_drop:-}" "${shell:-missing}" "${scp_flags:-}"\n',
        "registry summary",
    )

    migration = r'''
verify_owner_strip_quotes(){
  printf "%s" "$1" | $SED_BIN "s/^[\"']*//;s/[\"']*$//"
}

verify_owner_resolve_shell(){
  cf="$1"
  target_name=
  platform=
  shell=
  shell_kind=
  . "$cf"
  resolved="${shell:-${shell_kind:-}}"
  case "$resolved" in sh|bash) printf "%s" "$resolved"; return 0;; esac
  t=$(lower_name "$(verify_owner_strip_quotes "${target_name:-}")")
  p=$(lower_name "$(verify_owner_strip_quotes "${platform:-}")")
  case "$t:$p" in
    berylax:*|*:openwrt|*:busybox|*:ash) printf "sh" ;;
    *) printf "bash" ;;
  esac
}

write_verify_owner_marker(){
  tmp="$VERIFY_OWNER_FILE.tmp.$$"
  {
    echo "verify_owner=dispatcher"
    echo "external_verify_wrapper=no"
    echo "remote_sha_required=yes"
    echo "bash_missing_fallback=fail_closed"
    echo "python_delivery=unsupported"
    echo "policy=$VERIFY_OWNER_POLICY"
  } > "$tmp" || return 1
  $CHMOD_BIN 600 "$tmp" >/dev/null 2>&1 || true
  $MV_BIN -f "$tmp" "$VERIFY_OWNER_FILE" >/dev/null 2>&1 || return 1
}

migrate_verify_owner_runtime(){
  $MKDIR_BIN -p "$STATE_DIR/backups" "$TARGETS_DIR" >/dev/null 2>&1 || return 1
  ts=$($DATE_BIN +%Y%m%d-%H%M%S 2>/dev/null || echo now)
  backup_dir="$STATE_DIR/backups/verify-owner-$ts"
  changed=0
  for cf in "$TARGETS_DIR"/*.conf; do
    [ -f "$cf" ] || continue
    shell_value=$(verify_owner_resolve_shell "$cf") || return 1
    case "$shell_value" in sh|bash) ;; *) log "FAIL verify_owner_migration unresolved_shell file=$cf"; return 1;; esac
    needs_change=0
    $GREP_BIN -Eq "^(verify|verify_cmd|verify_kind|shell_kind)=" "$cf" 2>/dev/null && needs_change=1
    $GREP_BIN -Eq "^shell=(\"?)(sh|bash)(\"?)$" "$cf" 2>/dev/null || needs_change=1
    [ "$needs_change" = "1" ] || continue
    [ "$changed" = "1" ] || { $MKDIR_BIN -p "$backup_dir" >/dev/null 2>&1 || return 1; changed=1; }
    bn=$($BASENAME_BIN "$cf")
    $CP_BIN -f "$cf" "$backup_dir/$bn" >/dev/null 2>&1 || return 1
    tmp="$cf.verify-owner.$$"
    $GREP_BIN -v -E "^(verify|verify_cmd|verify_kind|shell_kind|shell)=" "$cf" > "$tmp" 2>/dev/null || true
    printf "shell=\"%s\"\n" "$shell_value" >> "$tmp"
    $CHMOD_BIN 600 "$tmp" >/dev/null 2>&1 || true
    $MV_BIN -f "$tmp" "$cf" >/dev/null 2>&1 || return 1
    log "MIGRATE verify_owner target_config=$bn shell=$shell_value backup=$backup_dir/$bn"
  done
  for cf in "$TARGETS_DIR"/*.conf; do
    [ -f "$cf" ] || continue
    $GREP_BIN -Eq "^(verify|verify_cmd|verify_kind|shell_kind)=" "$cf" 2>/dev/null && { log "FAIL verify_owner_migration legacy_key_remaining file=$cf"; return 1; }
    $GREP_BIN -Eq "^shell=(\"?)(sh|bash)(\"?)$" "$cf" 2>/dev/null || { log "FAIL verify_owner_migration shell_missing file=$cf"; return 1; }
  done
  write_verify_owner_marker || return 1
  log "PASS verify_owner_migration changed=$changed marker=$VERIFY_OWNER_FILE policy=$VERIFY_OWNER_POLICY"
  return 0
}

'''
    text = replace_once(text, "import_bundle_if_needed(){\n", migration + "import_bundle_if_needed(){\n", "migration insertion")

    text = replace_once(
        text,
        '  [ -f "$RUNTIME_SSH_CONFIG" ] && $CHMOD_BIN 600 "$RUNTIME_SSH_CONFIG" >/dev/null 2>&1 || true\n\n  module_ver=""\n',
        '  [ -f "$RUNTIME_SSH_CONFIG" ] && $CHMOD_BIN 600 "$RUNTIME_SSH_CONFIG" >/dev/null 2>&1 || true\n\n  migrate_verify_owner_runtime || return 1\n\n  module_ver=""\n',
        "migration call",
    )

    text = replace_once(
        text,
        'target_shell(){ eval "v=\\"\\${SHELL_$1:-bash}\\""; printf \'%s\' "$v"; }\ntarget_verify(){ eval "v=\\"\\${VERIFY_$1:-}\\""; printf \'%s\' "$v"; }\ntarget_scp_flags(){ eval "v=\\"\\${SCP_FLAGS_$1:-}\\""; printf \'%s\' "$v"; }\n',
        'target_shell(){ eval "v=\\"\\${SHELL_$1:-}\\""; printf \'%s\' "$v"; }\ntarget_scp_flags(){ eval "v=\\"\\${SCP_FLAGS_$1:-}\\""; printf \'%s\' "$v"; }\n',
        "target verifier removal",
    )

    new_remote_verify = r'''remote_verify_script(){
  target="$1"; host="$2"; dst="$3"; qdst=$(sq "$dst")
  shell=$(target_shell "$target")
  case "$shell" in
    sh)
      "$SSH_BIN" -F "$RUNTIME_SSH_CONFIG" -o BatchMode=yes -o ConnectTimeout=12 "$host" "sh -c 'command -v sh >/dev/null 2>&1 && sh -n $qdst'" >/dev/null 2>&1
      ;;
    bash)
      "$SSH_BIN" -F "$RUNTIME_SSH_CONFIG" -o BatchMode=yes -o ConnectTimeout=12 "$host" "sh -c 'command -v bash >/dev/null 2>&1 && bash -n $qdst'" >/dev/null 2>&1
      ;;
    *)
      log "FAIL remote_verify invalid_shell target=$target shell=$shell verify_owner=dispatcher external_verify_wrapper=no"
      return 1
      ;;
  esac
}

# v4.12.6'''
    text = regex_once(text, r'remote_verify_script\(\)\{\n.*?\n\}\n\n# v4\.12\.6', new_remote_verify, "remote_verify_script")

    strict_sha = r'''
file_sha256_strict(){
  file="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" 2>/dev/null
  elif [ -x /data/data/com.termux/files/usr/bin/sha256sum ]; then
    /data/data/com.termux/files/usr/bin/sha256sum "$file" 2>/dev/null
  else
    return 1
  fi | while read -r h rest; do
    printf "%s" "$h"
  done | $GREP_BIN -E "^[0-9a-f]{64}$" | $TAIL_BIN -n 1
}

verify_remote_sha_match(){
  file="$1"; target="$2"; host="$3"; dst="$4"; base="$5"; verify_mode="$6"
  local_sha=$(file_sha256_strict "$file" 2>/dev/null || true)
  remote_sha=$(remote_sha256 "$host" "$dst" 2>/dev/null || true)
  [ -n "$local_sha" ] || { log "FAIL remote_sha local_sha_unavailable file=$base target=$target host=$host"; return 1; }
  [ "$remote_sha" = "$local_sha" ] || { log "FAIL remote_sha mismatch file=$base target=$target host=$host local_sha256=$local_sha remote_sha256=${remote_sha:-missing}"; return 1; }
  log "PASS verification file=$base target=$target host=$host verify_owner=dispatcher verify_mode=$verify_mode external_verify_wrapper=no remote_sha_match=yes local_sha256=$local_sha remote_sha256=$remote_sha host_run=no"
  return 0
}

'''
    text = replace_once(text, "breakglass_evidence(){\n", strict_sha + "breakglass_evidence(){\n", "strict sha helpers")

    text = replace_once(
        text,
        '    quarantined "$rec" "$t" local_preflight || quarantined "$rec" "$t" verify || quarantined "$rec" "$t" canonical_collision || all_quar=0\n',
        '    quarantined "$rec" "$t" local_preflight || quarantined "$rec" "$t" verify || quarantined "$rec" "$t" remote_sha || quarantined "$rec" "$t" canonical_collision || all_quar=0\n',
        "fully done remote sha quarantine",
    )

    text = replace_once(
        text,
        '    quarantined "$rec" "$t" local_preflight && continue\n    quarantined "$rec" "$t" verify && continue\n    inflight "$rec" "$t" && continue\n',
        '    quarantined "$rec" "$t" local_preflight && continue\n    quarantined "$rec" "$t" verify && continue\n    quarantined "$rec" "$t" remote_sha && continue\n    inflight "$rec" "$t" && continue\n',
        "process skip remote sha quarantine",
    )

    normal_sha = r'''    verify_mode=basic
    if is_shell "$base"; then
      verify_mode="$(target_shell "$t")-n"
    fi
    if ! verify_remote_sha_match "$file" "$t" "$host" "$dst" "$base" "$verify_mode"; then
      notify_delivery FAIL "$t" "$base" remote_sha
      add_quarantine "$rec" "$t" remote_sha
      clear_inflight "$rec" "$t"
      continue
    fi

    record_done "$rec" "$t"'''
    text = replace_once(text, '    record_done "$rec" "$t"', normal_sha, "normal path sha gate")

    owner_status = r'''  echo "== verification ownership =="
  echo "verify_owner=dispatcher"
  echo "external_verify_wrapper=no"
  echo "remote_sha_required=yes"
  echo "bash_missing_fallback=fail_closed"
  echo "python_delivery=unsupported"
  echo "verification_owner_marker=$VERIFY_OWNER_FILE"
  if [ -f "$VERIFY_OWNER_FILE" ]; then
    echo "verification_owner_marker_exists=yes"
    $CAT_BIN "$VERIFY_OWNER_FILE" 2>/dev/null || true
  else
    echo "verification_owner_marker_exists=no"
  fi
'''
    text = replace_once(
        text,
        '  $GREP_BIN -E "^(version=|versionCode=)" "$MODDIR/module.prop" 2>/dev/null || true\n  registry_summary\n',
        '  $GREP_BIN -E "^(version=|versionCode=)" "$MODDIR/module.prop" 2>/dev/null || true\n' + owner_status + '  registry_summary\n',
        "runtime owner status",
    )

    if "target_verify(){" in text or "else sh -n" in text:
        raise TransformError("legacy verify path remains")
    process_start = text.index("process_file(){")
    process_end = text.index("\nqueue_candidate(){", process_start)
    process = text[process_start:process_end]
    if process.index("verify_remote_sha_match") > process.index('record_done "$rec" "$t"'):
        raise TransformError("normal path SHA gate occurs after record_done")
    return text


def patch_module_prop(text: str) -> str:
    text = re.sub(r"^version=.*$", f"version={VERSION}", text, count=1, flags=re.M)
    text = re.sub(r"^versionCode=.*$", f"versionCode={VERSION_CODE}", text, count=1, flags=re.M)
    text = re.sub(
        r"^description=.*$",
        "description=Android/Magisk SSH file-drop dispatcher with dispatcher-owned remote syntax verification, strict shell profiles, fail-closed Bash handling, normal-path SHA-256 parity, WebUI controls, ntfy notifications, delivery safety, break-glass SCP and Sortify marker contract",
        text,
        count=1,
        flags=re.M,
    )
    return text


def patch_customize(text: str) -> str:
    text = re.sub(r'ui_print "SSH Drop Dispatcher [^"]+"', f'ui_print "SSH Drop Dispatcher {VERSION}"', text, count=1)
    return text.replace(
        "Delivery safety target checks + break-glass SCP + delivery status/wait + ntfy notifications + space-probe retry + Sortify marker contract: final + WebUI ntfy settings final + duplicate-alias guard final + low-latency target-only watchdog final",
        "Dispatcher-owned remote syntax verification + strict shell profiles + fail-closed Bash + normal-path SHA-256 parity + delivery safety + break-glass SCP + ntfy + Sortify marker contract",
    )


def patch_pidd_config(text: str) -> str:
    new_lint = r'''lint_targets(){
  rc=0
  [ -d "$TARGETS_DIR" ] || { echo "WARN missing targets_dir=$TARGETS_DIR"; return 0; }
  seen=" "
  for cf in "$TARGETS_DIR"/*.conf; do
    [ -f "$cf" ] || continue
    if grep -Eq '^(verify|verify_cmd|verify_kind|shell_kind)=' "$cf" 2>/dev/null; then
      echo "FAIL legacy_verify_or_shell_key file=$cf verify_owner=dispatcher external_verify_wrapper=no"
      rc=1
    fi
    target_name= enabled=1 ssh_host= remote_drop= shell=
    . "$cf"
    t=$(lower_name "$target_name")
    case "$t" in
      "") echo "FAIL missing target_name file=$cf"; rc=1; continue ;;
      *[!a-z0-9_]*) echo "FAIL invalid target_name file=$cf value=$target_name"; rc=1; continue ;;
    esac
    case "$seen" in *" $t "*) echo "FAIL duplicate target=$t file=$cf"; rc=1;; *) seen="$seen$t ";; esac
    [ "$enabled" = "0" ] || [ "$enabled" = "1" ] || { echo "FAIL invalid enabled target=$t value=$enabled"; rc=1; }
    [ -n "$ssh_host" ] || { echo "FAIL missing ssh_host target=$t"; rc=1; }
    [ -n "$remote_drop" ] || { echo "FAIL missing remote_drop target=$t"; rc=1; }
    case "$shell" in bash|sh) ;; "") echo "FAIL missing explicit shell target=$t"; rc=1;; *) echo "FAIL invalid shell target=$t value=$shell"; rc=1;; esac
  done
  [ "$rc" = "0" ] && echo "lint=ok verify_owner=dispatcher external_verify_wrapper=no"
  return "$rc"
}'''
    return regex_once(text, r'lint_targets\(\)\{\n.*?\n\}\n\nmarker_targets_for\(\)', new_lint + "\n\nmarker_targets_for()", "pidd-config lint")


def run_checks() -> None:
    for cmd in (
        ["sh", "-n", str(SERVICE)],
        ["sh", "-n", str(CUSTOMIZE)],
        ["sh", "-n", str(PIDD_CONFIG)],
    ):
        subprocess.run(cmd, cwd=ROOT, check=True)

    service = SERVICE.read_text(encoding="utf-8")
    required = (
        "VERIFY_OWNER_POLICY=" + POLICY,
        "verify_owner=dispatcher",
        "external_verify_wrapper=no",
        "remote_sha_required=yes",
        "bash_missing_fallback=fail_closed",
        "python_delivery=unsupported",
        'verify_remote_sha_match "$file" "$t" "$host" "$dst"',
        'scp_flags="-O"',
    )
    for token in required:
        if token not in service:
            raise TransformError(f"missing required token: {token}")
    if "target_verify(){" in service or "else sh -n" in service:
        raise TransformError("legacy verify path remains")

    process = service[service.index("process_file(){") : service.index("\nqueue_candidate(){")]
    if process.index("verify_remote_sha_match") > process.index('record_done "$rec" "$t"'):
        raise TransformError("process_file SHA check is not before record_done")


def build_zip() -> None:
    DIST.parent.mkdir(parents=True, exist_ok=True)
    if DIST.exists():
        DIST.unlink()
    source = ROOT / "source/magisk"
    with zipfile.ZipFile(DIST, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as zf:
        for path in sorted(source.rglob("*")):
            if path.is_file():
                zf.write(path, path.relative_to(source).as_posix())


def main() -> int:
    SERVICE.write_text(patch_service(SERVICE.read_text(encoding="utf-8")), encoding="utf-8", newline="\n")
    MODULE_PROP.write_text(patch_module_prop(MODULE_PROP.read_text(encoding="utf-8")), encoding="utf-8", newline="\n")
    CUSTOMIZE.write_text(patch_customize(CUSTOMIZE.read_text(encoding="utf-8")), encoding="utf-8", newline="\n")
    PIDD_CONFIG.write_text(patch_pidd_config(PIDD_CONFIG.read_text(encoding="utf-8")), encoding="utf-8", newline="\n")
    run_checks()
    build_zip()
    print(f"RESULT: SDD_VNEXT_DISPATCHER_VERIFY_OWNER_FIXTURES_PASS version={VERSION}")
    print(f"artifact={DIST.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"RESULT: SDD_VNEXT_DISPATCHER_VERIFY_OWNER_FIXTURES_FAIL error={exc}", file=sys.stderr)
        raise
