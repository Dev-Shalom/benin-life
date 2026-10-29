// Settings: every game_config value, grouped by category, with the most-used knobs on top.
import { useEffect, useMemo, useState } from 'react';
import { useSearchParams } from 'react-router-dom';
import { toast } from '../ui';
import { errorMessage } from '../lib/api';
import { useConfig } from '../lib/config';
import { adminApi, type ConfigRow, type PushStats, type Row } from './api';
import { Btn, JsonControl, LoadError, NumberControl, PageHead, Skeleton, Toggle } from './parts';
import { fmtValue, timeShort, useLoad } from './util';

const CATEGORY_META: Record<string, { title: string; emoji: string; blurb: string }> = {
  action: { title: 'Action timing', emoji: '⚡', blurb: 'Every action takes a few real seconds: shifts, trips, jail and hospital. Per-activity seconds live in Content → Activities.' },
  sim: { title: 'Sim movement', emoji: '🚶', blurb: 'How fast the Sim walks at home (the stride and step rate follow, so the feet never slide).' },
  time: { title: 'Time & speed', emoji: '⏱️', blurb: 'Old game-minute timing (used when Action timing is game_minutes) and presence.' },
  clock: { title: 'Game clock', emoji: '🕰️', blurb: 'Real Benin time or the old fast clock, night hours and the launch day.' },
  origin: { title: 'Origin (LAPO / Nepo)', emoji: '👶', blurb: 'Who is born rich, and what each origin starts with.' },
  start: { title: 'New players', emoji: '🌱', blurb: 'Starting needs and new-player protection.' },
  creator: { title: 'Sim creator', emoji: '🧑‍🎨', blurb: 'Creator steps and the arrival spot.' },
  needs: { title: 'Needs', emoji: '🍲', blurb: 'How quickly hunger, energy and the rest go down.' },
  career: { title: 'Jobs & careers', emoji: '💼', blurb: 'Pay, XP, shifts and performance.' },
  shop: { title: 'Shops', emoji: '🛍️', blurb: 'Buying, selling and Chowdeck delivery.' },
  rent: { title: 'Rent', emoji: '🏠', blurb: 'Weekly rent and what happens when you owe. Also how many days a home you left stays in Past homes, and the house upgrade settings.' },
  property: { title: 'Own your home', emoji: '🔑', blurb: 'Buying, building and renting out homes (docs/PROPERTY.md): the on/off switches, the agent and legal fees, the resale %, how fast a build goes (100 = as listed, 0 = at once), the rent band around the market rent, the landlord cut, caution, notice days and the owed-rent eviction rule. Prices, areas, designs and build costs are in Content: Property areas, Home types, Home prices and Build designs. Tenancies and listings: the Property tab.' },
  bank: { title: 'Bank & transfers', emoji: '🏦', blurb: 'Opening hours, limits and fees.' },
  pos: { title: 'PoS', emoji: '🏧', blurb: 'PoS cash-out charges.' },
  travel: { title: 'Travel & fares', emoji: '🛺', blurb: 'Speeds and fares for every way to move.' },
  traffic: { title: 'Traffic', emoji: '🚦', blurb: 'Rush hours and the Ramat Park go-slow.' },
  shrine: { title: 'Babalawo shrine', emoji: '🪔', blurb: 'B2 Baba\'s Shrine: charm fail chance, the money charm (payout, weekly demand, backfire), bad luck and the home guard cap. Services (prices, offerings, effects): Content → Shrine services. docs/BABALAWO.md.' },
  skills: { title: 'Skills', emoji: '🌟', blurb: 'R3 (docs/SKILLS.md): the master switch (off = no XP, no gates, no effects), a global XP multiplier (double XP weekend) and which skill cuts the Yahoo EFCC chance. The curve, pay and EFCC effects per skill, and what gives XP: Content → Skills / Skill XP curve / Skill sources.' },
  school: { title: 'School', emoji: '🎓', blurb: 'R4 (docs/SCHOOL.md): the school switch (off = no classes, certificate gates and pay bonuses stop), fee and class-cooldown multipliers, the exam pass-chance floor and cap, and which certificate counts as a UNIBEN degree. Courses and certificates: Content → Courses / Certificates. Grant or revoke a player\'s certificate: Players → detail.' },
  love: { title: 'Family & love', emoji: '💞', blurb: 'Family & love (docs/LOVE.md): the master switch, how old an account must be to link up, partners at once, asks a day, how long an ask waits and the wait after a decline, the flirt wait and the daily level cap, when the level starts to fall and how fast, the level where a pair becomes a couple, date invite time, the waits after a break-up, and the Link-ups list size. Flirt lines (the menu and prices): Content → Flirt lines. Dates and their places: Content → Dates. Couples, asks and reports: the Love tab.' },
  kids: { title: 'Kids', emoji: '🍼', blurb: 'Family & love, stage 2 (docs/LOVE.md): the master switch (off = no babies, no care, no alerts, clocks paused), baby plans (days as a couple, costs, how long to expect, caps), naming time, days until grown up, the needs-attention level and alert limits (cooldown, quiet hours, batch size), neglect (sickness, relatives, bringing a child home), what each care action restores, costs and waits. Kids v2 (docs/LOVE.md): random illness, the doctor, relatives (each parent pays a share), the gentle passing away switch, the thank-you gift tiers. Life stages, needs and rates: Content -> Child stages; illnesses: Child illnesses; care supplies: Kids items; shop prices: Shop prices. Auto baby names: Content -> Baby names. Children and removing one: the Love tab.' },
  cooking: { title: 'Cooking and markets', emoji: '🍲', blurb: 'Cooking (docs/COOKING.md): the kitchen switch, how far Oba Market prices move each Benin day (the band) and the supermarket markup, the biggest pot and how much longer it takes, the longest cook, how many portions a bag holds, whether a stove is needed, the daily Cooking XP cap and the easy-dish rule, the Catering certificate speed-up, sharing with a partner and home-cooked meals for children. Dishes and their ingredients: Content -> Recipes and Recipe ingredients. Ingredient base prices: Content -> Items (category ingredient).' },
  kids_school: { title: 'Kids school', emoji: '🎒', blurb: 'Kids school and university (docs/KIDS_SCHOOL.md): the school switch, how long a class lasts (24 h = one class a day), the pass mark, the grade formula (starting grade, fees on time, needs, homework, textbooks, bag and uniform, extra lessons, talent), missed classes, school requests (chance, penalties), WAEC (credit mark, credits needed) and university (levels, repeats, pocket money, degree classes, the decision time). The schools: Content -> Schools; subjects: Content -> School subjects; the request cards: Content -> Life moments. The Graduate gift is under Kids.' },
  moments: { title: 'Life moments', emoji: '🎭', blurb: 'Docs/MOMENTS.md: the story pop-ups (landlord, NEPA, a friend asking for a loan, the doctor). How many a day, the wait between them, Remind me later, when a card expires and how often the app checks. The stories themselves: Content -> Life moments.' },
  stories: { title: 'Daily stories', emoji: '📖', blurb: 'Docs/DAILY_STORIES.md: the daily story in the Stories app. The switch, how many stories a day, how long before one repeats, the hidden path (the biggest nudge a choice can give, how strongly it tilts the odds, karma, how fast it fades, the levels where words and subtle lines appear), luck on pop-up chances, follow-ups (chance cap, most waiting, longest wait), cash caps, blessings and police scenes, the push, and the 3 / 7 / 14 day streak rewards. The stories: Content -> Daily stories. The words: Content -> Path words.' },
  lounge: { title: 'Members\' Lounge', emoji: '🛋️', blurb: 'R7 (docs/LOUNGE.md): the lounge switch, whether tier requirements apply, paying from the bank first, the longest a membership can be stacked, free-drink vouchers, the VIP guest pass, the gold name tag, the big-spend announcements, and which activities / items are VIP-only. Tiers, prices and perks: Content → Lounge tiers. Zone cards: Content → Place zone actions (zones of type "lounge"). Playlist: Admin → Music.' },
  challenges: { title: 'Challenges', emoji: '🏆', blurb: 'R5 (docs/CHALLENGES.md): the switch, how many daily and weekly challenges each player gets, free rerolls, the cash multiplier (double-cash weekend) and the two bonus chests (cash, career XP, an item). Challenge templates and their stats: Content → Challenge templates / Challenge stats.' },
  yahoo: { title: 'Yahoo life', emoji: '💻', blurb: 'Y1: MiFi and cybercafe desk passes, cybercafe places (the Wi-Fi Joint and HK Quarters), EFCC bail / escape / jail time, lowest caught chance, cash out minimum, status phone hype and the VIP booth rank. R6: the cash-out options (full / half / launder: share, fee, chance multipliers, timer, the Mallam\'s name) and group missions (switch, places, pot bonus per member). Jobs, laptops, ranks and group missions: Content → Yahoo jobs / Laptops (Yahoo) / Yahoo ranks / Group missions. docs/YAHOO.md.' },
  hustles: { title: 'Side hustles', emoji: '💪', blurb: 'E2 (docs/HUSTLES.md): the hustles switch and the lowest energy to start. Pay, cooldown, daily cap, cost and risk per hustle: Content → Hustles / Bolt car classes / Fish.' },
  referral: { title: 'Referral bonus', emoji: '🎁', blurb: 'E2: bonus for the inviter and the new player, the milestone (any one of shifts / hustles / minutes played) and anti-abuse caps. Admin view: Earn.' },
  tips: { title: 'Tips', emoji: '🪙', blurb: 'E2: tip_player() limits. Used by the Tip button on every gist in Benin Gist (docs/GIST.md).' },
  invest: { title: 'Invest & Save', emoji: '💰', blurb: 'I1 (docs/INVEST.md): the Save and Invest tabs in the Bank app. invest.year_days = real days per game year (all yearly rates are per game year). Products and markets: Content → Invest & Save products / Invest markets.' },
  crime: { title: 'Crime & robbery', emoji: '🦹', blurb: 'Street robbery chances, losses and injuries. C1 pickpocketing (crime.steal_*), bail and escape odds (crime.bail_base, crime.escape_*). docs/CRIME.md.' },
  chat: { title: 'Chat', emoji: '💬', blurb: 'Chat switch, rate limits and moderation.' },
  gist: { title: 'Benin Gist', emoji: '🗣️', blurb: 'Benin Gist (docs/GIST.md): the master switch, photos (off by default: Storage), the limits (gist and comment length, posts per hour, comments / likes / group messages per minute, groups per day, the new-account wait), the member cap and how many groups a player can join, whether admins can add only friends, how the For you feed ranks (half-life, like and comment weights), how fast the Discover "most active" score fades, how many reports hide something, how long gists and messages are kept and how long likes and comments are batched into one alert. Reports, bans, the starter groups (rename them) and photo clean-up: the Gist tab.' },
  life: { title: 'Welcome back & new life', emoji: '🔁', blurb: 'The welcome-back screen and whether players may give up their Sim and start over.' },
  payments: { title: 'Payments (Paystack)', emoji: '💳', blurb: 'Real-money top-ups. Packs: Content → Top-up packs. Purchases: Payments. Setup: docs/PAYMENTS.md.' },
  daily: { title: 'Daily reward & gem hunt', emoji: '🎁', blurb: 'D1: the 7-day daily reward and the daily gem hunt. Reward amounts: Content → Daily reward. Finds: Content → Gem finds. docs/DAILY.md.' },
  wardrobe: { title: 'Wardrobe (Benin Boutique)', emoji: '👗', blurb: 'W1: the boutique and outfit slots. Items and brands: Content → Wardrobe items / Wardrobe brands. docs/WARDROBE.md.' },
  leaderboard: { title: 'Leaderboards', emoji: '🏆', blurb: 'The phone Ranks app: Rich list and VIP list tiers.' },
  club: { title: 'Clubs', emoji: '🪩', blurb: 'K1: weekend club prices. Friday and Saturday nights (a night runs until noon the next day) every club price is multiplied by club.weekend_price_mult, except the ids in club.weekend_exempt. Club hours: Content → Places. SP1 custom spray (docs/SPRAY.md): club.spray_min / spray_max / spray_cooldown_s, the tier thresholds club.spray_tier_* (Nice, Big, Huge, Oga, Billionaire, Trillionaire: each tier has its own MC lines in Content → Hype lines, kind spray_<tier>), the quick chips, and VIP spray (club.vip_spray_min, club.vip_hype_bonus_pct, club.vip_spray_chips, booking rules). SP2 Pick the money: club.pick_pct of every spray falls as notes for 5 s (club.pick_seconds), each tap = club.pick_note to cash, anti-cheat caps club.pick_max_taps_per_sec / club.pick_max_per_player, late-tap grace club.pick_grace_s, club.pick_self, the top-picker shout-out club.pick_summary.' },
  vip: { title: 'VIP perks', emoji: '👑', blurb: 'Arrival announcements for the top VIPs.' },
  push: { title: 'Push notifications', emoji: '🔔', blurb: 'P1 (docs/NOTIFICATIONS.md): pings to players\' phones. The first switch turns it all off; each category can be turned off for everyone. Rate limits: one push per chat per window (extra messages bundle as "3 new messages"), a cap per player per hour, and chat pushes are skipped for a player who is active in the game right now.' },
  market: { title: 'Benin Market', emoji: '🏷️', blurb: 'R9 (docs/MARKET.md): player-to-player trading. The master switch, listing limits per day and at once, how long listings and offers last, the lowest offer, report hiding and the thresholds for suspicious trades. Fee and price floor / ceiling per kind: Content -> Market settings. Live listings and trades: Market tab.' },
  business: { title: 'Business', emoji: '🏪', blurb: 'R10 (docs/BUSINESS.md): owning a business. The switch, how many a player can own, how long takings keep growing (48 h), restocking and the income floor with no stock, staff hiring, insurance, the owner shift (length, energy, boost, daily cap), the owner\'s cut of visitor spending, sell-back %, and the event chances per business day (robbery, NEPA outage, council levy, staff theft, great day). Types, prices, levels and per-type events: Content -> Business types. Plots: Content -> Business plots. Who owns what: Business tab.' },
  crews: { title: 'Gangs', emoji: '🤝', blurb: 'R11 (docs/CREWS.md): gangs and gang jobs. The switch, start fee and who may start a gang, rejoin cooldown, invites, the default and allowed bank share of loot, Prospect share, meeting spots, lobby countdown, jobs per day, member bonus, skill cut, jail time, bail and the gang bank fine after a bust, gang chat limits, blocked words / tags and emblems, and the weekly Top gangs prizes. Jobs and levels: Content -> Gang jobs / Gang levels. Gangs list, rename and disband: Gangs tab.' },
  offices: { title: 'Industry offices', emoji: '🏛️', blurb: 'Industry offices (docs/OFFICES.md): the switch, salaries on or off, how long a holder can be away, the hard rails every lever keeps (floor and cap as a share of the baseline), how often a change is announced to everybody, official statements, applications, the approval rating warning, and the medicine price. Offices, salaries and levers: Admin -> Offices.' },
  politics: { title: 'Politics (Benin Votes)', emoji: '🗳️', blurb: 'R12 (docs/POLITICS.md): elections and government. The switch, the next election starting by itself, the registration / campaign / voting windows and the term length (real hours and days), who may vote (account age), the clean-record rule, candidates per race, campaign costs and points (rally, poster, supporters, endorsements, gang endorsements), report limits, salaries on or off, the Governor\'s announcement and ward notice limits, and the blocklists for real parties and politicians. Offices, fees, salaries and requirements: Content -> Offices. Policies: Content -> Policies. Parties and wards: Content. Start / advance / cancel an election, disqualify and see tallies: Elections tab.' },
  company: { title: 'Company', emoji: '🏢', blurb: 'Companies (docs/COMPANIES.md): online companies that need no map plot. The switch, registration fee, how many a player can own, branches and their cost, the evening settle hour (18 = 6 PM Benin), how many uncollected evenings the till holds, the per-player evening sales cap, staff / Manager / generator, the Cheap / Fair / Premium pricing multipliers, how stars follow demand, the random events (good and bad reviews, NEPA outage, supplier problem), company value, the sell-to-system %, and rankings. Industries, areas, formats and marketing prices: Content -> Company industries / areas / formats / marketing. Who owns what: Companies tab.' },
  realbiz: { title: 'Real businesses', emoji: '📍', blurb: 'Real Benin businesses on the map for real money (docs/COMPANIES.md). Needs payments.enabled too. The switch, the listing price (in KOBO: 2500000 = N25,000), how many days a listing runs, live pins per area, listings per player, photos, the renew window, report alerts, the owner contact email and the terms text. The queue (approve, reject with automatic refund, suspend, remove): Real business tab. Map spots: Content -> Real business spots.' },
  economy: { title: 'Economy (money sinks)', emoji: '🏛️', blurb: 'E4 (docs/ECONOMY_SINKS.md): money that leaves the game. Master switches for each sink, the tiered transfer fee + stamp duty + daily soft cap, the weekly income tax bands and the new-player exemption, the weekly bills (house, car, business, land), the late fee and how long before an asset stops working, VAT and the luxury levy (rates, VAT-free and luxury categories), and the prestige sinks (donations, city party, Chief titles, philanthropist badges). The dashboard is the Economy tab; the Governor\'s Tax holiday policy is in Content -> Policies.' },
  admin: { title: 'Admin', emoji: '🛡️', blurb: 'Admin access. Hidden from players.' },
};

