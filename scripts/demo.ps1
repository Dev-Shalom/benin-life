# One-command local demo (Windows PowerShell). Needs Docker Desktop running and Node 20+.
# Starts local Supabase, applies all migrations fresh, writes .env.local, runs the game.
# Run from the repo folder:  powershell -ExecutionPolicy Bypass -File scripts\demo.ps1
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)
function Run($cmd) { Invoke-Expression $cmd; if ($LASTEXITCODE -ne 0) { throw "Failed: $cmd" } }
$exclude = 'studio,imgproxy,vector,logflare,supavisor,storage-api,postgres-meta,edge-runtime,mailpit'
Run 'npm ci'
# Retry once: right after Docker starts, the DB container can report 'not ready'.
npx supabase start -x $exclude
if ($LASTEXITCODE -ne 0) { Start-Sleep -Seconds 20; Run "npx supabase start -x $exclude" }
# Apply only new migrations (keeps existing accounts). Use 'npx supabase db reset' for a clean slate.
Run 'npx supabase migration up'
$status = npx supabase status -o env
function Get-Val($name) {
  $line = $status | Where-Object { $_ -match "^$name=" } | Select-Object -First 1
  return ($line -replace "^$name=", '').Trim('"')
}
$api = Get-Val 'API_URL'
$anon = Get-Val 'ANON_KEY'
Set-Content -Path .env.local -Value "VITE_SUPABASE_URL=$api`nVITE_SUPABASE_ANON_KEY=$anon" -Encoding ascii
Write-Host "Game: http://localhost:5173  (Ctrl+C to stop; 'npx supabase stop' to shut the database)"
Start-Process "http://localhost:5173"
npx vite --port 5173
