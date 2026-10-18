# Skills & progression (R3)

Inspired by LagosLife. Everything is server-side and admin-tunable; the client never sends XP.

Files:
- `supabase/migrations/20261017000400_skills.sql`, `supabase/tests/skills_test.sql` (11 groups)
- `src/api/skills.ts`, `src/state/skills.ts`, `src/screens/game/Skills.tsx` + `.css` (Skills tab, `<SkillHost/>` level-up toast)
- Hooks: `SimSheet.tsx` (Skills tab), `Game.tsx` (`<SkillHost/>`), `state/game.ts` (`skill_up` events open the toast instead of a plain one),
  `PlaceCard.tsx` and `HustlesApp.tsx` ("+15% from skill", "Needs Mechanic lvl 2"), `YahooApp.tsx` ("Needs Yahoo lvl 3", EFCC % after skill)
- Admin: `Content.tsx` (tabs Skills, Skill XP curve, Skill sources; `Skill level needed` on Hustles and Yahoo jobs), `Players.tsx` (Skills box),
  `Settings.tsx` (category Skills), `api.ts`

## Model
- `skills` (10): yahoo, driving, cooking, music, teaching, fishing, mechanic, business, fitness, charisma. Columns: pay % per level, EFCC cut % per
  level, EFCC cut cap, `trait_keys` (which `traits.effects.skill_xp.<key>` multipliers speed it up; the best one applies), blurb, where to train.
- `skill_curve`: cumulative XP per level. Default 0, 40, 120, 260, 460, 740, 1120, 1640, 2340, 3300 (levels 1 to 10). The level is never stored: it
  is worked out from XP, so a curve edit applies to everyone at once. The highest row is the max level.
- `skill_sources`: `kind` (hustle / yahoo / career / activity) + `ref` + `skill_id` + `xp`. One action can feed several skills.
- `player_skills(user_id, skill_id, xp)`: own rows readable, no client writes.
- Existing ids reused: trait keys `hustle`, `coding`, `cooking`, `music`, `dance`, `fitness`, `charisma` (career tracks keep their `skill` column
  for the trait multiplier; career XP goes through `skill_sources` kind `career`).

## Earning XP (`bl_skill_award(uid, kind, ref)`, the only place XP is given)
XP = source xp x best trait multiplier x `skills.xp_mult`, at least 1. A level-up writes a `skill_up` event (title, unlock lines, level) that the client turns into
the toast with confetti. Awarded from (patched live functions, guarded replace):
- `bl_hustle_resolve`: every finished hustle except a fraud loss.
- `bl_yahoo_resolve`: paid jobs and cash-outs (a caught run gives none).
- `bl_settle_shift`: each finished career shift (by track).
- `do_activity`: when an activity starts (cooking at home, jog round the stadium, club nights and gist, lectures, side projects...).

Default amounts: Bolt 8, PoS 6, jollof 7 cooking + 3 business, puff-puff 4+2, fried yam 5+3, DJ 12 music + 3 charisma, MC 8 + 5, tutor 8, fishing 6,
quick fix 6, engine job 12; Yahoo chat 8, romance 15, big job 30, cash out 4; career shift 5 to 6 (tech and Yahoo (IT), PoS and trade and business,
transport and driving, health and charisma, education and teaching); activities 1 to 4.
There is no gym place yet, so fitness comes from the stadium jog and chant.
Players who already ran hustles or Yahoo jobs are backfilled once by the migration (only while `player_skills` is empty).

## Effects (all in Content -> Skills)
- Hustle pay: x(1 + (level - 1) x pay %/100) on the hustle's main skill (the active source with the most XP). Default 5 %, so +45 % at level 10.
  Patched into `bl_hustle_pay_mult`, so cards, runs and results agree. Fishing pays in fish, so it is unchanged.
- Yahoo: the EFCC caught chance is cut by (level - 1) x 4 %, relative, capped at 36 % (`skills.caught_skill` picks the skill). Applied inside
  `bl_yahoo_resolve` (the stored run chance is untouched). `yahoo_status` and the run JSON also carry `skill_caught_pct` for the cards (the app shows it
  with the base struck through).
- Gates: `hustles.min_skill_level`, `yahoo_jobs.min_skill_level` (1 = open). Defaults: Big job Yahoo 3, Engine job Mechanic 2. DJ stays open.
  Refusal hint `skill_level`, message "Needs Mechanic level 2 (you are level 1). ...", short "Needs Mechanic lvl 2".
- Career promotions: not gated. Careers only have a `skill` column for the XP multiplier, not skill requirements, so this was skipped as briefed.
- Master switch `skills.enabled` (off = no XP, no gates, no effects), `skills.xp_mult` (double XP weekend).

## UI
- Sim sheet -> Skills tab: every skill with level badge, XP bar, XP to next level, current bonuses, "Level N gives" (jobs it opens, pay %, EFCC %),
  where to train and the sources with their XP.
- Level-up: tap-to-open toast at the top with confetti and the unlock line.
- Cards: zone cards and the Hustles app show "+X% from skill" and the lock "Needs Mechanic lvl 2"; the Yahoo app shows "Needs Yahoo lvl 3" and the EFCC % after skill.

## Admin
Content: Skills (effects), Skill XP curve, Skill sources, plus `Skill level needed` on Hustles and Yahoo jobs. Players -> detail -> Skills: level
picker and exact-XP box per skill (`admin_set_player_skill`, audit action `set_skill` with old and new XP and level). Settings -> Skills.

## Tests
`bash scripts/sql-test.sh -- supabase/tests/skills_test.sql`: grants and RLS, seeds and gates, hustle XP and trait multiplier, curve (and admin curve edit,
level-up event), XP from Yahoo / activity / career / xp_mult / master switch, EFCC reduction with forced rolls (level 1, 5, 10, cap, tune), gate refusals,
pay boost (+15 % at level 4, tune), admin set and audit, `skills_status`.
`hustles_test.sql` and `yahoo_test.sql` pin `skills.enabled = false` at the top (their maths is the pre-skills maths).