/** The knobs the owner touches most, with plain-English help. */
const QUICK: { key: string; hint: string }[] = [
  { key: 'realtime.mode', hint: 'auto = live updates, each player falls back to polling by itself when Realtime is full. poll_only = everyone polls (use during a spike when Realtime is over its plan limit). docs/SCALING.md.' },
  { key: 'push.enabled', hint: 'Push notifications to players. Off = nothing is queued or sent. Category switches and rate limits: Push notifications tab.' },
  { key: 'payments.enabled', hint: 'Real-money top-ups with Paystack. Turn on only after the keys are set (docs/PAYMENTS.md).' },
  { key: 'clock.mode', hint: 'real = the game shows the real time in Benin City. accelerated = the old fast clock.' },
  { key: 'needs.decay_speed', hint: 'How fast needs drop with the real clock. 1 = hunger empties in about 25 real hours (2.5 = about 10).' },
  { key: 'action.mode', hint: 'short = every action takes a few real seconds. game_minutes = the old long timers.' },
  { key: 'action.shift_seconds', hint: 'Real seconds one work shift takes.' },
  { key: 'action.travel_max_seconds', hint: 'No trip takes longer than this (real seconds).' },
  { key: 'action.scale_by_need', hint: 'Actions are shorter when the need is nearly full (sleep is 15 s only when exhausted).' },
  { key: 'sim.walk_speed', hint: 'How fast the Sim walks at home, in metres per second (1.9 = a brisk walk).' },
  { key: 'action.queue_max', hint: 'How many tasks a player can line up at once.' },
  { key: 'origin.nepo_pct', hint: 'Chance a new player is born a Nepo baby.' },
  { key: 'origin.force_next', hint: 'The very next new account gets this origin, then it switches itself off.' },
  { key: 'origin.lapo.start_cash', hint: 'Cash a LAPO baby starts with (the home choice can change it).' },
  { key: 'origin.nepo.start_cash', hint: 'Cash a Nepo baby starts with.' },
  { key: 'origin.nepo.start_bank', hint: 'Money already in a Nepo baby’s bank.' },
  { key: 'origin.nepo.allowance_daily', hint: 'Dad’s allowance per day for Nepo babies.' },
  { key: 'rent.enabled', hint: 'Turn weekly rent on or off for everyone.' },
  { key: 'life.restart_enabled', hint: 'Players can start a new life (new Sim, new origin roll). The old one is archived.' },
  { key: 'club.spray_min', hint: 'The smallest amount a player can spray in a club (cash in hand only).' },
  { key: 'club.vip_hype_bonus_pct', hint: 'VIP sprays (from the VIP section) get this much more hype and the gold VIP takeover.' },
  { key: 'club.weekend_price_mult', hint: 'Friday and Saturday nights every club price (entry, drinks, VIP table, bottles) is multiplied by this. 1 = same price every night.' },
  { key: 'crime.npc_base_pct', hint: 'Base chance of being robbed on a street trip.' },
  { key: 'crime.npc_max_pct', hint: 'Robbery chance never goes above this.' },
  { key: 'shrine.fail_pct', hint: 'Chance a charm from Baba\'s Shrine fails (money and offerings gone).' },
  { key: 'invest.enabled', hint: 'Invest & Save: switch off to stop new deposits and purchases (selling and withdrawing still work).' },
  { key: 'invest.year_days', hint: 'How many REAL days make one game year. Every yearly rate (10%, 18%...) accrues over this time. 30 = a year in a month.' },
  { key: 'hustles.enabled', hint: 'Side hustles (Bolt, PoS, food stall, DJ / MC, tutoring, fishing, mechanic): switch them all on or off.' },
  { key: 'referral.bonus_referrer', hint: 'Cash the inviter gets when their friend reaches the milestone (the new player gets referral.bonus_referred).' },
  { key: 'leaderboard.weekly_prize_1', hint: 'Prize for the top weekly earner, paid when the week closes (2nd and 3rd: weekly_prize_2 / _3).' },
  { key: 'school.enabled', hint: 'School: courses, classes and certificates. Off = no classes, and certificate gates and pay bonuses stop applying.' },
  { key: 'cooking.market_band_pct', hint: 'Cooking: how far Oba Market ingredient prices move each Benin day (+/- this percent). The same for every player.' },
  { key: 'cooking.xp_daily_cap', hint: 'Cooking: the most Cooking XP one player can earn in a Benin day (stops XP farming).' },
  { key: 'kids.enabled', hint: 'Kids: off = no new babies, no care, no alerts; every clock is paused and carries on when you switch it back on.' },
  { key: 'love.enabled', hint: 'Family & love: off = nobody can ask out, flirt or date (couples are kept).' },
  { key: 'lounge.enabled', hint: 'Members\' Lounge: off = nobody can enter or buy a pass (the pin shows closed).' },
  { key: 'friends.online_seconds', hint: 'A friend shows a green dot when they were active in the last this many seconds (Friends tab).' },
  { key: 'challenges.enabled', hint: 'Daily and weekly challenges. Off = nothing new is handed out and claims are refused.' },
  { key: 'skills.enabled', hint: 'Skills: XP, level gates, hustle pay boost and the EFCC cut. Off = none of it.' },
  { key: 'yahoo.enabled', hint: 'Yahoo life: laptop owners can do Yahoo jobs from the phone (home + MiFi, or cybercafe desk).' },
  { key: 'yahoo.bail_base', hint: 'Bail when EFCC catches a Yahoo player (doubles with each failed escape).' },
  { key: 'yahoo.launder_fee_pct', hint: 'Fee the Mallam / bureau de change keeps when a player launders the yahoo balance (the launder chance and timer: yahoo.launder_caught_mult / yahoo.launder_seconds).' },
  { key: 'yahoo.group_enabled', hint: 'Yahoo group missions with friends (missions, rewards and risk: Content → Group missions).' },
  { key: 'crime.steal_enabled', hint: 'Players can pickpocket another player standing near them at a public place.' },
  { key: 'crime.steal_caught_pct', hint: 'Chance a pickpocket is caught (then bail, jail or try to escape).' },
  { key: 'crime.bail_base', hint: 'Bail price after being caught pickpocketing (doubles with each failed escape).' },
  { key: 'career.pay_mult', hint: 'Multiplies every job’s pay. 1 = normal, 1.5 = +50%.' },
  { key: 'career.max_shifts_per_game_day', hint: 'How many shifts a player can work per day (resets at midnight, Benin time).' },
  { key: 'pos.fee_pct', hint: 'PoS cash-out charge.' },
  { key: 'bank.transfer_daily_limit', hint: 'Most a player can send per day.' },
  { key: 'bank.transfer_fee', hint: 'Fee for each phone transfer.' },
  { key: 'chat.enabled', hint: 'Turn location chat on or off for everyone.' },
];

