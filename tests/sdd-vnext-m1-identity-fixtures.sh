#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
HELPER="$ROOT/source/magisk/tools/sdd-identity.sh"

fail(){
  printf "FAIL: %s\n" "$*" >&2
  exit 1
}

pass(){
  printf "PASS: %s\n" "$*"
}

[[ -f "$HELPER" ]] || fail "helper missing"
bash -n "$HELPER" || fail "helper syntax"

TMP_FIXTURE=$(mktemp -d)
trap 'rm -rf "$TMP_FIXTURE"' EXIT
export TMPDIR="$TMP_FIXTURE"
export SDD_IDENTITY_SORT_BIN
SDD_IDENTITY_SORT_BIN=$(command -v sort)

source "$HELPER"

sha_a=$(printf a%.0s {1..64})
sha_b=$(printf b%.0s {1..64})

exact="target-pi3__release-20260720.zip"
[[ "$(sdd_identity_semantic_name "$exact")" == "$exact" ]] || fail "date suffix collapsed"
[[ "$(sdd_identity_alias_kind "$exact")" == exact ]] || fail "date suffix alias kind"
pass "intentional date suffix preserved"

alias="target-pi3__release (1).zip"
[[ "$(sdd_identity_semantic_name "$alias")" == "target-pi3__release.zip" ]] || fail "parenthesized alias"
[[ "$(sdd_identity_alias_kind "$alias")" == browser_parenthesized ]] || fail "parenthesized kind"
pass "parenthesized browser alias recognized"

dash="target-pi3__release-1.zip"
[[ "$(sdd_identity_semantic_name "$dash")" == "$dash" ]] || fail "dash alias enabled by default"
SDD_IDENTITY_DASH_ALIAS=1
[[ "$(sdd_identity_semantic_name "$dash")" == "target-pi3__release.zip" ]] || fail "dash alias opt-in"
SDD_IDENTITY_DASH_ALIAS=0
pass "dash alias is explicit opt-in"

targets=$(sdd_identity_normalize_targets pi4 pi3 pi4)
[[ "$targets" == "pi3,pi4" ]] || fail "target normalization: $targets"
pass "target set normalized and deduplicated"

key_exact=$(sdd_identity_key "target-pi3__release.zip" "$sha_a" "pi3" v4115)
key_alias=$(sdd_identity_key "$(sdd_identity_semantic_name "$alias")" "$sha_a" "pi3" v4115)
[[ "$key_exact" == "$key_alias" ]] || fail "exact/alias identity mismatch"
pass "exact and alias share identity when semantic name, SHA and targets match"

key_sha_conflict=$(sdd_identity_key "target-pi3__release.zip" "$sha_b" "pi3" v4115)
[[ "$key_sha_conflict" != "$key_exact" ]] || fail "SHA conflict not distinguished"
pass "changed SHA creates distinct identity"

key_target_conflict=$(sdd_identity_key "target-pi3__release.zip" "$sha_a" "pi3,pi4" v4115)
[[ "$key_target_conflict" != "$key_exact" ]] || fail "target conflict not distinguished"
pass "changed target set creates distinct identity"

if sdd_identity_key "bad|name.zip" "$sha_a" "pi3" v4115 >/dev/null 2>&1; then
  fail "unsafe identity component accepted"
fi
pass "unsafe identity delimiter rejected"

description=$(sdd_identity_describe "$alias" "$sha_a" pi4 pi3 pi4)
printf "%s\n" "$description" | grep -Fqx "identity_version=2" || fail "identity version"
printf "%s\n" "$description" | grep -Fqx "semantic_name=target-pi3__release.zip" || fail "semantic output"
printf "%s\n" "$description" | grep -Fqx "alias_kind=browser_parenthesized" || fail "alias output"
printf "%s\n" "$description" | grep -Fqx "targets=pi3,pi4" || fail "targets output"
printf "%s\n" "$description" | grep -Fq "identity_key=v2|semantic=target-pi3__release.zip|sha256=$sha_a|targets=pi3,pi4|policy=v4115" || fail "identity key output"
pass "machine-readable identity description"

printf "host_run=no\n"
printf "dns_ha_vip_route_change=no\n"
printf "RESULT: SDD_VNEXT_M1_IDENTITY_HELPER_FIXTURES_PASS\n"
