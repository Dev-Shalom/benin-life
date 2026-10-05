# Benin Life — Architecture & Build Contract

This file is the **binding contract** for every agent working on the repo. Read `docs/BRIEF.md` first for product intent.
If you need something another agent owns, code against the contract below — do not edit their files.

## 1. Stack
- Frontend: React 19 + TypeScript + Vite, react-router-dom v7, zustand. Plain CSS (tokens in `src/styles/tokens.css`). No UI framework.
- Backend: Supabase — Auth (email + password, no confirmation locally), Postgres (all game logic in `security definer` plpgsql RPCs), Realtime, Edge Functions (Deno) for payments only.
- Local dev: `npx supabase start` (Docker). DB container: `supabase_db_benin-life`. API: http://127.0.0.1:54321.
- Env (frontend): `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY` in `.env.local` (never committed).

## 2. Directory layout & ownership
```
docs/                         BRIEF, ARCHITECTURE (phase 0), others per owner
scripts/sql-test.sh           phase 0 — run migration(s)+test in a ROLLBACK transaction
supabase/migrations/
  20261004000100_core.sql               P1-DB
  20261004000200_core_seed.sql          P1-DB
  20261005000100_map_geo.sql            P1-MAP (location positions)
  20261005000200_origin.sql             P1-ORIGIN (LAPO/Nepo class roll — docs/ORIGIN.md)
  20261005000300_time_tuning.sql        P1-TIME
  20261005000400_creator.sql            R3a (traits, dreams, start homes, rent, origin overrides — docs/CREATOR.md)
  20261005000500_bladder.sql            R4 (bladder need, toilet/TV/radio activities, players_online — docs/HUD_HOME.md)
  20261004001000_economy.sql            P2-ECON
  20261004002000_finance_farm_health.sql P2-FIN
  20261004003000_crime_police.sql       P2-CRIME
  20261004004000_social.sql             P2-SOCIAL
  20261004005000_admin.sql              P2-ADMIN
  20261004006000_payments.sql           P2-PAY
supabase/tests/<owner>_test.sql         each owner
supabase/tests/_helpers.sql             phase 0
supabase/functions/                     P2-PAY only
src/lib/{supabase,api,types}.ts         phase 0 (append-only: you MAY add new exported types at the bottom of types.ts inside a section headed with your owner tag)
src/lib/{config,clock,pidgin,format}.ts P1-SHELL
src/state/                              P1-SHELL
src/styles/                             P1-SHELL
src/ui/                                 P1-SHELL (shared kit: Button, Sheet, Modal, NeedBar, Toast, Tabs, Spinner, Money)
src/screens/                            P1-SHELL
src/art/avatar/                         P1-AVATAR
src/art/map/                            P1-MAP
src/art/scenes/<SceneType>.tsx          P1-SCENES-A / P1-SCENES-B (see §7)
src/art/Scene.tsx                       phase 0 (dispatcher, do not edit)
src/panels/registry.ts                  phase 0 (do not edit)
src/panels/ActivitiesPanel.tsx          P1-SHELL
src/panels/{Jobs,Shop,Market,Housing,Inventory}Panel.tsx         P2-ECON
src/panels/{Bank,Pos,Loans,Esusu,Farm,Hospital,Babalawo}Panel.tsx P2-FIN
src/panels/{Police,Rob,Crimes}Panel.tsx                          P2-CRIME
src/panels/{Chat,Messages,Profile}Panel.tsx                      P2-SOCIAL
src/panels/{Wallet,Airport}Panel.tsx                             P2-PAY
src/api/<system>.ts                     each P2 owner (typed RPC wrappers); src/api/creator.ts = R3a
src/admin/                              P2-ADMIN (entry: src/admin/AdminApp.tsx default export)
```
Panels are discovered with `import.meta.glob`, so a missing panel file never breaks the build.

