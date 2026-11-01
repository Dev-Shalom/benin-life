# The Court

Owner request: players want a real court. Sue someone, real players as lawyers, a judge who is a real player, live hearings people can watch. Robbery victims said "we get robbed, file a report and nothing happens".
Migrations `20261111000100_court.sql` (settings, tables, evidence, verdict, debt) and `20261111000200_court_rpcs.sql` (every RPC). Test `supabase/tests/court_test.sql`.
Client: Phone, **Court** app (`src/screens/game/phone/CourtApp.tsx`, `phone/court/*`, `src/api/court.ts`). Admin: `/admin/court` (`src/admin/Court.tsx`), Settings, category `court`.
Names: "High Court, Benin" and a small-claims "Customary Court, Benin". Case numbers like `BC/1234/2026` (High) and `CC/1234/2026` (Customary).

## What you can sue over (only what the game recorded)
There is no free text accusation. You pick an event the game wrote down in the last 72 hours (`court.lookback_hours`). The court only hears the record.
| Type | Who sues | Record | Claim |
|---|---|---|---|
| Pickpocket | the victim | a successful `crime_attempts` row | the amount taken |
| Rent owed | the landlord | a tenancy that ended with rent owed (`property_events`) | rent owed minus the caution kept |
| Unfair eviction | the tenant | notice given within 7 days of moving in, no rent owed | 1 week of the rent at move-in |
| Market overcharge | the buyer | a `market_trades` row flagged `far_high` | price minus value |
Each type has a switch (`court.type_*_enabled`). One case per event (a dismissed case frees the event). A claim up to ₦100,000 goes to the Customary Court (smaller fee), bigger to the High Court.
Not built: Hustle jobs between players. That system does not exist in this game (the Hustles are NPC jobs). Adding a type means one branch in `bl_court_evidence`, one in `bl_court_my_events` and one setting.
Note: the victim of a pickpocket normally never learns who did it. Filing a case names the thief from the record (that is the investigation).

## The flow
1. **Sue someone** (3 steps): what happened, pick a lawyer (or speak for yourself), confirm and pay. Filing fee is a sink. A hearing is set `court.hearing_delay_minutes` later (default 30).
2. A judge is assigned (a sitting judge who is not a party and not a lawyer in the case, fewest live cases). If there is none, a judge can take the case from the app, or one is assigned when the hearing starts.
3. **Hearing** (LIVE): each side (and the lawyer) posts short statements (240 characters, cleaned and masked like chat, 8 per side, 3 s apart). The judge may add remarks and rules after `court.min_hearing_minutes` (2).
4. The judge has `court.ruling_window_minutes` (60) from the start. After that the **automatic ruling** applies: it re-reads the record. Record found = guilty with the recorded claim. It is deterministic, so a victim always gets an outcome.
5. No cron. A lazy clock (`bl_court_tick`) runs inside `court_status`, `court_case`, `court_live`, `court_post`, `court_rule`, `court_after`: it settles the caller's own due cases plus one global overdue case.

## Lawyers are players
- Register (Court, Lawyers): needs the **Law and Advocacy** certificate (a new UNIBEN course, `court.lawyer_cert`, empty = not needed) and an account at least 2 days old. Sitting judges cannot practise. Fee per case between ₦2,000 and ₦2,000,000.
- Ranks by wins: Junior Lawyer, Advocate (5), Barrister (15), Senior Advocate (40). All editable.
- The client picks a lawyer in the list (search by @name, Available now, Top by wins). The fee is **held in escrow** at once. The lawyer accepts or declines before the hearing starts. Decline, no answer or a ban returns the fee. On the verdict the lawyer is paid minus the court cut (5%, destroyed). The winner's lawyer gets a win, the other a loss.
- A lawyer cannot take both sides, cannot be a party, cannot be the judge of the case, has at most 5 live cases. A side has 3 hire attempts per case.

