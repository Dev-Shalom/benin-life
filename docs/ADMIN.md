# Admin dashboard (V1-7)

Files: `supabase/migrations/20261005001100_admin.sql`, `supabase/tests/admin_test.sql`, `src/admin/*` (lazy chunk; entry `AdminApp.tsx`), door + claim button in `src/screens/AdminRoute.tsx`. Open it at **`/admin`**, or in the game: Sim sheet → Settings → **Open admin panel** (shown only to admins).

## Becoming admin on the live site (https://benin-life.vercel.app)
**Option A, owner claim (easiest):**
1. Sign up / log in on the site with **dev.shalom1@gmail.com** or **code.devshalom@gmail.com** and finish creating your Sim (choose a home).
2. Go to `https://benin-life.vercel.app/admin`. You see "Admins only".
3. Press **"I'm the owner: claim admin"**. The page switches to the dashboard.
4. Recommended: in Settings → Admin, clear **Owner emails** (`admin.bootstrap_emails`) once every owner is admin, so nobody else can ever use the list.

The list is in `game_config` but **hidden from players** (RLS hides every `admin.*` key; only admins read it through `admin_config_list`). A claim is logged in the Audit log.
Note: if email confirmation is off on the Supabase project, whoever registers an email first owns it. Claim soon after launch (or create the accounts first), then clear the list.

**Option B, SQL editor:** Supabase dashboard → project `twwttirvesbwjvzjmenp` → SQL Editor:
```sql
update profiles set is_admin = true where username = '<your username>';
```

## Sections
| Section | What you can do |
|---|---|
| **Overview** | Online now, players / new today, money in the game (cash + bank), money made and spent today, chat messages today, pending reports; money today by reason (in vs out bars), origins split, jobs per track, richest 10. Auto-refreshes every 30 s. "Today" starts at midnight WAT. |
| **Settings** | Every `game_config` value grouped by category, with a search box. Number/percent/naira/minutes get a slider (when the range is sensible) plus an exact input with min–max; on/off gets a switch; text gets an input; `origin.force_next` gets tier chips. Changed rows turn amber with **Save** / **Undo**; a dark bar offers **Save all** (all-or-nothing). "↺ Back to …" puts back the value from before the last change. "⭐ Most used" holds the important knobs. |
| **Content** | Place zones / Zone actions / Mood lines (L2 interiors, docs/PLACES.md), People (NPCs) and Crowd profiles (L3: named background people with role, look, English + Pidgin lines, place types / place ids, zone, headliner; how many people per place type × hour band × all/weekday/weekend, people count inline; docs/PLACES.md "L3 crowds"), Homes, Furniture (3D kind, slot, activities it hosts, rest %), Starter furniture (origin + optional home → pieces, see docs/HUD_HOME.md), Traits, Dreams, Careers (track → levels with pay, shift minutes, XP and XP-to-next editable right in the list; tap a level for requirements/effects/perks JSON; Add level), Items (price inline; where sold, effects, resale; P1 vehicles: G-Wagon, GLE 63 Coupe, Urus, Cybertruck, Escalade, C300, new Camry, Bajaj Boxer, bicycle, all sold at the three dealers and editable here), Activities (cost and minutes inline), Places (an **Active** on/off switch on every row: off = hidden from players, see docs/PLACES.md "Soft launch"; **Opens at / Closes at** as time inputs, e.g. 21:00 → 05:00, both blank = always open, validated: set both or neither and they must differ; risk inline; night ×, CCTV, keke, congestion, actions), Events (L4, docs/EVENTS.md: matches, club nights, market days, owambe, premieres, pool parties; weekly weekday + times in Benin time or one-off start / end; ticket price inline, 0 = free; capacity; perks; an Active switch per row; events at hidden places never show), Origins (copy + perks), Banned chat words. Activities also have **Needs event** (an event kind or id) for event-only cards. No deletes: switch rows **Active** off instead (items: empty "Sold at" takes them off sale). |
| **Players** | Search by name or email; tap a player for balances, email, place, job, recent money and admin history. Give/take cash or bank (with a note the player sees; the amount takes shorthand like 500K, 2.5M, 5B, 1T, shows a live "= ₦5,000,000,000 (₦5B)" preview, has +1M/+1B/+1T quick adds, and asks for confirmation at ₦1B and up; one grant may move at most `admin.grant_max`, default ₦1Q, and no balance may pass ₦9Q), mute chat (15 min, 1 h, 1 day, 7 days, unmute), set origin (optionally with starter money/items), ban/unban and make/remove admin (two-tap confirm). |
| **Chat** | Reported messages with reasons and reporters; Hide / Unhide; mute the author. |
| **Audit** | Every config change (old → new, who; "system" = the game itself) and every admin action. Config entries have **↺ Restore old**. |

