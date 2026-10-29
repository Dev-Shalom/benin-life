# Admin grants: give a player anything

Owner request: "In the admin I want to control everything. I can already grant players money, business levels and other things. I want to be able to grant a player ANYTHING that exists in the game. For example a career level: it is up to me to give a player the amount of career level I choose. I do this from the admin side, on the player's own page."

Where: **Admin → Players → tap a player → Grant toolbox** (below the money box). Eleven collapsible sections, one open at a time, made for a phone (390 px, big tap targets, nothing scrolls sideways). The search box at the top ("Jump to: career, items, car, home, gang…") narrows the list; if only one section matches it opens by itself.

Migrations: `20261107000100_admin_grants_core.sql`, `20261107000200_admin_grants_things.sql`, `20261107000300_admin_grants_assets.sql`. Test: `supabase/tests/admin_grants_test.sql` (17 groups). UI: `src/admin/Grants.tsx` + `Grants.css`, wrappers in `src/admin/api.ts` (`adminApi.grant*`), audit text in `src/admin/grantAudit.ts`.

## How every grant behaves
- **Two taps.** Each grant, set or take button says "Tap again to confirm" first. Then a green toast with the result, and the numbers next to the controls refresh.
- **Admin only.** Every RPC starts with `bl_admin_guard()` (admin and not banned). Clients never write tables.
- **Validated.** Ids must exist, levels stay inside the game's real maximum (career level 1 to the job's top, business level 1 to the type's `max_level`, skill levels as before), quantities are limited, and anything the game refuses is refused with a plain message (a car the player already owns, more furniture than `max_qty`, a garage that does not fit the home, a business that is for sale on the Market, a player in the middle of a shift).
- **Same paths as the game.** Items use `bl_give_item`, furniture uses the same key numbering as `furniture_buy` / `furniture_sell`, homes use `bl_home_enter` (the move-house path), courses use `bl_cert_award` (the graduation alert and unlocks), crew joins use `bl_crew_add_member` (the gang is told), businesses re-settle first (`bl_biz_settle`) and re-sync the map pin (`bl_biz_loc_sync`).
- **Reason.** Required (3+ letters) for levels and money-like grants (career, status numbers, debts, Yahoo rank, jail, business and company changes, home, property, land, chief title). Optional for items, furniture, clothes, garage, passes, gang. The reason goes in the audit log and the player sees it.
- **Audited.** One `admin_audit` row per grant: who, player, what, old, new, reason (action names `grant_career`, `grant_item`, `take_item`, `set_numbers`, `jail_put` …). They show in Admin → Audit log (with a one-line summary) and in the player's "Admin history".
- **The player is told.** A normal alert in their Alerts (event kinds `admin_grant`, `admin_take`, `admin_jail`, `police_release`; toast tone green for gifts), for example "An admin gave you career level 3 (Staff Nurse, Health). Pay is ₦12,000 a shift. Reason: …". Nothing is rate limited or batched.
- **Never earned income.** No grant writes the ledger or a receipt, so nothing counts in `leaderboard.earn_reasons`, weekly earners or the tax. Gifts keep their cost basis at 0 (`invested`, property `basis`, land `cost`), so a gifted business or home cannot be sold back for cash profit.
- **No banned or deleted targets.** A banned account is refused ("Unban it first"); a deleted account has no Sim row ("That player doesn't exist"). Taking things back from a banned account is still allowed.
- **Safe states.** Career changes are refused mid-shift; moving a home is refused when the player is busy, jailed, travelling, visiting or hosting guests, owes rent, or has builders changing the whole home; business and company changes are refused while the thing is listed on the Market; a property someone lives in cannot be taken.

## Audit: everything a player can own, earn, level or hold

