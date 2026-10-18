# Crews (R11)

Players found a **crew**, recruit other players, pool money in a crew bank, level the crew up and run **group jobs** for big loot, with real
jail risk. It is a **game mechanic**: job names are abstract, there is no method of any real crime anywhere, and no real cult or gang name is used
(Benin has real cult problems). Crews are fictional names the players choose, and a blocklist in Settings keeps real names out.

Migration: `supabase/migrations/20261018001000_crews.sql`. Tests: `supabase/tests/crews_test.sql` (20 groups).
Client: `src/api/crews.ts`, `src/state/crew.ts` (status store, `<CrewHost/>` in `src/screens/game/Yahoo.tsx`), `src/screens/game/phone/CrewApp.tsx` (+ `.css`),
`src/ui/CrewTag.tsx` (the `[TAG]`), Ranks app -> Crews tab (`RanksApp.tsx`). Admin: `src/admin/Crews.tsx`, Content -> Crew jobs / Crew levels, Settings -> Crews.

## How it works
1. **Found.** Phone, Crew, Create: a name (3-20 letters/numbers, checked with the chat banned-words list and `crew.blocked_names`), a tag of 3-4 letters
   (`crew.blocked_tags`), a colour and an emblem from `crew.emblems`. Fee `crew.found_fee` (default 500,000, bank first then cash, ledger `crew_fee`).
   Founder gate: Charisma level `crew.found_min_charisma` (2) **or** an account at least `crew.found_min_account_hours` (72) old. No crew and no rejoin cooldown.
2. **Ranks.** Boss, Lieutenant, Member, Prospect. New recruits start as Prospects (`crew.new_member_rank`).
   | Action | Boss | Lieutenant | Member | Prospect |
   |---|---|---|---|---|
   | Chat, deposit, join jobs, leave | yes | yes | yes | yes |
   | Invite, open / start / cancel a job lobby, upgrade (spend bank), recruiting door | yes | yes | no | no |
   | Kick | anybody below | Members and Prospects | no | no |
   | Promote | any rank (max `crew.max_lieutenants` Lieutenants) | Prospect -> Member only | no | no |
   | Loot split, rename, transfer Boss, disband | yes | no | no | no |
   A Prospect takes `crew.prospect_share_pct` (50%) of a normal share. A Prospect cannot be made Boss.
3. **Invites.** Boss / Lieutenants invite **friends first** (the list shows friends, online first) or **anybody by username** (search 2+ letters). Each invite is an alert
   plus a push in the **friends** category (`/play?go=crew`). It expires after `crew.invite_expire_hours` (48). Limits: `crew.invite_daily_cap` (20 a day per crew), one pending
   invite per player, `crew.join_min_account_hours` (24) account age to be invited, blocked players cannot be invited. Max members come from the crew level.
   A crew can also set **recruiting** (open door): anybody eligible joins as a Prospect from Browse.
4. **Crew bank.** Members deposit (`crew_deposit`, min `crew.min_deposit`, ledger `crew_deposit`). The bank grows from job loot and weekly prizes. It is spent on
   level upgrades and renames only, by the Boss / Lieutenants. Every movement is a `crew_bank_log` line (deposit, job, upgrade, fine, prize, fee, refund), shown in the Bank tab.
5. **Levels.** `crew_levels` (Content -> Crew levels): XP needed, cost from the bank, max members, loot bonus %, perks text. Defaults: 1 Street crew (6 members), 2 Block crew
   (XP 100, 1M, 10 members, +5%), 3 District crew (XP 300, 3M, 15, +10%), 4 City crew (XP 700, 8M, 20, +15%), 5 Big name crew (XP 1500, 20M, 30, +20%).
   Crew XP comes from **paid** jobs only (a bust gives none). Levelling is a choice: enough XP **and** the cost in the bank, then Upgrade.
6. **Chat.** There is no group-chat concept in Messages ("Groups" there is place chat), so the crew has its own chat (`crew_messages`), polled every 4 s while open.
   Same mask / clean rules as place chat, a rate limit (`crew.chat_rate_seconds`, `crew.chat_burst_per_minute`), mutes apply, old messages are deleted lazily.
7. **Leave, kick, transfer, disband, cooldown.** Leaving or being kicked starts the `crew.rejoin_cooldown_hours` (48) cooldown on joining **and** founding. The Boss cannot
   leave: transfer first or disband. Nobody can leave or be kicked while on a running job; the crew cannot be disbanded mid-job. A disband (Boss or admin) shares the bank
   equally into the members' **bank** accounts (ledger `crew_refund`, rounding to the oldest member). If the Boss's account disappears the oldest Lieutenant takes over; an empty crew closes.

