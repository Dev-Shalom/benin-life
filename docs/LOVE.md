# Family & Love (stage 1)

Owner: "There should be a way that players can try to ask other person out. When they accept, if they flirt to the person, they should have a flirting level. When it gets to 30% that is high, then the two of them are together. It shows in the Family app. They can do all sorts of things like in real life together: go out together, go to certain places together, have some fun together. (Later: give birth in the game and care for the child.)"

Migration `supabase/migrations/20261026000200_family_love.sql`, test `supabase/tests/love_test.sql`. Client: `src/screens/game/phone/FamilyApp.tsx` + `FamilyApp.css`, `src/api/love.ts`, `src/screens/game/LoveAskButton.tsx` (the "Ask out" button on a player's card), admin `src/admin/Love.tsx`. Help article `family-love`, tour step `family`.

One phone icon, **Family** 💞, three tabs: **Link-ups** · **Us** · **Family**. Deep links: `go=family` (Link-ups), `go=family:us`, `go=family:family`, `go=family:linkups`.

Everything is server-authoritative and lazy (no cron). Clients never read or write the tables: RLS is on, there is no grant and no policy; every action is a security-definer RPC.

## The rules as built (every number is a Setting, category `love`)
1. **Opt-in.** `profiles.love_open` (default OFF) gates being asked and being listed. Switching it off withdraws the asks you sent and drops the asks you got.
2. **Ask out** `love_ask(target)`. Needs: `love.enabled`; both opted in; both accounts at least `love.min_account_days` (2) old; neither at `love.max_partners` (1; talking and couple both count); no block either way (the existing chat block list, `bl_social_blocked`); the caller under `love.asks_per_day` (5, rolling 24 h, every ask counts); not within `love.decline_cooldown_days` (3) of a decline by that person; not within the break-up cooldowns; not yourself; no pending ask either way. The target gets an alert (`love_ask`) and a push (category `friends`). A pending ask expires after `love.ask_expire_hours` (48). **Declining is silent**: the asker sees "No reply" (an expired ask shows the same). Accepting makes a relationship in status `talking`, tells the asker, and ends every other open ask of anybody now at their limit. `love_withdraw(ask)` takes back an ask you sent.
3. **Flirt level** (one shared integer 0-100 per pair). `love_flirt(rel, flirt)` sends a line from the `love_flirts` menu (no free text): price (ledger `love_flirt`, a sink), points added, `min_level` to unlock, cooldown per sender `love.flirt_cooldown_minutes` (20), and a daily cap per pair `love.flirt_daily_cap` (20 points per game day, flirts and dates together). At the cap the flirt is refused and costs nothing; with only a little room left it adds what fits and still costs the full price. The partner gets an alert + push (pushes for one chat fold into "3 new flirts for you"). **Decay** is lazy: after `love.decay_after_days` (3) idle days (no flirt, no date) the level loses `love.decay_per_day` (2) a day. Reading computes the shown level without writing; the next write (flirt, date) stores it, for that pair only. A couple never falls under the couple level (they stay a couple); a talking pair can fall to 0.
4. **Couple.** The flirt (or date) that takes the level to `love.couple_level` (30) flips the status to `couple`: both get a `love_couple` alert + push ("You are now a couple 💞"), a `couple` row goes in the pair's log. The level keeps counting to 100 as "bond". Profiles show "💞 With @name" (a talking pair shows "💬 Talking to @name") unless the player turns `profiles.show_relationship` off (default on) in the Family tab. `get_public_profile` gained `relationship` and `love_open`.
5. **Dates** `love_date_invite(date, rel?)` then `love_date_respond(invite, accept)`. `love_dates` rows: place (a real `locations` id, or empty = on the phone), `cost_each`, `fun_gain`, `social_gain`, `bond_points`, `cooldown_hours` (per pair per date), `min_status` (`talking` or `couple`). The inviter must stand at the place when inviting; **both** must be there when the partner accepts (and neither jailed, in hospital or travelling). On accept each pays `cost_each` (ledger `love_date`, a sink, all or nothing: either of them short of money refuses the whole date), each gets Fun and Social (`bl_adjust_needs`), the pair gets `bond_points` (inside the daily cap; with no room left the date still happens and says "bond capped for today"). An invite waits `love.date_invite_expire_minutes` (30); one pending invite per pair; expiry is lazy.
6. **Break-up** `love_breakup(rel?)`: either partner, any time. Status `ended` with `ended_at` and `ended_by`, history kept, pending date invites cancelled, the partner told kindly. Both are blocked from asking each other for `love.breakup_cooldown_days` (3) and from asking anybody for `love.breakup_global_cooldown_hours` (24).
7. **Safety.** `love_report(target, reason)` (needs an ask or a relationship between the two; one open report per pair; `love.report_daily_cap` 5 a day; text cleaned, max 300) lists in Admin -> Love; the app offers "Also block them" (the existing `chat_block`). `love.enabled` is the kill switch (existing couples are kept). Flirt lines and date names are admin data, refused by a trigger when the chat banned-words list would mask them, and have length checks. No explicit content anywhere.

## Settings (Admin -> Settings -> Family & love)
`love.enabled, love.min_account_days, love.max_partners, love.asks_per_day, love.decline_cooldown_days, love.ask_expire_hours, love.flirt_daily_cap, love.flirt_cooldown_minutes, love.decay_after_days, love.decay_per_day, love.couple_level, love.date_invite_expire_minutes, love.breakup_cooldown_days, love.breakup_global_cooldown_hours, love.list_size (page size, max 50), love.online_minutes ("Online now" filter), love.poll_seconds (Family app refresh, 45), love.report_daily_cap`. Each has a label and description.

## Tables (RLS on, no grants)
| Table | What |
|---|---|
| `love_relationships` | one row per pair at a time (`user_a < user_b`): status talking / couple / ended, level, started_at, couple_at, ended_at, ended_by, asked_by, last_activity_at, decay_days. Unique live row per pair; partial indexes per user |
| `love_asks` | from_user, to_user, status pending / accepted / declined / expired / withdrawn, expires_at, responded_at, relationship_id |
| `love_flirts` | the menu (id, text, icon, points, cost, min_level, active, sort), 12 seeded PG-rated Pidgin lines |
| `love_dates` | the date menu, 12 seeded, real places: Oba Market, Ring Road, Oba's Palace, Emotan Statue, National Museum, Mama Osas Buka, Benin City Mall, Kada Plaza, Ogba Zoo & Nature Park, Kingdom Lounge (couples), a hotel getaway (couples), a phone date with no place |
| `love_log` | what happened between the two (started, flirt, date, couple, ended) with points and the game day (the daily cap sums it) |
| `love_date_invites` | one pending invite per pair |
| `love_reports` | reporter, reported, reason, status open / reviewed / dismissed |

## RPCs (all `security definer`, `set search_path = public`, granted to `authenticated` only)
Players: `love_overview()` (one read: me, incoming / outgoing asks, my relationships with log, flirt and date menus, the rules the UI quotes), `love_candidates(filter all|here|online, offset)` (paged, at most 50 a page, indexed, public info only: no money, no location), `love_set_open`, `love_set_show_relationship`, `love_ask`, `love_respond`, `love_withdraw`, `love_flirt`, `love_date_invite`, `love_date_respond`, `love_breakup`, `love_report`. Admin: `admin_love_overview`, `admin_love_report_set`, `admin_love_end` (audited). Private helpers `bl_love_*` are revoked from clients.

## Ledger and economy
Reasons `love_flirt` and `love_date`: pure sinks, never earned (`bl_earn_reasons()` drops them even if an admin lists them), labelled in `bl_ledger_label`, category "Shops, food and fun" in `bl_econ_category`. Nobody is ever paid for a flirt or a date.

## Alerts (events table, `bl_event`)
New kinds: `love_ask, love_accept, love_couple, love_flirt, love_date_invite, love_date, love_breakup`. Push goes through the existing `friends` category (`bl_push_enqueue`), links `/play?go=family:linkups|us|family`. The Alerts list shows an "Open Family" button; the Family icon shows a badge for unread `love_*` alerts.

## Performance
The Family app polls `love_overview()` only while it is open (`startPoller`: visible tab, not AFK, backs off when idle) every `love.poll_seconds`, and again at once when a `love_*` alert arrives. The Link-ups list is loaded on open, filter change or after an action, never polled. No Realtime subscription was added. Every list is capped (page at most 50, 20 asks, 15 log rows, 5 dates in "recent"). The list filter uses `profiles_love_open_idx` (partial, `last_seen desc`) and the partial relationship indexes. Decay only touches the pair being read or written.

## Admin
Settings -> Family & love; Content -> **Flirt lines** and **Dates** (text fields have length limits, shown in the form and checked in the table); **Love** page (open players, talking, couples, ended in 7 days, asks waiting, open reports, a report inbox with Reviewed / Dismiss and "End link-up", audited as `love_report_*` / `love_end`). Mute or ban a player in Players.

## Tests
`supabase/tests/love_test.sql` (rolled back; clock pinned to 10:00 Benin time, time travel with `bl.test_offset_seconds`): grants, RLS, private helpers, seeds, ledger reasons never earned · opt-in and the list · ask rules (self, block, age, one partner, daily cap, withdraw, decline cooldown, expiry) · accept · flirts (preset only, sink, cooldown, cap, locks) · couple at 30, public profile, bond to 100 · dates (both at the place, money all-or-nothing, needs, bond, cooldown, couple-only, jail, travel, expiry, shared cap) · lazy decay · break-up cooldowns · reports and admin · kill switch · no client access to the tables.

## Stage 2: kids (not built; the tables are ready)
Plan: `love_children(id, rel_id → love_relationships, parent_a, parent_b, name, born_at, stage, needs jsonb, ...)` with its own lazy care clock (same pattern as decay: compute on read, write on action). A couple at or above a bond level (a setting) can "try for a baby", a pregnancy timer runs lazily, both parents get alerts, and care actions (feed, school fees) are money sinks with new ledger reasons. The relationship id, the log (`love_log.kind` gets `birth`, `care`) and the Family tab ("Kids: coming soon" placeholder) are where it plugs in. Break-up rules for parents (custody, support) need an owner decision first.

## Decisions to confirm with the owner
- A couple does not fall back to "talking" when the level decays; it only loses bond down to the couple level.
- The Link-ups list shows a name, face, street cred, office title, gang tag, "Online" and "Same place". No wealth tier badge (it is derived from money).
- An ask counts toward the daily limit even when withdrawn, declined or expired.
- Dates need the inviter at the place when inviting and both at the place when accepting.
