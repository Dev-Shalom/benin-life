# Careers: jobs that pay (V1-3)

Files: `supabase/migrations/20261005000700_careers.sql`, `supabase/tests/careers_test.sql`, wrappers in `src/api/careers.ts`,
types in `src/lib/types.ts` (`// V1-3`), shared UI `src/panels/careers/CareerUI.tsx` + `careerHooks.ts`, the Work panel
`src/panels/JobsPanel.tsx` (action id `jobs`), the phone's Jobs app (`src/screens/game/Phone.tsx`), the Sim sheet's Career tab
(`src/screens/game/SimSheet.tsx`), auto-collect in `StatusBanners.tsx`, the "Go to work" wish chip in `Hud.tsx`, office scene
`src/art/scenes/office.tsx`, 3D landmark in `src/art/city3d/engine/build.ts`.

Test (migrations applied): `bash scripts/sql-test.sh -- supabase/tests/careers_test.sql`

## How it plays
1. **Apply from anywhere** (phone → Jobs, or the Work tab at a workplace). Applying replaces your current job (the
   button says "Switch" and asks for a second tap). You start at the track's entry level (see Head start).
2. **Work at the job's place.** Travel there, open the place → **Work** → "Work a shift · ₦X · 5 hrs". The shift's need
   costs apply at once, you are busy ("Working: Intern", progress ring), and the pay arrives when the timer ends.
3. **Paid at the end.** The client calls `work_finish()` when the busy timer runs out (also after a reload). If it never
   does, the next `work_shift` / `job_apply` / `job_quit` settles the finished shift first. Toast: "Shift done! You earned
   ₦3,200 (performance 87%)." plus "Promoted to Junior Dev!" or what is still missing.
4. **Promotion is automatic** when a finished shift brings XP to the level's `xp_to_next` **and** the next level's
   requirements are met. If something is missing, XP is held at the bar and the next shift after you fix it promotes you.

Why "apply anywhere, work on site": choosing a job from the phone feels natural (like a job app), while the shift itself
gives the map a purpose: you travel to the Tech Hub, UBTH or the motor park every day.

## Tables (RLS on; select for anon + authenticated; no client writes)
- **`career_tracks`** (id, name, emoji, category `official|hustle`, location_ids text[], description, skill, sort, active).
  `skill` = the trait `effects.skill_xp` key that boosts XP on this track (`coding` for Tech, `hustle` for PoS/Trade/Transport).
- **`career_levels`** (track_id, level, title, pay_per_shift, shift_game_minutes, energy_cost, effects jsonb, xp_per_shift,
  xp_to_next (null = top), requirements jsonb, perks jsonb). PK (track_id, level).
- **Requirements** (on the level you are moving **into**):
  - `min_shifts_in_level` n: shifts worked at the level below (promotion only; ignored for direct hires).
  - `item` id: the item must be in your inventory (e.g. `laptop`).
  - `degree` true: best Education level ever ≥ `career.degree_level` (2 = Graduate Assistant).
  - `min_level_track` {track: level}: best level ever reached on another track.
  - `min_street_cred` n.
- **`profiles`** adds `job_started_at`, `job_shifts_in_level`, `job_total_shifts`, `job_shift_day`, `job_shifts_today`,
  the running shift `job_shift_ends_at`, `job_shift_pay`, `job_shift_xp`, `job_shift_perf`, and `career_best` jsonb
  (best level per track, e.g. `{"education": 2, "tech": 3}`).
- **Location `bronze_tech_hub`** "Bronze Tech Hub" (Ugbowo, scene `office`, 535,190, risk .12, night× 1.4, CCTV, keke ok,
  congestion 1.1, actions `jobs,activities`) + activities `office_coffee` (₦400) and `tech_meetup`; `ease_yourself` now
  includes `office`. `mercy_clinic`, `ekiosa_market` and `santana_market` gained the `jobs` action.

## Formulas (all numbers from config / level rows)
- **Performance %** = `perf_min + (perf_max − perf_min) × score/100`, × trait `work_performance`, clamped to
  [`career.perf_min_pct` 40, `career.perf_max_pct` 120]; `score` = weighted mean of hunger, energy, hygiene and
  (100 − stress) with weights `career.perf_weight_*` (30/35/15/20). Needs are read when the shift **starts**.
- **Pay** = `pay_per_shift × perf/100 × traits work_pay × career.pay_mult`, rounded to ₦10, ledger reason `salary`
  (meta track/level/perf), into **cash**.
