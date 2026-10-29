# Politics: Benin Votes (R12)

A **fictional, light, satirical** game system. Players run for office in the city, campaign, vote at polling units and, if they win, get a title, a daily
salary and small powers for a term. **No real party** (APC, PDP, LP and so on) and **no real politician** appears anywhere: parties are seeded made-up
ones (Progressive Benin Movement, Oba-Town People's Party, Benin Unity Alliance, Jollof Justice Party) or founded by players, and a blocklist in Settings
refuses real names in party names, abbreviations, promises and announcements. The election body is fictional too ("Benin Votes"). There are no
real-world election claims and no vote buying (there is a report button).

Migration: `supabase/migrations/20261018001100_politics.sql`. Tests: `supabase/tests/politics_test.sql` (14 groups).
Client: `src/api/politics.ts`, `src/state/politics.ts` (status store, `<PoliticsHost/>` in `src/screens/game/PollingStrip.tsx`),
`src/screens/game/phone/PoliticsApp.tsx` (+ `.css`), `src/screens/game/PollingStrip.tsx` (polling-unit line on the place card, election-day banner),
`src/ui/OfficeTag.tsx` (the title badge). Admin: `src/admin/Elections.tsx`, Content -> Offices / Policies / Parties / Wards, Settings -> Politics.

## The election cycle (real time, all admin-tunable)
All offices are elected **together in one cycle** (simplest and most fun: "election week"). One cycle at a time (`election_cycles`, a unique index allows only one open).
| Phase | Default | What happens |
|---|---|---|
| Registration | 48 h (`pol.registration_hours`) | candidates declare (fee, requirements) |
| Campaign | 72 h (`pol.campaign_hours`) | rallies, posters, promise edits, supporters / endorsements / crew endorsements |
| Voting day | 24 h (`pol.voting_hours`) | polling units open, every eligible player votes once per office |
| Results + swearing-in | at the close | tally, tie-breaks, the old government steps down, winners are sworn in |
| Term | 14 days (`pol.term_days`) | titles, salaries, powers. Commissioners and policies end with it |

The clock is **lazy** (no cron): every Benin Votes call (`pol_status` and all actions) first runs `bl_pol_tick()`, which moves the cycle to the next phase when its time has
come, settles a closed cycle, pays salaries that are due and ends terms. Phase times are stored on the cycle row when it starts, so changing Settings later does not move a running
election. The game polls `pol_status` every 2 minutes (and just after the next phase boundary), so the banner and the app flip on time.

**The next cycle starts itself** (`pol.auto_cycle`, default on) after a cycle that was **closed**: it is due `term_days - (registration + campaign + voting)` after the results
(default 14 d - 6 d = 8 days), so the next results land when the term ends. The first election is started by an admin (Admin -> Elections). A **cancelled** election never restarts by itself, and
auto off means an admin starts every election. If a cycle closes with no candidates, nothing is filled and the old government has already ended its term.
Whoever wins replaces the **whole** government at the close (a seat with no candidate stays vacant).

## Offices (Content -> Offices, table `offices`)
| Office | Seats | Title | Fee | Needs | Salary / day |
|---|---|---|---|---|---|
| Councillor | one per ward (8) | Hon. | 10,000 | account 3 d, lives in the ward | 20,000 |
| Chairman of the City | 1 | Chairman | 50,000 | account 5 d, Charisma 2 | 50,000 |
| Governor | 1 | Gov. | 250,000 | account 7 d, Charisma 4, a BSc **or** Business Management certificate **or** career level 5 | 100,000 |
| 6 Commissioners (Works, Finance, Youth & Sports, Information, Commerce, Security) | 1 each, appointed | Comm. | none | account 3 d to be appointed | 40,000 |
Everyone also needs: **not in jail**, and **no EFCC case** (a Yahoo bust, `jail_cases.kind = 'efcc'`) in the last `pol.clean_record_days` (7). Charisma rules need `skills.enabled`.
A Councillor runs in the **ward where they live** (their home's map district decides the ward). One candidacy per player per election. A player holds one office at a time.
Every number is editable; a player's status shows a ✓ / ✗ checklist per office.

## Godfather ticket (paid bypass of the requirements)
Migration `supabase/migrations/20261022000100_godfather_ticket.sql`, tests `supabase/tests/godfather_ticket_test.sql`. A player who fails the requirements can buy a ticket when declaring (`pol_declare(..., p_ticket := true)`), **on top of** the normal fee.
- **Prices** (Content -> Offices, column `ticket_price`, empty = no ticket): Councillor 5,000,000,000, Chairman 25,000,000,000, Governor 50,000,000,000 (raised in 20261022000200_ticket_prices, EFCC probe 10 %), Commissioners none (appointed). Seeded once, never overwritten.
- **Settings** (Settings -> Politics): `pol.ticket_enabled` (true), `pol.ticket_probe_pct` (25, percent), `pol.ticket_report_flag_count` (1).
- **Waives**: account age, Charisma, education / career (BSc, Business certificate, career level) and the clean-record (EFCC case) rule. **Also waives jail** (20261022000300_ticket_for_all: owner "nothing can stop a Godfather") and can be bought by a player who already qualifies. **Does not waive**: the Councillor ward rule, one candidacy per election, race caps, promise moderation, the fee.
  Refused with `ticket_not_needed` when every requirement is met, and with `ticket_off` when the switch is off or the office has no price. `pol_status` returns `ticket_price` and `ticket_available` (something fails and the ticket covers all of it) per office.
- **Payment**: fee + ticket in one transaction, bank first then cash, all or nothing. Ledger `godfather_ticket` ("Godfather ticket"): a pure sink, never earned (also blocked in `bl_earn_reasons` if listed in `leaderboard.earn_reasons`); Admin -> Economy files it under fees. Admin **Cancel** refunds the ticket (a credit, like the fee). Withdrawing, an admin disqualification and an EFCC catch refund nothing.
- **Bad sides**: (1) the candidate is tagged `🎟️ Godfather ticket` on candidate cards, the ballot and the Admin candidates table; (2) a **secret EFCC probe**: at declare time the server rolls (`pol.ticket_probe_pct`) whether EFCC will catch them, and a random time inside the campaign window (from now if later). Stored only in `pol_ticket_probes` (RLS on, no client policy, no grant, never returned by any RPC). `bl_pol_tick()` resolves due probes first (also on voting day, before the count): caught = disqualified (reason `EFCC probe: godfather ticket`, votes voided, alert `pol_disqualified`), cleared = alert `pol_ticket_cleared` ("found nothing... this time"); (3) vote-buying reports flag a ticket candidate for admin at `pol.ticket_report_flag_count` instead of `pol.report_flag_count`.

## Wards and polling units (Content -> Wards, table `wards`)
Eight wards = the business areas: Ugbowo, Uselu, Ring Road, GRA, Sapele Rd, New Benin, Ikpoba Hill, Airport Rd. Each lists the map districts that belong to it (so
Oluku counts as Ugbowo, Aduwawa as Uselu, Ekenwan as Airport Rd and so on) and has one **polling unit** place: `pu_ugbowo`, `pu_uselu`, `pu_ring_road`, `pu_gra`, `pu_sapele_rd`,
`pu_new_benin`, `pu_ikpoba_hill`, `pu_airport_rd` (street scene, at least 46 map units from every other pin). They are **open only on voting day**: `bl_place_open` is patched so a place id
starting `pu_` is open exactly while a cycle is in its voting window, travel there is refused otherwise ("Polling units open on voting day only"), and anybody still inside when it closes is
sent home by the usual closed-place rule. Each has a **Polling desk** zone with a "Vote here" card that opens Benin Votes on the Vote tab. The place card shows a polling-unit line
("Election day" while open) and the game shows an **Election day banner** (and a "registration open" one) above the place card.

## Campaigning
- **Declare** (`pol_declare`): office, promise (10 to 140 characters, moderated), party or independent. Fee through the usual pay rule (bank first, then cash), ledger `campaign_fee`.
  Charisma XP for declaring. A candidate can edit the promise (registration and campaign) or withdraw (the fee is not refunded).
- **Rally** (`pol_rally`, campaign only): where you stand, a public place (not home, not a polling unit, open now); Councillors must be inside their ward. Costs `pol.rally_cost` (20,000, ledger
  `campaign_spend`), gives Charisma XP (skill source `politics:rally`), `pol.rally_points` (10) + `pol.rally_attendee_points` (2) for every other online player standing there (at most
  `pol.rally_attendee_cap` 10): a crowd beats cash. Cooldown 20 min, 6 a day. It is **announced in the place** (a `place_announcements` row, kind `rally`) and everybody there gets an alert.
- **Poster** (`pol_poster`): the simple "campaign poster" slot (billboards were not reused: their system is paid ads with owners and moderation of its own). `pol.poster_cost` 10,000, 3 points, cooldown 6 h, at most 5.
- **Backing** (`pol_back`, registration and campaign): one backing per player per race, switching moves it. **Support** (anonymous, free, `pol.support_points` 1), **Endorse** (named, needs Charisma
  `pol.endorse_min_charisma` 2, 4 points), **Crew endorsement** (a crew Boss or Lieutenant, the crew needs `pol.crew_endorse_min_members` 2, one per crew per race, 8 points, the crew tag shows on the card).
  Backing needs an account older than `pol.vote_min_account_days` (anti-alt); you cannot back yourself.
- **Momentum**: points = rally points + posters x 3 + backing points, shown **against the leader of the race** as a bar and a label (Leading, Close behind, Chasing, Cold, No momentum yet). It carries
  **no vote counts**. It is not money alone: endorsements and crews count, and rallies scale with the crowd.
- **Vote buying is not a mechanic.** Every candidate card has **Report vote buying** (`pol_report_vote_buying`, one per player per candidate, 5 a day, old accounts only). Admin sees the open reports
  (`pol.report_flag_count` 3 highlights a candidate) and can disqualify.
- Blocklists (`pol.blocked_words`, `pol.blocked_party_words`): real politicians, the real election body and real parties. Words of 3 letters or fewer (APC, PDP, LP ...) match whole words only; longer ones match
  ignoring spaces and punctuation. The chat banned words and a no-links rule apply too.

## Voting (`pol_vote`, `pol_ballot`)
Server side only. Rules: voting is open (cycle in its voting window by the **clock**, not a stale status), the account is older than `pol.vote_min_account_days` (3), not banned, not in jail,
**standing at your own ward's polling unit** (not travelling, not visiting a house), the candidate is on the ballot, a Councillor race must be your ward. **One vote per account per office per
election** (a unique key; a second try says "already voted"). Your ballot (`pol_ballot`) lists your ward's Councillor race, the Chairman and the Governor, in a per-voter shuffled order; it says **that** you voted, never
**for whom**. **Ballot secrecy**: `pol_votes` is closed to every client; `pol_results` and `admin_pol_tallies` return nothing until the cycle closes; the admin page shows turnout only (votes and voters); `final_votes` is written at the close.
Admin disqualification during voting voids the votes cast for that candidate (those voters can vote again).

**Tally and ties**: most votes wins; a tie is broken by **most rally points**; if those tie too, a **deterministic coin flip** (the lowest `md5(cycle : race : player : coin)` wins, so it is fixed
once the candidates are fixed). The result row says `tie = rally` or `coin`, and the Results tab shows "won on rally points" / "won on a coin flip". **Low turnout is fine**: a lone candidate wins even with 0 votes.

## In office
- **Title badge** (`bl_pol_title`): next to the name in the people-here list, the tap-a-player sheet, public profiles (`get_public_profile.title`), place chat (stamped on each message in `chat_messages.pol_title`
  by a trigger, like the crew tag), friend cards, and your own Sim sheet. Five live functions were patched with guarded replaces.
- **Salary**: `offices.salary_per_day` for every full day of the term, paid lazily (to the bank, ledger `office_salary`, **counted as earned**: added once to `leaderboard.earn_reasons`). Never past the
  term end; `pol.salary_enabled` switches it.
- **Governor**: appoint (`pol_appoint`, by username, account age `pol.appoint_min_account_days`, not already in office) and sack (`pol_sack`) the six Commissioners (they serve to the end of the Governor's term);
  **one Government announcement a day** (`pol_announce`, 24 h cooldown, 200 characters, moderated like chat) through the existing broadcast system (a `broadcasts` row to everyone: Alerts inbox popup and the
  Announcements push, titled "Government announcement: Gov. @name", expiring after a day); **ONE policy per term** (`pol_set_policy`) from the whitelist below.
- **Policies** (Content -> Policies, `gov_policies`; effects apply server side while the Governor is in office, small values):
  | Policy | Effect | Default | Patched into |
  |---|---|---|---|
  | Keke Fridays | keke fares cheaper on a weekday (5 = Friday, Benin time) | -30% | `bl_travel_quote` (cost line) |
  | Market levy holiday | council levy chance for business owners | -25% (relative) | `bl_biz_settle` |
  | Youth sports week | Fitness XP | +25% | `bl_skill_award` |
  | Clean Benin | hygiene decays slower | -20% | `bl_decay_row` |
  With no policy (or the switch off) every multiplier is exactly 1.
- **Councillor**: one **ward notice** per term (`pol_ward_notice`): an alert to the ward's recently active residents (last 3 days, at most 300), moderated.
- **Resign** (`pol_resign`); a resigning Governor ends the Commissioners. **Impeachment / recall (the optional petition) was not built**: admins can remove a holder (below).

## Pushes and alerts
Events-category pushes (opt-in, `push.cat_events`) to every player with a device: **registration open**, **voting day**, **results are out** (deduped per cycle). Alerts to candidates and holders: `pol_won`, `pol_lost`,
`pol_appointed`, `pol_sacked`, `pol_removed`, `pol_disqualified`, `pol_cancelled`, `pol_rally` (people at the rally), `pol_ward_notice`. Deep link `go=politics` (and `politics:vote`, `politics:elect`).

## Admin (Admin -> Elections, and Content / Settings)
- **Elections page**: the cycle with its dates, turnout; **Start** (optional hours override per window), **Advance** (ends the current phase now; later windows keep their length), **Cancel** (reason; every declared
  candidate's fee is refunded, ledger `campaign_fee` as a credit; the sitting government stays); the candidates table with rally points, backing, **vote-buying reports (text)** and **Disqualify** (reason required,
  audited `pol_disqualify` with the votes voided; reports marked reviewed); **Remove from office** (reason, audited `pol_remove_holder`; removing a Governor ends the Commissioners); History with **Tallies** (closed only).
  Audit actions: `pol_start`, `pol_advance`, `pol_cancel`, `pol_disqualify`, `pol_reports_dismiss`, `pol_remove_holder`.
- **Content tabs**: Offices, Policies, Parties, Wards. **Settings -> Politics**: every `pol.*` key.

## Settings (Settings -> Politics)
`pol.enabled`, `auto_cycle`, `registration_hours`, `campaign_hours`, `voting_hours`, `term_days`, `vote_min_account_days`, `clean_record_days`, `max_candidates_per_slot`, `promise_max_len`, `party_fee`, `rally_cost`,
`rally_points`, `rally_attendee_points`, `rally_attendee_cap`, `rally_cooldown_minutes`, `rally_max_per_day`, `poster_cost`, `poster_points`, `poster_cooldown_hours`, `poster_max`, `support_points`,
`endorse_points`, `crew_endorse_points`, `endorse_min_charisma`, `crew_endorse_min_members`, `report_flag_count`, `report_daily_cap`, `salary_enabled`, `announce_cooldown_hours`, `announce_max_len`,
`ward_announce_max_len`, `appoint_min_account_days`, `blocked_words`, `blocked_party_words`. `pol.enabled = false` refuses every write, freezes the clock and switches the titles, salaries and policies off.

## Ledger
| Reason | Meaning | Counts as earned |
|---|---|---|
| `campaign_fee` | candidacy fee, party fee (a credit when an election is cancelled) | no |
| `campaign_spend` | rally, poster | no |
| `office_salary` | the daily salary | **yes** |
| `godfather_ticket` | Godfather ticket (a credit when an election is cancelled) | no |

## RPCs
Players: `pol_status`, `pol_candidates`, `pol_ballot`, `pol_results`, `pol_party_create`, `pol_declare`, `pol_set_promise`, `pol_withdraw`, `pol_rally`, `pol_poster`, `pol_back`, `pol_unback`,
`pol_report_vote_buying`, `pol_vote`, `pol_appoint`, `pol_sack`, `pol_announce`, `pol_set_policy`, `pol_ward_notice`, `pol_resign`. Admin: `admin_pol_overview`, `admin_pol_start`, `admin_pol_advance`,
`admin_pol_cancel`, `admin_pol_disqualify`, `admin_pol_dismiss_reports`, `admin_pol_remove_holder`, `admin_pol_tallies`. All security definer, granted to `authenticated` only; every `bl_pol_*` helper (and the chat trigger)
is revoked from clients. All politics tables have RLS and no client access except the four catalogues (offices, gov_policies, wards, parties). Patched live functions (guarded replace on `pg_get_functiondef`, grants kept):
`players_here`, `get_public_profile`, `bl_chat_row`, `bl_friend_card`, `bl_ledger_label`, `bl_admin_table_spec`, `bl_place_open`, `bl_travel_quote` (two patches), `bl_skill_award`, `bl_decay_row`, `bl_biz_settle`,
`bl_zone_action_check`, `place_interior`.

## Defaults the owner should know
- Nothing happens until an admin starts the first election (Admin -> Elections). After that the next ones start themselves (turn off with `pol.auto_cycle`). A cycle is 6 days (2 + 3 + 1) and a term is 14 days.
- Fees: Councillor 10,000, Chairman 50,000, Governor 250,000, a party 50,000. Salaries: 20,000 / 50,000 / 100,000 / 40,000 per day. A full governor term pays 1.4M. Rally 20,000, poster 10,000.
- Voting needs an account at least 3 days old (also backing and reporting).
- Winners replace the **whole** government (a vacant seat stays vacant); there is no incumbent carry-over.
- Polling units are always on the map but **closed except on voting day**.
- Titles are part of the badge line: Hon., Chairman, Gov., Comm. (edit in Content -> Offices).
- The blocklists contain a starter set of real party and politician names. Add more in Settings -> Politics when you hear them.

## Not built
Impeachment / recall by petition (admin can remove a holder), staggered cycles (one cycle for everything), reusing the billboard ad slots for posters, per-ward Councillor events beyond the one notice, party membership or party
funding, run-offs, a realtime channel for the app (it polls), a "no campaigning near the polling unit" radius (rallies simply cannot be held at a polling unit).

## Tests
`bash scripts/sql-test.sh -- supabase/tests/politics_test.sql` (14 groups, time travel with `bl.test_offset_seconds`): grants / RLS / private helpers, seeds, cycle phases (start, advance, windows), parties and declare (requirements, fee bank
first, moderation, race cap, withdraw), campaign (rally cost / XP / announcement / crowd points / cooldown / daily cap, poster, supporters, endorsements, crew endorsement, momentum, reports), voting (not open, wrong place, young
account, wrong ward, travelling, jail, once per office, ballot shows that not for whom, secrecy before the close), close (tallies, tie by rally points, coin flip, lone candidate, vacant seats, alerts), swearing-in (holders, titles in
places / profile / chat / friends, salary accrual, ledger, earned), Governor (appoint, sack, policy once + effects on travel, Fitness XP, hygiene, levy, announcement moderation and rate limit, ward notice, resign),
polling units open only on voting day, auto cycle timing, admin (disqualify + audit + voided votes, reports, remove holder, cancel + refunds, secrecy), term end (last salary stops, policies stop, cancelled never restarts),
switch off, removing a Governor.
`map_geo_test.sql` and `places_test.sql` were pinned: the 8 `pu_*` polling units are counted separately (like the business plots) and `politics` is an allowed panel ref.


## E3 retune (migration `20261019000100_economy_balance.sql`, docs/BALANCE.md)
Salary is paid for holding the seat. Per day: Councillor ₦20k -> **₦10k**, Chairman ₦50k -> **₦25k**, Governor ₦100k -> **₦50k**, each Commissioner (appointed, so an alt can hold one) ₦40k -> **₦15k**. The fees (₦10k / ₦50k / ₦250k), rally and poster costs are unchanged. `politics_test` pins the old salaries.

## More seats (migration `20261025000100_more_seats.sql`, test `more_seats_test.sql`)
Three new city-wide elected seats, kind `chairman` (a plain seat: title, badge, salary, a race on every ballot, no powers), sorted after the Governor:
| Office | Title | Fee | Needs | Salary / day | Godfather ticket |
|---|---|---|---|---|---|
| Youth Leader of Benin | Youth Ldr. | 5,000 | account 1 d | 5,000 | 1B |
| Speaker of the House | Rt. Hon. | 30,000 | account 5 d, Charisma 2 | 20,000 | 15B |
| Deputy Governor | Dep. Gov. | 150,000 | account 7 d, Charisma 3 | 35,000 | 35B |
All editable in Content -> Offices. A seat added while an election is past registration has no candidates that cycle (vacant until the next one).
`politics_test.sql` switches the three off to keep testing the original three races.

## Industry offices and My Office (docs/OFFICES.md)
Industry offices (Governor of the Bank and the Commissioners of transport, health, markets and trade, education, housing, power) live in their own tables and are filled by admin appointment; the election is untouched. The title badge slot: an **elected office title wins**, then an industry office, then a bought Chief title (`bl_pol_title`). A player who is sworn into an elected seat loses an industry office (one office at a time).
The holder-only **My Office** phone app now holds the doing for political holders too: the Governor's Commissioner appointments, daily announcement and policy, and the Councillor's ward notice are the same component (`MyOffice`) and RPCs, shown in My Office. Benin Votes -> Government shows who holds what, the Industry offices list, and an "Open My Office" card for holders. The RPCs still check the seat on the server.
