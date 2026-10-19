# Review plan: Fynta's feedback (14 Oct 2026)

The owner decided:
- **Keep the Nepo/LAPO start roll.**
- **Add an admin open/closed switch for each club.**
- **Add politics, crime gangs and business ownership.**
- **Keep the transfer waiting time.**

## Order (one step at a time; each step is built, tested and documented)
1. **R1 Bugs (DONE):** a table blocks a bed in the top house, tapping a garage car shows its name, and a wall sticks onto the road at Ugbowo WiFi Junction.
2. **R2 Club switch (DONE):** each club can be turned on or off in Admin, so players gather in 2 clubs while numbers are small.
3. **Sound fix (DONE)** (from the earlier queue).
4. **Push notifications (DONE)** for all players, with an on/off toggle (earlier queue).
5. **R3 Skills (DONE):**
   - XP and levels for Yahoo, driving, cooking, music, teaching, fishing, mechanic and business.
   - The Yahoo level lowers the EFCC chance.
   - Hustles pay more at higher levels, and some jobs need a minimum level.
5b. **M1 Club music (DONE):**
   - The admin uploads MP3s into playlists and sets a playlist per club and per event. The event playlist wins while the event is on.
   - Shuffle or in order, looping forever.
   - Radio-style sync from the server clock: everyone hears the same moment, and leaving and coming back continues where the club is now.
   - Spotify or YouTube links are not possible (licensing and API).
6. **R4 School (DONE):** UNIBEN classes and short courses that give certificates. Certificates unlock better jobs and give XP. Players choose between time spent learning and money earned now.
7. **R5 Challenges (DONE):** daily and weekly goals that pay cash and XP (docs/CHALLENGES.md).
8. **R6 Yahoo strategy (DONE, docs/YAHOO.md):**
   - Cash-out choices: full (high risk), half (lower risk), or laundered (fee, much lower risk).
   - Group Yahoo missions with friends: more risk, more reward.
   - Also from the earlier queue: the HK Quarters map place and the Elon format job.
9. **R7 Friends and the lounge (DONE):**
   - A Friends tab in Messages showing who is online, with invites to places and missions.
   - A members' lounge open all day, with membership rules (a fee or level to join) and member perks.
   - Challenges done with friends count towards the daily and weekly goals.
10. **R8 House upgrade (DONE, docs/HOUSE_UPGRADES.md):** expand the house you live in instead of buying a new one.
11. **R9 Player trading (DONE, docs/MARKET.md):** sell items, furniture, cars and land to other players (houses are rented, so no house sales).
12. **R10 Own a business (DONE, docs/BUSINESS.md):** shop, buka, bar, salon, PoS, car wash, chemist, filling station and event centre on limited plots, with takings every real hour (48 h cap), restock, staff, owner shifts, random events, upgrades, a cut of visitor spending, sell-back or sell on the Market.
13. **R11 Crime gangs:** create a crew, recruit players, do group jobs.
14. **R12 Politics (DONE, docs/POLITICS.md):**
    - Run for councillor or governor and campaign.
    - Players vote at polling units.
    - Winners get perks and duties for a term.
    - The governor appoints players as ministers, each with a role and perks.
14b. **E3 Economy balance (DONE):**
   - Audit every way to earn and spend: jobs, hustles, yahoo, invest, clubs, shops, houses and cars.
   - Fix anything that pays too much or too little for the time and risk.
   - Check that every stated chance (%) really happens at that rate, using simulation tests.
   - Goal: enough to work towards for weeks, so players stay busy between updates.
14c. **Rename Crew → Gang (DONE):** every player-facing word (app, buttons, Help, tour, Ranks, alerts, server messages). Internal ids stay `crew_*`. Runs right after E3.
14d. **E4 Money sinks (DONE, docs/ECONOMY_SINKS.md):** players can still earn big, but money must leave the game. Covers:
   - transfer fee and stamp duty on big transfers
   - progressive weekly income tax on high earners only
   - upkeep on houses, cars and businesses (bigger for more assets)
   - VAT on shop purchases, more on luxury items
   - fun prestige sinks: status items, donations, big parties
   - admin money-supply dashboard: total money, daily in and out, top holders
   All rates are admin-tunable and gentle for new players.
14e. **M2 Owner earnings (owner request), after E4:**
   1. Billboard ad price: ₦150k for 7 days on any board (1 day ₦30k, 3 days ₦75k).
   2. Starter pack (about ₦500) and first top-up doubled.
   3. Benin Life VIP, ₦2,000 per 30 days via Paystack: gold name and badge, monthly money bonus, no transfer wait, free Lounge pass, extra slots.
   4. Real-money flex shop: exclusive cars and outfits, name colours, club entrance effect, chat stickers. Cosmetic only, no power.
   5. Admin earnings page (daily and monthly by product).
   All prices are admin-tunable.
15. **Later, from the earlier queue:** Link-ups, Church/prophet, Benin Gist.

**Company app (paused, wip/companies):** owner wants it INSIDE the existing Business app (tabs: My companies · Map plots · Discover · Real business), not a separate phone app. Merge similar apps instead of adding new ones.