## Jobs
`crew_jobs` (Content -> Crew jobs): abstract names and a one-line flavour blurb only. Seeded (all admin-editable):
| Job | Crew lvl | Members | Time | Pot (whole) | Caught | Cooldown | Supplies each | Skills |
|---|---|---|---|---|---|---|---|---|
| Night market shakedown | 1 | 2-4 | 60 s | 300k-900k | 22% | 20 min | 0 | Charisma |
| Hit a container at the port | 2 | 3-5 | 90 s | 1.2M-3.5M | 30% | 45 min | 20k | Fitness, Driving |
| Ring Road warehouse job | 2 | 3-6 | 90 s | 2M-5M | 32% | 60 min | 30k | Fitness, Charisma |
| Bank van job | 4 | 4-8 | 150 s | 8M-25M | 40% | 3 h | 100k | Driving, Fitness, Charisma |
Flow (server side; tables `crew_runs`, `crew_run_members`):
1. **Lobby.** A Boss / Lieutenant opens a job (`crew_job_open`): crew level, the per-crew job cooldown, `crew.max_jobs_per_day` (8), one open job per crew, enough members in the
   crew. Everybody in the crew gets an alert and a friends push. The countdown is `crew.lobby_seconds` (120).
2. **Join.** Members who are **online** (seen within `time.presence_real_minutes`), free (not busy, jailed, in hospital, on the road) and standing at a **meeting spot**
   (`crew.meeting_places`, default Upper Sakponba, Third East Circular and Siluko Road: street corners, no CCTV) join with `crew_job_join`. Up to the job's max members.
3. **Start.** A leader presses Start now (needs the minimum), or the countdown ends (the next status call by any member starts it; no cron). At the start everybody is checked again:
   a member who walked away, got busy, left the crew or cannot pay the supplies is **dropped** (and told). Fewer than the minimum left = the job is called off and nobody is charged.
   The supplies (`buy_in`, bank first then cash, ledger `crew_job`) are taken, the members are busy ("Crew job: ...") and the chance is fixed.
4. **One roll** at the end of the duration (`bl_crime_roll`, tests pin `bl.test_rand`).
   - **Chance:** the job's caught % cut by the **average level of the job's skills** over the crew: each player's average over the job's skills, then the crew's average;
     cut = (average - 1) x `crew.skill_cut_per_level` (1.5) %, at most `crew.skill_cut_cap` (30) %, relative. Example: base 22%, Charisma average 4 -> -4.5% -> 21.01%. Skills off = no cut.
   - **Caught:** every participant gets a **jail case through the existing jail flow** (`jail_cases`, kind `police`): the "Police don catch you!" popup with bail
     (`crew.bail_base`, default 20M like pickpocketing), go to jail (`crew.jail_seconds` 120) or escape (the usual doubling), held at Police HQ, wanted +1. Nobody is paid, the
     supplies are lost, and the crew bank pays a fine of `crew.bust_fine_pct` (15%) of the bank, at most `crew.bust_fine_max` (2M) ("part of the loot is lost"). No crew XP.
   - **Paid:** pot = random(pot range) x (1 + level bonus %) x (1 + `crew.member_bonus_pct` (8%) per extra member). The crew bank takes the **Boss's share** (default 30%,
     allowed 10-80%, `crew_options`); the rest splits into the members' **cash** (ledger `crew_payout`) by weight (Prospect 0.5, everybody else 1), rounded down to 100. The rounding
     and the Prospects' unclaimed part go to the crew bank, so every naira of the pot is accounted for. Crew XP, the members' job count, and Charisma / Fitness / Driving XP
     (skill sources kind `crew`) are awarded.
5. **Safety.** A crew job never takes money from another player: the only things that move are the crew's own members' supplies, the crew bank and new loot. Pickpocketing
   stays exactly as it was. Rate limits and cooldowns: per-job cooldown per crew, jobs per day, invites per day, chat rate, one report per player per crew (5 a day).

## Meeting spot, not a hideout
A members-only hideout building was **not built** (it would need a new interior, gating and travel code). Crews meet at the public **meeting spots** instead
(`crew.meeting_places`). Being there also means other players can see you.

## Tag next to names
`[RNG]` (the crew colour) shows next to names in: the people-here list and the tap-a-player sheet (`players_here`, `get_public_profile`), place chat (a `crew_tag`
column stamped on each message by a trigger, `bl_chat_row`), the friends list (`bl_friend_card`), your own Sim sheet and People row, the Ranks -> Crews board and the crew app.
These five live functions were patched with guarded replaces (`pg_get_functiondef`, raise when a marker is missing, grants kept).

## Top crews (turf, light)
Ranks app -> **Crews** tab: this week's crews by loot (the pots of paid jobs), then jobs done. The first call after a week closes (Monday 00:00 Benin time) settles it, once:
the top three crews with at least `crew.weekly_min_jobs` (2) paid jobs get `crew.weekly_prize_1/2/3` (500k / 250k / 100k) **into the crew bank** (bank log "prize") and an alert.
`crew.weekly_enabled` switches it. The week the migration ran is skipped (no retroactive prize).

