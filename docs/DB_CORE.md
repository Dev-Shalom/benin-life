# DB Core reference (P1-DB)

Files: `supabase/migrations/20261004000100_core.sql` (schema, helpers, RPCs), `supabase/migrations/20261004000200_core_seed.sql` (locations, config, activities), `supabase/tests/core_test.sql`.

Test: `bash scripts/sql-test.sh supabase/migrations/20261004000100_core.sql supabase/migrations/20261004000200_core_seed.sql -- supabase/tests/core_test.sql`

## Tables & access
| table | client access |
|---|---|
| locations, game_config, items, activities | `select` for anon + authenticated |
| profiles, ledger, events, inventory | `select` own rows only (authenticated) |
| config_audit | `select` for admins only |

No client insert/update/delete on anything: privileges are revoked and there are no write policies, so every write goes through `security definer` RPCs. Realtime publication `supabase_realtime`: profiles, events, game_config.

## Helpers (internal; execute revoked from public/anon/authenticated, service_role keeps it)
| function | notes |
|---|---|
| `bl_now()` | `now()` + `bl.test_offset_seconds` |
| `bl_rand()` | `random()` or `bl.test_rand` |
| `bl_cfg(key)` / `bl_cfg_bool` / `bl_cfg_text` | raise if the key is missing |
| `bl_naira(n) -> text` | `₦12,345` |
| `bl_require_uid() -> uuid` | raises `Abeg login first` (hint `not_logged_in`) |
| `bl_location(id) -> locations` | raises `That place no dey for map o.` |
| `bl_me() -> profiles` | locks the caller's row, applies lazy needs decay, raises with hint `no_profile` / `banned` |
| `bl_decay_row(profiles, at) -> profiles` | pure decay in memory, no write |
| `bl_apply_needs(uid) -> profiles` | lazy decay persisted (locks row); idempotent |
| `bl_assert_free(profiles)` | raises (hint `jailed`, `hospitalized`, `traveling`, `busy`) |
| `bl_adjust_needs(uid, jsonb)` | applies decay first, then clamps each need to 0–100; ignores unknown keys |
| `bl_add_money(uid, 'cash'\|'bank', delta, reason, meta)` -> new balance | writes `ledger`; raises `Your money no reach, my guy.` (hint `insufficient_funds`) |
| `bl_event(uid, kind, title, body, data)` -> id | |
| `bl_jail(uid, game_min, reason)` -> until | extends any current sentence, **moves the player to `crime.jail_location`**, cancels travel and busy |
| `bl_hospitalize(uid, game_min, reason)` -> until | extends the stay, **moves the player to `crime.hospital_location`** unless they are already at a hospital-scene location, cancels travel and busy |
| `bl_set_busy(uid, game_min, label)` -> until | |
| `bl_is_admin()` | caller is admin and not banned |
| `bl_real_seconds(game_min)` | × `time.real_seconds_per_game_minute` |
| `bl_game_clock(at default bl_now())` -> GameClock json | |
| `bl_distance_km(from, to)`, `bl_traffic(from, to, at)` | travel math |
| `bl_street_robbery_chance(uid, loc, mode, traffic, at)` -> 0..1 | used by both `travel_quote.risk_pct` and the robbery roll |
| `bl_roll_street_robbery(uid, loc, mode, traffic)` -> jsonb or null | `{amount, injured, health_loss, location}`; takes the cash (ledger `street_robbery`), adds stress, may injure, and creates a `robbed` event |
| `bl_travel_quote(profiles, dest)` | shared by `travel_quote` and `travel_start` |

P2-CRIME: if you `create or replace` `bl_roll_street_robbery`, also replace `bl_street_robbery_chance` (same signature) so the UI's risk warning matches.

