# Economy balance

## E3 audit (2026-10-19): a fair economy with weeks of things to work towards

The owner said: *"There are some things that pay more that should not pay more (and the reverse), and there's a percentage of things that's supposed to happen and does not happen."* This is the audit, the fix and the proof. Everything in it is generated from the live local database (seeded values, not only the older docs): the "before" numbers are the values at migration `20261018001100_politics`, the "now" numbers are what `supabase/migrations/20261019000100_economy_balance.sql` sets.

**What was found, in one paragraph.** Crime paid 1,000 x a starter job with no daily limit (Chat a client N2M an hour, the Big job N71M an hour; one Night market shakedown job paid a 3-man crew N600k, 8 jobs a day); gear-free hustles (Tutor, MC, fishing) out-paid hustles that need gear; five business types lost money when stocked (restock cost 60 to 127 % of income); a risk-free MMF at 18 % beat shares and "high risk" USDT, and land grew 22 to 35 % a month with almost no volatility; the gem hunt and challenges paid a starter twice what a day of work did; one 20-second shift paid a referral N40k per alt account; and the Market had a lap that made +30 % of a business's value out of nothing. All of that is fixed below. On probabilities: every stated chance was rolled at the stated rate (no mismatch of more than the sampling band in 75 checks), but the running-job EFCC bar and the Yahoo "escape" line showed numbers the roll does not use; both fixed.

### How the numbers are made

