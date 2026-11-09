# Security fix pack (21 Nov 2026)

Files: `supabase/migrations/20261121000100_security_pack.sql`, `supabase/tests/security_test.sql`, `supabase/functions/_shared/cronAuth.ts` (+ `.test.ts`), `supabase/functions/player-push`, `delete-my-account`, `admin-delete-user`, `_shared/paystack.ts`, `public/_headers`, `src/screens/Auth.tsx`, `src/screens/WelcomeBack.tsx`, `src/screens/game/DeleteAccount.tsx`, `src/lib/{passwordPolicy,turnstile,reauth}.ts`, `src/ui/Turnstile.tsx`.

## What was fixed

| # | Problem | Fix |
|---|---|---|
| 1 | **Admin takeover.** `admin.bootstrap_emails` held the owner emails and email confirmation is off, so anyone could sign up with an unregistered owner email and press "Claim admin". | The setting is emptied by the migration when an admin already exists (a project with no admin yet keeps its list so it can still claim). `admin_claim()` also refuses unless (a) the list is not empty, (b) `auth.users.email_confirmed_at` is set, (c) there is no admin at all. It never changes an existing admin. To bootstrap a brand new project: put the email in `admin.bootstrap_emails` (Admin, or SQL), confirm the email, claim, then empty the list again. |
| 2 | `life_restart()` wiped a Sim with one call. | `life_restart(p_confirm text)`: `p_confirm` must equal the Sim name (any case, trimmed) and the JWT's `amr` claim must contain a `password` entry whose timestamp is younger than `security.reauth_minutes` (default 15). `amr` survives token refresh, so a refresh token alone cannot pass; a missing `amr` fails closed. The app asks for the password and runs `signInWithPassword` first (that gives a fresh JWT), then calls the RPC. The zero-argument `life_restart()` stays but only raises "Please confirm with your password." so old app versions fail safe. `admin_audit` still logs `life_restart` (now with `reauth: true`). |
| 3 | `push_subscribe` accepted any https URL (blind SSRF) and let a user take over another user's endpoint. | `bl_push_endpoint_ok()` allows only `fcm.googleapis.com`, `*.push.services.mozilla.com`, `web.push.apple.com`, `*.push.apple.com`, `*.notify.windows.com` (covers `wns2-*`). On conflict the row is only updated when it already belongs to the caller, otherwise `endpoint_taken`. Same for `admin_push_subscribe`. Existing rows with other hosts were deleted by the migration. |
| 4 | `player-push` treated the public anon key as a cron credential and skipped its 3 second throttle. | Only the header `x-cron-secret` equal to the Supabase secret `CRON_SECRET` (constant-time compare, ignored when the secret is unset or empty) skips the throttle. The anon and service keys still authenticate but go through the throttle. See "How cron auth works". |
| 5 | CORS did not know the Cloudflare Workers site. | `_shared/paystack.ts` also allows `https://benin-life*.<account>.workers.dev`. Every function that answers browsers (`admin-push`, `admin-delete-user`, `billboard-refund`, `delete-my-account`, `player-push`, `paystack-verify`) uses this one helper. `paystack-webhook` is server to server and has no CORS. |
| 6 | Account deletion order and leftovers. | See "Account deletion" below. |
| 7 | `admin_audit_admin` policy let a banned admin read the audit log. | Recreated with `and not p.banned`, like `feedback_admin`. |
| 8 | Staff-looking usernames. | `bl_check_new_profile` (patched in place, no trigger on profiles) rejects names equal to or starting with a word in `security.reserved_names`. Names are lower-cased with `_ . -` and spaces removed first. A plain word blocks itself and itself plus digits (`support`, `support2`, `shalom1`); a word ending in `*` also blocks every name that starts with it. Default: `admin*,administrator*,beninlife*,moderator*,official,support,staff,system,owner,shalom,mod`, so Stafford, Systems, Supporter, Owners, Officially, Modupe and Shalom_Fan stay free. The setting is a comma separated text (it also accepts a JSON array), so the Admin Settings screen can edit it. A past admin who starts a new life keeps the right to their old name. Existing usernames are not touched. |
| 9 | Weak passwords. | Sign-up and "choose a new password" need 8+ characters, not only digits, not in a short list of very common passwords. Sign-in is unchanged, so nobody is locked out. `supabase/config.toml` has `minimum_password_length = 8` (local only). |
| 10 | No bot protection. | Optional Cloudflare Turnstile on sign-up, log-in and password reset, and on the password re-check for "Start a new life". Only active when `VITE_TURNSTILE_SITE_KEY` is set. |
| 11 | No security headers. | `public/_headers` (Cloudflare) and `vercel.json` send `X-Frame-Options: DENY`, `frame-ancestors 'none'`, `nosniff`, `strict-origin-when-cross-origin`, HSTS, and a Permissions-Policy limiting camera, microphone and geolocation to the site itself (voice notes use the microphone). There is deliberately **no script/style CSP** because it could break the game (three.js, inline styles, Paystack). The existing cache rules stay. Workers static assets read `_headers` from the built `dist` folder, so `wrangler.jsonc` needs no change. |

