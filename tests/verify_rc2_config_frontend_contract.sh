#!/usr/bin/env bash
set -euo pipefail

ROOT=${1:-$(cd "$(dirname "$0")/.." && pwd)}
SDD="$ROOT/source/magisk/tools/sdd.sh"
FRONTEND="$ROOT/source/magisk/tools/dispatch-config-v2.sh"
BRIDGE="$ROOT/source/magisk/tools/sdd-termux-install.sh"
SETUP_TARGET="$ROOT/source/magisk/tools/sdd-setup-target.sh"

for f in "$SDD" "$FRONTEND" "$BRIDGE" "$SETUP_TARGET"; do
  /bin/sh -n "$f"
done

grep -F 'CONFIG_TOOL=${SDD_CONFIG_TOOL:-$STATE_DIR/tools/dispatch-config-v2.sh}' "$SDD" >/dev/null
grep -F 'dispatch-config-v2.sh' "$BRIDGE" >/dev/null
grep -F 'dispatch_config_frontend=v2' "$BRIDGE" >/dev/null
grep -F 'install-termux-command|install-termux) install_termux' "$FRONTEND" >/dev/null
! grep -Eq '^verify=' "$SETUP_TARGET"

grep -F 'verify_owner=dispatcher' "$SETUP_TARGET" >/dev/null
grep -F 'external_verify_wrapper=no' "$SETUP_TARGET" >/dev/null

printf '%s\n' 'RESULT: SDD_RC2_CONFIG_FRONTEND_FIXTURES_PASS version=4.13.0-verify-owner-rc2 frontend=v2 bridge=sdd-termux-v2'
