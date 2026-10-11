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

## Backups: turn them on before real money comes in (L1)
Supabase dashboard → project `twwttirvesbwjvzjmenp`:
1. **Daily backups.** Organization → **Billing** → upgrade the organization to **Pro**. Daily backups start by themselves (kept 7 days on Pro). Check them at Project → **Database → Backups → Scheduled backups**: a new row should appear within a day.
2. **Point-in-time recovery (PITR)** (restore to any second, recommended once top-ups and ads are live). Project → **Settings → Add-ons → Point in time recovery → Change** → pick 7 days → Confirm. It needs at least the Small compute add-on (Settings → Add-ons → **Compute size**); the dashboard tells you if it does. Then Database → Backups shows a **Point in time** tab.
3. **Restore drill (5 minutes, once):** Database → Backups → pick yesterday's backup → **Restore**. Do this only on a test project, or read the confirmation screen and cancel; a restore overwrites the live database.
4. **Free-plan fallback** (if you stay on Free for now): weekly by hand, `supabase db dump --linked -f backup-YYYY-MM-DD.sql` and `supabase db dump --linked --data-only -f data-YYYY-MM-DD.sql` (needs the DB password from Settings → Database). Keep the files somewhere private (they contain player emails).
5. **Storage** (billboard ad images, voice notes) is not in database backups. It is small; if you need a copy, download the `billboard-ads` bucket from Storage.

## Vercel settings to check (L1)
Vercel dashboard → project:
| Where | What to check |
|---|---|
| Settings → Git | Production Branch = **`main`**. |
| Settings → Environment Variables (Production) | `PAYSTACK_PUBLIC_KEY` (or `VITE_PAYSTACK_PUBLIC_KEY`) = your live `pk_live_…` key (a `pk_test_` key means test checkouts). `VITE_SUPABASE_URL` / `VITE_SUPABASE_ANON_KEY` come from the committed `.env.production`, so leave them unset in Vercel or make sure they match. |
| Settings → Deployment Protection | **Vercel Authentication off for Production** (otherwise players get a Vercel login page). |
| Settings → Domains | `benin-life.vercel.app` (and your custom domain if you add one; then update Supabase Site URL + Redirect URLs). |
| Deployments | The newest `main` deploy says **Ready**, and https://benin-life.vercel.app/version.json shows its commit SHA. |
| Settings → Functions / Usage | Hobby plan limits (bandwidth). Vercel Hobby is non-commercial; real-money top-ups and ads count as commercial use, so plan to move to **Pro** when you start selling. |

## Client errors (L1)
The app reports crashes to the database so you can see them without player screenshots.
- **What is sent:** the top-level crash screen (ErrorBoundary), every panel crash, `window.onerror`, unhandled promise rejections and stale-chunk reloads. Code: `src/lib/errorReport.ts` (hooked in `src/main.tsx` and `src/ui/ErrorBoundary.tsx`). Noise is skipped (ResizeObserver, "Failed to fetch" on bad data, cross-origin "Script error"). The same message is sent at most once a minute and at most 20 reports per tab. Dev builds send nothing unless `localStorage['bl.debug.errors'] = '1'`.
- **Where it lands:** table `client_errors` through `client_error_log()` (migration `20261012000600_launch.sql`). Only the user id from the session, the message (≤ 500 chars), stack (≤ 4,000), page path without query string, build id and browser are stored. Players can't read the table. Per player at most `errors.per_user_per_hour` (30) an hour; logged-out visitors share 10× that. Rows older than `errors.keep_days` (14) are deleted.
- **Where you see it:** Admin → **Overview → App errors** (last 24 h / 3 days / 7 days, grouped by message, tap for the stack, user and browser). Switch it off with `errors.enabled`.

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

## Password reset emails at scale (S1)
Tested end to end locally (2026-10-11, Playwright): /auth → **Forgot password?** → email → the email arrives
("Reset your password") → its link goes through Supabase `/auth/v1/verify` → lands on `/auth?mode=reset` → **Choose a
new password** → saved → signed in (`/play`, or `/create` for an account without a Sim) → log out → the old password is
refused, the new one works. Code: `src/screens/Auth.tsx` (`resetPasswordForEmail` with
`redirectTo: <origin>/auth?mode=reset`), `src/state/game.ts` (a `PASSWORD_RECOVERY` session lands on the reset form).
Nothing in the app needed fixing. On the **live** project check these, in order:

1. **Authentication → URL Configuration**
   - **Site URL** = `https://benin-life.vercel.app` (exactly; if it is localhost, every email link points to localhost).
   - **Redirect URLs** must include `https://benin-life.vercel.app/**`. Without it Supabase ignores the app's
     `redirectTo` and sends players to the Site URL root instead of the reset form. (Optional:
     `https://benin-life-*.vercel.app/**` for preview deploys.)
