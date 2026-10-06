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
  ageNote: 'For players 18 and over. Benin Life is a game: the money is fake and nothing here is real-world advice.',
  panelMissing: 'Coming soon. This part of the city is still being built.',
};

export type NeedKey = 'hunger' | 'energy' | 'hygiene' | 'fun' | 'social' | 'bladder' | 'health' | 'stress';

export const NEED_KEYS: NeedKey[] = ['hunger', 'energy', 'hygiene', 'fun', 'social', 'bladder', 'health', 'stress'];

/** The six everyday needs shown in the HUD and the Sim sheet (R4). Health and stress live in the sheet. */
export const HUD_NEEDS: NeedKey[] = ['hunger', 'energy', 'fun', 'social', 'hygiene', 'bladder'];

export const NEED_META: Record<NeedKey, { label: string; short: string; icon: string; emoji: string; color: string; inverted?: boolean }> = {
  hunger: { label: 'Hunger', short: 'Hunger', icon: 'food', emoji: '🍲', color: '#f08c2e' },
  energy: { label: 'Energy', short: 'Energy', icon: 'bolt', emoji: '⚡', color: '#2f7fd6' },
  hygiene: { label: 'Hygiene', short: 'Hygiene', icon: 'soap', emoji: '🫧', color: '#14a89a' },
  fun: { label: 'Fun', short: 'Fun', icon: 'party', emoji: '🎉', color: '#e3a612' },
  social: { label: 'Social', short: 'Social', icon: 'chat', emoji: '💬', color: '#e0457b' },
  bladder: { label: 'Bladder', short: 'Bladder', icon: 'drop', emoji: '🚽', color: '#7b61d9' },
  health: { label: 'Health', short: 'Health', icon: 'heart', emoji: '❤️', color: '#e0473a' },
  stress: { label: 'Stress', short: 'Stress', icon: 'stress', emoji: '😤', color: '#8a94a6', inverted: true },
};

/** A nudge for a low need: the wish chip text and what helps (R4; real wishes arrive in Phase 2). */
export const NEED_TIP: Partial<Record<NeedKey, { text: string; emoji: string }>> = {
  hunger: { text: 'Eat something', emoji: '🍲' },
  energy: { text: 'Get some sleep', emoji: '😴' },
  hygiene: { text: 'Take a bath', emoji: '🫧' },
  bladder: { text: 'Use the toilet', emoji: '🚽' },
  fun: { text: 'Do something fun', emoji: '🎉' },
  social: { text: 'Go and see people', emoji: '💬' },
};

export const WEEKDAYS_SHORT = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

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

// ---- Origin (LAPO baby vs Nepo baby): birth lottery reveal + HUD ----
export interface OriginCopy {
  /** Big title on the reveal. */
  title: string;
  /** One-line tagline under the title. */
  line: string;
  /** Emoji on the big reveal tile. */
  emoji: string;
  /** Short HUD badge text. */
  badge: string;
}

export const ORIGIN_COPY: Record<string, OriginCopy> = {
  // Nepo babies are school-trained: polished English, and it's always "Dad".
  nepo: {
    title: 'Nepo Baby!',
    line: "Dad has connections. Just don't embarrass the family name.",
    emoji: '👑',
    badge: 'Nepo',
  },
  // LAPO babies keep a light street voice.
  lapo: {
    title: 'LAPO Baby!',
    line: 'Na hustle go carry you. Small money, big dreams.',
    emoji: '💪',
    badge: 'LAPO',
  },
};

/** Copy for a tier, with a generic fallback for tiers added later as data. */
export function originCopy(id: string, name: string, tagline: string): OriginCopy {
  return (
    ORIGIN_COPY[id] ?? {
      title: `${name}!`,
      line: tagline || 'Life has given you your own start.',
      emoji: '🎲',
      badge: name.split(' ')[0] ?? name,
    }
  );
}

export const ORIGIN_UI = {
  ask: (name: string) => `Everyone in Benin City is born into something. What was ${name} born into?`,
  rolling: 'Rolling the dice of life…',
  skip: 'Tap to skip',
  once: 'Decided once for your account.',
  bank: (amount: string) => `${amount} in the bank from day one`,
  noBank: 'Nothing in the bank yet. Every naira you get, you earn.',
  item: (name: string) => `Your own ${name}, from day one`,
  allowance: (amount: string) => `Dad sends ${amount} allowance every day`,
  headStart: (n: number) => `Career head start: +${n} level${n === 1 ? '' : 's'} at your first job`,
  easyLoan: 'LAPO micro-loans are easy to get when you need a push (coming soon)',
  cashByHome: 'Your starting cash depends on where you choose to live',
  emptyBag: 'Empty bag for now. Your first buy will taste sweet.',
  collectDad: "Collect Dad's allowance",
  dadChip: 'Dad',
};

// ---- Character creator (R3b) ----
export const CREATOR = {
  steps: ['Look', 'Personality', 'Dream', 'Birth lottery', 'Home'] as const,
  next: 'Next',
  continue: 'Continue',
  shuffle: 'Shuffle the look',
  logoutConfirm: 'Log out? Your Sim is not saved until you finish the Dream step.',
  logout: 'Log out',
  nameLabel: "Your Sim's name",
  namePlaceholder: 'your_name',
  nameHelp: '3 to 20 letters, numbers or _. Everyone in Benin City will see it.',
  nameBad: 'Use 3 to 20 letters, numbers or _ (no spaces or symbols).',
  nameTaken: (n: string) => `Someone already has "${n}". Try another name.`,
  body: 'Body',
  presets: 'Outfit presets',
  presetsHint: 'A whole look in one tap. Change any piece after.',
  presetsEdited: 'Edited. Tap the preset again to reset it.',
  edited: 'Edited',
  traitsAsk: (n: number, name: string) => `Choose ${n} traits for ${name}.`,
  traitsSwap: (out: string) => `Swapped out ${out}. You can keep 2.`,
  traitsMore: (n: number) => `Choose ${n} more`,
  dreamAsk: (name: string) => `What's ${name}'s big dream?`,
  dreamPick: 'Pick a dream',
  creating: 'Rolling the dice…',
  chooseHome: 'Choose where to live',
  homeAsk: (name: string, day: string) => `Where will ${name} live? Rent is due every ${day}.`,
  startWith: (amount: string) => `Start with ${amount}`,
  rent: (amount: string) => `Rent ${amount}/wk`,
  pickHome: 'Pick a home',
  moveIn: 'Move in',
  seeLottery: 'See the reveal',
  catalogFailed: "Couldn't load the options. Check your connection.",
  loading: 'Getting things ready…',
};

export const WEEKDAYS = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