const same = (a: unknown, b: unknown) => JSON.stringify(a) === JSON.stringify(b);

function validate(row: ConfigRow, v: unknown): string | null {
  if (row.kind === 'bool') return typeof v === 'boolean' ? null : 'Pick on or off';
  if (row.kind === 'text') return typeof v === 'string' ? null : 'Must be text';
  if (row.kind === 'json') return v === undefined ? 'Invalid JSON' : null;
  if (v === '' || typeof v !== 'number' || !Number.isFinite(v)) return 'Enter a number';
  if (row.kind === 'naira' && !Number.isInteger(v)) return 'Whole naira only';
  if (row.min !== null && v < row.min) return `At least ${row.min}`;
  if (row.max !== null && v > row.max) return `At most ${row.max}`;
  return null;
}

function ValueControl({ row, value, onChange, tiers }: {
  row: ConfigRow; value: unknown; onChange: (v: unknown) => void; tiers: Row[];
}) {
  const [jsonText, setJsonText] = useState(() => JSON.stringify(row.value, null, 2));
  const CHOICES: Record<string, { id: string; name: string }[]> = {
    'clock.mode': [{ id: 'real', name: 'Real Benin time' }, { id: 'accelerated', name: 'Fast clock (old)' }],
    'action.mode': [{ id: 'short', name: 'Short (seconds)' }, { id: 'game_minutes', name: 'Game minutes (old)' }],
  };
  if (CHOICES[row.key]) {
    return (
      <div className="adm-chips" role="radiogroup" aria-label={row.label}>
        {CHOICES[row.key].map((o) => (
          <button key={o.id} type="button" role="radio" aria-checked={value === o.id}
            className={`adm-chip${value === o.id ? ' is-on' : ''}`} onClick={() => onChange(o.id)}>{o.name}</button>
        ))}
      </div>
    );
  }
  if (row.key === 'origin.force_next') {
    const opts = [{ id: '', name: 'Off (random roll)' }, ...tiers.map((t) => ({ id: String(t.id), name: String(t.name) }))];
    return (
      <div className="adm-chips" role="radiogroup" aria-label={row.label}>
        {opts.map((o) => (
          <button key={o.id || 'off'} type="button" role="radio" aria-checked={value === o.id}
            className={`adm-chip${value === o.id ? ' is-on' : ''}`} onClick={() => onChange(o.id)}>{o.name}</button>
        ))}
      </div>
    );
  }
  switch (row.kind) {
    case 'bool':
      return <Toggle checked={value === true} onChange={onChange} label={row.label} />;
    case 'text':
      return <input className="adm-input" value={String(value ?? '')} onChange={(e) => onChange(e.target.value)} />;
    case 'json':
      return <JsonControl expect="any" value={jsonText} onChange={(t, p, ok) => { setJsonText(t); onChange(ok ? p : undefined); }} />;
    default:
      return <NumberControl kind={row.kind} value={value as number | ''} min={row.min} max={row.max}
        invalid={!!validate(row, value)} onChange={onChange} />;
  }
}