### Account deletion (delete-my-account and admin-delete-user)
1. The database checks the confirmation and writes the "started" audit row with the snapshot (`self_delete_account`, `delete_user`). This is the same as before.
2. The function only **lists** the player's files (`bl_user_storage_paths`: billboard-ads, player-voice, gist-photos, real-biz, and club-music files the user uploaded that no track uses).
3. `auth.admin.deleteUser`. If it fails nothing else has been touched, `self_delete_account_failed` (or `delete_user_failed`) is written, and the answer is JSON `{ ok:false, error, message }` with a short reason. The app reads the body of the error response and shows that reason (with a plain fallback).
4. Only after it worked: the files are removed, `bl_delete_user_leftovers(uuid)` clears rows that hold the user id without a foreign key, and `self_delete_account_done` / `delete_user_done` is written (with `target_user` null, the id is in `data.user_id`, because the user no longer exists).

Why leftovers run **after** the delete and not before: if the cleanup ran first and `deleteUser` then failed, the player would have lost data but still have a login. The function does not need the user to exist, can be run again by hand, and the Sim is already gone, so the player cannot write new rows. If the cleanup step ever fails, run it by hand: `select bl_delete_user_leftovers('<uuid>');` as the service role.

`bl_delete_user_leftovers(p_uid)` has a fixed list of (table, column) pairs, built from `information_schema` (all `uuid` columns in `public` with no foreign key). It returns `{"table.column": rows}` for what it touched, is safe to run twice, and is granted to `service_role` only. Choices:
- **Deleted**: state, logs and applications that belong to the player (`player_*`, `roam_*`, `journey_*`, `drive_*`, `vehicle_state`, `return_*`, `weekly_*`, `cook_daily`, `home_resize_pending`, `kids_charges`, `business_log`, `company_log`, `ind_applications`, `ind_statements`, `ind_votes`, `court_lawyers`, `court_gallery`), and rows that cannot exist without them: court cases, hires and debts where they are a party (the case and its statements go together), the statements they wrote, the office seat they held (`ind_holders`, with its statements and votes), roam reports they sent or got, and love relationships they asked for.
- **Set to null** (the row matters to somebody else and the column only says who did something): `court_cases.judge_id`, `crew_boss_log.*`, `gist_comments.reply_to_user`, `gist_messages.money_to`, `ind_changes.user_id`, `ind_holders.appointed_by`, `kids_children.named_by / proposed_by`, `kids_school.fee_paid_by`, `kids_school_requests.paid_by`, `love_log.actor_id`, `love_relationships.ended_by`, `property_events.user_id`, and the admin attribution columns (`reviewed_by`, `decided_by`, `handled_by`, `granted_by`, `banned_by`, `removed_by`, `started_by`, `game_config.updated_by`).
- A case between two players is removed for both when one of them deletes the account (the claim, fine or debt cannot be collected from a person who is gone). A debt owed **to** the deleted player is dropped. A lawyer hire that was already paid stays paid in the other player's ledger.
- Payments stay for the books with `user_id = null` (unchanged).
- When a new table with an unprotected user column is added later, add it to this function (the list is hard-coded on purpose). `security_test.sql` and `admin_delete_test.sql` cover the FK side.

