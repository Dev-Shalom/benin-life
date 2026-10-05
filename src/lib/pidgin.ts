// Shared Naija Pidgin copy — P1-SHELL. Keep it playful, street-smart, never graphic.

// Shared game copy (P1-SHELL, rewritten in R1).
// Tone: clear, warm English by default. Pidgin only where a real Benin person would use it:
// street moments (agberos, robbery, market banter) and the LAPO-baby voice. Nepo babies are
// school-trained and say "Dad". Never parody, never graphic. The file name is historical.

export const GREETINGS = [
  'Welcome back',
  'Good to see you',
  'How far',
  'Welcome home',
  'Hey',
];

export const TIPS = [
  'Money in the bank is safe. Only the cash in your pocket can be stolen.',
  'Upper Sakponba and Third East Circular get risky at night. Think twice.',
  'The Ramat Park go-slow can eat your whole afternoon. Plan your trip.',
  'Keke only run on side roads, never on the major roads.',
  'The ECTS bus is cheap, and safer than walking.',
  'Everything is harder on an empty stomach. Eat something first.',
  "A babalawo's protection might lower your robbery risk... if you believe.",
  'Benin people head home before 8pm. There is a reason.',
  'There is a PoS on every corner, but every one of them takes a cut.',
  'New players get a short protection window. Use it well.',
];

export function pick<T>(arr: readonly T[]): T {
  return arr[Math.floor(Math.random() * arr.length)];
}

export function randomGreeting(name?: string): string {
  const g = pick(GREETINGS);
  return name ? `${g}, ${name}!` : `${g}!`;
}

export function randomTip(): string {
  return pick(TIPS);
}

export const P = {
  loading: 'Loading…',
  loadingGame: 'Loading Benin City…',
  retry: 'Try again',
  close: 'Close',
  cancel: 'Cancel',
  confirm: 'Confirm',
  back: 'Back',
  next: 'Next',
  done: 'Done',
  networkDown: 'Network problem. Check your connection and try again.',
  somethingWrong: 'Something went wrong. Please try again.',
  emptyHere: 'Nothing here yet.',
  noPeople: 'Nobody else is here right now. Just you and the mosquitoes.',
  goThere: 'Go there',
  youAreHere: "You're here",
  onTheRoad: "You're on the road",
  busy: "You're busy",
  jailed: "You're in a police cell",
  hospital: "You're in hospital",
  protected: 'New player protection',
  logout: 'Log out',
  ageNote: '18+ only. Benin Life is a game: the money is fake and nothing here is real-world advice.',
  panelMissing: 'Coming soon. This part of the city is still being built.',
};

export type NeedKey = 'hunger' | 'energy' | 'hygiene' | 'fun' | 'social' | 'health' | 'stress';

export const NEED_KEYS: NeedKey[] = ['hunger', 'energy', 'hygiene', 'fun', 'social', 'health', 'stress'];

export const NEED_META: Record<NeedKey, { label: string; short: string; icon: string; inverted?: boolean }> = {
  hunger: { label: 'Hunger', short: 'Hunger', icon: 'food' },
  energy: { label: 'Energy', short: 'Energy', icon: 'bolt' },
  hygiene: { label: 'Hygiene', short: 'Hygiene', icon: 'soap' },
  fun: { label: 'Fun', short: 'Fun', icon: 'party' },
  social: { label: 'Social', short: 'Social', icon: 'chat' },
  health: { label: 'Health', short: 'Health', icon: 'heart' },
  stress: { label: 'Stress', short: 'Stress', icon: 'stress', inverted: true },
};

/** How a need feels at value v (0–100). */
export function needMood(key: NeedKey, v: number): 'good' | 'warn' | 'bad' {
  const score = NEED_META[key].inverted ? 100 - v : v;
  if (score >= 55) return 'good';
  if (score >= 25) return 'warn';
  return 'bad';
}

/** Risk 0–1 → label. */
export function riskLabel(p: number): { label: string; tone: 'good' | 'warn' | 'bad' } {
  if (p < 0.15) return { label: 'Calm', tone: 'good' };
  if (p < 0.3) return { label: 'Stay alert', tone: 'warn' };
  if (p < 1.4) return { label: 'Risky', tone: 'bad' };
  // Same threshold as the map's night danger glow (isNightRisky).
  return { label: 'Danger zone', tone: 'bad' };
}