## Ledger and weekly top earners
| Reason | Meaning | Counts as earned (weekly top earners, challenge "earn") |
|---|---|---|
| `crew_payout` | a member's loot share | **yes** (added once to `leaderboard.earn_reasons`) |
| `crew_deposit` | member to crew bank | no (a transfer) |
| `crew_fee` | founding fee | no (spending) |
| `crew_job` | job supplies | no (spending) |
| `crew_refund` | bank shared out on a disband, buy-ins returned | no (a transfer back; counting it would let a deposit and a disband farm "earnings") |
Decision: loot is earned money; deposits and refunds are transfers, so they never count. The crew bank is not a player ledger: its lines live in `crew_bank_log`.

## Report and admin
- **Report crew** (name abuse): `crew_report` (Browse, Report). Admin sees the open count; `crew.report_flag_count` (3) highlights a crew.
- **Admin -> Crews:** list (boss, level, members, bank, jobs, loot, reports), **Members** view (**audited** as `crew_view`), Rename (name and tag, same word / real-name checks, audited `crew_rename`),
  **Disband** (audited `crew_disband`, bank shared out, members told, no rejoin cooldown), mark reports reviewed (audited).
- **Content -> Crew jobs** and **Crew levels**: every number above. **Settings -> Crews**: every `crew.*` key.

## Settings (Settings -> Crews)
`crew.enabled`, `found_fee`, `found_min_charisma`, `found_min_account_hours`, `join_min_account_hours`, `rejoin_cooldown_hours`, `invite_expire_hours`, `invite_daily_cap`, `max_lieutenants`,
`new_member_rank`, `default_bank_pct`, `bank_pct_min`, `bank_pct_max`, `prospect_share_pct`, `min_deposit`, `rename_fee`, `rename_cooldown_days`, `meeting_places`, `lobby_seconds`, `max_jobs_per_day`,
`member_bonus_pct`, `skill_cut_per_level`, `skill_cut_cap`, `jail_seconds`, `bail_base`, `bust_fine_pct`, `bust_fine_max`, `chat_max_len`, `chat_rate_seconds`, `chat_burst_per_minute`,
`chat_retention_hours`, `report_flag_count`, `blocked_names`, `blocked_tags`, `emblems`, `weekly_enabled`, `weekly_prize_1..3`, `weekly_min_jobs`. `crew.enabled = false` refuses founding,
joining, inviting and new jobs; running jobs still finish, leaving and chat still work.

## RPCs
Players: `crew_status`, `crew_browse`, `crew_create`, `crew_invite_candidates`, `crew_invite`, `crew_invite_cancel`, `crew_invite_respond`, `crew_join_open`, `crew_leave`, `crew_kick`, `crew_set_rank`,
`crew_transfer`, `crew_disband`, `crew_options`, `crew_rename`, `crew_deposit`, `crew_upgrade`, `crew_bank_log_list`, `crew_chat_send`, `crew_chat_recent`, `crew_report`, `crew_top`, `crew_job_open`,
`crew_job_join`, `crew_job_leave`, `crew_job_cancel`, `crew_job_start`. Admin: `admin_crews_list`, `admin_crew_get`, `admin_crew_disband`, `admin_crew_rename`, `admin_crew_dismiss_reports`.
All security definer, granted to `authenticated` only; every `bl_crew_*` helper (and the two triggers) is revoked from clients. All crew tables have RLS and no client access (only the job and level
catalogues are readable); players always go through the RPCs. Lock order everywhere: crew row, then the players' rows (in id order).

## Defaults the owner should know
Founding costs 500,000; a founder needs Charisma 2 or a 72 hour old account; 48 hour rejoin cooldown; new recruits are Prospects (half share); the crew bank takes 30% of loot (Boss can set 10-80%);
the four jobs above (22-40% caught, supplies 0-100k each, 20 min to 3 h cooldown per crew, max 8 jobs a day); a bust jails every participant with the pickpocket bail (20M, so most serve the 2 minutes or
escape) and costs the crew bank 15% (max 2M); weekly Top crews prizes 500k / 250k / 100k into the crew bank; blocked name words include the real cult names.
Pot sizes are not yet part of the E3 economy audit: a 5-member port job pays about 2.3M-4.5M, so check them there.

## Not built
A members-only hideout building (meeting spots instead), turf fights between crews, per-crew perks beyond the loot bonus and member cap, NPC members, crew-vs-crew jobs, banning a player from crew chat
separately from the global mute, and a realtime channel for crew chat (it polls).

## Tests
`bash scripts/sql-test.sh -- supabase/tests/crews_test.sql` (20 groups): grants / RLS / private helpers, seeds, create (fee bank-first, name moderation incl. real names, founder gate, switch), invites
(friends first, username, gates, rate limit, expiry, full), ranks and permissions, bank (deposit, log, spend refused), lobby (refusals, join gates, start), paid run with the exact split and ledger, busted
run (jail for all, fine, no loot, jail flow works), skill cut (levels, average, cap, skills off), cooldown / daily cap / auto start / dropped member / too few, level up unlocks (bonus, supplies, Prospect half
share), leave / kick / transfer / rejoin cooldown / on job, recruiting / browse / report, crew chat, tag in places / profile / chat / friends, weekly settle (prize into the bank, once), disband and
refunds, admin (audited view, rename, disband, reports, content tables), earned vs transfer.