## RPCs (authenticated only)
`create_profile(p_username, p_gender, p_avatar)` -> GameState · `update_avatar(p_avatar)` (also syncs `gender` from `avatar.gender`) · `get_my_state()` -> GameState (read-mostly, see below) · `travel_quote(p_dest)` · `travel_start(p_dest, p_mode)` -> `{message, arrives_at, cost, game_minutes, real_seconds}` · `travel_arrive()` -> `{message, location, robbed?}` · `do_activity(p_activity)` -> `{message, busy_until, effects}` · `players_here(p_location)` -> jsonb array (max 50, excludes the caller, banned players and players on the road) · `get_public_profile(p_id)`.

`get_my_state().profile` is the full `profiles` row minus `banned, needs_updated_at, last_seen, travel_*`. Columns other owners add appear automatically. While a player is travelling, `location_id` stays on the origin until `travel_arrive`.

**Redefined later:** `20261005000200_origin.sql` (P1-ORIGIN) replaces `create_profile` (same signature/validation; starter pack now comes from the rolled origin tier) and `get_my_state` (adds an `origin` block). See `docs/ORIGIN.md`. Group 2 of `core_test.sql` pins `bl.test_rand = 0.99` while creating its players so they are always the default LAPO tier (its start-state asserts stay exact); it resets the setting afterwards.

**`get_my_state` does not write on every call.** `profiles` is realtime-published and the shell refreshes on every change to its own row, so a write on each call would loop forever. Needs decay is computed in memory (`bl_decay_row`); the next gameplay RPC persists it through `bl_me()`, and the result is the same because decay is path-independent. `last_seen` is re-saved only when it is older than `time.last_seen_throttle_real_seconds` (30 s), which is well inside the 3-minute presence window. **P2 owners:** do not add per-call writes to `get_my_state`, and do not write `profiles` from read-only RPCs.

