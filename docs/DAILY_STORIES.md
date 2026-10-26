# Daily stories with a twist

Migrations `supabase/migrations/20261101000100_daily_stories.sql` (engine) and `20261101000200_daily_story_seeds.sql` (content) · test `supabase/tests/daily_story_test.sql` · client `src/screens/game/phone/StoriesApp.tsx` (+ `.css`), `src/api/stories.ts`, the Stories chip in `src/screens/game/Daily.tsx`, badge in `src/state/moments.ts` · admin Content -> **Daily stories** and **Path words**, Settings -> **Daily stories** · help article `daily-stories`.

## What the player sees
- One short story a day (a Benin day, WAT) in **Phone -> Stories**: a scene of 2 to 5 sentences, then 2 to 4 choices. A small chip on the HUD and a number on the Stories icon say when it is waiting. The Game events push (optional) says it too.
- They pick a choice. The card turns into the **reveal**: a colour for the tone (green good, red bad, purple plot twist, amber funny), a short animation, the changes as chips ("Got ₦1,000", "Stress +10"), and, when a seed was planted, "Something tells you this isn't over…".
- Follow-up stories ("Your story continues…") sit above today's story when they are due. Below: the **reading streak** and **Your path so far** (a sentence in words, never numbers).

## The twist
1. **Weighted outcomes.** A choice has a list of outcomes, each with a weight, a tone, effects and an optional filter. The server rolls one. The kind choice sometimes backfires, the risky one sometimes pays off. Cost is paid first, and the choice's own path nudge always lands (the intent counts).
2. **Delayed consequences.** An outcome can plant a seed: the `follow_up` effect (already in the closed list). It comes back 1 to 7 days later as a follow-up **story** (kind `chapter`, shown in Stories) or a pop-up **moment** (kind `system`, shown like any Life moment). The reveal tells the player a seed was planted, without saying what.
3. **Arcs.** Four arcs of 3 to 5 chapters (Igun Street bronze, a tokunbo car deal, Mama Blessing's buka, a secret admirer). Each outcome points at the next chapter, so later chapters change with the earlier choices and results.

## The hidden path (low-key)
Six scores per player in the new table `player_path`, from -100 to 100, never shown as numbers: `goodwill` (kind or selfish), `hustle` (bold or careful), `luck` (karma), `trouble` (shady or clean), `faith`, `family`. Not a `profiles` column, no trigger on profiles.
- A choice or an effect `{"t":"path","delta":{"goodwill":3}}` nudges them. Every nudge is cut to `stories.max_nudge` (6). **Karma:** `luck` also drifts with goodwill and trouble (30 % of the difference). Scores fade 2 points a week towards zero.
- They quietly **tilt which stories appear** (a story's `path_w`, and `conditions.path` as a filter) and **which outcome happens** (an outcome's `path_w` and its `requires`). The tilt is `1 + weight x score/100 x strength`, never more than 3 times either way. Luck also leans good outcomes up and bad ones down by at most 20 %.
- They give a few **small effects elsewhere** (all capped, all settings, no way to farm money):
  - **Luck** moves the success chance of a pop-up moment choice by at most 5 points (never a sure thing, doctor cards are left fair).
  - **Goodwill** (25 or more) gives a 4 % chance per moment roll of a **blessing** moment (`path_blessing_*`: a small gift, a free plate), at most once every 5 days. It replaces a normal roll, so it counts against the daily cap.
  - **Trouble** (25 or more) gives a 4 % chance of a **police or EFCC** scene (`path_police_*`, `path_efcc_*`), at most once every 6 days. Fictional, and the player can cooperate.
- **Words.** Table `path_lines` (Admin -> Content -> Path words): per score, side and level, a `word` for "Your path so far" ("A kind hustler with a bit of luck") and a `whisper`, the subtle line ("People around Ugbowo are starting to trust you."). A whisper shows once when a score first crosses a level, and sometimes (15 %) after a story. Never a number.

## Server rules
- **Server-authoritative.** `story_today()` makes (once) and returns today's stories, the follow-ups that are due, the streak and the path card. `story_answer(story, choice)` pays, nudges, rolls, applies, plants and returns the reveal. The client never sees chances, weights or effects. Random draws use `bl_rand()`, so tests can pin them.
- **One story a day, deterministic.** The pick is a hash of player, day and slot over the stories the player qualifies for (weight x path tilt), never one seen inside its cooldown (`stories.no_repeat_days`, 30, or the story's own cooldown; if everything was seen, the one seen longest ago). Same player, day and situation, same story. An unanswered story fades at midnight. One answer per story: a second try raises `already_answered`, a failed payment undoes everything.
- **Eligibility.** The Life moments conditions plus `partner`, `kids`, `car`, `job`, `gang`, `school`, `business` (true or false), `origin`, and `path {"trouble":{"min":15}}`. A daily story cannot use `at` or `hours`. `{partner}` and `{child}` are the real names, so a single player never reads "your wife".
- **Money.** Gains go through `bl_add_money` (reason `life_moment`, never earnings). One outcome pays at most `stories.max_cash_gain` (₦15,000), and all stories together at most `stories.daily_gain_cap` (₦25,000) a day. The seeded stories average a small net cost.
- **Seeds.** Follow-up chance is cut to `stories.followup_max_chance`, a player holds at most `stories.followup_max_pending` (4) waiting seeds, and the wait is at most `stories.followup_max_days` (7). A chapter that nobody answers fades after 7 days. Doctor and school cards are untouched.

## Streak
Answering the daily story counts the day. 3 days in a row pays **₦2,000**, 7 days **₦5,000**, 14 days **₦12,000**, each once per streak (it is paid when the step is reached, so nothing is lost; the reveal shows it). A missed day starts a new streak, and the steps can be earned again. Two stories on one day count as one day. Table `story_streak`.

## Push
The existing push job (`bl_push_tick`, every minute) calls `bl_story_push_tick()`: one "Your story for today is waiting" push per Benin day, after `stories.push_hour` (17), to players with a device and Game events on who have not read today's story and were seen in the last 3 days; and one "Your story continues" push when a follow-up is due. It goes through `bl_push_enqueue`, so the master switch, the category switch, the hourly cap and deduping all apply. Opens `/play?go=stories`.

## Weekly story: replaced
The old weekly community story (`weekly_storyline_*`, `storyline_current`, `storyline_choose`) is **replaced by the daily story**. The Stories app no longer shows it. The tables and RPCs stay so an old cached app still works, and its setting is reworded "Old weekly story". This was cleaner than running two systems: the daily engine is a superset (one story a week was one row of it).

## How it reuses Life moments
Stories are `life_moments` rows (kinds `daily` and `chapter`), so the closed lists, validators, banned words, the Admin editor and `bl_moment_apply` are shared; `path` was added to the effect list and `outcomes`/`path` to choices. Story **instances** live in `player_stories` instead of `player_moments`, so they never pop up, never use the moment daily cap and never block a random moment. `follow_up` and `bl_moment_create` route a `chapter` to `player_stories` and everything else to `player_moments`. The live functions were patched with the guarded replace (`pg_temp.ds_patch`).

## Content
50 daily rows: **46 standalone stories** (keke, okada, NEPA light, landlord, Oba Market, Ring Road, UNIBEN, church, owambe, family asks for money, a lost wallet, a "Yahoo" deal, a stranger in need, interview, flood on Sapele Road, the viewing centre, a juju rumour, love and a rumour about a partner, kids, car, gang, shop, PoS, checkpoint, Igun Street ...) plus **4 arc openers**; **39 chapters** (14 follow-ups, 25 arc chapters); 3 pop-up follow-ups; 5 blessing and police/EFCC moments. Real Benin places only, fictional people, no real politicians, parties or brands, no "Lagos". Edit them in Admin -> Content -> Daily stories.

## Admin
- **Content -> Daily stories** (the same table as Life moments, filtered): id, title, emoji, speaker, kind (`daily` / `chapter`), scene, conditions, path weights, choices with weighted outcomes, cooldown, weight. The list shows choices, outcomes and seeds per story. **Content -> Life moments** now hides them. **Content -> Path words** edits the words and subtle lines.
- **Settings -> Daily stories** (category `stories`, 30+ settings, all with label, description and limits): `stories.daily_enabled`, `per_day` (1), `no_repeat_days`, `max_nudge`, `path_strength`, `path_max_mult`, `karma_pct`, `path_decay_week`, `band_1` / `band_2`, `whisper_pct`, `luck_odds_pct`, `luck_chance_cap`, `followup_max_chance` / `_pending` / `_days`, `chapter_expire_days`, `max_cash_gain`, `daily_gain_cap`, `special_min_score`, `blessing_pct` / `_cooldown_days`, `police_pct` / `_cooldown_days`, `push_enabled`, `push_hour`, `push_max_per_tick`, `streak_days_1..3`, `streak_cash_1..3`.

## Tests
`bash scripts/sql-test.sh -- supabase/tests/daily_story_test.sql` (run it five times): grants and RLS, settings with labels, the content (40+ standalone, arcs 3 to 5 deep and branching, every follow-up exists, no wrong city), the closed list, eligibility for every condition, one story a day, deterministic pick, no repeat, answering (cost, all or nothing, weighted outcomes, path tilt, caps, seeds), the path (nudge and bounds, karma, words, subtle lines once, decay, luck, blessing, police), follow-ups arriving and expiring, arc branching, the streak, push, the switch, Admin and no client access.