## 3. Server conventions (Postgres)
- All tables: RLS **enabled**. Clients get `select` only where listed; **all writes go through RPCs** (`security definer`, `set search_path = public`). Grant `execute` on RPCs to `authenticated`; revoke from `anon`/`public` (except catalog reads).
- Helper functions (prefixed `bl_`) are internal: `revoke execute ... from public, anon, authenticated`.
- RPC naming: snake_case verbs, e.g. `travel_start`, `bank_deposit`. Parameters prefixed `p_`.
- **Success** returns `jsonb` with at least `{"message": "<pidgin>"}` plus data. **Failure**: `raise exception '<pidgin message>' using errcode = 'P0001';` — the client shows `error.message` verbatim, so write it in Pidgin.
- Time: always use `bl_now()` (never `now()`), so tests can time-travel via `set local bl.test_offset_seconds = '600'`.
- Randomness: always use `bl_rand()` (never `random()`), so tests can force rolls via `set local bl.test_rand = '0.01'`.
- Config: read balance values with `bl_cfg(key) -> numeric`, `bl_cfg_bool(key)`, `bl_cfg_text(key)`. **Never hard-code a balance number** — add a `game_config` row in your migration (`insert ... on conflict (key) do nothing`).
  - `kind='percent'` values are stored 0–100 (divide by 100 in formulas).
- Money: only via `bl_add_money(p_uid, p_account 'cash'|'bank', p_delta bigint, p_reason text, p_meta jsonb default '{}')`, which writes the `ledger` and raises `'Your money no reach'` if it would go negative.
- Needs: `bl_adjust_needs(p_uid, p_delta jsonb)` e.g. `'{"hunger": 30, "energy": -10}'` (clamped 0–100).
- Status: `bl_jail(p_uid, p_game_minutes int, p_reason text)`, `bl_hospitalize(p_uid, p_game_minutes int, p_reason text)`, `bl_set_busy(p_uid, p_game_minutes int, p_label text)`.
- Guard at the top of every gameplay RPC: `v_me := bl_me();` (loads caller row FOR UPDATE, applies lazy needs decay, raises if not logged in / no profile / banned / **no home chosen yet** (hint `no_home`, R3a), then charges weekly rent if due and `rent.enabled`). then `perform bl_assert_free(v_me);` (raises if traveling, busy, jailed or hospitalized — skip for RPCs that must work while jailed, e.g. bail). Creator steps and avatar edits use `bl_me_any()` instead (same row lock and decay, without the home check and rent).
- Notify a player: `bl_event(p_uid, p_kind text, p_title text, p_body text, p_data jsonb default '{}')` → row in `events` (realtime-published).
- Admin check: `bl_is_admin() -> boolean`.
- Real-time duration of game minutes: `bl_real_seconds(p_game_minutes numeric) -> numeric` = minutes × `time.real_seconds_per_game_minute` (0.75 since P1-TIME: an 8-hour sleep lasts 6 real minutes, faster than the clock on purpose).