2. **Custom SMTP (required before announcing).** The built-in sender allows only **2 emails per hour for the whole
   project**, goes to spam often, and is meant for testing. With 1,000 players, "Forgot password" would fail for
   nearly everyone. Set up a free sender:
   - **Resend** (free: 3,000 emails/month, 100/day): resend.com → sign up → Domains → add your domain (a custom domain
     is needed to send to anyone; add the DNS records it shows) → API Keys → create. In Supabase: **Authentication →
     Emails → SMTP Settings → Enable custom SMTP**: Host `smtp.resend.com`, Port `465`, Username `resend`, Password =
     the API key, Sender email `no-reply@<your-domain>`, Sender name `Benin Life`.
   - **Brevo** (free: 300 emails/day, no domain needed to start, verify the sender email): brevo.com → SMTP & API →
     SMTP → copy the login and create an SMTP key. Supabase SMTP: Host `smtp-relay.brevo.com`, Port `587`, Username =
     the Brevo SMTP login, Password = the SMTP key, Sender email = the verified address, Sender name `Benin Life`.
   - Then **Authentication → Rate Limits → "Rate limit for sending emails"**: raise it (it starts at about 30/hour with
     custom SMTP) to what your provider allows, e.g. 100/hour for Resend free, 250/hour for Brevo free.
   - Send yourself a reset from the live site and check it arrives (also check the spam folder).
3. **Email template sanity: Authentication → Emails → Templates → Reset Password.** Keep `{{ .ConfirmationURL }}` as the
   link (it carries the redirect to `/auth?mode=reset`). Suggested subject `Reset your Benin Life password`; body: "Tap
   the button to choose a new password for Benin Life. If you didn't ask for this, ignore this email." The link expires
   after 1 hour (Auth → Providers → Email → "Email OTP expiration"); an expired or reused link shows "This reset link
   has expired or was already used" with a button for a new one.
4. Keep **Rate limits** for sign-ups / sign-ins / token refresh at their defaults.

Local testing note: the local stack has no Mailpit container right now (Docker Hub rate limit). The S1 test used a
tiny stand-in on the same Docker network (`scratchpad/s1/mailsink/sink.js`, alias `supabase_inbucket_benin-life`,
API on :54324) and Vite on port 5173 (the local Auth redirect allow-list; `supabase/config.toml` now also lists 5242
and the live URL for the next `supabase start`).

## Launch-crowd limits (S1) — read docs/SCALING.md
Short version: **Free = about 200 players online at once, Pro with spend cap = 500, Pro without spend cap = thousands**
(then database compute decides). Upgrade to Pro, turn the spend cap off, pick Small/Medium compute and set up custom
SMTP before announcing. Every open game tab holds one Realtime connection (profile feed, config, global hype, the
place's presence + chat). The old global presence channel (N² messages) is gone (S1).

- **Vercel Hobby:** bandwidth and build minutes per month; Hobby is for non-commercial use. Hashed `/assets/*` are
  cached for a year (`vercel.json`), so returning players download almost nothing.

## If many players join, upgrade in this order
1. **Supabase Pro + spend cap off** (first): more Realtime connections (500 → 10,000 with the cap off), no pause, daily backups. Turn on **point-in-time recovery** once money is involved.
2. Custom SMTP for auth emails (above).
3. Compute add-on: Small (to ~1,000 online) or Medium (to ~3,000), or when Reports → Database CPU stays high.
4. Vercel Pro only if bandwidth runs out or you start charging money (Hobby terms).
5. Later: an archive job for old `ledger`/`events` rows, and a custom domain (add it in Vercel, then update Site URL + Redirect URLs in Supabase).

## Edge functions
`paystack-verify`, `paystack-webhook`, `admin-push`, `billboard-refund` and (S1) **`admin-delete-user`** deploy with
Actions → **Supabase Edge Functions** (`.github/workflows/supabase-functions.yml`, runs on pushes touching
`supabase/functions/**`). `admin-delete-user` needs no new secrets (it uses the built-in `SUPABASE_URL`,
`SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`). Until it is deployed, Admin → Players → Delete account shows
"Delete failed".

## Config that must stay set after deploy
`origin.force_next` = "nepo" (one-shot; the next new account is Nepo), `origin.nepo_pct` = 10, `time.real_seconds_per_game_minute` = 0.75, `clock.epoch` = "2026-10-05T00:00:00Z", `rent.enabled` = true. All editable in Admin → Settings.