| Term | Meaning |
|---|---|
| EV a run | expected naira after the odds: pay x (1 - bad outcome) plus the tips, minus the costs of the run (fuel, parts, wear, ingredients, bait) and, for crime, minus the caught chance x (35 % laptop seizure x the laptop's price + 50 % of the yahoo balance in flight) minus the cash-out leg. Crew and group jobs: the member's share after the crew bank cut and the buy-in |
| Runs a day | the cap in the table (`hustles.daily_cap`, `career.max_shifts_per_game_day` 3, the new `daily_cap` on yahoo jobs and group missions, `crew.max_jobs_per_day`, 6 business shifts) |
| EV a day | EV a run x runs a day at the cap. This is the number that matters: a day has a ceiling for every earner |
| ₦ per active hour | EV a run / (seconds + 5 s of tapping) x 3,600. It is what you would earn if the cap did not exist, so it is huge for everything, because a run is 20 to 60 seconds. Read it as "how fast does the cap fill", not as pay |
| Assumptions | performance 100 %, hour multiplier 1, skill level 1 (Yahoo level given where a job needs one), no certificate bonus (+5 to 10 % on top), one game year = `invest.year_days` = 30 real days, so every "per year" rate is per 30 real days and one invest day is 1.97 hours |

**The ladder (the target of this audit).** A legit day, 3 shifts: **starter ₦8,400** (level 1 average of Trade, PoS, Transport, Health, Tech), **mid ₦37,000** (level 3 average), **senior ₦105,000** (level 5 average), top **₦360,000** (Tech CTO). Hustles with gear should pay a bit more than the job at the same stage; skills, certificates and businesses more over time; **crime 1.3 to 2 x the legit option of the same tier after its risk, never 10 x**.

### 1. Earning audit: every way to make money

#### 1.1 Careers (legit, safe, unchanged)

3 shifts a day (`career.max_shifts_per_game_day`), pay x performance (40 to 120 %) x trait x certificate bonus (+5 to 10 %) x charms. Level-up needs `xp_to_next` and 3 shifts in the level, so Tech CTO is about 90 shifts (30 days) plus a degree, a laptop and two certificates.


| Track | Level (title) | Pay a shift | ₦/day (3 shifts) | ₦/active hour | Gate |
|---|---|---:|---:|---:|---|
| tech | 1 Intern | 3,500 | 10,500 | 547,826 | - |
| tech | 2 Junior Dev | 8,000 | 24,000 | 1,252,174 | laptop |
| tech | 3 Mid-level Dev | 15,000 | 45,000 | 2,347,826 | laptop |
| tech | 4 Senior Dev | 28,000 | 84,000 | 4,382,609 | laptop, degree, cert: ict,coding_bootcamp |
| tech | 5 Tech Lead | 45,000 | 135,000 | 7,043,478 | laptop, degree |
| tech | 6 Engineering Manager | 70,000 | 210,000 | 10,956,522 | laptop, degree |
| tech | 7 CTO | 120,000 | 360,000 | 18,782,609 | laptop, degree |
| pos | 1 PoS Attendant | 2,500 | 7,500 | 391,304 | - |
| pos | 2 PoS Operator | 5,000 | 15,000 | 782,609 | - |
| pos | 3 Super Agent | 12,000 | 36,000 | 1,878,261 | - |
| pos | 4 Aggregator | 25,000 | 75,000 | 3,913,043 | cert: accounting |
| trade | 1 Market Apprentice | 2,000 | 6,000 | 313,043 | - |
| trade | 2 Trader | 4,500 | 13,500 | 704,348 | - |
| trade | 3 Shop Owner | 9,000 | 27,000 | 1,408,696 | - |
| trade | 4 Wholesaler | 18,000 | 54,000 | 2,817,391 | cert: business_mgmt |
| trade | 5 Market Leader | 32,000 | 96,000 | 5,008,696 | - |
| trade | 6 Distributor | 55,000 | 165,000 | 8,608,696 | - |
| transport | 1 Keke Rider | 3,000 | 9,000 | 469,565 | - |
| transport | 2 Bus Driver | 6,500 | 19,500 | 1,017,391 | cert: driving |
| transport | 3 Park Supervisor | 14,000 | 42,000 | 2,191,304 | - |
| transport | 4 Transport Company Owner | 35,000 | 105,000 | 5,478,261 | - |
| health | 1 Ward Attendant | 3,000 | 9,000 | 469,565 | - |
| health | 2 Student Nurse | 5,000 | 15,000 | 782,609 | - |
| health | 3 Staff Nurse | 12,000 | 36,000 | 1,878,261 | degree |
| health | 4 Senior Nurse | 20,000 | 60,000 | 3,130,435 | degree |
| health | 5 Resident Doctor | 35,000 | 105,000 | 5,478,261 | degree |
| health | 6 Consultant | 60,000 | 180,000 | 9,391,304 | degree |
| health | 7 Chief Medical Director | 100,000 | 300,000 | 15,652,174 | degree |
| education | 1 UNIBEN Student | 1,000 | 3,000 | 156,522 | - |
| education | 2 Graduate Assistant | 6,000 | 18,000 | 939,130 | - |
| education | 3 Lecturer II | 12,000 | 36,000 | 1,878,261 | - |
| education | 4 Lecturer I | 18,000 | 54,000 | 2,817,391 | - |
| education | 5 Senior Lecturer | 28,000 | 84,000 | 4,382,609 | - |
| education | 6 Professor | 45,000 | 135,000 | 7,043,478 | - |
| education | 7 Vice-Chancellor | 80,000 | 240,000 | 12,521,739 | - |

#### 1.2 Hustles (gear helps, daily caps)

Needs and EV a run before → now. Tutor, MC and fishing had no (or a ₦8k) entry cost and paid 2 to 5 x a starter day; the DJ controller (₦220k) paid back in 4 days; Bolt Premium / Black took 468 / 1,047 days to pay back the car.


| Hustle | Needs | Runs a day | Risk event | EV a run before → now | EV a day before → now |
|---|---|---:|---|---:|---:|
| PoS agent batch | PoS machine ₦35k | 6 | 12% bad run, 4% loss | 3,302 → 3,302 | 19,810 → 19,810 |
| Sell jollof rice | stall ₦3k/day + ₦4.5k ingredients | 4 | 10% bad run | 3,725 → 3,725 | 14,900 → 14,900 |
| Sell puff-puff | stall + ₦1.5k | 4 | 10% bad run | 2,166 → 2,166 | 8,664 → 8,664 |
| Sell fried yam and egg | stall + ₦2.5k | 4 | 10% bad run | 3,375 → 3,375 | 13,500 → 13,500 |
| Play a DJ set | DJ controller ₦220k (x0.4 without) | 2 | 15% tip | 28,000 → 17,800 | 56,000 → 35,600 |
| Headline DJ slot | Music Production cert + controller | 2 | 20% tip | 54,500 → 54,500 | 109,000 → 109,000 |
| MC the night | nothing | 3 | 20% tip | 15,000 → 7,600 | 45,000 → 22,800 |
| Tutor a student | nothing, 8am to 5pm | 4 | 10% tip | 10,000 → 4,300 | 40,000 → 17,200 |
| Go fishing | rod ₦8k, bait ₦300 | 10 | 10% nothing bites | 2,735 → 1,113 | 27,348 → 11,130 |
| Quick fix | ₦1k parts | 5 | - | 4,750 → 3,250 | 23,750 → 16,250 |
| Engine job | Mechanic lvl 2, ₦3k parts | 2 | 10% bad run | 9,825 → 9,825 | 19,650 → 19,650 |
| Fleet service contract | Mechanic Trade Test cert, ₦4k parts | 2 | 8% bad run | 20,000 → 20,000 | 40,000 → 40,000 |
| Bolt economy | car ₦1.7M, fuel + wear | 5 | 8% passenger cancels | 6,320 → 6,320 | 31,600 → 31,600 (payback 54 → 54 days) |
| Bolt comfort | car ₦6M, fuel + wear | 5 | 8% passenger cancels | 11,120 → 11,120 | 55,600 → 55,600 (payback 108 → 108 days) |
| Bolt premium | car ₦40M, fuel + wear | 5 | 8% passenger cancels | 17,104 → 26,320 | 85,520 → 131,600 (payback 468 → 304 days) |
| Bolt luxury | car ₦150M, fuel + wear | 5 | 8% passenger cancels | 28,640 → 45,920 | 143,200 → 229,600 (payback 1047 → 653 days) |

#### 1.3 Yahoo (crime, solo and group)

The EFCC chances are the owner's "fairer" values (12 / 16 / 24 / 14 %, 35 % laptop seizure, 50 % balance confiscation) and were **not touched**; pay, gates and caps were. EV includes the 35 % laptop seizure (the best laptop you own is the one at risk, so a ₦330k EliteBook costs ₦115k every time EFCC wins), the 50 % balance loss, a ₦5,000/day cybercafé desk and one full cash-out per 4 jobs (14 % chance, 50 % of the balance taken when caught, the rest retried). Level cut: Yahoo level 4 = -12 % of the chance, level 10 = -36 %.


| Job | Gate before → now | Pay avg before → now | EFCC (owner's, unchanged) | Cap a day | EV a run before → now | EV a day before → now |
|---|---|---:|---:|---|---:|---:|
| Chat a client | any laptop → any laptop | 27,500 → 6,500 | 12.0% | none → 8 | 17,462 → 2,263 | 1,042,735 (30 min, no cap) → 13,106 (4 min) |
| Romance job | any laptop → ThinkPad ₦280k + Yahoo 2 | 225,000 → 46,200 | 14.4% | none → 4 | 144,703 → 14,756 | 5,204,306 (30 min, no cap) → 54,024 (3 min) |
| Elon format | ThinkPad ₦280k + Yahoo 4 → EliteBook ₦330k + Yahoo 4 | 735,000 → 118,800 | 15.8% | none → 3 | 463,614 → 58,951 | 14,508,128 (30 min, no cap) → 171,853 (3 min) |
| Big job | Dell XPS ₦1.1M + Yahoo 3 → Dell XPS ₦1.1M + Yahoo 3 | 2,012,500 → 276,000 | 18.4% | none → 2 | 1,205,596 → 96,574 | 35,569,974 (30 min, no cap) → 188,147 (2 min) |


Group missions (member share, a friend or two, laptop ₦45k):


| Mission | Members | Pot avg before → now | EV a member a run before → now | Cap a day | EV a member a day before → now |
|---|---:|---:|---:|---|---:|
| Crew hustle | 2 | 1,000,000 → 55,000 | 395,302 → 19,003 | none → 3 | 395,302 per run (no cap) → 57,009 |
| HK big table | 3 | 7,500,000 → 425,000 | 1,670,563 → 90,291 | none → 2 | 1,670,563 per run (no cap) → 180,582 |

#### 1.4 Crews and group missions

A crew needs a ₦500,000 founding fee, an account 72 hours old and Charisma 2, and members join after 24 hours; level 2 needs ₦1M of crew bank and 100 XP, level 4 ₦12M and 700 XP. Per member, with the default 30 % to the crew bank and the 8 % member bonus; the caught chance is the job's own (skills cut it up to 30 %).


| Crew job | Crew level | Example members | Pot avg before → now | EFCC | EV a member a job before → now | Cooldown |
|---|---:|---:|---:|---:|---:|---:|
| Night market shakedown | 1 | 3 | 600,000 → 80,000 | 22% | 126,672 → 16,890 | 20 min |
| Hit a container at the port | 2 | 4 | 2,350,000 → 400,000 | 30% | 354,813 → 43,798 | 45 min |
| Ring Road warehouse job | 2 | 4 | 3,500,000 → 550,000 | 32% | 512,283 → 55,216 | 60 min |
| Bank van job | 4 | 6 | 16,500,000 → 2,500,000 | 40% | 1,759,550 → 181,750 | 180 min |

#### 1.5 Businesses

Income is per real day at level 1, rolled between min and max when bought; costs are rent + power a day; a restock buys 48 h of stock. Without stock income slides to 50 %. The best play was to skip restocking for five types.


| Business | Price | Gross a day | Rent + power | Restock a day (48 h ÷ 2) before → now | Net a day, stocked before → now | Payback with stock (days) before → now |
|---|---:|---:|---:|---:|---:|---:|
| Provision shop / mini-mart | 600,000 | 15,000 | 2,500 | 9,000 → 3,000 | 3,500 → 9,500 | 171 → 63 |
| Buka / chop house | 900,000 | 20,000 | 4,000 | 12,500 → 4,000 | 3,500 → 12,000 | 257 → 75 |
| Barbing & hair salon | 700,000 | 15,500 | 3,000 | 4,000 → 4,000 | 8,500 → 8,500 | 82 → 82 |
| Car wash | 1,000,000 | 18,000 | 3,500 | 3,000 → 3,000 | 11,500 → 11,500 | 87 → 87 |
| PoS & business centre | 1,200,000 | 22,500 | 4,500 | 0 → 0 | 18,000 → 18,000 | 67 → 67 |
| Beer parlour / bar | 1,800,000 | 35,000 | 7,500 | 27,500 → 7,000 | 0 → 20,500 | never → 88 |
| Chemist shop | 2,800,000 | 37,500 → 45,000 | 5,500 | 35,000 → 7,500 | -3,000 → 32,000 | never → 88 |
| Filling station | 9,000,000 | 110,000 → 122,500 | 17,000 | 140,000 → 22,000 | -47,000 → 83,500 | never → 108 |
| Event centre | 18,000,000 | 210,000 | 27,000 | 0 → 0 | 183,000 → 183,000 | 98 → 98 |

#### 1.6 Invest and save

Expected return per **30 real days** (one game year). Shares: drift + dividends (0.25 % chance a step x 3 % of the price). Farms: payout less the expected bad events, over the cycle. Transport / POS: income minus the expected breakdown / fraud / network losses. Land: drift only, with the round-trip cost of agent fees (5 to 7 % each way), the community settlement (4 to 18 %) and the levy chance. Nothing is capped by amount, so any yield above the risk it carries is a money machine for the rich.


| Product | Risk | Expected return per 30 real days before → now | Cap on the amount |
|---|---|---:|---|
| Bronze Savings | safe | 10.0% → 6.0% | none |
| Money market fund | safe | 18.0% → 9.0% | none |
| SafeLock 7 days | safe | 15.0% → 9.5% | none |
| SafeLock 30 days | safe | 18.0% → 11.0% | none |
| SafeLock 90 days | safe | 22.0% → 13.0% | none |
| Fixed deposit 30 days | safe | 16.0% → 10.5% | none |
| Fixed deposit 90 days | safe | 19.0% → 12.5% | none |
| Treasury bill 91 days | safe | 16.0% → 11.0% | none |
| Treasury bill 182 days | safe | 17.8% → 13.5% | none |
| Treasury bill 364 days | safe | 21.9% → 15.0% | none |
| FGN bond price | safe | 19.0% → 12.5% | none |
| Dangote Cement | medium | 14.5% → 19.5% | none |
| MTN Nigeria | medium | 16.5% → 20.5% | none |
| Zenith Bank | medium | 18.4% → 23.4% | none |
| GTCO | medium | 20.4% → 24.4% | none |
| Okomu Oil | medium | 19.4% → 23.4% | none |
| Presco | medium | 22.3% → 27.3% | none |
| Tether (USDT) | high | 6.0% → 10.0% | none |
| Bitcoin (BTC) | high | 55.0% → 30.0% | none |
| Poultry unit | medium | 49.6% → 38.3% | none |
| Fish pond unit | medium | 52.2% → 40.7% | none |
| Cassava farm unit | medium | 36.5% → 36.5% (unchanged) | none |
| Plantain farm unit | medium | 35.9% → 35.9% (unchanged) | none |
| Okada (motorbike) | medium | 24.3% → 24.3% (unchanged) | none |
| Keke (tricycle) | medium | 38.3% → 38.3% (unchanged) | none |
| Sienna bus | medium | 38.1% → 38.1% (unchanged) | none |
| POS stand | medium | 32.6% → 32.6% (unchanged) | none |
| POS shop (3 machines) | medium | 35.6% → 35.6% (unchanged) | none |
| Room & parlour block | high | 33.5% → 27.5% | none |
| 2-bedroom flat | high | 33.3% → 27.3% | none |
| Duplex for rent | high | 33.5% → 27.5% | none |
| Land: GRA (price drift) | high | 22% → 12% a 30 days; round trip costs about 14%: break-even 20 → 36 days | none (max 100 plots a deal) |
| Land: Ugbowo (price drift) | high | 28% → 15% a 30 days; round trip costs about 18%: break-even 19 → 36 days | none (max 100 plots a deal) |
| Land: Sapele Rd (price drift) | high | 24% → 13% a 30 days; round trip costs about 20%: break-even 25 → 47 days | none (max 100 plots a deal) |
| Land: Airport Rd (price drift) | high | 30% → 16% a 30 days; round trip costs about 22%: break-even 22 → 41 days | none (max 100 plots a deal) |
| Land: Ikpoba Hill (price drift) | high | 26% → 14% a 30 days; round trip costs about 26%: break-even 30 → 56 days | none (max 100 plots a deal) |
| Land: Okhoro (price drift) | high | 33% → 17% a 30 days; round trip costs about 30%: break-even 27 → 53 days | none (max 100 plots a deal) |
| Land: Ekenwan (price drift) | high | 35% → 18% a 30 days; round trip costs about 36%: break-even 31 → 59 days | none (max 100 plots a deal) |

#### 1.7 Everything else that pays

| Source | Amount | Gate / cap | Verdict |
|---|---|---|---|
| Daily reward | 7-day ladder ₦1,000 / 1,500 / 2,000 / 2,500 + kada / 4,000 / 5,000 / 10,000 + drink, average ₦3,700 | once a day | fine, unchanged |
| Gem hunt | 3 gems x ₦3,000 + ₦5,000 for all three = **₦14,000 a day for walking** | 3 a day | **now ₦1,000 each + ₦2,000 = ₦5,000** (a starter works for ₦8,400) |
| Challenges + chests | 3 dailies (average ₦2,075) + ₦3,000 chest, 3 weeklies (average ₦9,076) + ₦20,000 chest = about **₦15,900 a day** | 1 reroll a day | **x0.7 on every reward, chests ₦2,000 / ₦12,000 = about ₦9,700 a day**; friend challenges are the alt-farm ones |
| Referral | ₦20,000 + ₦20,000 after ANY of 1 shift / 3 hustles / 60 minutes (one 20-second shift) | 5 a day, 100 ever | **₦10,000 + ₦10,000 after 9 shifts / 15 hustles / 240 minutes, 3 a day, 30 ever** |
| Weekly top earners | ₦200k / 100k / 50k to the top 3 who earned at least ₦20,000 | weekly | prizes unchanged, minimum **₦100,000** (three alts could take all three prizes) |
| Weekly Top crews | ₦500k / 250k / 100k to the crew bank, crews with 2 jobs | weekly | prizes unchanged, minimum jobs **8** |
| Office salary | Councillor ₦20k, Chairman ₦50k, Governor ₦100k, six Commissioners ₦40k a day for sitting in the seat (Commissioners are appointed, so alts) | 14-day terms, 16 seats | **₦10k / 25k / 50k / 15k** |
| Tips (player to player) | up to ₦1M a tip, ₦5M a day, no fee: a way round the ₦200k a day bank transfer limit | none | **₦100k a tip, ₦300k a day** |
| Pickpocket | 5 to 15 % of the victim's cash (₦100 to ₦50,000), 62 % caught, 45 s cell | 180 s cooldown, 600 s per victim, accounts older than 24 h | zero-sum between players, the 62 % is verified below; unchanged |
| Money pick-up in clubs | ₦10,000 a tap, at most 50 taps a drop; a drop is 20 % of somebody's spray, the other 80 % and every unpicked note leave the economy | per drop | conserved (nothing is created); owner's numbers, unchanged |
| Babalawo money charm | ₦3M + 2 cows + schnapps + cloth buys ₦150k to ₦300k every time you come back after 8 h (at most one a visit) for 14 days, a ₦300k + goat call every 7 days, 10 % fail | one at a time | about +₦2M per 14 days for a rich player who visits 3 times a day: a rich-stage gamble, owner's prices, **left alone** |
| Selling things | shop buy-back 30 to 60 % (laptops 40 to 50 %), fish 100 % at a market, cars 60 % → **50 %** (the free Nepo car paid ₦1.5M on day 1) | market only | no buy-then-sell profit anywhere (see section 4) |
| Bank interest, dividends, harvests, rents | section 1.6 | | tuned |
| Business visitor cut | 30 % of what a visitor spends goes to the owner's bank | not on your own place | not a loop: the visitor pays 100 %, 70 % leaves the economy |
| Nepo allowance | ₦5,000 a day, ₦500,000 in the bank, 2 career levels, a car and a laptop | 10 % of new players (`origin.nepo_pct`) | owner's, unchanged |
| LAPO start cash | ₦85,000 | new LAPO | **owner's, unchanged** (see the alt-farming note in section 7) |

### 2. Spending audit

#### 2.1 Where money goes

| Sink | Price | Notes |
|---|---|---|
| Food and needs | about 48 hunger lost a day (4 an hour x `needs.decay_speed` 0.5): one home-cooked meal ₦600 (45 hunger), noodles ₦400, jollof ₦2,000, kada ₦3,000; soap ₦300, pain relief ₦300 | ₦1,000 to ₦2,000 a day |
| Rent | face-me ₦1,200 to ₦1,500 a week, hostel ₦1,000, self-contain ₦4,000, mini-flat ₦8,000, GRA duplex ₦25,000 | ₦215 to ₦3,600 a day; unpaid rent becomes owed rent, never a dead end |
| Transport | walk free, keke ₦150 + ₦100/km, bus ₦300, Bolt-style drop ₦500 + ₦250/km | ₦500 to ₦2,000 a day |
| Gear | Tokunbo laptop ₦45k, ThinkPad ₦280k, EliteBook ₦330k, XPS ₦1.1M, MacBooks ₦1.85M / ₦4.35M; rod ₦8k, PoS machine ₦35k, DJ controller ₦220k; MiFi ₦50k a week, desk ₦5k a day, stall ₦3k a day | the thing a hustle or crime tier is paid for |
| Cars | bicycle ₦180k to Lambo Urus ₦450M; dealers x0.88 / x1.0 / x1.2; resale 50 % | status and the Bolt classes |
| Houses | upgrades ₦0.45M (generator) to ₦22M (mini-flat to duplex); average furniture piece ₦553k (₦4k to ₦12M) | 10 to 220 days of mid-game surplus each |
| School | courses ₦12k to ₦180k (BSc), certificates | a few days of surplus each |
| Business | ₦0.6M to ₦18M, upgrades 40 / 80 / 150 % of the price, restock, rent + power, staff ₦2k to ₦6k a day, insurance 3 % for 7 days | |
| Clubs, lounge, spray | beer ₦1,500, bottle ₦45k, Big Boy booth ₦250k, spray ₦1k to ₦10T, lounge ₦5k a day / ₦150k / ₦1M a month | weekend x1.5 (owner's) |
| Babalawo | ₦50k to ₦3M + offerings (goat ₦102k, cow ₦1.44M) | owner's prices |
| Fees and levies | market fee 5 % (business 8 %), POS fee 1.5 % (min ₦100), bank transfer ₦50, broker 0.5 to 0.8 %, land agent 5 to 7 % + community 4 to 18 % + levy, business levy 8 % chance a day for 35 % of a day's income, street robbery 6 % x cash factor, crew bust fine 15 % of the bank (max ₦2M), launder fee 10 % | the only "taxes" in the game |
| Crime costs | yahoo desk, laptop seizure, balance confiscation, crew buy-ins ₦20k to ₦100k, crew upgrades ₦1M / 3M / 8M / 20M, found fee ₦500k, bail ₦5k to ₦50M (jail is 45 to 120 seconds, so bail is a luxury) | |

#### 2.2 A typical day at three stages

**Stage A: a new LAPO (₦85,000 cash, day 1 to 7).** Costs a day: food ₦1,000 to ₦2,000, rent ₦215 to ₦570, transport ₦500 to ₦2,000, soap ₦300, so **₦2,000 to ₦4,000**. One-off wants: a laptop ₦45k, a rod ₦8k, a PoS machine ₦35k, a self-contain move ₦16k, a first course ₦12k to ₦25k.

| Income a day | Before | Now |
|---|---:|---:|
| Starter job, 3 shifts | 8,400 | 8,400 |
| Daily reward (average) | 3,700 | 3,700 |
| Gem hunt | 14,000 | 5,000 |
| Challenges, chests and weeklies | 15,900 | 9,700 |
| Two cheap hustles (fishing + tutoring) | 67,000 | 28,000 |
| **An honest, busy day** | **about 109,000** | **about 55,000** |
| Crime on top: Chat a client with a ₦45k laptop | **₦1,040,000 in 30 minutes, no cap** | **₦13,100 a day (8 jobs, 4 minutes)** |

Before, a LAPO who tried crime on day 1 made more in half an hour than the whole honest ladder paid in a month, and nobody needed a job. Now the honest day is about 6 x a day of work, crime adds 1.5 x the starter job after its risk, and the ₦85,000 start still buys the laptop, the rod, a course and a week of food.

**Stage B: mid-game (week 4 to 8, ₦3M to ₦5M of assets).**

| Income a day | Before | Now |
|---|---:|---:|
| Career level 4 (Tech Senior Dev ₦28k a shift; Nurse and Trade pay ₦18k to ₦20k) | 84,000 | 84,000 |
| DJ set with a ₦220k controller | 56,000 | 35,600 |
| Bolt Economy (₦1.7M car) | 31,600 | 31,600 |
| One business (provision shop / salon / buka, restocked) | 3,500 to 8,500 | 8,500 to 12,000 |
| ₦3M in the MMF | 18,000 | 9,000 |
| Daily reward + challenges + gem hunt | 33,600 | 18,400 |
| **Honest total** | **about 229,000** | **about 189,000** |
| Crime on top: Romance + Elon format (ThinkPad / EliteBook) | about ₦19.7M in two 30-minute sessions | **₦54,000 + ₦172,000 a day (6 minutes)** |

Costs a day: rent ₦1,100, food ₦2,000, lounge ₦5,000 (₦150k a month), a club night ₦5k to ₦20k, a course ₦25k to ₦30k; fuel and wear are inside the hustle EV. **Surplus about ₦150,000 a day, ₦4.5M a month**: one house upgrade (extra bedroom ₦1.8M to ₦3.8M, solar ₦2.2M to ₦5.5M), one business upgrade (₦240k to ₦1.8M), the next business (₦0.7M to ₦2.8M) or a better car every month. Weeks of goals, not days.

**Stage C: rich (₦100M or more).**

| Income a day | Before | Now |
|---|---:|---:|
| Tech CTO (₦120k a shift) | 360,000 | 360,000 |
| Bolt Luxury (₦150M car) | 143,000 | 230,000 |
| Event centre + Filling station + Chemist (₦29.8M of businesses) | 183,000 + 38,000 + 13,000 (the other two were better never restocked) | 183,000 + 83,500 + 32,000 |
| ₦50M in 364-day T-bills | 364,000 | 250,000 |
| **Honest total** | **about 1.1M** | **about 1.14M** |

Costs: VIP lounge ₦1M a month (₦33k a day), Big Boy booth ₦250k a night, spray (unlimited), a Babalawo charm ₦0.8M to ₦3M + offerings, crew upgrades ₦20M, house tier upgrade ₦22M, luxury garage ₦12M, a soundproof generator ₦12M, a ₦95M to ₦450M car. At about ₦1M a day a ₦450M car is 15 months of income and a ₦22M house upgrade is three weeks: there is always a next goal, and the passive MMF no longer outruns the work (₦100M in the MMF paid ₦600k a day risk-free; now ₦300k).



### 3. The ten biggest outliers and what changed

| # | Outlier | Before | Now |
|---|---|---|---|
| 1 | **Yahoo Big job** vs career pay | ₦500k to ₦3M (average ₦2M) every 5 minutes, uncapped: **₦71M an active hour**, ₦35M in a 30-minute session; a CTO earns ₦360k a day | ₦160k to ₦320k, **2 a day**, Dell XPS (₦1.1M) + Yahoo level 3: EV **₦188k a day** (1.8 x a senior legit day, 0.5 x a CTO day) |
| 2 | **Yahoo Elon format** | ₦200k to ₦1.2M, ThinkPad, level 4, uncapped (**₦14.5M in 30 minutes**) | ₦70k to ₦150k, EliteBook (tier 2), level 4, **3 a day**: EV **₦172k a day** (1.6 x senior) |
| 3 | **Yahoo Chat a client / Romance job** (day-1 crime) | Chat ₦5k to ₦50k every 30 s (**₦1M in 30 minutes** on a ₦45k laptop); Romance ₦50k to ₦400k with the same laptop | Chat ₦3k to ₦10k, 8 a day (**₦13.1k a day**, 1.6 x a starter); Romance ₦28k to ₦60k, 4 a day, needs a ThinkPad + Yahoo 2 (**₦54k a day**, 1.5 x mid tier) |
| 4 | **Crew Night market shakedown** (and the other crew jobs) | ₦300k to ₦900k a minute-long job, 8 jobs a day: **about ₦1M a member a day**; Bank van ₦8M to ₦25M | pot ₦50k to ₦110k, **3 jobs a day**: ₦17k a member a job. Container ₦250k to ₦550k, Warehouse ₦350k to ₦750k, Bank van ₦1.5M to ₦3.5M (₦44k / ₦55k / ₦182k a member a job) |
| 5 | **Group missions** | Crew hustle ₦400k to ₦1.6M every 10 minutes, HK table ₦3M to ₦12M every 20 minutes, uncapped | ₦30k to ₦80k, 3 a day (₦57k a day each); ₦300k to ₦550k, 2 a day (₦181k a day each) |
| 6 | **Business payback** | restock cost 60 to 127 % of income: Provision 171 days, Buka 257, Beer parlour / Chemist / Filling station **never** (they lost ₦0 / ₦3k / ₦47k a day stocked, so nobody restocked) | restock about 20 % of income; every type pays back in **63 to 108 days** with stock |
| 7 | **Market business loop** (free money) | list a business at 250 % of its value, an alt buys it, sells it to the system for 60 % of what it paid: **+30 % of the value per lap** (₦5.4M a lap for an Event centre) | invested is capped at the catalogue value: a lap loses 40 % of the value plus the 8 % fee |
| 8 | **Referral and side money** (free money) | one 20-second shift = ₦20k + ₦20k per alt account; gem hunt ₦14k a day for walking; challenges ₦15.9k a day (a starter job is ₦8.4k) | referral: 9 shifts / 15 hustles / 240 minutes, ₦10k + ₦10k, 3 a day, 30 ever; gems ₦5k; challenges ₦9.7k; tips ₦100k / ₦300k a day (they bypassed the ₦200k transfer limit) |
| 9 | **Invest yields against risk** | MMF 18 % (any time, risk-free) > Dangote 10 %; USDT "high risk" 6 %; land 22 to 35 % a month with 7 to 9 % vol; BTC +55 % a month; poultry / fish farms 1.65 / 1.74 % a day vs 1.2 % for the other farms | safe 6 to 15 %, shares 19.5 to 27.3 %, USDT 10 %, BTC 30 %, land 12 to 18 % (break-even 36 to 59 days instead of 19 to 31), flats 27.5 % total, farms 1.3 to 1.4 % a day |
| 10 | **Gear-free hustles that out-paid gear** and **office salary** | Tutor ₦40k a day, MC ₦45k a day, fishing ₦27k a day for an ₦8k rod, DJ set ₦56k a day; Commissioner ₦40k a day for an appointed seat | Tutor ₦17k, MC ₦23k, fishing ₦11k, DJ set ₦36k; Bolt Premium / Black payback 468 / 1,047 → 304 / 653 days; salaries ₦10k / 25k / 50k / 15k |

Not outliers (checked, left alone): career pay (a smooth ladder), house upgrade prices (10 to 220 days of mid-game surplus each, see 2.2), keke / Okada / Sienna / POS units (0.8 to 1.3 % a real day after their own bad events, payback 78 to 123 days), the Babalawo money charm, the Market fees, and every owner value in section 6.

**Every change, with its reason.** All 91 are in the one migration, each guarded (a row only changes when every column in the guard is still at the old default) and each logs `E3 changed ...` / `E3 SKIPPED ...` notices; game settings also write `config_audit`.


| Where | Before | Now | Why |
|---|---|---|---|
| `yahoo_jobs.chat_client` | pay_min 5,000, pay_max 50,000 | pay_min 3,000, pay_max 10,000 | starter crime: about 1.5x a starter job after the laptop risk |
| `yahoo_jobs.chat_client` | daily_cap 0 | daily_cap 8 | 8 a day like every other earner has a cap |
| `yahoo_jobs.romance_job` | pay_min 50,000, pay_max 400,000 | pay_min 28,000, pay_max 60,000 | mid tier: about 1.5x a mid-tier legit day once the ThinkPad it risks is counted |
| `yahoo_jobs.romance_job` | min_tier 0, min_skill_level 1 | min_tier 1, min_skill_level 2 | needs a ThinkPad (₦280k) and Yahoo level 2 so day 1 cannot reach mid-tier pay |
| `yahoo_jobs.romance_job` | daily_cap 0 | daily_cap 4 | 4 a day |
| `yahoo_jobs.elon_format` | pay_min 200,000, pay_max 1,200,000 | pay_min 70,000, pay_max 150,000 | senior tier: about 1.6x a senior legit day (Tech Lead / Resident Doctor level) |
| `yahoo_jobs.elon_format` | min_tier 1 | min_tier 2 | needs an EliteBook (₦330k) as well as Yahoo level 4 |
| `yahoo_jobs.elon_format` | daily_cap 0 | daily_cap 3 | 3 a day |
| `yahoo_jobs.big_job` | pay_min 500,000, pay_max 3,000,000 | pay_min 160,000, pay_max 320,000 | top crime: needs a Dell XPS (₦1.1M); about 1.8x a senior legit day and below a CTO day, not 10x |
| `yahoo_jobs.big_job` | daily_cap 0 | daily_cap 2 | 2 a day |
| `group_missions.crew_hustle` | reward_min 400,000, reward_max 1,600,000 | reward_min 30,000, reward_max 80,000 | whole pot split between 2 to 4 friends; about a romance job each |
| `group_missions.crew_hustle` | daily_cap 0 | daily_cap 3 | 3 a day |
| `group_missions.hk_big_table` | reward_min 3,000,000, reward_max 12,000,000 | reward_min 300,000, reward_max 550,000 | whole pot split between 3 to 4 friends (Yahoo level 4); about a Big job each |
| `group_missions.hk_big_table` | daily_cap 0 | daily_cap 2 | 2 a day |
| `crew_jobs.market_shakedown` | reward_min 300,000, reward_max 900,000 | reward_min 50,000, reward_max 110,000 | starter crew job: about ₦17k a member a job, 3 a day (legit mid job ₦36k a day) |
| `crew_jobs.port_container` | reward_min 1,200,000, reward_max 3,500,000 | reward_min 250,000, reward_max 550,000 | ₦44k a member a job after the ₦20k buy-in; needs crew level 2 (₦1M of upgrades) |
| `crew_jobs.ring_road_warehouse` | reward_min 2,000,000, reward_max 5,000,000 | reward_min 350,000, reward_max 750,000 | ₦55k a member a job after the ₦30k buy-in; needs crew level 2 |
| `crew_jobs.bank_van` | reward_min 8,000,000, reward_max 25,000,000 | reward_min 1,500,000, reward_max 3,500,000 | ₦180k a member a job after the ₦100k buy-in; needs crew level 4 (₦12M of upgrades and 700 XP); 3 hour cooldown |
| `hustles.tutor_session` | pay_min 6,000, pay_max 12,000, bonus_min 5,000, bonus_max 15,000 | pay_min 2,500, pay_max 5,000, bonus_min 3,000, bonus_max 8,000 | no gear, no certificate, day 1: ₦9k a run x 4 beat every starter job; now about 2x a starter day |
| `hustles.mc_gig` | pay_min 8,000, pay_max 18,000, bonus_min 5,000, bonus_max 15,000 | pay_min 4,000, pay_max 9,000, bonus_min 3,000, bonus_max 8,000 | no gear needed: was the best gear-free hustle at ₦13k a run |
| `hustles.dj_set` | pay_min 15,000, pay_max 35,000, bonus_min 10,000, bonus_max 30,000 | pay_min 10,000, pay_max 22,000, bonus_min 6,000, bonus_max 18,000 | ₦220k controller paid back in 4 days; the headline slot (certificate) still pays more |
| `hustles.mech_quick` | pay_min 3,500, pay_max 8,000 | pay_min 2,500, pay_max 6,000 | no gear and no certificate paid like a PoS machine |
| `items.fish_tilapia_small` | price 1,200 | price 600 | a cast was worth 3 x a starter shift (₦2.7k a cast, 10 casts a day for an ₦8k rod) |
| `items.fish_tilapia` | price 2,500 | price 1,200 | same |
| `items.fish_catfish` | price 5,500 | price 2,600 | same |
| `items.fish_mudfish` | price 9,000 | price 4,200 | same |
| `items.fish_giant_catfish` | price 30,000 | price 12,000 | same |
| `hustle_car_classes.premium` | pay_mult 2.2 | pay_mult 3.0 | ₦40M car paid back in 440 days; now about 290 |
| `hustle_car_classes.luxury` | pay_mult 3.5 | pay_mult 5.0 | ₦150M car paid back in 1,000 days; now about 620 |
| `business_types.provision_shop` | restock_cost 18,000 | restock_cost 6,000 | was 60 % of income |
| `business_types.buka` | restock_cost 25,000 | restock_cost 8,000 | was 62 % of income |
| `business_types.beer_parlour` | restock_cost 55,000 | restock_cost 14,000 | was 79 % of income |
| `business_types.chemist` | income_min 30,000, income_max 45,000, restock_cost 70,000 | income_min 36,000, income_max 54,000, restock_cost 15,000 | was 93 % of income; +20 % income so the ₦2.8M price pays back in 88 days |
| `business_types.filling_station` | income_min 90,000, income_max 130,000, restock_cost 280,000 | income_min 100,000, income_max 145,000, restock_cost 44,000 | was 127 % of income; +11 % income so the ₦9M price pays back in 108 days |
| `invest_products.bronze_savings` | rate_pct 10 | rate_pct 6 | any-time money: lowest yield |
| `invest_products.mmf` | rate_pct 18 | rate_pct 9 | any-time money must pay less than a locked deposit |
| `invest_products.safelock_7` | rate_pct 15 | rate_pct 9.5 | 7 days locked |
| `invest_products.safelock_30` | rate_pct 18 | rate_pct 11 | 30 days locked |
| `invest_products.safelock_90` | rate_pct 22 | rate_pct 13 | 90 days locked |
| `invest_products.fd_30` | rate_pct 16 | rate_pct 10.5 | 30 days locked |
| `invest_products.fd_90` | rate_pct 19 | rate_pct 12.5 | 90 days locked |
| `invest_products.tbill_91` | rate_pct 16 | rate_pct 11 | sovereign, 91 days |
| `invest_products.tbill_182` | rate_pct 17.75 | rate_pct 13.5 | sovereign, 182 days |
| `invest_products.tbill_364` | rate_pct 21.85 | rate_pct 15 | sovereign, 364 days: the best safe yield |
| `invest_products.fgn_bond` | rate_pct 19 | rate_pct 12.5 | coupon; the price also wobbles +-3 % |
| `invest_products.farm_poultry` | gain_min_pct 25, gain_max_pct 35 | gain_min_pct 20, gain_max_pct 30 | was 1.6 % a day after events (the best medium-risk yield by far); now about 1.3 % |
| `invest_products.farm_fish` | gain_min_pct 28, gain_max_pct 38 | gain_min_pct 22, gain_max_pct 32 | was 1.7 % a day after events; now about 1.35 % |
| `invest_markets.stk_dangcem` | drift_pct_year 10 | drift_pct_year 15 | a risky share must beat the safe MMF (9 %): drift plus about 4 % dividends |
| `invest_markets.stk_mtnn` | drift_pct_year 12 | drift_pct_year 16 | same |
| `invest_markets.stk_gtco` | drift_pct_year 15 | drift_pct_year 19 | same |
| `invest_markets.stk_zenith` | drift_pct_year 13 | drift_pct_year 18 | same |
| `invest_markets.stk_okomu` | drift_pct_year 14 | drift_pct_year 18 | same |
| `invest_markets.stk_presco` | drift_pct_year 16 | drift_pct_year 21 | same |
| `invest_markets.crypto_usdt` | drift_pct_year 6 | drift_pct_year 10 | "high risk" paid less (6 %) than the safe MMF (18 %) |
| `invest_markets.land_gra` | drift_pct_year 22 | drift_pct_year 12 | land: break-even after about 35 days instead of 20 |
| `invest_markets.land_ugbowo` | drift_pct_year 28 | drift_pct_year 15 | same |
| `invest_markets.land_sapele` | drift_pct_year 24 | drift_pct_year 13 | same |
| `invest_markets.land_airport` | drift_pct_year 30 | drift_pct_year 16 | same |
| `invest_markets.land_ikpoba` | drift_pct_year 26 | drift_pct_year 14 | same |
| `invest_markets.land_okhoro` | drift_pct_year 33 | drift_pct_year 17 | same |
| `invest_markets.land_ekenwan` | drift_pct_year 35 | drift_pct_year 18 | same |
| `invest_markets.property_index` | drift_pct_year 14 | drift_pct_year 8 | rental flats earned 0.65 % a day in rent plus 14 % a 30 days in price: about 1.1 % a day for a 0.5 % vol index |
| `invest_markets.crypto_btc` | drift_pct_year 55 | drift_pct_year 30 | Bitcoin drifted +55 % every 30 days (x128 a year) with about 29 % vol: a Sharpe near 2 with no cap on the amount; 30 % still pays the risk |
| `offices.councillor` | salary_per_day 20,000 | salary_per_day 10,000 | ₦280k a 14-day term for holding a seat |
| `offices.chairman` | salary_per_day 50,000 | salary_per_day 25,000 | about a Senior Nurse day |
| `offices.governor` | salary_per_day 100,000 | salary_per_day 50,000 | about a Tech Lead day |
| `offices.commissioner_works` | salary_per_day 40,000 | salary_per_day 15,000 | appointed, no campaign: below a Staff Nurse shift x 3 |
| `offices.commissioner_finance` | salary_per_day 40,000 | salary_per_day 15,000 | same |
| `offices.commissioner_youth` | salary_per_day 40,000 | salary_per_day 15,000 | same |
| `offices.commissioner_information` | salary_per_day 40,000 | salary_per_day 15,000 | same |
| `offices.commissioner_commerce` | salary_per_day 40,000 | salary_per_day 15,000 | same |
| `offices.commissioner_security` | salary_per_day 40,000 | salary_per_day 15,000 | same |
| `yahoo.launder_fee_pct` | 15 | 10 | launder was strictly worse than a full cash out (15 % fee vs about 8 % expected loss); 10 % makes it a real choice for people who fear the laptop seizure |
| `crew.max_jobs_per_day` | 8 | 3 | 8 jobs a day x 7 hours of cooldown was a second full-time job; 3 keeps crime to a few minutes a day |
| `daily.gem_prize` | 3000 | 1000 | ₦14k a day for walking was more than a starter day of work (was already recommended in docs/BALANCE.md L1) |
| `daily.gem_all_bonus` | 5000 | 2000 | same |
| `challenges.reward_mult` | 1 | 0.7 | challenges + chests paid about ₦17k a day; now about ₦10k, still a nice extra on top of work |
| `challenges.daily_chest_cash` | 3000 | 2000 | same |
| `challenges.weekly_chest_cash` | 20000 | 12000 | same |
| `referral.bonus_referrer` | 20000 | 10000 | a milestone ANY of one shift / 3 hustles / 60 minutes paid ₦40k per alt account |
| `referral.bonus_referred` | 20000 | 10000 | same |
| `referral.min_shifts` | 1 | 9 | one 20-second shift completed the milestone; 9 shifts is 3 days of work |
| `referral.min_hustles` | 3 | 15 | same |
| `referral.play_minutes` | 60 | 240 | same |
| `referral.daily_cap` | 5 | 3 | less alt farming per day |
| `referral.max_total` | 100 | 30 | ₦10k x 100 = ₦1M per inviter was too big |
| `tips.max_amount` | 1000000 | 100000 | a tip moved up to ₦5M a day with no fee and no count limit, while a bank transfer is ₦200k a day: tips were the loophole for moving farmed money to one account |
| `tips.daily_max` | 5000000 | 300000 | same: now close to the bank transfer limit (₦200k) |
| `leaderboard.weekly_min_earned` | 20000 | 100000 | ₦20k a week was a few starter shifts: three alt accounts could take all three weekly prizes (₦350k) |
| `crew.weekly_min_jobs` | 2 | 8 | two jobs a week was enough for an alt crew to win the ₦500k Top crew prize |
| `cars.resale_pct` | 60 | 50 | the free Nepo car paid ₦1.5M on day 1 (₦1.25M now); also keeps buy-then-sell under the 70 % a business owner earns back from visitors |
| `crew.disband_fee_pct` | (new) | 10 | when a Boss disbands, this share of the crew bank is kept; an admin disband charges nothing |
| `yahoo_jobs.daily_cap`, `group_missions.daily_cap` | (new column) | 0 = no cap; seeded as in the rows above | per player per Benin day; cash out is never capped |


### 4. Free-money loops: checked and fixed

| Loop | Verdict |
|---|---|
| Shop buy → sell back | none: buy-back is 30 % (soap) to 60 % (souvenir) of the list price, laptops 40 to 50 %, cars 50 % (was 60 %); the cheapest dealer sells at x0.88, so a car round trip loses 43 %. Fish are the only 100 % item and no shop sells them |
| Market floor / ceiling (20 to 300 %, businesses 50 to 250 %) | pairs of accounts lose the 5 to 8 % fee on every kind except one: **business, fixed** (+30 % of its value a lap, now a loss; test `economy_balance_test` group 4). The Market stays a way to move money between accounts without the ₦200k transfer limit at a 5 to 8 % cost, kept on purpose, flagged in section 7 |
| Referral farming | **fixed**: one shift paid ₦40k per alt; now 9 shifts (3 days) or 15 hustles or 240 minutes of check-ins, ₦10k each, 3 a day and 30 ever. Still beatable with patience: see section 7 |
| Challenge farming | friend challenges can be done with alts (DMs, a house visit, a hustle together); **cut with `challenges.reward_mult` 0.7** and the chests; 1 free reroll a day stays. Not a creation loop beyond the reward itself |
| Business visitor cut with alts | none: the visitor pays 100 %, the owner gets 30 %, 70 % leaves the economy; nothing a visitor can buy resells above 60 % |
| Disband refunds | **fixed**: the whole bank was shared back to the members' banks with no cost, a free transfer between accounts; now 10 % stays (`crew.disband_fee_pct`), an admin disband is free |
| Crew deposit loops | none: a deposit can only leave through an upgrade (a sink) or the disband (now 10 %); the crew bank is not payable to players otherwise |
| Land flips | none as a flip (a round trip costs 14 to 36 % in fees); **held land was the money machine** (22 to 35 % a month at 7 to 9 % vol): drift cut to 12 to 18 % |
| Tips | **fixed**: ₦5M a day with no fee next to a ₦200k a day bank transfer; now ₦100k a tip, ₦300k a day |
| Weekly prizes | **tightened**: a week of ₦20k earned (a few starter shifts) won ₦200k; the Top crews prize (₦500k) needed 2 jobs. Minimums are now ₦100k earned and 8 jobs |
| The free Nepo car | ₦1.5M on day 1 → ₦1.25M (`cars.resale_pct` 50) |
| Yahoo launder | strictly worse than a full cash out (15 % fee for 3.5 % chance against about 8 % expected loss): fee 10 % |



### 5. Probability verification ("a percentage that should happen and does not")

`supabase/tests/odds_test.sql` runs the REAL resolve functions with `bl.test_rand` cleared inside a rolled-back transaction, and checks every stated chance three ways: **stated** (setting / table plus the modifiers that apply), **shown** (what the status RPCs and `*_json` helpers send to the screens must equal what the roll uses, exactly) and **observed** (rate over N trials within 4 binomial standard deviations). The default file takes about 50 s (trials 250 to 4,000 per check, bands ±3 to ±10 points); the table below is a deeper run with 4 x the trials (`select set_config('odds.mult','4',false)` before the file), bands about ±1.5 to ±5 points. 75 checks, all inside their band, all "shown" values equal to the rate used.

| Check | Stated | Shown on screen / by the server | Observed (real resolve, no forced roll) | Trials | Band (4 sigma) |
|---|---:|---:|---:|---:|---:|
| yahoo chat client, lvl 1, Tokunbo laptop | 12.00% | 12.00% | 12.04% | 2800 | ±2.5 |
| yahoo chat client, lvl 6 (-20% cut) | 9.60% | 9.60% | 9.25% | 2000 | ±2.6 |
| yahoo romance, lvl 2, ThinkPad (-1 pt) | 14.40% | 14.40% | - (formula and screens only) | - | - |
| yahoo elon format, lvl 4, EliteBook (-2 pts) | 15.84% | 15.84% | 14.90% | 2000 | ±3.3 |
| yahoo big job, lvl 3, XPS (-4 pts) | 18.40% | 18.40% | 17.75% | 1600 | ±3.9 |
| cash out FULL (14% x 100%) | 14.00% | 14.00% | 14.31% | 1600 | ±3.5 |
| cash out HALF (14% x 60% = 8.4%) | 8.40% | 8.40% | 7.69% | 1600 | ±2.8 |
| cash out LAUNDER (14% x 25% = 3.5%) | 3.50% | 3.50% | 3.19% | 1600 | ±1.8 |
| yahoo group crew_hustle, avg lvl 3 (-8%) | 18.40% | 18.40% | 18.95% | 2000 | ±3.5 |
| crew job market_shakedown, avg skill 3 (-3%) | 21.34% | 21.34% | 20.44% | 1600 | ±4.1 |
| pickpocket, no charms (62%) | 62.00% | - | 61.85% | 2000 | ±4.3 |
| pickpocket, protection 45 + victim guard 50% | 67.50% | - | 66.31% | 1600 | ±4.7 |
| escape, police case (52% caught) | 52.00% | 52.00% | 48.38% | 1600 | ±5.0 |
| escape, EFCC case (55% caught) | 55.00% | 55.00% | 55.00% | 1600 | ±5.0 |
| escape, vanishing charm (cap 30%) | 30.00% | 30.00% | 31.25% | 1600 | ±4.6 |
| escape, bad luck (+10 pts = 62%) | 62.00% | 62.00% | 60.69% | 1600 | ±4.9 |
| hustle bolt_shift risk event | 8.00% | - | 8.75% | 1600 | ±2.7 |
| hustle pos_agent loss (fake alert etc.) | 4.00% | - | 4.13% | 2400 | ±1.6 |
| hustle pos_agent risk event | 11.52% | - | 11.58% | 2400 | ±2.6 |
| hustle vend_jollof risk event | 10.00% | - | 11.30% | 1000 | ±3.8 |
| hustle vend_puff risk event | 10.00% | - | 8.10% | 1000 | ±3.8 |
| hustle vend_fried_yam risk event | 10.00% | - | 8.90% | 1000 | ±3.8 |
| hustle dj_set tip / bonus | 15.00% | - | 13.69% | 1600 | ±3.6 |
| hustle dj_headline tip / bonus | 20.00% | - | 19.00% | 1000 | ±5.1 |
| hustle mc_gig tip / bonus | 20.00% | - | 19.42% | 1200 | ±4.6 |
| hustle tutor_session tip / bonus | 10.00% | - | 8.10% | 1000 | ±3.8 |
| hustle mech_engine risk event | 10.00% | - | 9.90% | 1000 | ±3.8 |
| hustle mech_fleet risk event | 8.00% | - | 7.90% | 1000 | ±3.4 |
| fishing: nothing bites | 10.00% | - | 10.13% | 2400 | ±2.4 |
| fishing: fish_tilapia_small (weight 40) | 36.00% | - | 37.04% | 2400 | ±3.9 |
| fishing: fish_tilapia (weight 25) | 22.50% | - | 22.50% | 2400 | ±3.4 |
| fishing: fish_catfish (weight 17) | 15.30% | - | 13.67% | 2400 | ±2.9 |
| fishing: fish_mudfish (weight 8) | 7.20% | - | 7.17% | 2400 | ±2.1 |
| fishing: fish_giant_catfish (weight 2) | 1.80% | - | 2.08% | 2400 | ±1.1 |
| fishing: river_junk (weight 8) | 7.20% | - | 7.42% | 2400 | ±2.1 |
| business provision shop, no staff levy | 8.00% | - | 7.73% | 8000 | ±1.2 |
| business provision shop, no staff outage | 14.00% | - | 13.96% | 8000 | ±1.6 |
| business provision shop, no staff goodday | 10.00% | - | 9.80% | 8000 | ±1.3 |
| business provision shop, no staff robbery | 6.00% | - | 6.28% | 8000 | ±1.1 |
| business shop, 2 staff + shift boost levy | 6.40% | - | 6.54% | 8000 | ±1.1 |
| business shop, 2 staff + shift boost theft | 4.00% | - | 3.66% | 8000 | ±0.9 |
| business shop, 2 staff + shift boost outage | 14.00% | - | 14.43% | 8000 | ±1.6 |
| business shop, 2 staff + shift boost goodday | 10.00% | - | 10.40% | 8000 | ±1.3 |
| business shop, 2 staff + shift boost robbery | 2.40% | - | 2.54% | 8000 | ±0.7 |
| business event centre (type override) goodda | 35.00% | - | 35.60% | 6000 | ±2.5 |
| babalawo consultation fail | 0% | 0% | - (card vs stored visit) | - | - |
| babalawo road_opener fail | 10% | 10% | - (card vs stored visit) | - | - |
| babalawo protection fail | 10% | 10% | - (card vs stored visit) | - | - |
| babalawo vanishing fail | 10% | 10% | - (card vs stored visit) | - | - |
| babalawo home_guard fail | 10% | 10% | - (card vs stored visit) | - | - |
| babalawo attraction fail | 10% | 10% | - (card vs stored visit) | - | - |
| babalawo fame_bath fail | 10% | 10% | - (card vs stored visit) | - | - |
| babalawo efcc_blindfold fail | 10% | 10% | - (card vs stored visit) | - | - |
| babalawo money_charm fail | 10% | 10% | - (card vs stored visit) | - | - |
| babalawo cleansing fail | 0% | 0% | - (card vs stored visit) | - | - |
| babalawo road opener fails 10% | 10.00% | 10.00% | 9.55% | 2000 | ±2.7 |
| babalawo cleansing never fails (0%) | 0.00% | 0.00% | 0.00% | 200 | ±0.2 |
| exam: Catering, skill lvl 1 (55%) | 55.00% | 55.00% | 56.15% | 2000 | ±4.4 |
| exam: Catering, skill lvl 6 (55 + 5 x 6 = 85 | 85.00% | 85.00% | 84.88% | 1600 | ±3.6 |
| money pick: spray 5000 | 20% | 20% | 0 (under one note) | - | - |
| money pick: spray 49999 | 20% | 20% | 0 (under one note) | - | - |
| money pick: spray 50000 | 20% | 20% | 20.00% | - | - |
| money pick: spray 123456 | 20% | 20% | 20.00% | - | - |
| money pick: spray 1000000 | 20% | 20% | 20.00% | - | - |
| money pick: spray 77777777 | 20% | 20% | 20.00% | - | - |
| origin roll: Nepo (origin.nepo_pct) | 10.00% | - | 10.30% | 16000 | ±0.9 |
| street robbery on foot at Oba Market, N20k | 3.82% | 3.82% | 3.88% | 6000 | ±1.0 |
| street robbery: injured (crime.injury_pct) | 15.00% | - | 15.62% | 1210 | ±4.1 |
| invest POS stand: network down, a day | 3.00% | 3.00% | 3.08% | 8400 | ±0.7 |
| invest Okada: engine knock, a day | 2.00% | 2.00% | 2.01% | 8400 | ±0.6 |
| invest poultry harvest: bird flu | 10.00% | 10.00% | 10.75% | 2000 | ±2.7 |
| invest poultry harvest: thieves | 5.00% | 5.00% | 5.85% | 2000 | ±1.9 |
| invest land Ekenwan: development levy | 35.00% | 35.00% | 34.38% | 1600 | ±4.8 |
| link-up hotel night: phone / cash missing | 10.00% | - | 9.94% | 1600 | ±3.0 |
| link-up hotel night: partner finds out | 35.00% | - | 34.38% | 1600 | ±4.8 |

**Mismatches found and fixed**

| Where | What was wrong | Fix |
|---|---|---|
| Yahoo app, running-job bar | showed `caught_pct` (before the Yahoo level cut) while the roll uses the cut chance | the bar and the start toast now use `skill_caught_pct` (client; the server already sent it) |
| Yahoo app, "escape x % chance" line | showed the bare `yahoo.escape_caught_pct`, ignoring a vanishing charm (cap 30) and bad luck (+10) | `yahoo_status().prices.escape_caught_pct` now returns what `bl_escape_pct_peek` uses (tested with both charms) |
| Hustle PoS network failure | stated 12 % but happens 11.5 % (rolled only when no fake alert happened) | documented, kept (inside the band, forced-roll tests depend on the order) |
| Crew job list `est_pct` | estimate for the whole crew, not the lobby members | documented, agrees when everyone joins |
| Exam pass chance | not a bug: a passed class pays Cooking XP (course rows, not `skill_sources`) so the level, and the chance, rises as you pass; my first loop saw 89 % until it reset the XP | test resets XP; behaviour kept |

No chance was found that is "never rolled": every `*_pct` / `chance` setting is read by a resolve function (the only unreferenced one, `home.walk_max_share_pct`, is documented as dead).


### 6. Owner-set values: untouched, and owner-edited values skipped

**Left exactly as the owner set them** (and asserted by `economy_balance_test`, group 1): LAPO start cash ₦85,000; the Babalawo service prices and the x1.2 offerings (goat ₦102,000, cow ₦1,440,000, money charm ₦3M, EFCC blindfold ₦1.2M ...); the Yahoo "fairer" catch chances 12 / 16 / 24 / 14 %, `yahoo.seize_laptop_pct` 35 and `yahoo.confiscate_pct` 50; the club weekend price x1.5; the money pick (₦10,000 a tap, 20 % of a spray falls, 5 s, 50 taps); `origin.nepo_pct` 10; jail escape 52 % / EFCC escape 55 %; pickpocket 62 %; every other chance.

**Skipped because the owner already edited them in Admin:** none on the local database (`config_audit` holds only `origin.force_next` and `origin.nepo_pct` 10 → 12 → 10, and the migration does not touch either). The live database may differ: every guarded row prints `E3 SKIPPED <table.id> (owner value ..., expected old default ..., wanted ...)` when it meets an edited value and leaves it alone. Pay, gates and caps of one yahoo job are separate guards, so an edited pay does not block the new daily cap. Run the migration with `psql` (not the dashboard) to read those notices, or check `config_audit` for the keys listed in section 3.



### 7. Not changed, and what the owner may want to decide

- **LAPO start cash ₦85,000 and alt farming.** It is the owner's number, so it stays. Each throw-away account is worth ₦85,000 plus the daily reward, and the only brakes are the 24-hour wait before an account can send money, sell on the Market or tip, the ₦200,000 a day transfer limit and the new ₦300,000 tip limit. If farming shows up in Admin → Overview ("Money today by reason"), the first lever is `bank.transfer_min_account_real_minutes` 1,440 → 4,320, then `origin.lapo.start_cash`.
- **The referral milestone is still "any one" of shifts, hustles or minutes.** Nine shifts is three days of daily visits, but an account that only idles with the app open for 240 minutes also qualifies. Making it "all three" is a code change (`bl_referral_progress`), not a setting.
- **The Market as a transfer channel** (5 to 8 % fee, 10 listings a day, up to 300 % of the catalogue price) still moves money between accounts faster than the bank. Lowering `market_settings.ceiling_pct` from 300 to 200 or raising the fee to 8 % would make it less attractive.
- **Money charm** returns about +₦2M per 14 days for a rich player who visits three times a day. Owner's prices; revisit the payout (`shrine.money_payout_min` / `max`) only if rich players buy it every two weeks.
- **`wanted` is counted but changes nothing** (no police chance reads it), and the setting `home.walk_max_share_pct` is dead (documented). A wanted level that raises the caught chance would be a good late-game crime brake.
- **Hustle odds are rolled in order** (loss, then risk, then tip, each only when the one before did not happen), so PoS "network down 12 %" really happens 11.5 % of the time (12 % x 96 % no fake alert). It is inside the sampling band and kept, because forced-roll tests and the Admin text depend on the order.
- **Crew job cards show an estimate for the whole crew** (`est_pct`); the lobby and the running job use the members who joined. Both are labelled by the app; they agree when everybody joins.
- **Career pay above level 5** (Tech Manager ₦70k, CTO ₦120k a shift) is already the best legit income; nothing legit beats a CTO except a level-4 Filling station plus a Bolt Luxury. Crime now sits under it.



### 8. Files and tests

- `supabase/migrations/20261019000100_economy_balance.sql` (one migration, guarded, ends with `notify pgrst, 'reload schema'`): the tuning, the daily cap column and gates (`yahoo_job_start`, `yahoo_status`, `bl_yahoo_group_gate`, `yahoo_group_status`), the Market business fix (`bl_biz_market_give`), the crew disband fee (`bl_crew_dissolve`), the Yahoo escape % (`yahoo_status`), the admin editor column (`bl_admin_table_spec`). Verified by applying it to a copy of the old values: 91 changes, 0 skipped, and the result equals the live database.
- `supabase/tests/odds_test.sql`: the probability checks (section 5), about 50 s. `economy_balance_test.sql`: seeds, caps, market loop, disband fee, referral, the ladder (crime EV a day against the legit tier, with windows) and business payback.
- Existing suites that assert launch values pin them at the top (`yahoo_test`, `yahoo_strategy_test`, `skills_test`, `hustles_test`, `business_test`, `crews_test`, `invest_save_test`, `politics_test`); behaviour is unchanged.
- Client: `YahooApp.tsx` (the running bar shows the cut chance, "Done for today", "n left today"), `YahooGroups.tsx`, `api/yahoo.ts`, Admin `Content.tsx` (Most runs a day). Help article `yahoo` and `crew` text. Feature docs YAHOO, CREWS, BUSINESS, INVEST, HUSTLES, POLITICS, CHALLENGES, DAILY and MARKET have an "E3 retune" note.



---

## L1 launch numbers (2026-10-12), kept for history

> Superseded in places by E3 above: LAPO start cash is now ₦85,000 (owner), and the gem hunt prizes in the table below were applied by E3 (₦1,000 / ₦2,000).

Numbers read from the local database (same defaults as live unless you changed them in Admin). Nothing here is changed by a migration: these are **suggestions for you to set in Admin**. Every key is in Admin → Settings (search the key), except rents, which are in Admin → Content → Homes.

The clock is real Benin time (`clock.mode` = real). One game day is one real day. Hunger drops about 4 points an hour (`needs.hunger_per_hour` 4 × `needs.decay_speed` 1), so a Sim needs about 2 proper meals a day.

## What a new player has

| | LAPO (Ekenwan face-me) | LAPO (UNIBEN hostel) | LAPO (Uselu self-contain) | Nepo (GRA duplex) |
|---|---|---|---|---|
| Start cash | ₦8,000 | ₦6,000 | ₦4,000 | ₦50,000 + ₦500,000 bank |
| Weekly rent | ₦1,500 | ₦1,000 | ₦4,000 | ₦25,000 |
| Extras | none | none | none | ₦5,000/day allowance, 2 career levels head start, tokunbo car (list ₦2.5M), laptop |

## A LAPO player's first days

| | Per day |
|---|---|
| Food, cheapest way (cook at home ₦600 for 45 hunger, garri ₦300 for 20) | about ₦1,300 to ₦2,000 |
| Rent (face-me) | about ₦215 |
| Starter job (3 shifts a day, `career.max_shifts_per_game_day` 3): Trade ₦2,000, PoS ₦2,500, Health/Transport ₦3,000, Tech ₦3,500 a shift, up to 120% when well fed and rested | ₦6,000 to ₦10,500 |
| Daily reward (7-day ladder ₦1,000 → ₦10,000) | ₦1,000 to ₦10,000 |
| Gem hunt (3 gems × ₦3,000 + ₦5,000 bonus for all three) | up to ₦14,000 |

**Verdict:** a LAPO player covers food and rent from the first day of work; nobody is stuck. After a week of steady shifts (about ₦40,000) they can afford the ₦16,000 move into a self-contain. In the journey test (L1lapoA) one shift paid ₦2,390.

**Can someone go broke for good on day 1?** No. Walking is free, applying for a job is free, sleeping at home is free and restores energy, and a shift only needs hunger ≥ 10 and energy ≥ 15. The worst case is a Sim with no money and hunger under 10 after claiming today's reward: they wait until midnight (Benin time) for the next daily reward (₦1,000 buys three garri) or pick up a gem by walking, then work again. Starving only drains health to a floor of 10. Rent they can't pay becomes rent owed (sleep restores less energy until it is paid) and is never a dead end. So no default is changed in the migration.

**Nepo:** comfortable, not maxed. The ₦500,000 bank covers 20 weeks of duplex rent; good furniture costs ₦0.1M to ₦6.5M per piece and cars ₦1.6M to ₦250M. The one shortcut: selling the free tokunbo car on day 1 pays ₦1.5M (60% of list) into the bank.

## Recommended admin values

| Key | Current | Suggested | Why |
|---|---|---|---|
| `daily.gem_prize` | 3000 | **1000** | Three gems a day pay more than a full day of starter work (₦14,000 vs ₦6,000). Lower so work stays the main income and alt accounts farm less. |
| `daily.gem_all_bonus` | 5000 | **2000** | Same reason. With the line above the hunt pays up to ₦5,000 a day. |
| `cars.resale_pct` | 60 | **45** (optional) | A Nepo can sell the free starter car for ₦1.5M on day 1. At 45% it is ₦1.1M. Also matches `furniture.resale_pct` 45. |
| Content → Homes → GRA duplex weekly rent | 25000 | **50000** | Real GRA duplex rent is about ₦3M to ₦6M a year (₦60,000 to ₦115,000 a week). ₦50,000 still gives a Nepo 10 weeks from the start bank, and makes the allowance and a job matter. |
| Content → Homes → Mini-flat weekly rent | 8000 | 8000 (keep) | In line with real Mission Road prices (₦300k to ₦500k a year). |
| Content → Homes → Uselu self-contain start cash (LAPO) | 4000 | **6000** | LAPO players who pick it start with exactly one week's rent and ₦0 for food. ₦6,000 leaves two days of food. |
| `origin.nepo.allowance_daily` | 5000 | 5000 (keep) | Small next to Nepo pay; a nice daily touch. |
| `career.pay_mult` | 1 | 1 (keep) | Starter pay already covers food and rent from day 1. |
| `career.max_shifts_per_game_day` | 3 | 3 (keep) | Caps grinding at about 1 minute of real work a day per job level. |
| `house.move_in_weeks` | 4 | 4 (keep) | Self-contain move after about a week of work feels right. |
| `bank.transfer_min_account_real_minutes` | 1440 | 1440 (keep) | Stops new alt accounts sending their freebies to a main account on day 1. |
| `origin.nepo_pct` | 10 | 10 (keep) | Nepo should stay rare. |
| Top-up packs (Content → Top-up packs) | ₦200 → ₦20,000 game naira | keep | ₦20,000 is about three days of starter wages: worth it, not game-breaking. |

Change them after launch traffic shows how fast people earn: Admin → Overview → "Money today by reason" shows where the naira comes from (look for `Daily gem hunt` vs `work`).


## Owner decision on Yahoo (19 Oct 2026)
The owner chose the "middle ground": Yahoo and group-mission pay ranges and gates stay as approved; only daily caps were added (chat 15, romance 8, Elon 4, Big job 3, each group mission 3). The Yahoo rows in the tables above that show cut pay were NOT applied. Measured after caps: chat about 16x a starter day, romance 31x mid, Elon 19x senior, Big job 34x senior. Everything else in E3 was applied.