function ConfigItem({ row, draft, setDraft, onSave, onRevert, tiers, hint, card }: {
  row: ConfigRow; draft: unknown; setDraft: (v: unknown | undefined) => void; onSave: () => Promise<void>;
  onRevert: () => Promise<void>; tiers: Row[]; hint?: string; card?: boolean;
}) {
  const value = draft === undefined ? row.value : draft;
  const dirty = draft !== undefined && !same(draft, row.value);
  const err = dirty ? validate(row, value) : null;
  const [busy, setBusy] = useState(false);
  const canRevert = !dirty && row.key !== 'origin.force_next' && row.prev_value !== null && row.prev_value !== undefined && !same(row.prev_value, row.value);
  return (
    <div className={`adm-cfg${card ? ' adm-cfg--card' : ''}${dirty ? ' is-dirty' : ''}`} id={`cfg-${row.key}`}>
      <div className="adm-cfg__text">
        <div className="adm-cfg__label">{row.label || row.key}</div>
        <div className="adm-cfg__desc">{hint ?? row.description}</div>
        <code className="adm-cfg__key">{row.key}</code>
      </div>
      <div className="adm-cfg__control">
        <ValueControl row={row} value={value} tiers={tiers} onChange={(v) => setDraft(same(v, row.value) ? undefined : v)} />
        {err && <div className="adm-field__err">{err}</div>}
        <div className="adm-cfg__meta">
          {dirty ? (
            <>
              <span className="adm-cfg__was">was {fmtValue(row.kind, row.value)}</span>
              <Btn small tone="quiet" onClick={() => setDraft(undefined)}>Undo</Btn>
              <Btn small tone="primary" disabled={!!err || busy}
                onClick={async () => { setBusy(true); try { await onSave(); } finally { setBusy(false); } }}>
                {busy ? 'Saving…' : 'Save'}
              </Btn>
            </>
          ) : (
            <>
              <span className="adm-cfg__stamp">
                {row.updated_by_name ? `Changed ${timeShort(row.updated_at)} by ${row.updated_by_name}` : ''}
              </span>
              {canRevert && (
                <Btn small tone="quiet" disabled={busy} title="Put back the value from before the last change"
                  onClick={async () => { setBusy(true); try { await onRevert(); } finally { setBusy(false); } }}>
                  ↺ Back to {fmtValue(row.kind, row.prev_value)}
                </Btn>
              )}
            </>
          )}
        </div>
      </div>
    </div>
  );
}