| Thing | Where it lives | Grant before | Grant now |
|---|---|---|---|
| Money, cash and bank | `profiles.cash / bank` | yes (give or take) | yes (unchanged) |
| Certificates | `player_certificates` | yes (grant, revoke) | yes (unchanged) |
| Lounge membership | `lounge_members` | yes | yes (unchanged) |
| House upgrades | `player_house_upgrades` | grant only | grant (no remove: it changes the home) |
| Businesses (give, remove) | `businesses` | yes | yes (unchanged) |
| **Business level, staff, insurance, stock** | `businesses.level / staff / insured_until / stock_until` | no | **yes** (`admin_business_set`) |
| **Companies: give one** | `companies`, `company_branches` | no | **yes** (`admin_company_grant`); remove stays on Admin → Companies |
| **Company size, staff, manager, generator** | `companies`, HQ `company_branches.format_id` | no | **yes** (`admin_company_set`) |
| Skills, level and XP | `player_skills` | yes | yes (unchanged) |
| Origin | `profiles.origin` | yes | yes (unchanged) |
| Sending-money trust | `profiles.transfer_trusted` | yes | yes (unchanged) |
| **Career: job, level, XP, promote, demote, remove job** | `profiles.job_id / job_level / job_xp / career_best` | no | **yes** (`admin_grant_career`, `admin_career_remove`) |
| **Courses: mark completed, reset** | `course_enrolments` (+ certificate) | no (certificate only) | **yes** (`admin_complete_course`, `admin_reset_course`) |
| **Street cred, wanted level** | `profiles.street_cred / wanted` | no | **yes** (`admin_set_numbers`) |
| **Reputation numbers (goodwill, hustle, luck, trouble, faith, family)** | `player_path` | no | **yes** (`admin_set_numbers`) |
| **Yahoo rank** | `yahoo_players.total_earned` (rank follows it) | no | **yes** (`admin_set_yahoo_rank`) |
| **Needs** (hunger, energy, hygiene, fun, social, health, stress, bladder) | `profiles` | no | **yes** (`admin_refill_needs`) |
| **Busy timer, road trip, running shift, hospital stay** | `profiles.busy_* / travel_* / job_shift_* / hospitalized_until` | no | **yes** (`admin_clear_states`) |
| Jail: release | `jail_cases`, `profiles.jailed_until` | yes (open cases list) | yes, also by player |
| **Jail: put in jail** | same | no | **yes** (`admin_jail_set`, a real case with bail) |
| **Debts (rent owed, tax owed)** | `profiles.rent_owed / tax_owed` | no | **yes** (`admin_clear_debts`) |
| **Bag items** (food, drink, tools, laptops, phones, ingredients, kids things) | `inventory` | no | **yes** (`admin_give_item`, `admin_take_item`) |
| **Cars** | `inventory` (category vehicle) | no | **yes** (same RPCs, one of each car) |
| **Garage** | `player_garages` | no | **yes** (`admin_give_garage`, `admin_remove_garage`) |
| **Furniture** | `player_furniture`, `player_house_furniture` | no | **yes** (`admin_give_furniture`, `admin_take_furniture`) |
| **Clothes (boutique)** | `player_wardrobe` | no | **yes** (`admin_give_wardrobe`, `admin_take_wardrobe`) |
| **Market stall pass** | `hustle_passes` | no | **yes** (`admin_give_hustle_pass`, `admin_take_hustle_pass`) |
| **Home type** (start home) | `profiles.start_home / housing_id` via `bl_home_enter` | no | **yes** (`admin_set_home`, also into an owned property) |
| **Owned property** | `properties` | no | **yes** (`admin_give_property`, `admin_take_property`) |
| **Land plots** | `invest_positions` kind `land` | no | **yes** (`admin_give_land`, `admin_take_land`) |
| **Gang membership and rank** | `crew_members` | no (disband and rename only) | **yes** (`admin_crew_set`, `admin_crew_remove`) |
| **Chief title** | `chief_titles` | no | **yes** (`admin_set_chief_title`, `admin_remove_chief_title`) |
| Office titles (elected and industry offices) | `office_holders`, `ind_holders` | yes (Admin → Offices, Elections) | linked from the toolbox, not duplicated |
| Gist ban | `gist_bans` | yes (Admin → Gist) | also a "Lift the Gist ban" button on the player page |
| Chat mute, ban, admin flag | `profiles` | yes | yes (unchanged) |
| Charms from Baba's Shrine | `player_charms` | clear only | clear only (see skipped) |

Plus the read side: `admin_grant_state(player)` (every current value the toolbox shows) and `admin_grant_catalog()` (what can be granted).

### Skipped, with the reason
| Thing | Why |
|---|---|
| Family: couple link, children, a child's grade or university level | A couple needs two real players and their consent; a child lives on timers (hunger, school terms, exams) tied to both parents. Ending a couple or removing a child already exists (Admin → Love, Admin → Kids). Giving one would corrupt both parents' state. |
| Investments: savings, bonds, stocks, crypto | Priced by the market simulation and money-like (a gifted share is cash on sale). Land is included because plots are an owned thing with a fixed price. Give money instead. |
| Billboard ads, real-business pins, top-ups and payments | Paid in real money (Paystack). Approve or sponsor in Admin → Ads / Real business. |
| Daily reward streak, story streak, challenges, weekly prizes | Habit counters and progress that reset by themselves; a gift would vanish at the next reset. |
| Shrine charms (give) | A charm is a timed effect created by a shrine visit with an offering and a roll. Clearing exists. |
| Fuel | Does not exist as an item: fuel is part of a car's running cost (`hustle_car_classes.fuel_mult`). |
| Spray hype points | A score built from real spraying; can be added later if wanted. |
| Crew level, bank, XP | Belong to the gang, not the player (Admin → Crews). |
| Receipts | Receipts record purchases. A gift is not a purchase, so none is created. |