### Core tables (P1-DB) — other owners may `alter table ... add column if not exists` in their own migration, never drop/rename.
- `profiles` (id uuid pk → auth.users, username unique, gender, avatar jsonb, is_admin, banned, cash bigint, bank bigint, hunger/energy/hygiene/fun/social/health/stress numeric, needs_updated_at, location_id → locations, home_location_id, housing_id text, job_id text, job_level int, job_xp int, street_cred int, wanted int, travel_to, travel_mode, travel_started_at, travel_arrives_at, busy_until, busy_label, busy_started_at (P1-TIME), jailed_until, jail_reason, hospitalized_until, protected_until, charm_strength numeric 0–1, charm_until, last_seen, created_at; P1-ORIGIN adds origin text → origin_tiers default 'lapo', allowance_claimed_day int)
- `locations` (id text pk, name, district, scene, blurb, risk numeric 0–1, night_risk_mult, cctv bool, keke_ok bool, congestion numeric, remote_km numeric, x, y numeric (map space 0–1000), actions text[], sort int)
- `game_config` (key pk, value jsonb, category, label, description, kind, min, max, updated_at, updated_by)
- `config_audit` (id, admin_id, key, old_value, new_value, created_at) — written by admin RPCs (P2-ADMIN)
- `ledger` (id bigserial, user_id, account, delta, balance_after, reason, meta jsonb, created_at)
- `events` (id bigserial, user_id, kind, title, body, data jsonb, read bool, created_at)
- `items` (id text pk, name, category, price bigint, description, effects jsonb, sold_at text[] (location ids), sellable bool, resale_pct numeric, icon text, sort int) — rows seeded by P2-ECON (P2-FIN may add seeds/charms)
- `inventory` (user_id, item_id, qty, primary key(user_id,item_id))
- `activities` (id text pk, name, scenes text[] (which location scenes offer it), home_only bool, cost bigint, game_minutes int, effects jsonb, night_only bool, sort int)
- R3a (`docs/CREATOR.md`): `traits` (id, name, emoji, description, effects jsonb, sort, active), `dreams` (id, name, emoji, description, goal jsonb, sort, active), `start_homes` (id, name, emoji, location_id, district, tag, description, weekly_rent, start_cash jsonb per origin, allowed_origins text[], locked_quip, housing_id, sort, active) — select for anon+authenticated; `admin_audit` (admin-only select). `profiles` adds `traits text[]`, `dream`, `start_home`, `home_chosen bool` (default true), `weekly_rent`, `rent_due_at`, `rent_owed`. Trait `effects.decay` multipliers are applied in `bl_decay_row`.
- R4 (`docs/HUD_HOME.md`): `profiles.bladder` numeric default 100 (100 = comfortable). Decays `needs.bladder_per_hour` × trait `effects.decay.bladder`; at 0, hygiene drops an extra `needs.bladder_empty_hygiene_per_hour`. `bl_adjust_needs` accepts a `bladder` key. New activities `use_toilet` (home), `ease_yourself` / `public_toilet` (paid, outside), `watch_tv`, `listen_radio`.
- `origin_tiers` (P1-ORIGIN: id text pk, name, tagline, welcome, chance_key → game_config key of its roll %, is_default (exactly one), sort, perks jsonb) — select for anon+authenticated. See `docs/ORIGIN.md`.
- Realtime publication `supabase_realtime`: profiles, events, game_config (+ chat tables by P2-SOCIAL).

### Core RPCs (P1-DB)
| RPC | Args | Returns |
|---|---|---|
| `create_profile` | p_username text, p_gender text, p_avatar jsonb | GameState — rolls the origin tier and applies its starter pack (redefined by P1-ORIGIN) |
| `update_avatar` | p_avatar jsonb | {message} |
| `get_my_state` | – | GameState (see `src/lib/types.ts`) incl. `origin` block (P1-ORIGIN; keep it if you redefine) — also bumps last_seen |
| `claim_allowance` | – | {message, amount, account:'bank', bank, day} — Dad allowance once per game day (P1-ORIGIN) |
| `create_profile_v2` | p_username, p_gender, p_avatar, p_traits text[], p_dream text | GameState — Sim created with no home yet (R3a); `creator.homes` lists the homes for the rolled origin |
| `choose_start_home` | p_home text | GameState + message — once; pays the starter pack, sets rent (R3a) |
| `creator_catalog` | – | {trait_count, traits, dreams, homes, rent_weekday} — anon too |
| `admin_set_origin` | p_user uuid, p_origin text, p_apply_perks bool | {message, old, new, cash, bank, items} — admin only |
| `travel_quote` | p_dest text | {dest, km, options:[{mode, label, allowed, reason?, cost, game_minutes, real_seconds, risk_pct}]} |
| `travel_start` | p_dest text, p_mode text | {message, arrives_at} |
| `travel_arrive` | – | {message, robbed?: {amount, injured}} — rolls street robbery |
| `do_activity` | p_activity text | {message} |
| `players_here` | p_location text | [{id, username, avatar, street_cred, last_seen}] seen within 3 real minutes |
| `get_public_profile` | p_id uuid | {id, username, avatar, gender, street_cred, job_id, location_id, created_at} |
| `players_online` | – | {count, minutes} — Sims seen in the last `time.presence_real_minutes` (R4, HUD pill) |