## Judges
Four industry offices `court_judge_1..4` ("High Court Judge I..IV", badge **Hon. Justice**, ₦1.5M a day, 14-day term) in the existing `ind_offices` table. Appointment, salary, badge, term, inactivity and removal are the existing industry-office code (docs/OFFICES.md). Admin -> Court has "Appoint judge" (first free seat) and "Remove judge" (their open cases go back to the pool). Players can also apply from Benin Votes, Industry offices. The offices have no levers.

## Outcomes
- **Guilty**: the defendant pays the claim from **cash, then bank**, never below zero. What they cannot pay becomes **court debt**, taken from `court.debt_collect_pct` (30%) of their future earnings through the ledger (a guarded patch of `bl_add_money`, right after the tax garnish; only earned reasons count). The plaintiff is paid from the debt on their next call. Plus a **fine** (20% of the claim, at least ₦2,000), a sink. Plus `-5` street cred. The plaintiff gets the filing fee back. Repeat offenders: the 2nd guilty verdict within 30 days opens a **jail case** in the existing Police system (60 s, then 120 s, and so on); the "Police don catch you" popup, bail and escape work as usual.
- **Not guilty**: nothing moves. The plaintiff loses the filing fee.
- Restitution, fines, refunds and lawyer money are **never earnings** (even if Admin adds the reasons to `leaderboard.earn_reasons`). Lawyer fees are not earnings by default either.
- Alerts for both sides, both lawyers and the judge (the Alerts app plus a push in the existing "events" category, same caps). Link: `go=court`.
- Ledger reasons: `court_fee`, `court_fee_refund`, `court_restitution_out/in`, `court_fine`, `court_debt`, `court_refund(_out)`, `lawyer_escrow`, `lawyer_fee_in`, `lawyer_fee_refund`.

## Gallery and realtime
`court_gallery_join` takes a seat (limit `court.gallery_size`, 30; parties, lawyers and the judge never use a seat; a watcher who stops checking in for 10 minutes loses the seat). ONE Realtime channel per hearing (`court-<id>`, table `court_statements`, filter `case_id`), no global channel. The table policy lets only people in the case or the gallery read rows. A 45 s check-in keeps the seat and settles the case. In Realtime fallback mode the app polls `court_after` every 6 s. Ruled cases are public record.

## Anti-abuse
No suing yourself (the game has no device or IP tracking, so alts cannot be detected; the account-age rule `court.min_account_hours` 12, fees and fines limit the benefit). One case per event. Filing cooldown 5 minutes, 3 open cases, 5 a day. A lawyer cannot take both sides. A judge cannot rule on, take or be assigned a case they are part of. Statement limits and mute check. All RPCs are security definer, anon refused, `bl_court_*` helpers private.

## Admin
Admin -> Court: counts, judges (appoint, remove), cases (rule guilty / not guilty = **override**, dismiss and refund; each needs a reason and is audited in `admin_audit`: `court_override`, `court_dismiss`, `court_judge_appoint`, `court_judge_remove`, `court_lawyer_ban`), lawyers (ban, reinstate) and every `court.*` setting. An override of an executed ruling puts the money back as far as it can (the plaintiff pays back what they still have), restores street cred, ends the court debt, then rules again.

## Defaults
Filing fee ₦5,000 (Customary ₦1,500, claims up to ₦100,000), hearing delay 30 min, ruling window 60 min, gallery 30, fine 20%, court cut 5%, debt collection 30%, look-back 72 h.

## Not built
A map place for the court (places need art and pins in code: the Court is a phone app). Hustle job cases. Appeals. A Police report link on the case (the Police app has a "Take them to court" button).

## Tests
`bash scripts/sql-test.sh -- supabase/tests/court_test.sql` (15 groups): grants, RLS and volatility; settings; filing only from recorded events; lawyers (register, list, search, rank); hiring and escrow; judge, hearing, gallery limit, guilty verdict; not guilty; automatic ruling, debt, collection, not earnings; jail for repeat offenders; statement cleaning; anti-abuse; other case types; admin; realtime RLS; patched functions. `school_test` and `offices_test` counts were updated (a new course and four judge offices).