/** P1: how the player push outbox is doing (sent / failed in the last 24 hours). */
function PushOutbox() {
  const [st, setSt] = useState<PushStats | null>(null);
  const [err, setErr] = useState('');
  const load = () => { adminApi.pushStats().then((s) => { setSt(s); setErr(''); }).catch((e) => setErr(errorMessage(e))); };
  useEffect(() => {
    load();
    const t = window.setInterval(load, 30_000);
    return () => window.clearInterval(t);
  }, []);
  if (err) return <p className="adm-sub">Push counts: {err}</p>;
  if (!st) return <Skeleton rows={1} />;
  const cats = Object.entries(st.by_category).map(([k, n]) => `${k} ${n}`).join(' · ');
  return (
    <div className="adm-pushbox">
      <div className="adm-stats">
        <div className="adm-stat adm-stat--green"><span className="adm-kicker">Sent (24 h)</span><b className="adm-stat__value">{st.sent_24h}</b><span className="adm-stat__sub">{cats || 'nothing yet'}</span></div>
        <div className={`adm-stat${st.failed_24h ? ' adm-stat--amber' : ''}`}><span className="adm-kicker">Failed (24 h)</span><b className="adm-stat__value">{st.failed_24h}</b><span className="adm-stat__sub">{st.last_error ?? 'no errors'}</span></div>
        <div className="adm-stat"><span className="adm-kicker">Waiting</span><b className="adm-stat__value">{st.pending}</b><span className="adm-stat__sub">{st.oldest_pending_s > 120 ? `oldest due ${Math.round(st.oldest_pending_s / 60)} min ago: is the Cron job running?` : 'queued now'}</span></div>
        <div className="adm-stat"><span className="adm-kicker">Players with a device</span><b className="adm-stat__value">{st.players}</b><span className="adm-stat__sub">{st.devices} devices · skipped (24 h) {st.skipped_24h}</span></div>
      </div>
      <p className="adm-sub">Log kept for {st.keep_days} days: {st.sent_total} sent, {st.failed_total} failed.</p>
    </div>
  );
}

