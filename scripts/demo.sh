#!/usr/bin/env bash
# One-command local demo (Mac/Linux). Needs Docker running and Node 20+.
# Starts local Supabase, applies all migrations fresh, writes .env.local, runs the game.
set -euo pipefail
cd "$(dirname "$0")/.."
npm install
EXCLUDE=studio,imgproxy,vector,logflare,supavisor,storage-api,postgres-meta,edge-runtime,mailpit
# Retry once: right after Docker starts, the DB container can report 'not ready'.
npx supabase start -x "$EXCLUDE" || { sleep 20; npx supabase start -x "$EXCLUDE"; }
npx supabase db reset
status="$(npx supabase status -o env)"
api="$(printf '%s\n' "$status" | sed -n 's/^API_URL="\{0,1\}\([^"]*\)"\{0,1\}$/\1/p')"
anon="$(printf '%s\n' "$status" | sed -n 's/^ANON_KEY="\{0,1\}\([^"]*\)"\{0,1\}$/\1/p')"
printf 'VITE_SUPABASE_URL=%s\nVITE_SUPABASE_ANON_KEY=%s\n' "$api" "$anon" > .env.local
echo "Game: http://localhost:5173  (Ctrl+C to stop; 'npx supabase stop' to shut the database)"
(sleep 3; command -v open >/dev/null && open http://localhost:5173 || xdg-open http://localhost:5173 || true) >/dev/null 2>&1 &
npx vite --port 5173