The delete screen is also reachable by a logged-in user with no Sim yet: it shows at the bottom of the first creator step.

### Indexes
`create index if not exists` for every foreign key to `auth.users` or `profiles` that had no index starting with its column, including `money_drops.sprayer`, `kids_care_log.user_id`, `market_trades.buyer_id`, `market_listings.buyer_id / buyer_only`, `love_date_invites.from_user / to_user`, `property_residence.landlord_id`, `property_income.tenant_id`, `city_party_guests.user_id`, `weekly_earn_winners.user_id`. `profiles` itself is not touched (its own `home_visit_host_id` column is left alone on purpose). `security_test.sql` fails if a new FK like this is added without an index.

## Limits you should know
- The password re-check trusts the JWT `amr` claim (method `password` with a timestamp), which the auth server writes at password sign-in and keeps through refreshes. The server still cannot see the password itself, but a stolen refresh token or an old session cannot pass without a new password sign-in.
- On a shared phone the push endpoint stays with the first account. Sign-out now frees it (best effort), and if the server still answers `endpoint_taken` the app drops the local subscription, gets a new endpoint and retries once.

## Owner actions (Supabase and Cloudflare dashboards)
1. **Production password length.** Authentication > Providers > Email (or Sign In / Providers > Password) > **Minimum password length = 8**. The `config.toml` change only affects local development.
2. **Turnstile (optional but recommended).** Cloudflare dashboard > Turnstile > Add widget (domain `playbeninlife.app` and your `*.workers.dev` host) > copy the **site key** and **secret key**. Supabase > Authentication > Attack Protection > **Enable CAPTCHA protection** > provider Turnstile > paste the secret. Then set `VITE_TURNSTILE_SITE_KEY` to the site key in the Cloudflare build variables (Workers > benin-life > Settings > Variables, build) and redeploy. Order matters: set the site key and deploy first, then switch on CAPTCHA in Supabase, otherwise sign-ups fail until the new build is live. Sign-up, log-in, password reset and "Start a new life" all send the token.
3. **Cron secret (recommended).** Create a long random string. Run `supabase secrets set CRON_SECRET=<it>` (or Edge Functions > Secrets) and add the HTTP header `x-cron-secret: <it>` to the `player-push` Cron job. Details below.
4. **Email confirmation.** Keep it off until custom SMTP can send 300+ confirmation emails a day (the built-in sender allows only a few per hour). With it off, CAPTCHA, the password rules and the rate limits are the defence against fake sign-ups.
5. **Leaked password protection** (blocks passwords found in the HaveIBeenPwned list) needs the Supabase Pro plan. Until then the small built-in list and the 8 character rule are all there is.
6. **Deploy.** Run the database workflow (migration) and Actions > Supabase Edge Functions (deploys `player-push`, `delete-my-account`, `admin-delete-user`). Deploy the migration first.
7. After the deploy check Admin > Settings > `admin.bootstrap_emails` shows empty, and that the owner is still an admin.

## How cron auth works
`player-push` is called by the Supabase Cron job (every minute, header `Authorization: Bearer <anon key>`, docs/NOTIFICATIONS.md) and by signed-in players right after they send a DM or money.
- Header `x-cron-secret` equals `CRON_SECRET` (secret set and not empty): this is the cron caller. No throttle, and it always runs the minute work (tick). No Authorization header is needed.
- Anon or service key, or a player JWT: accepted, but only one run per 3 seconds per function instance (extra calls answer `{ok:true, throttled:true}`), and the minute work runs at most once per 55 seconds.
- Anything else: 401.

