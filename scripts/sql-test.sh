#!/usr/bin/env bash
# Run SQL migrations + a test file inside a single transaction that is ROLLED BACK,
# so parallel agents can test against the shared local DB without colliding.
#
# Usage:
#   bash scripts/sql-test.sh supabase/migrations/A.sql [B.sql ...] -- supabase/tests/x_test.sql
#   bash scripts/sql-test.sh -- supabase/tests/x_test.sql      # migrations already applied
#   BL_PSQL="psql -h /tmp -p 54322 -U postgres -d postgres" bash scripts/sql-test.sh ...  # no Docker
#
# Prints NOTICE output; exits non-zero on the first error.
set -euo pipefail
cd "$(dirname "$0")/.."

CONTAINER="${BL_DB_CONTAINER:-supabase_db_benin-life}"
migrations=()
tests=()
seen_sep=0
for arg in "$@"; do
  if [[ "$arg" == "--" ]]; then seen_sep=1; continue; fi
  if [[ $seen_sep -eq 0 ]]; then migrations+=("$arg"); else tests+=("$arg"); fi
done

{
  echo "\\set ON_ERROR_STOP on"
  echo "set client_min_messages = notice;"
  echo "begin;"
  for f in "${migrations[@]}"; do echo "-- >>> $f"; cat "$f"; echo; done
  cat supabase/tests/_helpers.sql; echo
  for f in "${tests[@]}"; do echo "-- >>> $f"; cat "$f"; echo; done
  echo "rollback;"
} | if [[ -n "${BL_PSQL:-}" ]]; then
  # Plain Postgres (no Docker), e.g. BL_PSQL="psql -h /tmp -p 54322 -U postgres -d postgres".
  # Load scripts/supabase-stub.sql into that database once first.
  $BL_PSQL -q -v ON_ERROR_STOP=1
else
  MSYS_NO_PATHCONV=1 docker exec -i "$CONTAINER" psql -U postgres -d postgres -q -v ON_ERROR_STOP=1
fi

echo "SQL-TEST OK (rolled back)"
