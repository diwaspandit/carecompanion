#!/usr/bin/env bash
# Applies every migration to a throwaway Postgres 17 container (the live project's major
# version) and runs the RLS contract tests. Needs Docker; touches nothing remote.
set -euo pipefail

root=$(cd "$(dirname "$0")/../.." && pwd)
name="carecompanion-rls-$$"

docker run -d --rm --name "$name" -e POSTGRES_PASSWORD=postgres postgres:17 >/dev/null
trap 'docker rm -f "$name" >/dev/null 2>&1 || true' EXIT

# The image's init step runs a socket-only server first; TCP answers once the real server is up.
until docker exec "$name" psql -h 127.0.0.1 -U postgres -tAc 'select 1' >/dev/null 2>&1; do sleep 1; done

run() { docker exec -i "$name" psql -h 127.0.0.1 -U postgres -v ON_ERROR_STOP=1 -q; }

run < "$root/Supabase/tests/local_stub.sql"
for migration in "$root"/Supabase/migrations/*.sql; do
  run < "$migration"
done
run < "$root/Supabase/tests/rls_test.sql"
run < "$root/Supabase/tests/rls_production_test.sql"
