# Disk IO: what was draining the budget and what was fixed (2026-10-19)

Supabase emailed the owner: the production project is depleting its **Disk IO budget**. When the budget is gone the
database is throttled (slow requests, then timeouts). This page says what we found in the code, what the migration
`supabase/migrations/20261019000600_disk_io.sql` and the client changes fix, what was measured, and what the owner
does in the Supabase dashboard.

No production access was used. Everything below was measured on a local copy: 300 players, 300k ledger rows, 120k
alerts, 30k chat rows, then a scripted session of the polled RPCs with a simulated clock.

## What was found (biggest first)

| # | Source | Where | Why it costs disk IO |
|---|---|---|---|
| 1 | **The heartbeat rewrites a wide `profiles` row for every online player every minute** | `get_my_state()` (every 60 s per player, plus after every action) | `last_seen` was part of **two indexes** (`profiles_online_idx`, `profiles_location_seen_idx`). An UPDATE that changes an indexed column cannot be a HOT update: every heartbeat wrote a new heap tuple **and two index entries**, left a dead tuple, wrote WAL, and the table and indexes bloated. All other profile updates (cash, needs ...) were already HOT; this one write was the exception and the most frequent write in the game. |
| 2 | Presence readers | `world_counts()` (every player, every 60 s), `players_online`, `players_here`, `players_here_ids` | `world_counts` hashed **every private-home location row** (one per player) on every call: O(players) work per call, O(players squared) overall. |
| 3 | `billboard_list()` sweep | every client, every 5 min | ran `DELETE FROM admin_notifications ...` and `DELETE FROM billboard_counter_log ...` on **every call**, both with no usable index (full table scans, growing tables). |
| 4 | `billboard_track()` | every player with a billboard on the map, every minute | one counter-log upsert + one UPDATE per seen ad (hot rows shared by all players) per minute per player. |
| 5 | "Settle on read" that locks or writes when nothing is due | `business_mine()` (30 s poll while the Business app is open) settled every owned business on every poll (`SELECT ... FOR UPDATE` + UPDATE of `settled_at`); `yahoo_group_status()` / `bl_yahoo_group_tick` locked the group row (`FOR UPDATE`, which writes the tuple) on every 5 s poll | A row lock is a write (xmax + WAL). |
| 6 | Unbounded growth | `events`, `hustle_runs`, `yahoo_runs`, `money_drops`/`money_drop_picks`, `business_log`, `pol_campaign_log`, `house_interactions`, `shrine_notices`; `place_announcements` and the push log only cleaned on some paths (push log purge was one unbounded DELETE) | bigger tables and indexes = more pages to vacuum, cache and checkpoint. |
| 7 | Poll intervals | see the table below | steady background reads from every open tab, also for players who walked away. |

### What was checked and found fine (no change needed)
* **Triggers**: every `bl_chal_*` trigger already has a column list and/or `WHEN` clause, and exits through
  `bl_chal_open()` which is an indexed lookup (`player_challenges_open_idx`). The `profiles` triggers are all
  `UPDATE OF <columns>` with `WHEN` clauses, so the heartbeat fires none of them.
* **Settle-on-read** for skills, school, challenges, politics (`bl_pol_tick`), crews (`bl_crew_*`), market expiry,
  weekly settles, the crime stale-case closer: all are guarded by `WHERE` conditions, so a poll with nothing due
  writes nothing (verified: zero tuples written on the 2nd and later call for every status RPC).
* **Indexes** on the hot queries: `ledger (user_id, created_at desc)`, `chat_messages (location_id, id desc)`,
  `events (user_id, id desc)`, `push_outbox` due/status partial indexes, `player_messages` conversation and unread
  partial index, `market_listings` browse/expiry, `player_challenges` open partial index, `player_house_upgrades`
  open partial index. EXPLAIN on the populated copy: index scans everywhere, **no sequential scan on ledger, chat or
  events** during the whole session. The only seq scans on growing tables were the two billboard deletes (3) and the
  private-home hash in `world_counts` (2).
* **Heartbeat throttle** already existed (`time.last_seen_throttle_real_seconds`, 30 s) but equalled the heartbeat
  period, so it never saved a write. It is now 55 s.
