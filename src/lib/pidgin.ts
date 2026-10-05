// Shared Naija Pidgin copy — P1-SHELL. Keep it playful, street-smart, never graphic.

export const GREETINGS = [
  'How far',
  'Wetin dey sup',
  'My guy',
  'Oya na',
  'Odogwu',
  'Chairman',
  'Boss',
  'How body',
  'Correct person',
  'Big man',
];

export const TIPS = [
  'Bank money no fit get robbed — only cash for pocket dey vulnerable.',
  'Night for Upper Sakponba and Third East Circular? Omo, think twice.',
  'Ramat Park traffic fit hold you tire. Plan your waka.',
  'Keke no dey enter major road — na side roads dem dey run.',
  'ECTS bus cheap and e safe pass trekking.',
  'If belle empty, everything go dey hard. Chop something.',
  'Babalawo protection fit reduce robbery chance… if you believe.',
  'People dey rush house before 8pm for Benin. Na sense.',
  'PoS dey everywhere, but dem go collect their own cut.',
  'New players get small protection at first — use am well.',
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
  loading: 'Hold on small…',
  loadingGame: 'We dey load Benin for you…',
  retry: 'Try again',
  close: 'Close',
  cancel: 'Leave am',
  confirm: 'Oya, do am',
  back: 'Back',
  next: 'Next',
  done: 'E don do',
  networkDown: 'Network don cut. Check your data and try again.',
  somethingWrong: 'Wahala dey somewhere. Try again small time.',
  emptyHere: 'Nothing dey here for now.',
  noPeople: 'Nobody dey here now — na only you and mosquito.',
  goThere: 'Go there',
  youDeyHere: 'You dey here',
  onTheRoad: 'You dey road',
  busy: 'You dey busy',
  jailed: 'You dey cell',
  hospital: 'You dey hospital',
  protected: 'New player protection',
  logout: 'Comot (Log out)',
  sixteenPlus: '16+ only. Na game — fake money, real wahala. Nothing for here be real crime advice.',
  panelMissing: 'This one never ready. Dem still dey build am.',
};

export type NeedKey = 'hunger' | 'energy' | 'hygiene' | 'fun' | 'social' | 'health' | 'stress';

export const NEED_KEYS: NeedKey[] = ['hunger', 'energy', 'hygiene', 'fun', 'social', 'health', 'stress'];

export const NEED_META: Record<NeedKey, { label: string; short: string; icon: string; inverted?: boolean }> = {
  hunger: { label: 'Belle (Food)', short: 'Belle', icon: 'food' },
  energy: { label: 'Energy', short: 'Power', icon: 'bolt' },
  hygiene: { label: 'Body clean', short: 'Clean', icon: 'soap' },
  fun: { label: 'Enjoyment', short: 'Enjoy', icon: 'party' },
  social: { label: 'Paddy dem', short: 'Social', icon: 'chat' },
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
  if (p < 0.3) return { label: 'Shine your eye', tone: 'warn' };
  if (p < 0.5) return { label: 'Risky', tone: 'bad' };
  return { label: 'Danger zone', tone: 'bad' };
}

export const MODE_META: Record<string, { label: string; blurb: string }> = {
  walk: { label: 'Trek', blurb: 'Free, but leg go pain you' },
  keke: { label: 'Keke', blurb: 'Side roads only' },
  bus: { label: 'ECTS Bus', blurb: 'Green bus, cheap & steady' },
  drop: { label: 'Drop', blurb: 'Ride-hail, quick & safer' },
  car: { label: 'Your Motor', blurb: 'Fuel money only' },
};

/** Map Supabase auth errors to friendly Pidgin. */
export function authErrorPidgin(raw: string): string {
  const m = raw.toLowerCase();
  if (m.includes('invalid login')) return 'Email or password no correct. Check am well.';
  if (m.includes('already registered') || m.includes('already been registered') || m.includes('already exists'))
    return 'This email don get account already — login instead.';
  if (m.includes('password') && (m.includes('6') || m.includes('short') || m.includes('weak')))
    return 'Password too short, my guy. Make am reach 6 characters at least.';
  if (m.includes('email') && (m.includes('invalid') || m.includes('valid')))
    return 'That email no look correct. Check am again.';
  if (m.includes('not confirmed')) return 'Confirm your email first — check your inbox.';
  if (m.includes('rate') || m.includes('too many')) return 'You don try too many times. Rest small, then try again.';
  if (m.includes('fetch') || m.includes('network')) return P.networkDown;
  if (m.includes('signup') && m.includes('disabled')) return 'Sign up close for now. Try again later.';
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
  nepo: {
    kicker: 'Omo! You be…',
    title: 'Nepo baby',
    line: 'Papa get connection. You don land for {home} with motor for compound and laptop for table.',
    cheer: 'Enjoy am, but abeg no spoil the family name o.',
    badge: 'Nepo',
  },
  lapo: {
    kicker: 'You be…',
    title: 'LAPO baby',
    line: 'Na hustle go carry you. {home}, small money for pocket, and big dream for head.',
    cheer: 'Plenty big men for Benin start from one room. Your own story go sweet pass.',
    badge: 'LAPO',
  },
};

/** Copy for a tier, with a generic fallback for tiers added later as data. */
export function originCopy(id: string, name: string, tagline: string): OriginCopy {
  return (
    ORIGIN_COPY[id] ?? {
      kicker: 'You be…',
      title: name,
      line: tagline || 'Life don give you your own start for {home}.',
      cheer: 'Oya, show Benin wetin you carry.',
      badge: name.split(' ')[0] ?? name,
    }
  );
}

export const ORIGIN_UI = {
  rolling: 'Life dey roll the dice…',
  skip: 'Tap to skip',
  enter: 'Oya enter Benin',
  cash: 'For pocket',
  bank: 'For bank',
  allowance: 'Papa allowance',
  perDay: '/ day',
  headStart: 'Career head start',
  levels: (n: number) => `+${n} level${n === 1 ? '' : 's'}`,
  easyLoan: 'LAPO loan',
  easyLoanValue: 'Easy access (soon)',
  emptyBag: 'Bag',
  emptyBagValue: 'Na your hustle go fill am',
  home: 'Your house',
  collectPapa: 'Collect Papa money',
  papaChip: 'Papa',
};
