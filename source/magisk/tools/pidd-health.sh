#!/system/bin/sh
set -u
STATE_DIR=${PIDD_STATE_DIR:-/data/adb/ssh-drop-dispatcher}
HEALTH_FILE=$STATE_DIR/health.env
echo "== pidd health =="
[ -f "$HEALTH_FILE" ] || { echo "missing health.env"; exit 1; }
sed -n "1,160p" "$HEALTH_FILE"
