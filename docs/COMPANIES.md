# Companies and real businesses (inside the Business app)

Migration `supabase/migrations/20261020000100_companies.sql`, test `supabase/tests/companies_test.sql`. Client: `src/screens/game/phone/CompanyApp.tsx` (the hub), `BusinessApp.tsx` (Map plots), `RealBizForm.tsx`, `src/screens/CompanyPage.tsx` (public card `/c/<id>`), `src/api/company.ts`, `src/lib/realBiz.ts`. Admin: `src/admin/Companies.tsx`, `src/admin/RealBusiness.tsx`.

## What it is
Any player can open **online companies** with no map plot (the 18 plots being taken no longer blocks anybody), grow branches, hire staff, and cash out each evening. Players can **discover** other companies and rank them. A **real Benin business owner** can pay real money (Paystack) to put a pin on the map for 30 days. The listing is an advert only: no money moves between players and real businesses.

## One phone icon: Business
There is one icon, "Business" (id `business`). Tabs inside it:

| Tab | What |
|---|---|
| My companies | Start a company (big card, "₦50,000 to register", green Register pill, Rankings pill), the company dashboards, Cash out all, player shop (coming soon) |
| Map plots | The original plot businesses (BusinessApp, docs/BUSINESS.md): My businesses / Buy a business |
| Discover | Browse every company and every verified real business (search, industry, area, kind) and a Rankings switch (top companies by sales in the last 7 evenings) |
| Real business | Price and days, "List my real business", and the owner's own listings (status, views, taps, renew) |

Deep links: `go=business` opens Map plots (old "takings ready" pushes), `go=company` opens My companies, `go=business:mine|plots|discover|real` and `go=company:plots|discover|real` pick a tab. Paystack return handling does not use `go=` links (Inline popup, then `paystack-verify`).

## Money model (settings in Admin -> Settings -> Company, `company.*`)
Registration fee `company.reg_fee` (₦50,000) plus the industry setup cost x area multiplier. Revenue settles once per evening at `company.settle_hour` (18 = 6 PM Benin) into the **Till**, lazily on the next read (no cron; no write when nothing is due). The till holds `company.max_nights` evenings (Manager adds `company.manager_extra_nights`). Weekly bills (staff, manager, upkeep) come out of the till, 1/7 per evening. Rating 1-5 from pricing, staff and marketing; evening events (good review, bad review, NEPA outage, supplier problem) roll through `bl_co_roll`. Value = `company.value_days` days of profit (floor `company.value_floor_pct`). Sell to the system at `company.sell_pct`, or list on the Market (kind `company`, 8% fee, 50-250% band in `market_settings`). Other keys: `company.max_owned`, `max_branches`, `branch_cost_pct`, `player_night_cap`, `hire_fee_weeks`, `manager_*`, `generator_*`, `price_*`, `demand_*`, `cap_*`, `rating_*`, `ev_*`, `keep_nights`, `rank_limit`, `shop_enabled`, `enabled`.
Content editors (Admin -> Content): Company industries, areas, formats, marketing, Real business spots.

Real business keys (`realbiz.*`): `enabled`, `price_kobo` (2500000 = ₦25,000, kobo), `days` (30), `max_per_area` (6), `max_per_player` (2), `max_images` (3), `renew_window_days` (7), `report_alert`, `contact_email`, `terms`. Needs `payments.enabled` too.

## Ledger reasons
`company_fee`, `company_setup`, `company_branch`, `company_format`, `company_staff`, `company_manager`, `company_generator`, `company_marketing` (sinks), `company_sell` (credit), `company_income` (the cash out: earned income, so it is in `leaderboard.earn_reasons` and the weekly tax applies). Labels in `bl_ledger_label`, categories in `bl_econ_category`.

