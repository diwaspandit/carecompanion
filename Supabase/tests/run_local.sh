#!/usr/bin/env bash
# Applies migrations to a throwaway local Postgres and runs the RLS contract test.
# Requires Homebrew postgresql (initdb, pg_ctl, psql). Touches nothing remote.
set -euo pipefail
export LC_ALL=${LC_ALL:-en_US.UTF-8}

root=$(cd "$(dirname "$0")/../.." && pwd)
data=$(mktemp -d)
port=${PGPORT_TEST:-55432}
trap 'pg_ctl -D "$data" -m immediate stop >/dev/null 2>&1 || true; rm -rf "$data"' EXIT

initdb -D "$data" -U postgres --auth=trust >/dev/null
pg_ctl -D "$data" -o "-p $port -k $data" -l "$data/log" -w start >/dev/null

run() { psql -h "$data" -p "$port" -U postgres -d postgres -v ON_ERROR_STOP=1 -q "$@"; }

run -f "$root/Supabase/tests/local_stub.sql"
for migration in "$root"/Supabase/migrations/*.sql; do
  run -f "$migration"
done
run -f "$root/Supabase/tests/rls_test.sql"
run -f "$root/Supabase/tests/senior_link_test.sql"