Phones get a bottom tab bar and full-screen detail panes; desktops get a sidebar and a list + detail two-pane layout.

## Important knobs
| Key | What it does |
|---|---|
| `time.real_seconds_per_game_minute` | Activity, sleep, jail and hospital speed. 0.75 = an 8-hour sleep takes 6 real minutes. Lower = faster. |
| `origin.nepo_pct` | % chance a new player is a Nepo baby (the rest are LAPO babies). |
| `origin.force_next` | The very next new account gets this origin, then the game clears it (logged as "system"). |
| `origin.lapo.*`, `origin.nepo.*` (start_cash, start_bank, allowance_daily, items, career_head_start) | What each origin starts with. Start cash can also come from the chosen home (Content → Homes → start cash per origin). |
| `rent.enabled` | Weekly rent on/off. Turning it back on rolls overdue rent days forward (no back-charge). |
| `crime.npc_base_pct` / `crime.npc_max_pct` | Street robbery base chance and cap. Per-place risk is in Content → Places. |
| `career.pay_mult` / `career.max_shifts_per_game_day` | Pay multiplier for every job / shifts per game day. Per-level pay is in Content → Careers. |
| `pos.fee_pct`, `bank.transfer_fee`, `bank.transfer_daily_limit` | PoS charge and phone transfer fee / daily limit. |
| `chat.enabled` | Location chat on/off for everyone. |
| `admin.bootstrap_emails` | Emails allowed to press "claim admin". Hidden from players. |
| `life.welcome_enabled` | Welcome-back screen (house, Sim, money, Continue / New life / Log out) on/off. Category "Welcome back & new life". |
| `life.welcome_after_minutes` | In the same tab, the welcome-back screen shows again after this many real minutes away (default 30). A new tab always shows it once. |
| `life.restart_enabled` | Players may start a **New life** (default on): the old Sim is archived in `profile_archive`, the account stays, the creator runs again (origin roll, `origin.force_next` applies). Audited as `life_restart`. |
| `sim.walk_speed` | (M2, category "Sim movement") How fast the Sim walks at home in trousers, m/s (default 1.9, range 0.5–4). Stride and step rate follow, so the feet never slide. |
| `sim.robe_speed_mult` | Walk speed in a long robe / wrapper / maxi as a share of `sim.walk_speed` (default 0.7; skirts sit halfway). |
| `sim.tired_slowdown` | How much slower a very tired Sim walks (default 0.18 = 18 % at full tiredness). |
| `action.queue_max` | (M2, Action timing) How many tasks a player can line up, the running one included (default **7** since P1, range 1–20; the P1 migration only moved it from 5 to 7 where it was still the old default). The HUD shows the running pill plus at most 2 queue circles ("+N" for the rest). |
| `home.walk_max_share_pct` | Not used since M2 (the Sim always walks first, the action starts on arrival). Kept for older clients. |
| `life.restart_cooldown_hours` | Hours a player must wait between new lives (default 0 = no wait). |
| `places.hours_enabled` | (L2, category "places") Opening hours on/off. On: places with hours (clubs 9 PM – 5 AM, Kada Cinemas 10 AM – midnight, Benin City Mall 9 AM – 10 PM, Ogba Zoo 8 AM – 6 PM) refuse actions and purchases while closed and show "Opens 9 PM". Hours per place: Content → Places → Opens at / Closes at. |
| `places.soft_launch_seeded` | (F1) One-shot flag. The soft-launch migration hid every club except 360 Signature the first time it ran and set this to true, so a later re-run never overrides your choices. Leave it on; switch places on/off in Content → Places → Active (audited like every row edit). |
| `places.mood_seconds` | Seconds between mood lines on the place card (default 7). Lines: Content → Mood lines. |
| `places.npc_per_zone` | Only a fallback since L3: background people per zone when the named-people call fails (default 2). Who is there now comes from Content → People (NPCs) and Crowd profiles. |
| `crowd.max_visible` | Most people drawn inside a place, real players first (default 10, max 30). The People count still shows everyone; the rest show as "+N more here". Lower it for very weak phones. |
| `crowd.npc_list_max` | (L3) Most named background people returned per place (People list + 3D, default 30, max 60). The People count still uses the full crowd-profile number. |
| `crowd.rigs_high` | (L3) How many of the nearest people get the full 3D avatar (instead of a simple figure) at Graphics High (default **6** since P1, max 8; moved from 4 only where untouched). Each costs 1 draw call and ~1.1k triangles. |
| `crowd.rigs_low` | (L3) Same at Graphics Low (default 2). |
| `crowd.chatter_seconds` | (L3) Average seconds between background people saying one of their lines as a speech bubble (default 22; 0 = never). Tapping a person always works. |
| `cars.bank_first` | Buying a car at a dealer takes the bank balance first, then cash (default on; cars cost millions). |
| `travel.bicycle.*`, `travel.motorcycle.*` | (P1, category travel) Own bicycle / motorcycle when the player has no car: speed (12 / 35 km/h), base cost and cost per km (bicycle free; motorcycle ₦40/km fuel). The bicycle ignores traffic; the motorcycle feels about a third of it. The "Your own …" option still uses mode `car` and its robbery risk. |
| `places.p1_people_seeded` | (P1) One-shot flag: the P1 migration raised the empty all-day crowd profiles (staff on duty) and opened the Tokunbo Lot's luxury corner once. Leave it on. |
| `hype.enabled` | (P2, category "hype") The club hype man announces big spends (banner, bubble over him, chat line, Doremi stinger) and the biggest go app-wide. Off = silent. |
| `hype.cooldown_s` | At most one announcement per player in this many seconds (default 30). The spend still goes through; "Shut down the club" always announces in the club. |
| `hype.global_min` | Spends at or above this (default ₦500,000) also show as a slim ticker to everyone in the game (~6 s). |
| `hype.global_cooldown_s` | At most one app-wide ticker in this many seconds (default 90), so the screen never floods. |
| `hype.bottle_window_s` | Bottles one player buys in this window (default 300 s) count up in one line ("E don pop 3 bottles"). |
| `hype.shutdown_cost` | Price of "Shut down the club" (default ₦2,000,000, cash). The card price follows. |
| `hype.shutdown_cred` | Street cred for shutting down the club (default 25). |
| `hype.round_fun` / `hype.round_social` | What every other player in the club gets from the round (default +10 fun / +8 social). |
| `hype.retention_hours` | Announcements older than this are cleaned up (default 24). |
| `music.club_track_url` | (P2, category "music") Empty (default) = the game's own synthesized amapiano groove in clubs. Set a URL to an audio file you hold the rights to and clubs loop it instead (Music setting / mute still apply). |
| `events.banner_enabled` | (L4, category "events") The slim top banner for LIVE events and ones starting soon (tap opens the place's sheet). Off = no banner; "On today", pin badges and event cards still work. |
| `events.banner_lead_hours` | Upcoming events show in the banner (and in "On today" even when they start after midnight) this many hours before they start (default 3, 0–24). |

Changes go live at once: `game_config` is in the realtime publication and `src/lib/config.ts` updates every client on each change (and reloads after a reconnect). The MC's announcement lines are in **Content → Hype lines** (P2: kind, club line, ticker line; placeholders {name} {place} {count} {bottles} {amount}). Content tables are read fresh by the game's RPCs (e.g. a new item price shows in the shop on the next open).

## Security
- Every admin RPC starts with `bl_admin_guard()` → `bl_is_admin()` (is_admin and not banned). The `/admin` route check is only a door. Helpers (`bl_admin_*`) are revoked from clients; RPCs are revoked from `anon`.
- `admin_row_upsert` only accepts whitelisted tables and columns with type checks (plus place/origin id checks); everything else is refused before any SQL runs. Table and column names are quoted with `format('%I')`; values go through `jsonb_populate_record`.
- `admin_config_set` validates the kind and min/max; the existing `game_config` triggers (epoch, force_next, arrival place, rent switch) still run.
- You can't ban yourself, and you can't remove your own admin if you're the last admin.
- Writes are audited: config in `config_audit`, the rest in `admin_audit` (`row_insert`/`row_update`, `grant_money`, `ban`/`unban`, `mute`/`unmute`, `make_admin`/`remove_admin`, `set_origin`, `chat_hide`/`chat_unhide`, `admin_claim`).

## Tests
`bash scripts/sql-test.sh -- supabase/tests/admin_test.sql` (8 groups): privileges, admin.* hidden from players/anon, 17 RPCs refuse non-admins, admin_claim (listed / unlisted / no profile / banned), config kinds + ranges + audit + triggers + set_many atomic + revert, table whitelist/types/inserts/soft-disable, players (search, grant/take ledger, ₦1T grant + exact balance math, grant caps, bl_naira/bl_naira_short formatting, ban, mute, admin toggles, last-admin guard, banned admin locked out, set origin), stats/audit list/chat reports.