## RPCs
Player: `company_status`, `company_register`, `company_branch_add`, `company_branch_upgrade`, `company_hire`, `company_fire`, `company_manager`, `company_generator`, `company_set_pricing`, `company_marketing_buy`, `company_cashout`, `company_sell`, `company_rankings`, `company_discover`, `company_public` (also **anon**: the share page works signed out; returns only name, logo, industry, areas, stars, owner username, 7-evening sales, rank; allow-listed in `launch_safety_test`), `real_biz_form`, `real_biz_create`, `real_biz_cancel`, `real_biz_mine`, `real_biz_renew_start`, `real_biz_map`, `real_biz_get`, `real_biz_track`, `real_biz_report`.
Admin: `admin_company_overview`, `admin_company_remove`, `admin_real_biz_queue`, `_approve`, `_reject`, `_suspend`, `_unsuspend`, `_remove`, `_refund_start`, `admin_real_biz_revenue`.
Service role only (Edge Functions): `bl_real_biz_paid`, `bl_real_biz_refund_claim`, `bl_real_biz_refund_result`, `bl_real_biz_sweep`. All `bl_co_*`, `bl_rb_*`, `bl_real_biz_*` helpers are revoked from public, anon and authenticated.
Tables (RLS on, no client write): `company_industries`, `company_areas`, `company_formats`, `company_marketing`, `companies`, `company_branches`, `company_nights`, `company_log`, `real_biz_slots`, `real_businesses`, `real_biz_reports`, `real_biz_counter_log`. Players read their own `companies` rows and their own `real_businesses` rows (never `pay_raw` or refund JSON).

## Real business flow (real money)
1. Player fills the form (name, category, description, phone / WhatsApp / Instagram / website, address, area, a free map spot, 1-3 photos uploaded to the `real-biz` bucket, terms). `real_biz_create` validates and moderates (see below), then stores the listing as `awaiting_payment` with the **price taken from `realbiz.price_kobo` on the server** and a reference `BLRB-<32 hex>`. The client only gets back `{reference, amount_kobo, email}`.
2. Paystack Inline charges that amount. `paystack-verify` (player JWT, must own the reference) and `paystack-webhook` (HMAC-SHA512 `x-paystack-signature`, `verify_jwt = false`) both call `verifyAndMarkRealBiz`: Paystack's own verify API must say `success`, currency NGN, same reference; then `bl_real_biz_paid(reference, amount_kobo)` compares Paystack's amount in kobo with the stored price.
3. Exact amount: the listing moves to `pending_review` **once** (a second call, from webhook or verify, returns `already`) and admins are notified. Wrong amount, or no free spot: the listing is `rejected` with `refund_status = pending` and admins get a "refund needed" alert.
4. Admin (Admin -> Real business): approve (status `live`, `ends_at = now + days`, verified pin on the map and in Discover), reject with a reason (automatic refund through the `billboard-refund` Edge Function with `biz_id`), suspend / unsuspend (time left is kept), remove (optional refund). Photos are shown for checking. Every action is written to `admin_audit`. Players can report a live listing (admin push at the `realbiz.report_alert` threshold).
5. Expiry: `bl_real_biz_sweep` (run on form, mine, queue and create reads) sets `live` rows past `ends_at` to `expired`; `real_biz_map` also filters `ends_at > now()`. Unpaid checkouts older than a day are cancelled (a late payment for a cancelled listing is still handled).
6. Renewal: only in the last `realbiz.renew_window_days` days of a live listing; new reference, same server price, extends `ends_at` by `days`. Renewal payments that cannot be applied (wrong amount, status) raise a "refund needed" admin alert (manual refund from the Paystack dashboard).

### Moderation
Name (3-40), description (15-400, no links), address (5-120) go through `bl_chat_clean` + `bl_chat_mask` (admin banned-word list), no `<`/`>`, and `bl_rb_text_ok` (whole-word match of the Benin Votes blocked real politicians, parties and election bodies, `pol.blocked_words`). Company names get the same checks. Phone / WhatsApp digits only (8-15), Instagram name pattern, website must be https (`bl_billboard_link_ok`), one contact is required, emoji pin from an allow-list, photos only from the caller's folder that exist in storage. Limits: listings per player, pins per area, 10 tries an hour.

## Tests
`bash scripts/sql-test.sh -- supabase/tests/companies_test.sql` (15 groups; starts by emptying companies and real businesses inside its rolled-back transaction so a dev DB with data does not change the result). Also `market_test` (company kind), `launch_safety_test` (anon allow-list). Never call live Paystack in tests; the Edge Functions are checked by reading and by the RPC tests.

## Not verified here
The Edge Functions were not run against Paystack (no live keys, by design). Check one real Paystack test-mode payment before launch.