- **XP** = `xp_per_shift × perf/100 × career.xp_mult × traits skill_xp[track.skill]`, rounded.
- **Need costs** at shift start: `effects` + `energy −energy_cost`. Normal decay keeps running during the shift.
- **Refusals** (P0001 + hint): `no_job`, `not_here` ("You work at Bronze Tech Hub. Go there…"), `too_tired`
  (energy < `career.min_energy` 15), `too_hungry` (hunger < `career.min_hunger` 10), `shift_limit`
  (`career.max_shifts_per_game_day` 3, all jobs together), `busy`/`traveling`/`jailed`/`hospitalized` (bl_assert_free),
  `on_shift` (quit/apply/finish too early), `already_hired`, `bad_track`.
- **Head start / entry level** (`bl_career_entry_level`):
  - First ever hire: `1 + origin.<tier>.career_head_start` (Nepo 2), capped at `career.head_start_max_level` (3). With
    `career.head_start_first_job_only` (true) later hires start at 1.
  - Rejoining a track you held: best level there − `career.rejoin_levels_lost` (1), never below 1.
  - Then walked down until that level's requirements (except `min_shifts_in_level`) are met. Example: a Nepo baby enters
    Tech at **Mid-level Dev** (owns the laptop) but Health at **Student Nurse** (no degree yet).
- Firing/demotion: not in v1 (no config key until it exists).

## RPCs
| RPC | Returns |
|---|---|
| `jobs_catalog()` | `{current, degree, tracks:[{id,name,emoji,category,description,skill,locations:[{id,name}],entry_level,levels:[{level,title,pay_per_shift,shift_game_minutes,xp_to_next,requirements:[{key,label,met}]}]}]}` (read-only) |
| `job_apply(p_track)` | `{message, track, level, title, settled}` + `hired` event |
| `job_quit()` | `{message}` |
| `work_shift()` | `{message, busy_until, pay, xp, perf, settled}` |
| `work_finish()` | `{message, pay, xp, perf, promoted?:{level,title,pay}, blocked?:{title,missing[]}}` or `{message:null}`; `promoted` event |
| `get_my_state().career` | `{job: null \| {track, track_name, emoji, skill, level, title, top_level, pay_per_shift, shift_game_minutes, energy_cost, xp, xp_to_next, shifts_in_level, total_shifts, shifts_today, max_shifts_per_day, perf_now, pay_now, started_at, locations, next:{level,title,pay_per_shift,requirements}, pending:{ends_at,pay,xp,perf}}, degree, best}` (still read-only) |

Helpers (`bl_has_degree`, `bl_career_reqs`, `bl_career_reqs_met`, `bl_career_perf`, `bl_trait_mult`,
`bl_career_entry_level`, `bl_settle_shift`, `bl_career_info`) are revoked from public/anon/authenticated.
The client hides the realtime toasts for `hired`/`promoted` events because the RPC result already toasts them.

## Pay table (seeded; admin-editable rows)
Shift lengths in game time; real time = game minutes × `time.real_seconds_per_game_minute` (0.75 → 4 h = 3 min, 5 h =
3 min 45 s, 6 h = 4 min 30 s). All levels give 10 XP per shift at 100 % performance. "3 sh" = 3 shifts at the level below.

