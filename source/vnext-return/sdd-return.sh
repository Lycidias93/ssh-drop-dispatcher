#!/system/bin/sh
set -u

STATE_DIR=${SDD_STATE_DIR:-/data/adb/ssh-drop-dispatcher}
MODDIR=${SDD_MODDIR:-/data/adb/modules/ssh_drop_dispatcher}
FORMAT=${SDD_FORMAT:-env}
HELPER=${SDD_RETURN_HELPER:-$MODDIR/bin/sdd-return-helper-arm64}

[ -x "$HELPER" ] || {
  echo "return=FAIL"
  echo "error_code=RETURN_HELPER_MISSING"
  echo "RESULT: SDD_RETURN_DONE outcome=fail exit_code=69"
  exit 69
}

SDD_STATE_DIR="$STATE_DIR" SDD_MODDIR="$MODDIR" SDD_FORMAT="$FORMAT" "$HELPER" "$@"