## How to use each section
- **Career.** Pick the job and the level (the list shows every level's title), optionally an XP number (0 up to the level's bar), type a reason, tap Set job and level, tap again. "Promote +1" and "Demote −1" move one level. If you lower a level, tick "also lower their best-ever level" to stop the game from restoring it when they rejoin the job. Skips the promotion requirements (laptop, degree, shifts in level); the shift counter for the level restarts. XP at the bar promotes on their next shift if the requirements are met, as in the game. Remove job = quit.
- **Skills and courses.** The old skill and certificate boxes sit here. Courses: Mark completed (every class, certificate and graduation alert) or Reset (also takes the certificate back if it was completed).
- **Street cred, wanted, reputation.** Leave a box empty to keep the current number. Street cred 0 to 1,000,000, wanted 0 to 5, path numbers −100 to 100. Yahoo rank sets the player's "dirty money earned" to the rank's entry level (down or up). Debts: clear rent owed or tax owed (reason needed, no money moves).
- **Needs, jail, stuck states.** Refill every need or one. Clear a stuck busy timer, road trip, running shift (no pay) or hospital stay. Put in jail 1 to 3,600 seconds (a normal police case with the usual bail) or Release.
- **Items and bag.** Search, pick, quantity 1 to 99, Give. The bag list has Take 1 and Take all. The player's bag total stops at 9,999 per item.
- **Cars and garage.** Give a car (one of each, no duplicates) or take it back. Build a garage free (must fit the home type like the normal build) or remove it; cars stay owned.
- **Furniture, clothes, stall pass.** Furniture up to the piece's `max_qty` (20 at most) lands in "My items" ready to place. Take 1 removes a bought or gifted copy (pieces that came with the house stay). Clothes by name (gender and colour rules apply). The stall pass gives 1 to 720 hours.
- **Home, property, land.** Set a home type ("Move them in, free": same path as moving house, no move-in fee, furniture re-placed) or send them into a property they own. Give a property from the offers list (worth ₦0 on resale, living and upgrades work). Take only a property nobody lives in. Land: give 1 to 100 plots, take back only plots not under a house or build.
- **Business and company.** For each owned business: level, staff, insurance days, stock hours. The old grant and remove box is below. For each company: size (kiosk, shop, store), staff, manager, generator. "Give a company" makes one with a head office.
- **Gang and titles.** Put in a gang as Lieutenant, Member or Prospect (full gangs and the lieutenant limit are respected; Boss changes inside the gang), change rank or remove (not the Boss, not mid-job). Chief title and "of" ward. Office titles: link to Admin → Offices and Admin → Elections.
- **Perks and bans.** Lounge membership and Baba's charms (old boxes) and the Gist ban lift.

## Limits at a glance
Career XP 0 to the level bar (top level 1,000,000) · street cred 0 to 1,000,000 · wanted 0 to 5 · path numbers −100 to 100 · jail 1 to 3,600 s · item quantity 1 to 99 per grant, 9,999 held · furniture 1 to 20, at most the piece's `max_qty` · plots 1 to 100 per grant, 1,000 held · stall pass 1 to 720 h · business insurance 0 to 90 days · business stock 0 to `business.stock_max_hours` · companies at most `company.max_owned`, properties at most `property.max_owned`.

## Security
All 34 RPCs are `security definer` with `set search_path = public`, granted to `authenticated` only (anon and public revoked) and check `bl_admin_guard()` inside. The helpers (`bl_ag_target`, `bl_ag_reason`, `bl_ag_log`, `bl_ag_alert`, `bl_ag_fail`) are revoked from anon and authenticated. The migrations change no table, add no trigger, no foreign key and no loop over players, so they finish in well under a second on the live database.

## Tests
`bash scripts/sql-test.sh -- supabase/tests/admin_grants_test.sql`. Groups: privileges · non-admin refused for every RPC · career (set, promote, demote, best-ever, XP, remove, validation, mid-shift refusal, the game's own `get_my_state` shows the level) · needs and stuck states · jail (real case, release closes it) · numbers, debts, Yahoo rank (the game's rank function agrees) · items and cars (`item_use` eats a granted item, undo) · furniture (a granted chair sells through `furniture_sell`) · garage, clothes, pass · business level (hourly takings rise, pin level, listed refused) · company · home, property (the player can live in it), land · gang · chief title, course (certificate and graduation alert) · state and catalog · banned and deleted targets · audit rows, alerts, no ledger rows, nothing earned.