## Formulas
- **Clock:** `game_minutes = floor(real_seconds_since clock.epoch × clock.game_minutes_per_real_minute / 60 + clock.start_hour_offset×60)` (multiplied before dividing, so there is no off-by-one rounding); `day = floor(gm/1440)+1`. Night means `hour ≥ night_start` or `hour < night_end`.
  - `clock.epoch` (text, default `2026-10-05T00:00:00Z`, the launch day) replaced the hard-coded 2026-01-01Z in `20261005000300_time_tuning.sql`. The client (`src/lib/clock.ts`) reads the same key with the same default. A `game_config` trigger rejects an epoch that does not parse.
  - The shift from 2026-01-01 is exactly 3324 game days, so the time of day did not move; only the day number reset. Keep any new epoch on an even UTC hour (2 real hours = 1 game day at 12×), or the time of day jumps.
  - Needs decay, travel, busy/jail/hospital and protection all use real timestamps, so the epoch only changes the day and hour labels and anything keyed on game day (the Papa allowance's `allowance_claimed_day`).
- **Needs decay:** `game_hours = real_seconds_elapsed × speed / 3600`. Each need drops by `rate × game_hours`, and stress rises by its rate. Health drops `needs.starve_health_per_hour` per game hour **after** hunger or energy first hits 0; this drop is computed exactly inside the elapsed window. Starvation alone never takes health below `needs.starve_health_floor`. Values are stored rounded to 4 dp.
- **Travel:** `km = dist/1000 × travel.city_km_across + remote_km(a) + remote_km(b)`. `cost = ceil((base_cost + per_km×km)/10)×10`. `traffic = avg(congestion) × rush_mult (hours [am_start,am_end) or [pm_start,pm_end)) × ramat_mult` (either end in `ikpoba_hill`/`aduwawa` and flyover closed); walking uses traffic 1. `game_minutes = max(1, ceil(km/speed×60×traffic))`; `real_seconds = max(travel.min_real_seconds, game_minutes × travel.real_seconds_per_game_minute)`. A mode is blocked when it is keke and either end is not `keke_ok`, when it is car and the player has no `items.category='vehicle'` in inventory, or when the cost is more than the player's cash. The fare is charged at `travel_start`. Traffic for the robbery roll uses the start time's hour.
- **Street robbery:** `p = npc_base_pct/100 × risk × (night ? night_risk_mult × crime.night_mult : 1) × max(0, 1+(traffic−1)×traffic_weight) × min(cash_factor_max, cash_factor_min + cash/cash_ref) × crime.mode_mult_<mode> × (1 − charm)`, capped at `npc_max_pct/100`. `p` is 0 while protected or when cash is 0. Charm counts while `charm_until` is null or in the future. Loss is `cash × U(loss_min_pct, loss_max_pct)/100`. Injury happens with probability `injury_pct`, and health then drops by `U(injury_health_min, injury_health_max)`. Stress always rises by `crime.robbery_stress`.
- **Activities:** the player must be at a location whose `scene ∈ activity.scenes`. For `home_only` activities the location must also be `home_location_id`. `night_only` activities need night. The cost is paid, effects apply **immediately** (need keys plus optional `street_cred`), and then the player is busy for `game_minutes` (× `time.real_seconds_per_game_minute`). `bl_set_busy` stamps `profiles.busy_started_at = bl_now()` with `busy_until` (`20261005000300_time_tuning.sql`), and get_my_state's profile exposes it so the busy banner can draw its progress ring. Rows written before that migration have `busy_started_at` null; the client then starts the ring when it first sees the timer.

## Config keys (seeded here)
- clock: `clock.epoch` "2026-10-05T00:00:00Z" (text), `clock.game_minutes_per_real_minute` 12, `clock.start_hour_offset` 6, `clock.night_start_hour` 20, `clock.night_end_hour` 6
- time: `time.real_seconds_per_game_minute` 0.75 (was 5; set by `20261005000300_time_tuning.sql` only while it still held 5, so an admin's value survives a re-run; an 8-hour sleep = 6 real minutes; it also drives jail and hospital timers), `time.presence_real_minutes` 3, `time.last_seen_throttle_real_seconds` 30
- needs: `needs.hunger_per_hour` 4, `needs.energy_per_hour` 3, `needs.hygiene_per_hour` 2.5, `needs.fun_per_hour` 2, `needs.social_per_hour` 1.5, `needs.stress_per_hour` 1, `needs.starve_health_per_hour` 2, `needs.starve_health_floor` 10
- start: `start.cash` 5000, `start.bank` 0, `start.need_level` 80, `start.health` 100, `start.stress` 10, `start.protection_real_minutes` 120, `start.home_location` "ekenwan_room", `start.housing` "face_me_ekenwan"
- travel: `travel.city_km_across` 18, `travel.real_seconds_per_game_minute` 1, `travel.min_real_seconds` 3, `travel.<walk|keke|bus|drop|car>.{speed_kmh,base_cost,per_km}`: walk 5/0/0, keke 18/150/100, bus 15/300/0, drop 25/500/250, car 30/0/120
- traffic: `traffic.rush_mult` 1.8, `traffic.rush_am_start` 7, `traffic.rush_am_end` 10, `traffic.rush_pm_start` 16, `traffic.rush_pm_end` 20, `traffic.ramat_mult` 1.6, `traffic.ramat_flyover_open` false
- crime: `crime.npc_base_pct` 6, `crime.npc_max_pct` 35, `crime.night_mult` 1, `crime.traffic_weight` 0.5, `crime.cash_ref` 20000, `crime.cash_factor_min` 0.3, `crime.cash_factor_max` 1.5, `crime.mode_mult_{walk,keke,bus,drop,car}` 1.4/1.0/0.8/0.7/0.6, `crime.loss_min_pct` 20, `crime.loss_max_pct` 60, `crime.injury_pct` 15, `crime.injury_health_min` 15, `crime.injury_health_max` 35, `crime.robbery_stress` 15, `crime.jail_location` "police_hq", `crime.hospital_location` "ubth"

## Activities seeded
sleep, nap, bathe, cook_home (all home_only) · owo_soup, banga_starch, black_soup, noodles_egg, pepper_soup (buka; pepper soup is also at clubs) · suya (street/motorpark) · gist_joint · watch_football · club_night (night_only, +1 street_cred) · lounge_chill · museum_tour · palace_visit · campus_stroll · bronze_casting · market_stroll · cyber_browse · salon_freshen · plane_spotting (22 in total).