| Track (where) | Lvl | Title | ₦ / shift | Shift | Energy | XP to next | Needs |
|---|---|---|---|---|---|---|---|
| 💻 Tech (Bronze Tech Hub) | 1 | Intern | 3,500 | 5 h | 14 | 40 | – |
| | 2 | Junior Dev | 8,000 | 5 h | 15 | 70 | 3 sh, laptop |
| | 3 | Mid-level Dev | 15,000 | 5 h | 16 | 110 | 3 sh, laptop |
| | 4 | Senior Dev | 28,000 | 5 h | 16 | 160 | 3 sh, laptop, degree |
| | 5 | Tech Lead | 45,000 | 5 h | 17 | 220 | 3 sh, laptop, degree |
| | 6 | Engineering Manager | 70,000 | 5 h | 17 | 300 | 3 sh, laptop, degree |
| | 7 | CTO | 120,000 | 5 h | 18 | top | 3 sh, laptop, degree |
| 🏧 PoS & Fintech (3 PoS stands) | 1 | PoS Attendant | 2,500 | 4 h | 12 | 40 | – |
| | 2 | PoS Operator | 5,000 | 4 h | 12 | 70 | 3 sh |
| | 3 | Super Agent | 12,000 | 4 h | 13 | 110 | 3 sh |
| | 4 | Aggregator | 25,000 | 4 h | 13 | top | 3 sh |
| 🛒 Trade (6 markets) | 1 | Market Apprentice | 2,000 | 4 h | 14 | 40 | – |
| | 2 | Trader | 4,500 | 4 h | 14 | 70 | 3 sh |
| | 3 | Shop Owner | 9,000 | 4 h | 13 | 110 | 3 sh |
| | 4 | Wholesaler | 18,000 | 4 h | 13 | 160 | 3 sh |
| | 5 | Market Leader | 32,000 | 4 h | 12 | 220 | 3 sh |
| | 6 | Distributor | 55,000 | 4 h | 12 | top | 3 sh |
| 🛺 Transport (4 motor parks) | 1 | Keke Rider | 3,000 | 5 h | 16 | 40 | – |
| | 2 | Bus Driver | 6,500 | 5 h | 16 | 70 | 3 sh |
| | 3 | Park Supervisor | 14,000 | 5 h | 14 | 110 | 3 sh |
| | 4 | Transport Company Owner | 35,000 | 5 h | 12 | top | 3 sh |
| 🩺 Health (UBTH, Mercy Clinic) | 1 | Ward Attendant | 3,000 | 6 h | 16 | 40 | – |
| | 2 | Student Nurse | 5,000 | 6 h | 16 | 70 | 3 sh |
| | 3 | Staff Nurse | 12,000 | 6 h | 17 | 110 | 3 sh, degree |
| | 4 | Senior Nurse | 20,000 | 6 h | 17 | 160 | 3 sh, degree |
| | 5 | Resident Doctor | 35,000 | 6 h | 18 | 220 | 3 sh, degree |
| | 6 | Consultant | 60,000 | 6 h | 18 | 300 | 3 sh, degree |
| | 7 | Chief Medical Director | 100,000 | 6 h | 18 | top | 3 sh, degree |
| 🎓 Education (UNIBEN) | 1 | UNIBEN Student (stipend) | 1,000 | 4 h | 12 | 50 | – |
| | 2 | Graduate Assistant (= degree) | 6,000 | 4 h | 12 | 70 | 3 sh |
| | 3 | Lecturer II | 12,000 | 4 h | 12 | 110 | 3 sh |
| | 4 | Lecturer I | 18,000 | 4 h | 12 | 160 | 3 sh |
| | 5 | Senior Lecturer | 28,000 | 4 h | 12 | 220 | 3 sh |
| | 6 | Professor | 45,000 | 4 h | 12 | 300 | 3 sh |
| | 7 | Vice-Chancellor | 80,000 | 4 h | 13 | top | 3 sh |

Balance notes: a starter shift (₦2,000-3,500) buys 1.5-2 buka meals (~₦1,500); 3 shifts a game day (10-14 real
minutes of work) pay ₦6,000-10,500, so a LAPO baby covers food and the cheapest rent (₦1,000-1,500 a week) on
day one and the ₦4,000 self-contain after a couple of days. Top levels pay ₦25,000-120,000 a shift. At 100 %
performance the first promotion takes 4 shifts (2 game days with the cap); a full 7-level ladder is ~90 shifts (~30 game
days, ~60 real hours of play). LAPO Tech interns are gated at Intern until they own a laptop: since V1-4 it costs ₦45,000 at Bronze Tech Hub or the Ugbowo Wi-Fi joint (~16 real hours of intern savings), and the unmet requirement links to the nearest seller's Shop tab (`docs/SHOPS.md`).

## Admin tuning
- **Config** (category `career`): `career.max_shifts_per_game_day`, `career.min_energy`, `career.min_hunger`,
  `career.perf_min_pct`, `career.perf_max_pct`, `career.perf_weight_{hunger,energy,hygiene,stress}`, `career.pay_mult`,
  `career.xp_mult`, `career.degree_level`, `career.head_start_first_job_only`, `career.head_start_max_level`,
  `career.rejoin_levels_lost`. Plus `origin.<tier>.career_head_start` and `time.real_seconds_per_game_minute`.
- **Rows:** edit `career_levels` (pay, shift length, energy, effects, XP, requirements) and `career_tracks`
  (places, active). New levels/tracks appear in the Jobs app automatically. A track's places must have the `jobs`
  action to show the Work tab. Until the admin page (V1-7) exists, edit with SQL, e.g.
  `update career_levels set pay_per_shift = 4000 where track_id = 'tech' and level = 1;`
- **Adding a track:** insert the track (with `location_ids`, optional `skill`), its levels 1..n (top level
  `xp_to_next` null), and make sure each place has `jobs` in `locations.actions`.
