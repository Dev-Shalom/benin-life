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
| **Content** | Homes, Furniture (3D kind, slot, activities it hosts, rest %), Starter furniture (origin + optional home → pieces, see docs/HUD_HOME.md), Traits, Dreams, Careers (track → levels with pay, shift minutes, XP and XP-to-next editable right in the list; tap a level for requirements/effects/perks JSON; Add level), Items (price inline; where sold, effects, resale), Activities (cost and minutes inline), Places (risk inline; night ×, CCTV, keke, congestion, actions), Origins (copy + perks), Banned chat words. No deletes: switch rows **Active** off instead (items: empty "Sold at" takes them off sale). |
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
| `life.restart_cooldown_hours` | Hours a player must wait between new lives (default 0 = no wait). |

Changes go live at once: `game_config` is in the realtime publication and `src/lib/config.ts` updates every client on each change (and reloads after a reconnect). Content tables are read fresh by the game's RPCs (e.g. a new item price shows in the shop on the next open).

## Security
- Every admin RPC starts with `bl_admin_guard()` → `bl_is_admin()` (is_admin and not banned). The `/admin` route check is only a door. Helpers (`bl_admin_*`) are revoked from clients; RPCs are revoked from `anon`.
- `admin_row_upsert` only accepts whitelisted tables and columns with type checks (plus place/origin id checks); everything else is refused before any SQL runs. Table and column names are quoted with `format('%I')`; values go through `jsonb_populate_record`.
- `admin_config_set` validates the kind and min/max; the existing `game_config` triggers (epoch, force_next, arrival place, rent switch) still run.
- You can't ban yourself, and you can't remove your own admin if you're the last admin.
- Writes are audited: config in `config_audit`, the rest in `admin_audit` (`row_insert`/`row_update`, `grant_money`, `ban`/`unban`, `mute`/`unmute`, `make_admin`/`remove_admin`, `set_origin`, `chat_hide`/`chat_unhide`, `admin_claim`).

## Tests
`bash scripts/sql-test.sh -- supabase/tests/admin_test.sql` (8 groups): privileges, admin.* hidden from players/anon, 17 RPCs refuse non-admins, admin_claim (listed / unlisted / no profile / banned), config kinds + ranges + audit + triggers + set_many atomic + revert, table whitelist/types/inserts/soft-disable, players (search, grant/take ledger, ₦1T grant + exact balance math, grant caps, bl_naira/bl_naira_short formatting, ban, mute, admin toggles, last-admin guard, banned admin locked out, set origin), stats/audit list/chat reports.