**The existing scheduler keeps working without any change.** The repo has no `pg_cron` or `net.http_post` job and no GitHub workflow for this: the only scheduler is the dashboard Cron job from docs/NOTIFICATIONS.md, which sends the anon key once a minute. Under the throttle that call is still accepted. It is only skipped when another call ran less than 3 seconds earlier, and the next minute catches up (the outbox is a queue). The one change in behaviour is that a minute tick can now be skipped when a player's poke already did the tick less than 55 seconds earlier, so on a very busy instance bundled pushes can arrive up to a minute later. Adding the `x-cron-secret` header removes that: the cron call then always ticks.

## Investigating a "my account was hacked" report
Run these in the Supabase SQL editor (service role). Replace `<uid>` and `<email>`.

```sql
-- who is it
select id, email, created_at, last_sign_in_at, email_confirmed_at, updated_at, raw_app_meta_data
  from auth.users where email ilike '<email>';

-- sign-ins, password changes and token events (newest first); the payload holds the action and the IP address
select created_at, ip_address, payload->>'action' as action, payload->>'actor_username' as actor, payload
  from auth.audit_log_entries
 where payload->>'actor_id' = '<uid>' or payload->>'actor_username' = '<email>'
 order by created_at desc limit 100;

-- live and recent sessions: where from, which browser (delete a row to sign that session out)
select id, created_at, updated_at, not_after, ip, user_agent
  from auth.sessions where user_id = '<uid>' order by created_at desc;

-- money moved (newest first): reasons like transfer_out, bank_transfer, shop, gift
select id, created_at, account, delta, balance_after, reason, meta
  from public.ledger where user_id = '<uid>' order by id desc limit 200;
select reason, count(*), sum(delta) from public.ledger
 where user_id = '<uid>' and created_at > now() - interval '7 days' group by 1 order by 3;

-- tips sent and received
select * from public.tips where from_user = '<uid>' or to_user = '<uid>' order by created_at desc limit 100;

-- admin actions about this player, and every time they restarted or deleted something
select id, created_at, admin_id, action, data from public.admin_audit
 where target_user = '<uid>' or admin_id = '<uid>' order by id desc limit 100;

-- earlier lives (a "New life" archives the old Sim: money, bag, recent history)
select id, life_no, username, origin, cash, bank, archived_at, extra->'ledger_recent' as recent_money
  from public.profile_archive where user_id = '<uid>' order by id desc;

-- signs of a takeover: push devices, linked IPs of other accounts with the same address
select id, endpoint, user_agent, created_at from public.push_subscriptions where user_id = '<uid>';
select u.id, u.email, a.ip_address, count(*) from auth.audit_log_entries a
  join auth.users u on u.id::text = a.payload->>'actor_id'
 where a.ip_address in (select ip_address from auth.audit_log_entries where payload->>'actor_id' = '<uid>')
 group by 1, 2, 3 order by 4 desc limit 50;
```

If the account is compromised: ban it from Admin > Players (it stops the game at once), delete the rows in `auth.sessions` for the user, ask the player to use "Forgot password", and check `auth.audit_log_entries` for a `user_updated_password` or `user_modified` action you did not expect. A reported admin takeover: `select id, username from profiles where is_admin;` and compare with `admin_audit where action in ('admin_claim','set_admin')`.

## Tests
`bash scripts/sql-test.sh -- supabase/tests/security_test.sql` (admin_claim, life_restart, push_subscribe, reserved names, leftovers, storage paths, indexes, audit policy) and `deno test supabase/functions/_shared/cronAuth.test.ts`. The shared helper `supabase/tests/_helpers.sql` now puts a fresh `iat` and a fresh password `amr` entry in the test JWT (`pg_temp.login`) and has `pg_temp.my_sim()`; `life_test.sql` and `kids_test.sql` call `life_restart(pg_temp.my_sim())`.