Street robbery baseline lives in `bl_roll_street_robbery(p_uid uuid, p_location text, p_mode text, p_traffic numeric) returns jsonb` (P1-DB). P2-CRIME may `create or replace` it with a richer version **keeping the signature**.

## 4. Game rules (baseline numbers = config defaults)
- Clock: `clock.game_minutes_per_real_minute` = 12 (1 game day = 2 real hours). Game time = real minutes since `clock.epoch` (default 2026-10-05T00:00Z, the launch day = Day 1) × speed + `clock.start_hour_offset`(6h); client and server read the same key. Night = hour ≥ `clock.night_start_hour`(20) or < `clock.night_end_hour`(6).
- Needs decay per game hour: hunger 4, energy 3, hygiene 2.5, fun 2, social 1.5, bladder 5 (R4); stress +1; health −2 per game hour while hunger or energy is 0; hygiene −4 extra per game hour while bladder is 0.
- Start: depends on the rolled origin tier (P1-ORIGIN, `docs/ORIGIN.md`); in the R3a creator flow the cash comes from the chosen start home per origin (`docs/CREATOR.md`), the bank and items from the origin. `origin.nepo_pct` 10% → **Nepo baby**: cash ₦50,000, bank ₦500,000, home/location `gra_duplex`, housing `duplex_gra`, items `tokunbo_car,laptop`, career head start 2, Dad allowance ₦5,000/game day. Otherwise **LAPO baby** (default): cash ₦5,000, home/location `ekenwan_room`, housing `face_me_ekenwan`, easy micro-loans (Phase 2 hook). Per-tier keys `origin.<tier>.{start_cash,start_bank,home_location,housing,items,career_head_start,allowance_daily}`; missing ones fall back to `start.*`. New-player protection 120 real minutes for everyone.
- Travel: km = distance(x,y)/1000 × `travel.city_km_across`(18) + remote_km of each end. Modes (`travel.<mode>.*`): walk 5 km/h ₦0; keke 18 km/h ₦150 + ₦100/km (only if both ends `keke_ok`); bus (ECTS) 15 km/h ₦300 flat; drop 25 km/h ₦500 + ₦250/km; car 30 km/h ₦120/km fuel (needs an inventory item with category `vehicle`). Traffic = avg(congestion) × rush mult 1.8 (07–10, 16–20) × Ramat Park mult 1.6 if either end in district `ikpoba_hill`/`aduwawa` and `traffic.ramat_flyover_open` false. Walk ignores traffic. Real seconds = game minutes × `travel.real_seconds_per_game_minute`(1.0), min 3s.
- Street robbery p = `crime.npc_base_pct`/100 × zone risk × (night ? night_risk_mult × `crime.night_mult` : 1) × (1 + (traffic−1) × `crime.traffic_weight`) × cash_factor × mode_factor × (1 − charm_strength); cash_factor = min(1.5, 0.3 + cash/`crime.cash_ref`); mode factors walk 1.4 / keke 1.0 / bus 0.8 / drop 0.7 / car 0.6; 0 while protected; cap `crime.npc_max_pct`. Loss = cash × U(`crime.loss_min_pct`,`crime.loss_max_pct`)/100; `crime.injury_pct` chance → health −U(15,35) and suggest UBTH.