export const MODE_META: Record<string, { label: string; blurb: string }> = {
  walk: { label: 'Walk', blurb: 'Free, but slow' },
  keke: { label: 'Keke', blurb: 'Side roads only' },
  bus: { label: 'ECTS bus', blurb: 'Cheap and steady' },
  drop: { label: 'Drop', blurb: 'Ride-hail, quick and safer' },
  car: { label: 'Your car', blurb: 'Just fuel money' },
};

/** Map Supabase auth errors to friendly English. */
export function authErrorMessage(raw: string): string {
  const m = raw.toLowerCase();
  if (m.includes('invalid login')) return "That email and password don't match. Check them and try again.";
  if (m.includes('already registered') || m.includes('already been registered') || m.includes('already exists'))
    return 'There is already an account with this email. Log in instead.';
  if (m.includes('same') && m.includes('password')) return 'Pick a password you have not used before.';
  if (m.includes('password') && (m.includes('6') || m.includes('short') || m.includes('weak')))
    return 'Your password needs at least 6 characters.';
  if (m.includes('email') && (m.includes('invalid') || m.includes('valid')))
    return "That email doesn't look right. Check it and try again.";
  if (m.includes('not confirmed')) return 'Confirm your email first. Check your inbox for the link.';
  if (m.includes('rate') || m.includes('too many') || m.includes('security purposes'))
    return 'Too many attempts. Wait a minute, then try again.';
  if (m.includes('fetch') || m.includes('network')) return P.networkDown;
  if (m.includes('signup') && m.includes('disabled')) return 'Sign-ups are closed right now. Please try again later.';
  return P.somethingWrong;
}

// ---- Origin (LAPO baby vs Nepo baby) — reveal screen + HUD ----
export interface OriginCopy {
  /** Small line above the title. */
  kicker: string;
  /** Big title. */
  title: string;
  /** Line under the title; `{home}` is replaced with the home location name. */
  line: string;
  /** Warm closing line. */
  cheer: string;
  /** Short HUD badge text. */
  badge: string;
}

export const ORIGIN_COPY: Record<string, OriginCopy> = {
  // Nepo babies are school-trained: polished English, and it's always "Dad".
  nepo: {
    kicker: 'You were born a',
    title: 'Nepo baby',
    line: "Dad has connections. You're starting out in {home}, with a car in the compound and a laptop on the desk.",
    cheer: "Enjoy it. Just don't embarrass the family name.",
    badge: 'Nepo',
  },
  // LAPO babies keep a street voice, used lightly.
  lapo: {
    kicker: 'You were born a',
    title: 'LAPO baby',
    line: "Na hustle go carry you. You're starting out in {home}, with small money and a big dream.",
    cheer: 'Plenty big men for Benin started from one room. Your story starts here.',
    badge: 'LAPO',
  },
};

/** Copy for a tier, with a generic fallback for tiers added later as data. */
export function originCopy(id: string, name: string, tagline: string): OriginCopy {
  return (
    ORIGIN_COPY[id] ?? {
      kicker: 'You were born',
      title: name,
      line: tagline || 'Life has given you your own start in {home}.',
      cheer: 'Go show Benin City what you can do.',
      badge: name.split(' ')[0] ?? name,
    }
  );
}

export const ORIGIN_UI = {
  rolling: 'Rolling the dice of life…',
  skip: 'Tap to skip',
  enter: 'Enter Benin City',
  cash: 'Cash',
  bank: 'In the bank',
  allowance: "Dad's allowance",
  perDay: '/ day',
  headStart: 'Career head start',
  levels: (n: number) => `+${n} level${n === 1 ? '' : 's'}`,
  easyLoan: 'LAPO loan',
  easyLoanValue: 'Easy access (soon)',
  emptyBag: 'Bag',
  emptyBagValue: 'Empty for now',
  owned: 'Yours',
  home: 'Your home',
  collectDad: "Collect Dad's allowance",
  dadChip: 'Dad',
};