export default function Settings() {
  const { data: rows, setData: setRows, error, loading, reload } = useLoad(() => adminApi.configList());
  const { data: tiers } = useLoad(() => adminApi.tableRows('origin_tiers'));
  const [drafts, setDrafts] = useState<Record<string, unknown>>({});
  const [q, setQ] = useState('');
  const [params] = useSearchParams();
  const [cat, setCat] = useState<string>(params.get('cat') ?? 'quick');
  const [savingAll, setSavingAll] = useState(false);
  const { values: liveValues } = useConfig();

  // Another admin (or the game) changed something: refresh quietly, keep local drafts.
  useEffect(() => {
    if (rows) void adminApi.configList().then(setRows).catch(() => {});
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [liveValues]);

  const byKey = useMemo(() => new Map((rows ?? []).map((r) => [r.key, r])), [rows]);
  const categories = useMemo(() => {
    const m = new Map<string, ConfigRow[]>();
    for (const r of rows ?? []) {
      if (!m.has(r.category)) m.set(r.category, []);
      m.get(r.category)!.push(r);
    }
    const order = Object.keys(CATEGORY_META);
    return [...m.entries()].sort((a, b) => {
      const ia = order.indexOf(a[0]); const ib = order.indexOf(b[0]);
      return (ia < 0 ? 99 : ia) - (ib < 0 ? 99 : ib) || a[0].localeCompare(b[0]);
    });
  }, [rows]);

  const dirtyKeys = Object.keys(drafts).filter((k) => byKey.has(k) && !same(drafts[k], byKey.get(k)!.value));
  const invalid = dirtyKeys.some((k) => validate(byKey.get(k)!, drafts[k]));

  const setDraft = (key: string) => (v: unknown | undefined) =>
    setDrafts((d) => { const n = { ...d }; if (v === undefined) delete n[key]; else n[key] = v; return n; });

  const applySaved = async (keys: string[]) => {
    setDrafts((d) => { const n = { ...d }; keys.forEach((k) => delete n[k]); return n; });
    try { setRows(await adminApi.configList()); } catch { /* keep */ }
  };

  const saveOne = (key: string) => async () => {
    try {
      const r = await adminApi.configSet(key, drafts[key]);
      toast(r.message, 'good');
      await applySaved([key]);
    } catch (e) { toast(errorMessage(e), 'bad'); }
  };
  const revertOne = (row: ConfigRow) => async () => {
    try {
      await adminApi.configSet(row.key, row.prev_value);
      toast(`${row.label || row.key} is back to ${fmtValue(row.kind, row.prev_value)}.`, 'good');
      await applySaved([row.key]);
    } catch (e) { toast(errorMessage(e), 'bad'); }
  };
  const saveAll = async () => {
    setSavingAll(true);
    try {
      const changes: Record<string, unknown> = {};
      dirtyKeys.forEach((k) => { changes[k] = drafts[k]; });
      const r = await adminApi.configSetMany(changes);
      toast(r.message, 'good');
      await applySaved(dirtyKeys);
    } catch (e) { toast(errorMessage(e), 'bad'); } finally { setSavingAll(false); }
  };

  const needle = q.trim().toLowerCase();
  const matches = (r: ConfigRow) => !needle || r.key.toLowerCase().includes(needle) || r.label.toLowerCase().includes(needle)
    || r.description.toLowerCase().includes(needle);

  const item = (r: ConfigRow, hint?: string, card?: boolean) => (
    <ConfigItem key={r.key} row={r} draft={drafts[r.key]} setDraft={setDraft(r.key)} onSave={saveOne(r.key)}
      onRevert={revertOne(r)} tiers={tiers ?? []} hint={hint} card={card} />
  );

  return (
    <div className="adm-page">
      <PageHead title="Settings" sub="Every number in the game. Changes reach all players instantly." />
      {error && <LoadError error={error} onRetry={reload} />}
      {!rows && loading && <Skeleton rows={6} />}
      {rows && (
        <>
          <div className="adm-toolbar">
            <label className="adm-search">
              <span aria-hidden>🔎</span>
              <input type="search" placeholder={`Search ${rows.length} settings…`} value={q} onChange={(e) => setQ(e.target.value)} />
            </label>
          </div>
          {!needle && (
            <nav className="adm-catnav" aria-label="Categories">
              <button type="button" className={`adm-chip${cat === 'quick' ? ' is-on' : ''}`} onClick={() => setCat('quick')}>⭐ Most used</button>
              {categories.map(([c, list]) => (
                <button key={c} type="button" className={`adm-chip${cat === c ? ' is-on' : ''}`} onClick={() => setCat(c)}>
                  {CATEGORY_META[c]?.emoji ?? '⚙️'} {CATEGORY_META[c]?.title ?? c}
                  <span className="adm-chip__n">{list.length}</span>
                  {list.some((r) => dirtyKeys.includes(r.key)) && <span className="adm-dot" aria-label="unsaved" />}
                </button>
              ))}
            </nav>
          )}

          {needle ? (
            <section className="adm-card adm-cfglist">
              {rows.filter(matches).length === 0 && <p className="adm-empty">No setting matches “{q}”.</p>}
              {rows.filter(matches).map((r) => item(r))}
            </section>
          ) : cat === 'quick' ? (
            <section className="adm-quick">
              {QUICK.map((qk) => byKey.get(qk.key)).filter(Boolean).map((r) => item(r!, QUICK.find((x) => x.key === r!.key)!.hint, true))}
            </section>
          ) : (
            categories.filter(([c]) => c === cat).map(([c, list]) => (
              <section key={c} className="adm-card adm-cfglist">
                <div className="adm-cfglist__head">
                  <h2 className="adm-h2">{CATEGORY_META[c]?.emoji} {CATEGORY_META[c]?.title ?? c}</h2>
                  {CATEGORY_META[c] && <p className="adm-sub">{CATEGORY_META[c].blurb}</p>}
                </div>
                {c === 'push' && <PushOutbox />}
                {list.map((r) => item(r))}
              </section>
            ))
          )}

          {dirtyKeys.length > 0 && (
            <div className="adm-savebar" role="status">
              <span><b>{dirtyKeys.length}</b> unsaved {dirtyKeys.length === 1 ? 'change' : 'changes'}</span>
              <Btn tone="quiet" onClick={() => setDrafts({})}>Discard</Btn>
              <Btn tone="primary" disabled={invalid || savingAll} onClick={saveAll}>{savingAll ? 'Saving…' : 'Save all'}</Btn>
            </div>
          )}
        </>
      )}
    </div>
  );
}