## 5. Locations (seeded by P1-DB, used by map art). Map space 1000×1000, north up, Ring Road centre (500,500).
| id | name | district | scene | x | y | risk | night× | cctv | keke | cong | remote_km | actions |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| national_museum | Benin National Museum (King's Square) | oredo | museum | 500 | 500 | .15 | 1.5 | t | f | 1.3 | 0 | activities |
| oba_market | Oba Market | oredo | market | 448 | 452 | .35 | 1.8 | f | f | 1.4 | 0 | shop,market_p2p,jobs,activities |
| ring_road_pos | Ring Road PoS Line | oredo | pos | 540 | 452 | .40 | 2.0 | t | f | 1.5 | 0 | pos,jobs |
| oba_palace | Oba's Palace | oredo | palace | 432 | 512 | .05 | 1.0 | t | f | 1.2 | 0 | activities |
| igun_street | Igun Street (Bronze Casters) | oredo | workshop | 580 | 470 | .15 | 1.5 | f | t | 1.1 | 0 | jobs,shop,activities |
| mama_osas_buka | Mama Osas Buka | oredo | buka | 480 | 565 | .20 | 1.5 | f | t | 1.2 | 0 | activities,jobs |
| new_benin_market | New Benin Market | new_benin | market | 595 | 350 | .35 | 1.8 | f | f | 1.4 | 0 | shop,market_p2p,jobs,activities |
| new_benin_pos | New Benin PoS Junction | new_benin | pos | 645 | 375 | .45 | 2.0 | f | f | 1.4 | 0 | pos,jobs |
| mercy_clinic | Mercy Clinic | new_benin | hospital | 560 | 365 | .10 | 1.2 | t | t | 1.1 | 0 | hospital |
| mission_rd_flats | Mission Road Mini Flats | new_benin | home_flat | 530 | 405 | .15 | 1.6 | f | t | 1.1 | 0 | housing,activities |
| uselu_market | Uselu Market | uselu | market | 480 | 235 | .30 | 1.8 | f | f | 1.6 | 0 | shop,market_p2p,jobs,activities |
| fresh_cut_salon | Fresh Cut Barbing & Salon | uselu | salon | 515 | 290 | .20 | 1.5 | f | t | 1.1 | 0 | jobs,shop,activities |
| uselu_park | Uselu Motor Park | uselu | motorpark | 450 | 270 | .40 | 2.0 | f | f | 1.6 | 0 | jobs,activities |
| uniben | UNIBEN Ugbowo Campus | ugbowo | campus | 480 | 125 | .20 | 1.6 | t | t | 1.2 | 0 | jobs,activities |
| ubth | UBTH (Teaching Hospital) | ugbowo | hospital | 440 | 165 | .10 | 1.2 | t | f | 1.3 | 0 | hospital,jobs |
| back_gate_joint | UNIBEN Back Gate Joint | ugbowo | buka | 455 | 75 | .30 | 2.0 | f | t | 1.1 | 0 | activities |
| wifi_joint | Ugbowo Wi-Fi Joint | ugbowo | cyber | 400 | 135 | .25 | 1.8 | f | t | 1.0 | 0 | jobs,activities |
| oluku_park | Oluku Junction Park | oluku | motorpark | 390 | 40 | .50 | 2.2 | f | f | 1.5 | 0 | jobs,activities |
| ramat_park | Ramat Park Junction | ikpoba_hill | motorpark | 680 | 415 | .40 | 2.0 | f | f | 2.2 | 0 | jobs,activities |
| oregbeni_market | Oregbeni Market (Ikpoba Hill) | ikpoba_hill | market | 700 | 465 | .35 | 1.8 | f | f | 1.4 | 0 | shop,market_p2p,jobs |
| aduwawa_park | Aduwawa Motor Park | aduwawa | motorpark | 820 | 335 | .55 | 2.3 | f | f | 1.4 | 0 | jobs,activities |
| aduwawa_room | Aduwawa Face-Me-I-Face-You | aduwawa | home_face_me | 860 | 385 | .40 | 2.0 | f | t | 1.0 | 0 | housing,activities |
| third_east | Third East Circular | third_east | street | 665 | 520 | .50 | 3.0 | f | f | 1.3 | 0 | activities,jobs |
| ekiosa_market | Ekiosa Market | sakponba | market | 595 | 575 | .35 | 1.8 | f | f | 1.3 | 0 | shop,market_p2p |
| baba_shrine | Baba Osagie Shrine | sakponba | shrine | 640 | 615 | .30 | 1.8 | f | t | 1.0 | 0 | babalawo |
| upper_sakponba | Upper Sakponba | upper_sakponba | street | 700 | 665 | .55 | 3.0 | f | t | 1.2 | 0 | activities,jobs |
| santana_market | Santana Market | sapele_rd | market | 560 | 700 | .30 | 1.8 | f | f | 1.3 | 0 | shop,market_p2p |
| sapele_pos | Sapele Road PoS Stand | sapele_rd | pos | 545 | 640 | .50 | 2.2 | f | f | 1.4 | 0 | pos,jobs |
| bronze_lounge | Bronze Lounge | sapele_rd | club | 560 | 770 | .35 | 1.6 | t | f | 1.2 | 0 | activities,jobs |
| police_hq | Police Command HQ (GRA) | gra | police | 510 | 604 | .02 | 1.0 | t | f | 1.1 | 0 | police,jobs |
| bronze_bank | Bronze Bank (GRA) | gra | bank | 470 | 625 | .10 | 1.3 | t | f | 1.2 | 0 | bank,loans,esusu,jobs |
| gra_duplex | GRA Duplex Estate | gra | home_duplex | 450 | 690 | .10 | 1.4 | t | f | 1.0 | 0 | housing,activities |
| kingdom_lounge | Kingdom Lounge (GRA) | gra | club | 420 | 650 | .15 | 1.4 | t | f | 1.1 | 0 | activities |
| benin_airport | Benin Airport | airport_rd | airport | 330 | 615 | .05 | 1.0 | t | f | 1.1 | 0 | airport |
| siluko_rd | Siluko Road | siluko | street | 378 | 378 | .45 | 2.2 | f | t | 1.2 | 0 | activities,jobs |
| ekenwan_room | Ekenwan Face-Me-I-Face-You | ekenwan | home_face_me | 298 | 562 | .40 | 2.0 | f | t | 1.0 | 0 | housing,activities |
| uniben_hostel (R3a) | UNIBEN Hostel (Ugbowo) | ugbowo | home_face_me | 522 | 140 | .20 | 1.6 | t | t | 1.0 | 0 | housing,activities |
| uselu_selfcon (R3a) | Uselu Self-Contain | uselu | home_flat | 420 | 228 | .30 | 1.8 | f | t | 1.0 | 0 | housing,activities |
| iguobazuwa_farm | Iguobazuwa Farm Settlement | iguobazuwa | farm | 40 | 300 | .30 | 2.0 | f | f | 1.0 | 22 | farm,jobs |

Positions come from `docs/MAP_GEO.md` (OSM + Wikipedia check of real Benin City, compressed radially) and are applied by `supabase/migrations/20261005000100_map_geo.sql` (two small nudges for pin spacing: ring_road_pos 540,452, police_hq 510,604). Roads to draw (map art, `src/art/map/mapGeo.ts`): Ring Road circle r≈60 at (500,500); each radial road leaves the ring at its real bearing. Ugbowo–Lagos Rd N (bearing ~350) through Uselu (450,270)/(480,235), Ugbowo with UBTH (440,165) west of the road and UNIBEN (480,125) east of it, to Oluku (390,40), then off-map towards Lagos; Siluko Rd NW (~300–314) past (378,378) becoming Upper Siluko Rd towards Iguobazuwa (farm sign, farmland on the NW edge; the farm itself is off-map, `remote_km` 22); Mission Rd NNE (31) past Mission Rd Flats/Mercy Clinic to New Benin Market (595,350), continuing N as Upper Mission Rd; Akpakpava Rd NE (52) over the Ikpoba bridge (≈656,420) to Ramat Park (680,415); from Ramat the Benin–Auchi Rd runs ENE to Aduwawa (820,335) and the Benin–Agbor Rd E/ESE; Sakponba Rd SE/ESE (125) past Ekiosa (595,575) and Baba Osagie (640,615) to Upper Sakponba (700,665); Sapele Rd SSE (165) past Sapele Rd PoS, Santana (560,700) and Bronze Lounge (560,770) off-map S; Airport Rd SW (221) to Benin Airport (330,615); Ekenwan Rd WSW (~245) along the south side of the palace past Ekenwan (298,562); First/Second/Third East Circular run N–S east of the centre (Third East at x≈650). Ikpoba River runs N–S around x≈655–695 between the end of Akpakpava Rd and Ramat Park, then bends SE past Upper Sakponba. Oba's Palace compound is just W of King's Square (≈405,505), outside the ring. GRA = leafy district S of centre between Airport Rd and Sapele Rd (police HQ, Bronze Bank, Kingdom Lounge, GRA Duplex). Exit signs: LAGOS N via Oluku, AUCHI ENE via Aduwawa, AGBOR/Asaba E, SAPELE/Warri S, FARMS/Iguobazuwa NW.

## 6. Panel contract (frontend)
```ts
// src/lib/types.ts
export interface PanelProps { state: GameState; location: Location; refresh: () => Promise<void>; close: () => void; params?: Record<string, unknown> }
```
- Panels are default exports in `src/panels/<Name>Panel.tsx`. Action ids → files in `src/panels/registry.ts`.
- Location-bound panels render inside the location sheet as a tab when `location.actions` contains the id **and** the player is at that location. Global panels (`inventory`, `wallet`, `messages`, `crimes`) open from the HUD. `rob` and `profile` open from the "People here" list with `params: { targetId }`.
- Call RPCs via `rpc()` from `src/lib/api.ts`; after a state-changing call, `await refresh()`; show the returned `message` with `toast(message)` from `src/ui/Toast` (P1-SHELL exports `toast(msg, kind?)`).
- Use the shared UI kit from `src/ui` and tokens from `src/styles/tokens.css`. Mobile-first: panels must work at 360px width.
- Format naira with `naira(n)` from `src/lib/format.ts` (P1-SHELL).

## 7. Art contracts
- **Avatar** (`src/art/avatar/`, P1-AVATAR): `export function Avatar(props: { config: AvatarConfig; view?: 'full'|'portrait'; size?: number; className?: string })` from `src/art/avatar/Avatar.tsx`; catalog in `src/art/avatar/catalog.ts` exporting `AVATAR_OPTIONS` (per-slot option lists with Pidgin labels, gender-filtered), `defaultAvatar(gender)`, `randomAvatar(gender)`, `normalizeAvatar(raw): AvatarConfig`. Full view viewBox `0 0 200 400`; portrait viewBox `0 0 200 200`.
- **Map** (`src/art/map/`, P1-MAP): `export function BeninMap(props: { locations: Location[]; currentId?: string; selectedId?: string; onSelect: (id: string) => void; night: boolean; travel?: { from: string; to: string; progress: number } | null; crowd?: Record<string, number> })` from `src/art/map/BeninMap.tsx`. viewBox `0 0 1000 1000`. Pan + pinch/wheel zoom, tap pins.
- **Scenes** (`src/art/scenes/<SceneType>.tsx`): default export `(props: { night: boolean }) => JSX.Element`, root `<svg viewBox="0 0 800 450" preserveAspectRatio="xMidYMid slice" width="100%" height="100%">`. Dispatcher `src/art/Scene.tsx` (phase 0) lazy-loads by file name and falls back to a gradient. Unique `id`s inside each SVG must be prefixed with the scene name (`market-sky`) to avoid DOM id collisions.
  - P1-SCENES-A: market, hospital, campus, palace, museum, club, bank, police, motorpark, street, pos
  - P1-SCENES-B: home_face_me, home_flat, home_duplex, farm, airport, shrine, workshop, buka, salon, cyber
- All art: detailed layered SVG (multi-stop gradients, five-zone lighting, coloured shadows — never pure black, subtle grain), Benin palette (laterite red-earth #b5552b family, coral red #d2342a, bronze #b0793a / gold #d9a441, ECTS green #1f7a3f, lush tropical greens). Follow the `svg-creator` skill workflow (render → look → fix) at `~/.claude/skills/svg-creator/` using `python ~/.claude/skills/svg-creator/scripts/svg_loop.py render <file.svg> [width]` then Read the PNG it prints.

## 8. Testing protocol (every agent, before reporting done)
- Frontend: `npm run build` must pass (tsc + vite) with zero errors.
- SQL: `bash scripts/sql-test.sh <migration files...> -- <test file>` runs everything inside `BEGIN … ROLLBACK` against the local DB, so parallel agents don't collide. Tests use `supabase/tests/_helpers.sql` (`pg_temp.new_user(email)`, `pg_temp.login(uid)`) and must `raise exception` on failure. Use `set local bl.test_rand` / `bl.test_offset_seconds` for determinism.
- Only the phase verifier runs `npx supabase db reset` (applies all migrations) — agents must not.
- Art: render every SVG you produce and look at it before finishing.
- Report: list files created, what you verified (commands + results), and any assumption the user should sanity-check.

## 9b. Careers (user request — owned by P2-ECON)
- Data-driven tables: `career_tracks` (id, name, category 'official'|'hustle', location_ids text[], description) and `career_levels` (track_id, level int, title, pay_per_shift, shift_game_minutes, energy_cost, xp_to_next, requirements jsonb e.g. {"min_days_in_level":1,"min_street_cred":0,"education":"degree","item":"laptop"}, perks jsonb). `profiles.job_id` = track id, `job_level`, `job_xp` (core columns).
- Official tracks go lowest → highest (≥6 levels each): **Tech** (Intern → Junior Dev → Mid-level Dev → Senior Dev → Tech Lead → Engineering Manager → CTO) at a new location `bronze_tech_hub` ("Bronze Tech Hub", fictional, Ugbowo/GRA area, scene `office`); **Health** (Ward Attendant → Student Nurse → Staff Nurse → Senior Nurse → Resident Doctor → Consultant → Chief Medical Director) at UBTH/Mercy Clinic; **Police** (Recruit → Constable → Corporal → Sergeant → Inspector → ASP → DPO → Commissioner) at Police HQ; **Banking** (Intern → Teller → Customer Service → Relationship Manager → Branch Manager → Regional Head → MD/CEO) at Bronze Bank; **Education** (UNIBEN: Student → Graduate Assistant → Lecturer II → Lecturer I → Senior Lecturer → Professor → Vice-Chancellor); **Trade** (Market Apprentice → Trader → Shop Owner → Wholesaler → Market Leader (Iyaloja-style) → Distributor); **Bronze Art** (Igun Apprentice → Caster → Master Caster → Guild Elder); **Transport** (Keke Rider → Bus Driver → Park Supervisor → Transport Company Owner); **Entertainment** (Hype Man → DJ → Resident DJ → Club Manager → Promoter → Label Owner); **Beauty** (Salon Apprentice → Barber/Stylist → Senior Stylist → Salon Owner → Beauty Brand CEO); **PoS/Fintech agent** (PoS Attendant → PoS Operator → Super Agent → Aggregator).
- Hustle tracks (risky, also laddered): **Agbero** (Ticket Boy → Agbero → Park Chairman's Boy → Park Chairman), **Yahoo** (Learner → G-boy → Big Boy → Chairman — each level higher pay AND higher EFCC raid chance).
- Promotion: `career_promote()` RPC (or automatic on shift when xp ≥ xp_to_next and requirements met); demotion/firing chance for missed hygiene/energy or arrests (config). Each shift: XP gain × performance (based on needs). All numbers admin-tunable (`career.*` config + editable level rows via admin RPCs).
- New SceneType `office` (modern tech hub / corporate office) — drawn in Phase 2 by the art agent.

## 9. Copy & tone
Clear, warm English by default (updated in R1 after user feedback). Pidgin only where a real Benin person would use it: street moments (agberos, robbery, market banter) and the LAPO-baby voice, e.g. "Omo! Dem don rob you!", "Agbero don block road. Drop ₦200 abeg." Keep it natural, never a parody, never graphic. Nepo babies are school-trained and say "Dad"/"Daddy", never "Papa". Landing, auth and settings are plain English. Shared strings live in `src/lib/pidgin.ts`. Gangs: agberos + fictional crews only ("Ring Road Boys", "Sapele Lions") — never real cults. Treat the Oba/palace respectfully.
