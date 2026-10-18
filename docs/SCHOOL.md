# School and certificates (R4)

The player chooses between earning money now and investing time in learning that unlocks better jobs later. Everything is server-side and
admin-tunable; the client never sends XP, rolls an exam or awards a certificate.

Files:
- `supabase/migrations/20261018000100_school.sql`, `supabase/tests/school_test.sql` (15 groups)
- `src/api/school.ts`, `src/state/school.ts`, `src/screens/game/School.tsx` + `.css` (`<SchoolHost/>` graduation toast, `<CertificatesCard/>`),
  `src/screens/game/phone/SchoolApp.tsx` + `.css` (the School phone app)
- Hooks: `TaskRunner.ts` / `tasks.ts` (kind `class`), `TaskPill.tsx` (🎓, a class can't be stopped), `PlaceCard.tsx` (course cards, "+X% from certificate"),
  `Phone.tsx` (School app), `Game.tsx` (`<SchoolHost/>`, place cards re-read after a class), `state/game.ts` (`graduated` events open the toast),
  `SimSheet.tsx` (Certificates card on the Profile tab), `CareerUI.tsx` (track lock, certificate lines), `HustlesApp.tsx` / `YahooApp.tsx` (lock text),
  `lib/deeplink.ts` (`go=school`)
- Admin: `Content.tsx` (tabs Courses, Certificates; `Certificate needed` on Hustles, Yahoo jobs, Career tracks and Levels), `Players.tsx`
  (Certificates box: grant and revoke), `Settings.tsx` (category School), `api.ts`

## Model
- `certificates`: id, name, icon, blurb, `pay_bonus_pct`, `bonus_tracks` (career track ids), `bonus_hustles` (hustle ids), sort, active.
- `courses`: place (`location_ids` and/or `scenes`), `fee`, `classes`, `class_game_minutes` (shown) and `class_seconds` (the real timer), `cooldown_days`
  (game days between classes), `energy_cost` and `effects` (other need changes per class), `hour_from`/`hour_to`, `skill_id` + `xp_per_class`,
  prerequisite (`prereq_cert`, comma = any of, and/or `prereq_skill` + `prereq_skill_level`), `cert_id` (awarded on completion), exam
  (`exam`, `exam_base_pct`, `exam_per_level_pct`, `exam_text`), `modules` (names for long courses).
- `course_enrolments(user_id, course_id, status enrolled|completed, classes_done, fee_paid, last_class_day, exam_fails ...)`,
  `course_runs` (one row per class, like `hustle_runs`), `player_certificates(user_id, cert_id, earned_at, source course|admin, course_id)`.
  Players read their own rows only; no client writes anywhere.
- Gates (all nullable `req_cert text`, a comma means "any of"): `career_levels.req_cert`, `career_tracks.req_cert`, `hustles.req_cert`, `yahoo_jobs.req_cert`.
  A gate is a new `cert` key in the career requirement JSON (`bl_career_lreq(requirements, req_cert)`), so the Jobs app, the promotion check, the entry
  level and `jobs_catalog` all agree. Label flips to "Needs ICT certificate" while it is missing.
- `school.degree_cert` (default `bsc`): that certificate counts as a UNIBEN degree for every "A UNIBEN degree" career requirement (`bl_has_degree`).

## A class (runs like a hustle)
`course_enrol(id)` pays the fee (cash first, then bank, ledger "Course fee: <name>") and can be done from the School app anywhere or from the course card at
its place (instant "Enrol" buy). `course_start_class(id)` checks, in order: switch, enrolled, place (and the place's opening hours), the course's hour
window, energy, cooldown. It spends energy (and `effects`), starts a busy timer `Class: <name>` that cannot be stopped, and stamps the game day.
`course_finish_class()` (or `course_status()` after a reload) resolves it: progress +1, XP through `bl_skill_award(uid, 'course', id)` (trait
multipliers and `skills.xp_mult` apply, level-ups toast as before), and on the last class the certificate is awarded and a `graduated` event is written
(toast + confetti). Missing days never resets anything.
- Cooldown: next class allowed from the game day `last_class_day + ceil(cooldown_days x school.cooldown_mult)`. In real clock mode a game day is a
  Benin day (midnight to midnight), so "one class per game day" = once per Benin day. `school.cooldown_mult = 0` removes the wait (testing, events).
- Exam (only the final class of a course with `exam`): pass chance = `exam_base_pct + exam_per_level_pct x (skill level - 1)`, clamped to
  `school.exam_min_pct` (5) .. `school.exam_cap_pct` (95). Roll `bl_rand() x 100 < chance` passes. A fail: the class still costs time and energy and
  counts for the cooldown, but gives no XP and no progress (retake that class, `exam_fails` +1).
- Re-enrolling is refused while enrolled and while you hold the certificate. If an admin revokes the certificate the course shows as new again and a
  re-enrol starts from zero.

## Defaults (all in Content -> Courses / Certificates)
| Course | Place | Fee | Classes | Hours | Skill XP / class | Needs | Exam (base + per level) | Certificate |
|---|---|---|---|---|---|---|---|---|
| Computer Basics / ICT | UNIBEN | ₦12,000 | 4 | 8 AM - 5 PM | Yahoo 8 | - | no | ICT |
| Digital Marketing | UNIBEN | ₦18,000 | 4 | 8 AM - 5 PM | Business 6 | ICT | no | Digital Marketing |
| Accounting | UNIBEN | ₦25,000 | 6 | 8 AM - 5 PM | Business 8 | Business lvl 2 | 45% + 7 | Accounting |
| Catering & Hospitality | UNIBEN | ₦20,000 | 5 | 8 AM - 5 PM | Cooking 8 | - | 55% + 6 | Catering & Hospitality |
| Driving School | any motor park | ₦30,000 | 5 | 8 AM - 6 PM | Driving 8 | - | 50% + 8 | Driving Licence |
| Music Production | UNIBEN | ₦35,000 | 6 | 8 AM - 5 PM | Music 10 | Music lvl 2 | no | Music Production |
| Auto Mechanic Trade Test | Mechanic Village | ₦22,000 | 5 | place hours (7 AM - 7 PM) | Mechanic 10 | - | 40% + 9 | Mechanic Trade Test |
| Business Management | UNIBEN | ₦30,000 | 6 | 8 AM - 5 PM | Business 8 | Accounting | no | Business Management |
| Coding Bootcamp | Bronze Tech Hub | ₦80,000 | 8 | 9 AM - 6 PM | Yahoo 12 | ICT | 45% + 7 | Coding Bootcamp |
| UNIBEN Degree (BSc) | UNIBEN | ₦180,000 | 12 (4 modules) | 8 AM - 5 PM | Teaching 5 | ICT | 40% + 6 | BSc Degree |

Every class is 30 to 40 real seconds, costs 10 to 14 energy, and is limited to one per game day (`cooldown_days` 1).
Certificates and their permanent pay bonus: ICT +5% Tech career; Digital Marketing +5% food stalls and PoS agent; Accounting +8% PoS and Trade careers;
Catering +10% food stalls; Driving +8% Transport career and Bolt; Music Production +10% DJ set, Headline DJ, MC; Mechanic +10% mechanic hustles;
Business Management +5% Trade and PoS careers and PoS agent; Coding Bootcamp +8% Tech career; BSc +5% Education, Health and Tech careers.
Bonuses add up when several certificates cover the same target. Hustle pay (`bl_hustle_pay_mult`), career shift pay (`work_shift`) and the cards
all use the same multiplier.

### What is gated by default
Careers (levels): Tech lvl 4 Senior Dev needs ICT or Coding Bootcamp (on top of the laptop and degree it already needed); PoS & Fintech lvl 4 Aggregator
needs Accounting; Trade lvl 4 Wholesaler needs Business Management; Transport lvl 2 Bus Driver needs the Driving Licence. There is no bank track yet, so
the "bank manager needs Accounting" gate sits on the top PoS and Fintech level. No career track is gated.
Hustles: two NEW hustle variants, `dj_headline` (Headline DJ slot, ₦30k to ₦65k, any open club, Music Production) and `mech_fleet` (Fleet service contract,
₦18k to ₦32k, Mechanic Village, Mechanic Trade Test). The existing hustles are untouched, so DJ set and Engine job stay open. No Yahoo job is gated
(the column and the check exist: set `Certificate needed` on any Yahoo job).
Players who are already above a gated level keep their level (the gate only blocks the next promotion, and a re-join below).

## UI
- Phone -> **School**: certificates strip, the running class (live bar), the last result, then In progress / Available / Completed. Each card has fee,
  classes, class time, cooldown, place, hours, energy, XP, exam chance now, prerequisites (ticks) and "what it unlocks", and one button: Enrol,
  Start class N, Sit the exam, Go to <place>, or the reason it is locked (Next class in 5h 20m, Wrong place, Classes 8 AM - 5 PM, Too tired).
- **Place card**: the course cards sit in zones (UNIBEN lecture hall, library and quad; the motor park drivers' bench; Tech Hub hot desks; Mechanic Village
  repair bay). Not enrolled: tap = enrol (fee). Enrolled: queues like any action and walks to the zone, with `done/classes` and the module name.
- Locked: Jobs app track cards show "Needs ICT or Coding Bootcamp certificate" for the first gated level, Hustles and place cards show "Needs Music Production
  certificate", Yahoo shows `cert_short`.
- Graduation: a purple toast with confetti (tap opens the School app). Sim sheet -> Profile -> **Certificates**. The public profile
  (`get_public_profile`) now returns `certificates: [{id, name, icon, earned_at}]` (no screen shows it yet; chat and the crime UI only read avatar and rank).

## Admin
- Content -> **Courses** and **Certificates** (every field above), `Certificate needed` on Hustles, Yahoo jobs, Career tracks and Levels (comma = any of).
  Place cards: Content -> Zone actions, kind `class`, ref = the course id.
- Players -> detail -> **Certificates**: the list with where each came from, courses in progress, **Grant** (with a note) and **Revoke** (two taps).
  Audit actions `grant_cert` and `revoke_cert` (cert, name, note, `was_source`). A grant gives the player the graduation moment.
- Settings -> **School**: `school.enabled` (off = no classes; gates and bonuses stop), `fee_mult`, `cooldown_mult`, `exam_min_pct`, `exam_cap_pct`, `degree_cert`.

## Server notes
- Live functions patched by guarded replace on `pg_get_functiondef` (raises when a marker is missing, skips when already applied, keeps grants):
  `bl_career_reqs`, `bl_career_entry_level`, `bl_career_info`, `bl_settle_shift`, `jobs_catalog`, `job_apply`, `work_shift`, `bl_has_degree`,
  `bl_hustle_why`, `bl_hustle_pay_mult`, `bl_hustle_json`, `bl_hustle_card`, `yahoo_job_start`, `yahoo_status`, `bl_skill_award`, `get_public_profile`,
  `bl_hustle_ledger_label`, `bl_ledger_label`, `place_interior`, `bl_zone_action_check`, `bl_admin_table_spec`. `zone_actions_kind_check` gained `class`.
- Private helpers `bl_cert_*`, `bl_course_*`, `bl_school_*`, `bl_career_lreq` are revoked from anon and authenticated. Public RPCs: `course_status`,
  `course_enrol`, `course_start_class`, `course_finish_class`, admin `admin_player_certs`, `admin_grant_cert`, `admin_revoke_cert`.

## Tests
`bash scripts/sql-test.sh -- supabase/tests/school_test.sql`: grants, RLS and private helpers; seeds and defaults; enrol and pay (prerequisites, cash then bank,
fee multiplier, ledger text); wrong place / hours / not enrolled / too tired; a class (busy, energy, XP, progress, overdue settle, a week away keeps
progress, skills off); cooldown (same game day refused, next day free, multiplier); graduation (certificate, event, re-enrol refused, unlocks);
exams with forced rolls (fail = retake, 52% boundary, pass = certificate, chance by skill level, cap and floor tunable); career gates (level, promotion
blocked and then promoted, any-of list, BSc counts as degree, track gate, school off); hustle and Yahoo gates; pay bonus (hustle ratio, tuned, career shift
pay); admin grant, revoke and audit, content editor; place cards; public profile; master switch.
Time moves with `bl.test_offset_seconds` (classes run 8 AM - 5 PM, clubs at night), rolls with `bl.test_rand`.

## Not done / later
- A screen for other players' certificates (the data is in `get_public_profile`).
- Courses with several parallel tracks (e.g. choose a degree subject), tuition by term, scholarships, and class-mates (classes are solo).
- The skill sheet's "where to train" list does not list courses (they are not `skill_sources` rows; XP comes from the course itself).