* **E5 / growth activity tracking** (`player_activity_days`, `feature_events`): not in this repo yet. When that work
  lands it must write at most once per player per day (or per minute) with `INSERT ... ON CONFLICT DO NOTHING` /
  `UPDATE ... WHERE last_write < now() - interval '60 seconds'`, never from a polled RPC unconditionally.
* **Realtime publication** (`supabase_realtime`): `game_config`, `profiles`, `events`, `chat_messages`,
  `player_furniture`, `player_house_furniture`, `place_announcements`, `player_messages`, `house_room_positions`,
  `money_drops`. Every one is subscribed to by the client, so nothing was removed. See "Realtime" below.

## What was fixed

### Database (one migration, idempotent: `20261019000600_disk_io.sql`)
1. **HOT heartbeat.** New column `profiles.seen_bucket` (= `last_seen` rounded down to 5 minutes, kept by a trigger that
   only fires when `last_seen` is written). The two `last_seen` indexes are replaced by
   `profiles_online_bucket_idx` and `profiles_location_bucket_idx` on `seen_bucket`. The bucket changes once every
   5 minutes, so about 4 of 5 heartbeats are now **HOT updates with no index writes**. `world_counts`, `players_online`,
   `players_here` and `players_here_ids` filter on the bucket first (index) and on the exact `last_seen` second, so
   results are unchanged. `profiles` gets `fillfactor = 85` so HOT updates have room on the page.
