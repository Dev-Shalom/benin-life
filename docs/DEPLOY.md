# Deploying Benin Life (v1)

## How the live site works
| Piece | Where | How it updates |
|---|---|---|
| Website (React build) | **Vercel**, project serving https://benin-life.vercel.app | Every push to **`main`** builds (`npm run build` → `dist/`) and goes live. `vercel.json` rewrites every unknown path to `index.html` (SPA routes like `/play`, `/admin`); real files (`/assets/*`, icons, `manifest.webmanifest`) are served first. |
| Backend | **Supabase cloud**, project `twwttirvesbwjvzjmenp` (Postgres, Auth, Realtime) | The site reads `VITE_SUPABASE_URL` / `VITE_SUPABASE_ANON_KEY` from `.env.production` (committed; the anon key is public by design, RLS protects the data). |
| Database schema + seed | `supabase/migrations/*.sql` | GitHub Action **"Supabase preview DB"** (`.github/workflows/supabase-deploy.yml`) runs `supabase db push --include-all` on every push to `main` that touches `supabase/migrations/**`. Needs repo secrets **`SUPABASE_ACCESS_TOKEN`** and **`SUPABASE_DB_PASSWORD`** (GitHub → Settings → Secrets and variables → Actions). Can also be run by hand: Actions → Supabase preview DB → Run workflow. |

Work happens on `claude/kind-bell-e9reb8`; only verified steps are fast-forwarded to `main`.

Rules for migrations: **forward-only**. Never edit a migration that is already on `main`; add a new file. Every migration must be idempotent and safe on a database that already has players (`create … if not exists`, `on conflict do nothing`, `create or replace function`, no `truncate`/`drop table`).

## Releasing
1. Verify locally: all SQL suites (`bash scripts/sql-test.sh -- supabase/tests/*.sql`), `npm run build`.
2. `git push origin HEAD:main`.
3. Watch GitHub → Actions: "Supabase preview DB" must be green (only runs when migrations changed). Vercel dashboard → Deployments: the new build must say **Ready**.
4. Open https://benin-life.vercel.app, log in, do one quick action.

If a migration and a frontend change depend on each other, the DB job and the Vercel build run at the same time. Keep new SQL backward compatible with the old site (add, don't rename) so the order doesn't matter.

Open tabs from before a deploy reload themselves once if they ask for a JS chunk that no longer exists (`vite:preloadError` handler in `src/main.tsx`).

**Update notice (S1).** Every build gets an id (`<git sha>-<build time>`; on Vercel the SHA comes from `VERCEL_GIT_COMMIT_SHA`). The `bl-version-json` plugin in `vite.config.ts` writes it to `dist/version.json` and bakes it into the app as `import.meta.env.VITE_BUILD_ID`. Production tabs fetch `/version.json?t=…` (`cache: 'no-store'`) every 3 min and on window focus / tab visible (at most once per 20 s); when the id differs they show a small phone-style dialog "There's a new update ✨" with **Refresh** (`location.reload()`; game state is on the server and prefs in localStorage, so nothing is lost) and **Later** (hidden until an even newer build appears). Never runs in dev; a failed or non-JSON fetch is ignored. Vercel serves `version.json` from the filesystem before the SPA rewrite. Code: `src/ui/UpdateNotice.tsx`.

## Rolling back
- **Website:** Vercel → project → Deployments → pick the last good deployment → ⋯ → **Promote to Production** (instant, no rebuild). Then fix `main` (e.g. `git revert`) so the next push doesn't bring the bug back.
- **Database:** migrations can't be undone automatically. Write a new migration that reverses the change (e.g. re-create the old function body) and push it. Config mistakes are easier: Admin → Audit → **↺ Restore old**, or Admin → Settings → "↺ Back to …".
- Supabase free plan has **no point-in-time restore**; daily backups exist on paid plans. Before a risky migration, take a manual dump: Supabase dashboard → Database → Backups (paid) or `supabase db dump --linked -f backup.sql` (needs the DB password).

## Becoming admin
- **Owner claim (easiest):** sign up on the live site with an email listed in `admin.bootstrap_emails` (currently dev.shalom1@gmail.com, code.devshalom@gmail.com), finish creating the Sim, open https://benin-life.vercel.app/admin and press **"I'm the owner: claim admin"**. Then in Admin → Settings → Admin, **clear the owner emails list**.
- **SQL editor:** Supabase dashboard → SQL Editor → `update profiles set is_admin = true where username = '<your username>';`
- Details: `docs/ADMIN.md`.

**Do this before announcing.** With email confirmation off, whoever registers an owner email first can claim admin.

## Supabase Auth settings to check (dashboard → Authentication)
| Setting | Value |
|---|---|
| Sign In / Providers → Email → **Confirm email** | v1 assumes **off** (players land straight in the creator). If you turn it on, sign-up shows "Check your email to confirm it, then come back and log in"; the confirmation link returns to the Site URL. Turning it on also blocks mass sign-ups and stops strangers from taking the owner emails. |
| URL Configuration → **Site URL** | `https://benin-life.vercel.app` (not localhost, or email links point to localhost) |
| URL Configuration → **Redirect URLs** | `https://benin-life.vercel.app/**` (covers the password reset link `…/auth?mode=reset`). Add `http://localhost:5173/**` only if you test locally against the cloud project. |
| Email → SMTP | The built-in mailer has a very low hourly limit and is for testing only. Before many players use "Forgot password" (or if you turn Confirm email on), set up custom SMTP (Resend, Brevo, Mailgun, Amazon SES, …). |
| Rate limits | Keep the defaults on (sign-ups / sign-ins per hour per IP). |
| Password | Minimum length 6 matches the game's check; raise both together if you change it. |

## Free-tier limits to watch (check the current numbers on supabase.com/pricing and vercel.com/pricing; they change)
- **Supabase Free:** database size (around 500 MB), egress / bandwidth (a few GB a month), Realtime concurrent connections (around 200) and messages, monthly active users for Auth, and the project **pauses after about a week with no activity**. Watch them in Supabase → Settings → Usage / Reports.
  - Biggest growth: `ledger` (one row per money move), `events`, `chat_messages` (auto-trimmed after 48 h), `config_audit`/`admin_audit`.
  - Realtime: every open game tab holds one connection (profile, chat, config, S1 presence channel `online`). Presence messages are tiny (`{l: place}`) but each join/leave/move is broadcast to every online tab, so the message count grows with players². Concurrent players online is the number that hits the limit first.
- **Vercel Hobby:** bandwidth and build minutes per month; Hobby is for non-commercial use. The game is a static site, so this goes far; the 3D chunk (`three`, ~190 kB gzip) is the largest download and is cached after the first visit.

## If many players join, upgrade in this order
1. **Supabase Pro** (first): removes the pause, larger DB and egress, more Realtime connections, daily backups. Turn on **point-in-time recovery** add-on once money is involved.
2. Custom SMTP for auth emails (see above).
3. Bigger Supabase compute add-on if the dashboard shows high CPU (lots of RPCs per second).
4. Vercel Pro only if bandwidth runs out or you start charging money (Hobby terms).
5. Later: an archive job for old `ledger`/`events` rows, and a custom domain (add it in Vercel, then update Site URL + Redirect URLs in Supabase).

## Config that must stay set after deploy
`origin.force_next` = "nepo" (one-shot; the next new account is Nepo), `origin.nepo_pct` = 10, `time.real_seconds_per_game_minute` = 0.75, `clock.epoch` = "2026-10-05T00:00:00Z", `rent.enabled` = true. All editable in Admin → Settings.
