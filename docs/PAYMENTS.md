# Payments, leaderboards and VIP arrivals (PAY)

Server: `supabase/migrations/20261007000100_payments.sql` (idempotent). Edge Functions: `supabase/functions/{paystack-verify,paystack-webhook,_shared/paystack.ts}`. Deploy: `.github/workflows/supabase-functions.yml`. Tests: `supabase/tests/payments_test.sql`.
Client: `src/lib/payments.ts`, `src/panels/WalletPanel.tsx`, phone app `src/screens/game/phone/RanksApp.tsx`, `src/styles/pay.css`, VIP banner via `src/state/hype.ts` + `src/screens/game/Hype.tsx`. Admin: `src/admin/Payments.tsx`, Content → Top-up packs, Settings → payments.

## Setup (owner, one time)
1. **GitHub secret** `PAYSTACK_SECRET_KEY` (repo → Settings → Secrets and variables → Actions). The workflow **Supabase Edge Functions** copies it into the Supabase secret of the same name (never printed) and deploys both functions. Run it from the Actions tab (workflow_dispatch) after adding or changing the secret; it also runs on pushes to `main` that touch `supabase/functions/**`, `supabase/config.toml` or the workflow. With the secret empty it skips that step with a notice and still deploys.
2. **Vercel env** `PAYSTACK_PUBLIC_KEY` = your `pk_test_…` / `pk_live_…` (Production + Preview), then redeploy. `VITE_PAYSTACK_PUBLIC_KEY` also works. The public key is public by design. `vite.config.ts` exposes only the `VITE_` and `PAYSTACK_PUBLIC_` prefixes to the browser; never widen it to `PAYSTACK_` (that would match the secret key).
3. **Paystack dashboard** → Settings → API Keys & Webhooks: Webhook URL `https://twwttirvesbwjvzjmenp.supabase.co/functions/v1/paystack-webhook`. Callback URL: `https://benin-life.vercel.app/play` (Inline checkout doesn't redirect, so this is only a fallback).
4. **Test first** with the test keys (`sk_test_…` in GitHub, `pk_test_…` in Vercel) and Paystack's test card (4084 0840 8408 4081, any future expiry, CVV 408, PIN 0000, OTP 123456). Buy a pack, check the bank goes up, the ledger says "Top-up via Paystack" and admin → Payments shows it as success. Then swap both keys to live and re-run the workflow / redeploy.
5. **Turn it on:** admin → Settings → ⭐ Most used → **payments.enabled**. Off = the Wallet shows "Coming soon" and `payment_init` refuses.

## Flow and security
1. Wallet → `payment_init(p_pack)` (authenticated; needs `payments.enabled`, a profile, not banned; max 20 per hour). It inserts a `pending` payment with reference `BL-<32 hex>`, price and naira from `topup_packs`, and returns `{reference, amount_kobo, email (auth email), currency}`.
2. Paystack Inline v2 (`https://js.paystack.co/v2/inline.js`, loaded on first tap) charges that amount for that reference.
3. On success the client calls `paystack-verify` with `{reference}` and the player's JWT. The function checks the JWT user owns the payment, calls `GET https://api.paystack.co/transaction/verify/:reference` with the secret key, requires `status=success`, currency NGN and the same reference, then calls `bl_payment_credit(reference, paid_amount, raw)` with the service role and returns `{ok, credited, already, bank}`. 402 (not paid yet, e.g. transfer) is retried by the client 3×; otherwise the player sees "lands as soon as Paystack confirms".
4. `paystack-webhook` (verify_jwt = false in `supabase/config.toml`) checks `x-paystack-signature` = HMAC-SHA512(raw body, secret key) in constant time, and on `charge.success` runs the same verify + credit in the background (`EdgeRuntime.waitUntil`), answering 200 at once.
5. `bl_payment_credit` (security definer, **service_role only**; revoked from public/anon/authenticated) locks the row: unknown → error; already success → no-op (`already`); not pending → error; **amount ≠ amount_kobo → marked failed, nothing credited**; no profile (mid new-life) → stays pending for a later retry. Otherwise `bl_add_money(bank, +game_naira, 'topup')` (ledger label "Top-up via Paystack"), status success + paid_at, and an alert "Top-up received".
- `payments`: RLS, players read only their own rows (not `raw`); no client writes. `topup_packs`: players read active rows; edits only through admin (`admin_row_upsert`, audited).
- The client never credits anything; a forged success callback just makes verify fail.

## Leaderboards (phone → Ranks)
- `leaderboard_rich(p_limit=50)`: cash + bank, rows `{rank, id, username, avatar, origin, total, tier, me}`, `me` (your rank/total, rank null when hidden), `players`, `tiers`.
- `leaderboard_vip(p_limit=50)`: sum of successful payments; rows `{rank, id, username, avatar, origin, tier, amount, me}`, `amount` is null unless `leaderboard.vip_show_amounts` (your own `me.amount` is always shown to you). Never emails.
- Banned players are hidden; admins too while `leaderboard.hide_admins` (default on).
- Tiers (Settings → Leaderboards, text `Name:min, …`): `leaderboard.rich_tiers` "Hustler:0, Big Boy:1000000, Oga:10000000, Chairman:100000000, Billionaire:1000000000" (₦ game money); `leaderboard.vip_tiers` "Bronze:0, Silver:5000, Gold:20000, Platinum:100000, Odogwu:500000" (₦ real money).
- UI: two tabs, top-3 podium (cached 3D portraits, crown, medals, gold/silver/bronze rings), ranks 4+ list with tier badges, your row pinned at the bottom, refresh button.

## VIP arrivals
`travel_arrive` calls `bl_vip_arrival(uid, dest)` after the move: when `vip.arrivals_enabled`, the place is not the player's home, the player ranks ≤ `vip.arrival_top` (3) on the VIP list and has no `vip_arrival` in the last `vip.arrival_cooldown_min` (30) real minutes, it inserts a `place_announcements` row kind `vip_arrival` ("VIP #1 @Nosa just walked into Mama Osas Buka!"). Errors never break arriving. The client's place channel (`useHypeLive`) now runs at every place you're at (not only clubs); outside clubs it shows only `vip_arrival` rows, as a gold "VIP alert" banner (and a line in the place chat).
Note: `hype.cooldown_s` counts every announcement of a player, so a VIP who just arrived at a club gets their first hype line up to 30 s later.

## Config
`payments.enabled` (false), `payments.currency` ("NGN"), `leaderboard.hide_admins` (true), `leaderboard.vip_show_amounts` (false), `leaderboard.rich_tiers`, `leaderboard.vip_tiers`, `vip.arrivals_enabled` (true), `vip.arrival_cooldown_min` (30), `vip.arrival_top` (3).

## Packs (seed; admin edits them)
Small chops ₦20,000 for ₦200 · Correct money ₦120,000 for ₦1,000 (+20%) · Big boy pack ₦650,000 for ₦5,000 (+30%) · Oga pack ₦1.5M for ₦10,000 (+50%) · Odogwu pack ₦3.5M for ₦20,000 (+75%). Price is in kobo in the table (₦1 = 100 kobo, minimum 10000).

## Admin
- **Payments** (sidebar): revenue today (midnight WAT) / 7 days / all time, payers, pending / failed, game naira sold; filter All / Success / Pending / Failed; search username or reference. `admin_payments(p_status, p_search, p_limit)`.
- **Content → Top-up packs**: name, game naira, price in kobo (inline), bonus tag, sort, Active.
- **Settings**: categories Payments, Leaderboards, VIP perks; `payments.enabled` in ⭐ Most used.
