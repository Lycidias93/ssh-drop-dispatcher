#!/data/data/com.termux/files/usr/bin/bash
# CG_HANDOFF_V1_START
# cg_handoff_lane=sdd-v4145-stage
# cg_handoff_scope=pixel-dispatcher
# cg_handoff_host=pixel
# cg_handoff_route_class=none
# cg_handoff_secret_class=possible
# cg_handoff_run_mode=run
# cg_handoff_expected_marker=RESULT: SDD_V4145_STAGE_PASS
# CG_HANDOFF_V1_END
set -Eeuo pipefail
P=/data/data/com.termux/files/usr
export PATH="$P/bin:/system/bin:/vendor/bin:/product/bin"
M=/data/adb/modules/ssh_drop_dispatcher
U=/data/adb/modules_update/ssh_drop_dispatcher
S=/data/adb/ssh-drop-dispatcher
BASE=ssh-drop-dispatcher-magisk-v4.14.4-strict-scan-v1-candidate.zip
ZIP=ssh-drop-dispatcher-magisk-v4.14.5-batched-inventory-v1-candidate.zip
OLD_ZIP=8107e07359cbb2d1513828a9ae2665bb700213bedd75223e071027882be0b575
NEW_ZIP=204950c064b7c07a1970868fd1e0d0113831f747630a1f97bea5b72df250143a
OLD_SH=db5cddbed700d41b55245dbe282a08375e3c83e4e50fb4b08875d17459a1f563
OLD_PROP=3e53a04e99e2c85dfc871291a340555122c99c42dd6e38b0d880e33127209aa1
NEW_SH=db5cddbed700d41b55245dbe282a08375e3c83e4e50fb4b08875d17459a1f563
NEW_PROP=41945f16065fc356498c22c5ffe2b3afacfcf02c8de168f0f8db4f9aef65842b
OLD_ADAPTER=0b2798be374862fc079bed4bfd336f6e5863f868fd988cf0fd3725f27e02aed3
NEW_ADAPTER=3f11557c981cfe8617c70190c3d3c153c8dcd0fa77da20982df1ad25e2d98e4b
MAGISK=/debug_ramdisk/magisk
LOCK=$S/backups/v4145-stage.lock
backup=
attempted=0
success=0
own_lock=0
fail(){ printf 'RESULT: SDD_V4145_STAGE_STOP reason=%s\n' "$1" >&2; exit 65; }
hash(){ sha256sum "$1" | awk '{print $1;exit}'; }
same(){ [[ -f "$1" && ! -L "$1" && "$(hash "$1")" == "$2" ]]; }
absent(){ [[ ! -e "$1" && ! -L "$1" ]]; }
declare -a bridges=("$S/bin/sdd" "$S/bin/dispatch-config" "$P/bin/sdd" "$P/bin/dispatch-config")
declare -a bridge_hashes=(d5be756748bf1559fd8508ef24e92fcbdc2236cda525a7da5f3ca7064d7da574 2fdf77d110eb10a91b160b81ca7dc306f85c42d9e76387248b1ecdf0cae55638 e082bd31026d8867ddcae4f47d998eed1ff45b44a4ac3a8c182baf0a8603e418 19f9a513ed4f92cde554be842b43a166fd78fa32c71460edbce4007b6207dafa)
check_tree(){
  local dir=$1 zip=$2 n h count=0
  [[ -d "$dir" && ! -L "$dir" ]] || return 1
  while IFS= read -r n; do
    [[ "$n" == customize.sh ]] && continue
    [[ "$n" =~ ^[A-Za-z0-9_./-]+$ && "$n" != /* && "$n" != *..* ]] || return 1
    h="$(unzip -p "$zip" "$n" | sha256sum | awk '{print $1}')" || return 1
    same "$dir/$n" "$h" || return 1
    count=$((count+1))
  done < <(unzip -Z1 "$zip")
  [[ "$count" == 41 ]]
}
check_runtime(){
  local i f n=0
  for i in "${!bridges[@]}"; do
    same "${bridges[$i]}" "${bridge_hashes[$i]}" || return 1
    [[ "$(stat -c '%a %u %g' "${bridges[$i]}")" == "755 0 0" ]] || return 1
  done
  for f in "$M"/tools/*.sh; do
    same "$S/tools/${f##*/}" "$(hash "$f")" || return 1
    [[ "$(stat -c '%a %u %g' "$S/tools/${f##*/}")" == "755 0 0" ]] || return 1
    n=$((n+1))
  done
  [[ "$n" == 17 ]]
}
preflight(){
  local d=$1 battery level
  [[ "$(id -u)" == 0 && "$(getprop ro.product.device)" == mustang && "$(getprop sys.boot_completed)" == 1 ]] || fail identity
  battery="$(/system/bin/dumpsys battery)"
  level="$(printf '%s\n' "$battery" | awk '$1=="level:"{print $2;exit}')"
  printf 'PIXEL_MODULE_INSTALL_MIN_BATTERY_PERCENT=5 battery_level=%s\n' "$level"
  printf '%s\n' "$battery" | grep -E 'powered:'
  [[ "$level" =~ ^[0-9]+$ ]] && ((level>=5)) || fail battery
  [[ -x "$MAGISK" ]] || fail magisk_missing
  same "$d/$BASE" "$OLD_ZIP" && same "$d/$ZIP" "$NEW_ZIP" || fail package_hash
  unzip -t "$d/$BASE" >/dev/null && unzip -t "$d/$ZIP" >/dev/null || fail package_integrity
  same "$M/service.sh" "$OLD_SH" && same "$M/module.prop" "$OLD_PROP" && same "$M/bin/module-control-base" "$OLD_ADAPTER" || fail baseline
  absent "$M/update" && absent "$M/remove" && absent "$M/disable" && absent "$U" || fail pending_module_change
  check_tree "$M" "$d/$BASE" || fail live_tree
  check_runtime || fail runtime_bridge_or_tools
  [[ ! -s "$S/dispatch.inflight" ]] && absent "$S/scan.lock" && absent "$S/.followup.worker.lock" || fail dispatch_busy
  grep -qx 'status=OK' "$S/health.env" || fail dispatcher_health
  grep -qx 'DROP_DISPATCH_ENABLED=1' "$S/config.env" || fail enabled_state
  echo 'RESULT: SDD_V4145_PREFLIGHT_PASS'
}
save_backup(){
  local d=$1 i
  umask 077
  backup="$(mktemp -d "$S/backups/v4145-stage-XXXXXXXX")"
  chmod 700 "$backup"
  cp -a "$M" "$backup/module.live"
  cp "$d/$BASE" "$backup/$BASE"
  cp -a "$S/tools" "$backup/tools"
  mkdir "$backup/bridges"
  for i in "${!bridges[@]}"; do
    cp -a "${bridges[$i]}" "$backup/bridges/$i"
    same "$backup/bridges/$i" "${bridge_hashes[$i]}" || fail bridge_backup
  done
  check_tree "$backup/module.live" "$backup/$BASE" || fail module_backup
  same "$backup/$BASE" "$OLD_ZIP" || fail rollback_zip
  for f in "$M"/tools/*.sh; do same "$backup/tools/${f##*/}" "$(hash "$f")" || fail tools_backup; done
  cat /proc/sys/kernel/random/boot_id >"$backup/boot_id"
  hash "$S/config.env" >"$backup/config.sha256"
  printf '%s\n' "$NEW_ZIP" >"$backup/candidate.sha256"
  printf 'rollback_dir=%s\n' "$backup"
}
restore_file(){
  local src=$1 dst=$2 expected=$3 tmp ctx
  same "$src" "$expected" || return 1
  if same "$dst" "$expected"; then return 0; fi
  [[ -f "$dst" && ! -L "$dst" ]] || return 1
  ctx="$(ls -Zd "$dst" | awk '{print $1}')"
  tmp="$(mktemp "$dst.v4145-restore.XXXXXX")" || return 1
  cp -a "$src" "$tmp" && /system/bin/chcon "$ctx" "$tmp" && mv -fT "$tmp" "$dst" && same "$dst" "$expected"
}
undo_stage(){
  local i f
  # Do not touch queue, SSH, trust, or the running service.
  same "$M/service.sh" "$OLD_SH" && same "$M/bin/module-control-base" "$OLD_ADAPTER" || return 1
  if ! absent "$U"; then
    [[ -d "$U" && ! -L "$U" ]] || return 1
    mv "$U" "$backup/failed-stage" || return 1
  fi
  if ! absent "$M/update"; then
    [[ -f "$M/update" && ! -L "$M/update" ]] || return 1
    mv "$M/update" "$backup/failed-update-marker" || return 1
  fi
  same "$M/module.prop" "$OLD_PROP" || same "$M/module.prop" "$NEW_PROP" || return 1
  restore_file "$backup/module.live/module.prop" "$M/module.prop" "$OLD_PROP" || return 1
  for i in "${!bridges[@]}"; do
    restore_file "$backup/bridges/$i" "${bridges[$i]}" "${bridge_hashes[$i]}" || return 1
  done
  for f in "$backup"/tools/*.sh; do
    restore_file "$f" "$S/tools/${f##*/}" "$(hash "$f")" || return 1
  done
  check_tree "$M" "$backup/$BASE" && check_runtime && absent "$U" && absent "$M/update"
}
on_exit(){
  local rc=$?
  trap - EXIT
  if ((attempted && !success)); then
    if undo_stage; then echo 'RESULT: SDD_V4145_STAGE_ROLLBACK_PASS'; else echo 'RESULT: SDD_V4145_STAGE_ROLLBACK_STOP' >&2; fi
  fi
  if ((own_lock)); then rmdir "$LOCK" 2>/dev/null || true; fi
  exit "$rc"
}
case "${1:-}" in
  --root-verify) preflight "$2";;
  --root)
    d=$2
    preflight "$d"
    mkdir "$LOCK" || fail concurrent_stage
    own_lock=1
    trap on_exit EXIT
    save_backup "$d"
    preflight "$d"
    attempted=1
    "$MAGISK" --install-module "$d/$ZIP" >"$backup/magisk-install.log" 2>&1 || fail magisk_stage
    check_tree "$U" "$d/$ZIP" || fail staged_tree
    same "$U/service.sh" "$NEW_SH" && same "$U/module.prop" "$NEW_PROP" && same "$U/bin/module-control-base" "$NEW_ADAPTER" || fail staged_identity
    same "$M/service.sh" "$OLD_SH" && same "$M/bin/module-control-base" "$OLD_ADAPTER" || fail unexpected_live_cutover
    same "$M/module.prop" "$OLD_PROP" || same "$M/module.prop" "$NEW_PROP" || fail live_metadata
    [[ -f "$M/update" && ! -L "$M/update" ]] || fail missing_update_marker
    check_runtime || fail runtime_drift
    [[ "$(hash "$S/config.env")" == "$(cat "$backup/config.sha256")" ]] || fail configuration_drift
    printf 'staged_version=4.14.5-batched-inventory-v1\nreboot_required=yes\n' >"$backup/READY"
    success=1
    echo 'RESULT: SDD_V4145_STAGE_PASS'
    ;;
  ''|--verify)
    [[ "$(id -u)" == 10544 && "$(getprop ro.product.device)" == mustang ]] || fail termux_identity
    d="$(realpath "${CG_RUN_FILE_SOURCE_DIR:-${0%/*}}")"; self="$(realpath "$0")"
    [[ "$d" =~ ^[A-Za-z0-9_./-]+$ && "$self" =~ ^[A-Za-z0-9_./-]+$ ]] || fail unsafe_path
    mode=--root; [[ "${1:-}" == --verify ]] && mode=--root-verify
    exec "$P/bin/su" -c "$P/bin/bash $self $mode $d"
    ;;
  *) fail mode;;
esac