2. **Heartbeat throttle 30 s -> 55 s** (only if the owner had not changed it): refreshes after player actions inside a
   minute no longer rewrite the row. The client heartbeat is still 60 s, so players stay "online" (friends window is
   120 s; the client's "here" freshness was raised to 130 s to match).
3. `world_counts` uses an anti-join on the location instead of a hash of every private home.
4. **No lock without work**: `bl_yahoo_group_tick` only takes `FOR UPDATE` when the group is due; `business_mine`
   settles a business at most every 3 minutes (businesses earn per hour; `collect`, `work` etc. still settle fully).
5. **Billboards**: the sweep no longer scans two tables on every call; `billboard_track` accepts up to 50 views per
   ad per batch and one batch per 4 minutes (the client sends every 5 minutes instead of every minute).
6. **Retention, hourly, 5,000 rows per table per run, never the ledger or payments**
   (`bl_io_housekeeping()`, claimed through a row in `io_housekeeping` so only one request per hour does it; it runs
   from the existing lazy path `bl_billboard_sweep`, i.e. the first `billboard_list` after the hour). If a run hits the
   5,000 limit it comes back in 5 minutes instead of an hour, so a backlog drains without long requests.
   Deleted: `events` older than `io.logs_keep_days` (30), `hustle_runs` / `yahoo_runs` finished and older than
   `io.runs_keep_days` (90), settled `money_drops` (their picks cascade) / `business_log` / `pol_campaign_log` /
   `house_interactions` / `shrine_notices` older than 30 days, `place_announcements` past `hype.retention_hours`,
   `admin_notifications` older than 45 days, `billboard_counter_log` older than 2 days. Both keys are editable in
   Admin -> Settings. **Never touched:** `ledger`, `payments`, `receipts`, `tax_records`, `yahoo_ledger`,
   `invest_log`, `admin_audit`, `config_audit`. Chat, crew chat, push log and error reports already had retention.
7. `bl_push_tick` deletes the old push log in batches of 5,000 instead of one unbounded DELETE.

### Client
* New `src/lib/activity.ts`: `canPoll()` is true only for a **visible tab and a player who touched the game in the last
  10 minutes**; `idleFactor()` doubles poll periods after 2 idle minutes; `onResume()` catches up the moment an AFK
  player returns.
* `startPoller()` (used by chat, house room, presence, hype, poll-mode state/events) and the heartbeat now use it, and
  so do the hand-written intervals: presence `world_counts`, crew, Yahoo group, politics, shrine, alerts reload,
  billboards, daily, challenges, travel quote, place sheet, Business app, club music.
* Intervals: map counts (`world_counts`) 60 s -> 90 s, chat closed 30 s -> 60 s (it only feeds the unread dot), Yahoo group and crew run 5 s -> 8 s, politics
  120 s -> 180 s, house room 4 s -> 5 s (alone 20 s -> 30 s), poll-mode state 17.5 s -> 20 s (x2 when idle), travel
  quote and place sheet 60 s -> 90 s, Business app 30 s -> 60 s, billboard views batched every 5 min instead of 1 min.
* Realtime fallback (`src/lib/realtime.ts`) was reviewed: when realtime is healthy the chat, state, events and
  place pollers are not started at all (`bindRealtime` starts exactly one of channel or poller). The only things that
  poll while live are the 60 s heartbeat (`get_my_state`) and `world_counts` (map counts), by design.

## Measured (local copy, same scripted session before and after)
Session: 100 players x 40 simulated minutes = 4,000 player-minutes. Each player-minute: heartbeat `get_my_state`,
`world_counts`; every 2 min a politics poll; every 5 min billboard / daily / challenge / shrine / market / alerts
polls; a third of players also act once a minute (extra `get_my_state`); a fifth have the phone open (friends,
business, upgrades, skills, hustle, yahoo, crew every 3 min). The clock is simulated, so time-based settles happen.

| Metric (same 4,000 player-minutes) | Before | After | Change |
|---|---|---|---|
| `profiles` UPDATEs (the heartbeat is one per player-minute by design) | 4,293 | 4,260 | same count |
| ... of which HOT (no index writes) | 260 (6 %) | 3,358 (79 %) | **13x more HOT** |
| Index entries written per heartbeat (`profiles`) | 2 | 0.4 | -80 % |
| `profiles` index size after the session | 65 pages | 20 pages | -69 % (no index bloat) |
| WAL written in total (`pg_stat_wal`) | 3.85 MB | 1.91 MB | **-50 %** |
| WAL records | 31,195 | 17,872 | -43 % |
| Full-page images in the WAL (first touch of a page after a checkpoint) | 346 | 183 | -47 % |
| `update profiles set last_seen` WAL per call | 511 B | 266 B | -48 % |
| ... buffers dirtied by that statement | 82 | 36 | -56 % |
| `get_my_state()` total WAL (it contains that UPDATE) | 2.12 MB | 1.06 MB | -50 % |
| `billboard_list()`: full scans of `billboard_counter_log` (800 calls) | 800 | 1 (the hourly cleanup) | **-99.9 %** |
| `billboard_list()`: scans of `admin_notifications` (800 calls) | 1,600 | 801 | -50 % (the remaining one is the "pending push" EXISTS, which uses the partial index once the table has rows; empty here) |
| `business_mine()` polled every 30 s for 10 min with one business: `businesses` UPDATEs | 20 | 3 | **-85 %** |
| Polled status RPCs that write on a repeat call with nothing due | none found | none | already guarded (checked 40 RPCs, with the clock advanced between calls) |
| Sequential scans on `ledger`, `chat_messages`, `events`, `push_outbox`, `player_messages` | 0 | 0 | indexes were already right |

Notes on reading this:
* The test database is tiny, so most WAL here is full-page images (8 KB each, written the first time a page changes
  after a checkpoint). On production the saving shows up as fewer index pages dirtied per minute and less
  autovacuum work on `profiles`: with 1,000 players online that is about 1,000 heartbeat writes a minute, and they
  went from ~2 index entries + a dead tuple each to HOT updates that are cleaned up inside the page.
* HOT updates are pruned by whichever query next reads the page, so a few reads now write a little WAL
  (`world_counts` 22 KB -> 32 KB over the session). That is far smaller than what it saved on the write side.
* `world_counts` reads more buffers on a 300-player database (3 per online player instead of one hash over the
  homes); the planner switches to a hash anti-join when the table is large, and the old form got worse with every
  player ever created (one home row each). It is not disk IO either way (all cached).
* Idle players: before, a visible tab left alone kept polling forever; now every poller stops after 10 minutes without
  input and halves its rate after 2, so an abandoned tab costs 0 requests and, because the heartbeat stops too, it no
  longer keeps rewriting its profile row.

## Realtime (recommendation, not changed)
* `profiles` is the only big, frequently updated table in `supabase_realtime`. Every heartbeat UPDATE is decoded from
  the WAL by Realtime even though the client ignores it (the handler skips the echo of its own `last_seen` bump). The
  fix above cuts the WAL per heartbeat, but the decoding still happens. The proper next step (not done: it changes
  how the client learns about changes) is to publish only the columns the client needs, or move the per-player state
  feed to Broadcast.
* `money_drops` is updated on every pick, and `house_room_positions` on every house move in poll mode: both are small
  and short-lived but cost WAL during parties. They are needed by the client.
* To look: Supabase -> Database -> Publications -> `supabase_realtime`.

## Owner steps in the Supabase dashboard
1. **Deploy**: push the migration (`supabase db push`, or run the SQL file in the SQL editor) and deploy the client
   build. Then run once in the SQL editor: `vacuum (analyze) public.profiles;`.
2. **See Disk IO**: project -> **Reports -> Database**: charts "Disk IO % consumed", "Disk IOPS" and "Disk throughput"
   (and Settings -> Compute and Disk for the plan limits). The email is about the *% budget consumed* chart: on a
   Micro/Small instance the burst budget refills slowly, so a good result is the line staying flat or falling for a
   day after the deploy. Compare the same hours before and after.
3. **Find the top queries**: project -> **Database -> Query Performance** (Advisors). Sort by *Total time* and by
   *Rows read*; open a row to see the SQL and its calls. For the IO view, run this in the SQL editor
   (`pg_stat_statements` is enabled on Supabase):
   ```sql
   -- most disk reads (blocks read from disk, 8 KB each)
   select calls, shared_blks_read, shared_blks_dirtied, round(total_exec_time) as ms, left(query, 100) as q
     from pg_stat_statements order by shared_blks_read desc limit 15;
   -- most writes (blocks dirtied) and WAL
   select calls, shared_blks_dirtied, wal_bytes, left(query, 100) as q
     from pg_stat_statements order by wal_bytes desc limit 15;
   -- tables with the most updates, and how many were HOT (higher hot % = fewer index writes)
   select relname, n_tup_upd, n_tup_hot_upd, round(100.0 * n_tup_hot_upd / nullif(n_tup_upd, 0)) as hot_pct, n_dead_tup,
          seq_scan, idx_scan
     from pg_stat_user_tables order by n_tup_upd desc limit 15;
   -- growing tables
   select relname, pg_size_pretty(pg_total_relation_size(relid)) as size, n_live_tup
     from pg_stat_user_tables order by pg_total_relation_size(relid) desc limit 15;
   ```
   After the deploy, `profiles` should show a `hot_pct` near 80+ and `update profiles set last_seen ...` should drop
   out of the top of the WAL list. To measure from a clean baseline run `select pg_stat_statements_reset();` right
   after the deploy and look again after a few hours.
4. **Do you need a compute upgrade?** Not first. The Disk IO budget (baseline throughput/IOPS plus a daily burst
   allowance) scales with the compute size, and each size up roughly doubles the baseline (see
   https://supabase.com/docs/guides/platform/compute-and-disk for the current numbers). Deploy these fixes, watch
   Reports -> Database for 24-48 hours at a normal player count. Upgrade (Settings -> Compute and Disk, a short
   restart, do it off-peak) only if the Disk IO line still averages above about 50-60 % of the budget at normal load,
   or before a launch announcement (docs/SCALING.md already recommends Small for ~1,000 players online). A bigger
   instance also has more RAM for cache, so fewer reads reach the disk; it is the right second step, not the first.
   Do not buy extra disk IOPS before the query fixes are live.
5. Optional later: Settings -> Database -> check that the disk is not nearly full (autovacuum needs headroom), and
   in Settings -> Realtime keep `realtime.mode = auto`.

## Rules for new features (so this does not come back)
* A polled RPC must write nothing when nothing changed: guard with `WHERE`, `IS DISTINCT FROM`, a `next_due_at`
  column or an `EXISTS` check, and never `SELECT ... FOR UPDATE` before you know there is work.
* Never put a frequently written column in an index (it kills HOT). Index a coarse value instead.
* Every poller goes through `canPoll()` / `startPoller()`.
* Every append-only table gets a retention rule in `bl_io_housekeeping()` (ledger and payments excepted).
