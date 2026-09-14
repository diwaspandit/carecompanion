#!/usr/bin/env bash
# End-to-end check against the LIVE project using only the publishable key and real user
# sessions (no service_role). Proves shared-account flow and cross-account denial.
#
# Requires three confirmed email/password test users (Dashboard → Authentication → Add user,
# "Auto Confirm User"): Diwas (family), Maya (senior), Outsider.
#
# Usage:
#   SUPABASE_HOST=xxxx.supabase.co SUPABASE_ANON_KEY=sb_publishable_... \
#   DIWAS_EMAIL=... MAYA_EMAIL=... OUTSIDER_EMAIL=... TEST_PASSWORD=... \
#   Supabase/tests/live_smoke.sh
set -euo pipefail

: "${SUPABASE_HOST:?}" "${SUPABASE_ANON_KEY:?}" "${DIWAS_EMAIL:?}" "${MAYA_EMAIL:?}" "${OUTSIDER_EMAIL:?}" "${TEST_PASSWORD:?}"
base="https://$SUPABASE_HOST"
fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

token_for() {
  curl -sS -f "$base/auth/v1/token?grant_type=password" \
    -H "apikey: $SUPABASE_ANON_KEY" -H "Content-Type: application/json" \
    -d "$(jq -n --arg e "$1" --arg p "$TEST_PASSWORD" '{email:$e,password:$p}')" | jq -r .access_token
}

api() { # api TOKEN METHOD PATH [JSON]
  local token=$1 method=$2 path=$3 body=${4:-}
  curl -sS -X "$method" "$base/rest/v1/$path" \
    -H "apikey: $SUPABASE_ANON_KEY" -H "Authorization: Bearer $token" \
    -H "Content-Type: application/json" -H "Prefer: return=representation" \
    ${body:+-d "$body"}
}

diwas=$(token_for "$DIWAS_EMAIL"); maya=$(token_for "$MAYA_EMAIL"); outsider=$(token_for "$OUTSIDER_EMAIL")
[[ $diwas != null && $maya != null && $outsider != null ]] || fail "could not sign in all test users"
pass "three test users signed in"

run_id=$(date +%s)
account=$(api "$diwas" POST "rpc/create_care_account" "{\"account_name\":\"Smoke Sharma $run_id\",\"member_role\":\"family\"}")
account_id=$(jq -r .id <<<"$account"); code=$(jq -r .invite_code <<<"$account")
[[ $account_id =~ ^[0-9a-f-]{36}$ ]] || fail "create_care_account: $account"
pass "Diwas created account $account_id"

senior_id=$(api "$diwas" POST account_seniors \
  "{\"account_id\":\"$account_id\",\"name\":\"Maya Sharma\",\"age\":74,\"city\":\"Kathmandu, Nepal\",\"time_zone_identifier\":\"Asia/Kathmandu\"}" | jq -r '.[0].id')
[[ $senior_id =~ ^[0-9a-f-]{36}$ ]] || fail "add senior"
pass "Diwas added Maya as senior"

joined=$(api "$maya" POST "rpc/join_care_account" "{\"code\":\"$code\",\"member_role\":\"senior\"}" | jq -r .id)
[[ $joined == "$account_id" ]] || fail "Maya could not join with invite code"
pass "Maya joined with invite code"

check_in=$(api "$maya" POST check_ins "{\"account_id\":\"$account_id\",\"senior_id\":\"$senior_id\"}" | jq -r '.[0].id')
[[ $check_in =~ ^[0-9a-f-]{36}$ ]] || fail "Maya check-in insert"
pass "Maya checked in"

seen=$(api "$diwas" GET "check_ins?select=id&id=eq.$check_in" | jq length)
[[ $seen == 1 ]] || fail "Diwas cannot see Maya's check-in"
pass "Diwas sees Maya's check-in (shared account)"

leak=$(api "$outsider" GET "check_ins?select=id&account_id=eq.$account_id" | jq length)
[[ $leak == 0 ]] || fail "outsider read $leak Sharma check-ins"
leak=$(api "$outsider" GET "account_seniors?select=id&id=eq.$senior_id" | jq length)
[[ $leak == 0 ]] || fail "outsider read Sharma senior"
pass "outsider reads nothing from the Sharma account"

denied=$(api "$outsider" POST check_ins "{\"account_id\":\"$account_id\",\"senior_id\":\"$senior_id\"}" | jq -r '.code // empty')
[[ $denied == 42501 ]] || fail "outsider write was not rejected by RLS (got '$denied')"
pass "outsider write rejected by RLS (42501)"

anon=$(curl -sS "$base/rest/v1/check_ins?select=id" -H "apikey: $SUPABASE_ANON_KEY" | jq -r 'if type=="array" then length else .code end')
[[ $anon == 0 || $anon == 42501 ]] || fail "anon key read check_ins ($anon)"
pass "anon key reads nothing"

echo "LIVE SMOKE PASSED (account $account_id, invite $code)"
