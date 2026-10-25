// The guided tour, as data. docs/ONBOARDING.md explains how to add a step.
//
// RULE: when you add a feature, add a tour step here AND a Help article in helpArticles.ts.
//
// Each step points at a REAL element through a `data-tour="..."` attribute (grep for it in src/ to find the owner).
//   target     CSS selector. A comma list is tried left to right and the first visible element wins.
//              null, or nothing visible after ~1.8 s, shows a centred card with no spotlight.
//   before     optional: get the screen ready (open the phone, switch a tab). Runs every time the step is shown,
//              also when you press Back. Every step should leave the screen the way IT needs it, so most steps start
//              with toGame() / toPhone() / toSim().
//   placement  where the card prefers to sit; the tour flips it when there is no room.
//   isNew      shown again by "What's new" (mark the steps for your newest features, remove the flag later).
import { useUi, type SimTab } from '../state/ui';

export type TourPlacement = 'auto' | 'top' | 'bottom' | 'left' | 'right' | 'center';

export interface TourStep {
  id: string;
  target: string | null;
  title: string;
  body: string;
  /** Extra short lines under the body (each gets a tick). */
  points?: string[];
  placement?: TourPlacement;
  before?: () => void | Promise<void>;
  isNew?: boolean;
}

// ---- screen helpers for before() ---------------------------------------------------------------------------------
const ui = () => useUi.getState();
/** Back to the plain game screen: every sheet, panel and the phone closed. */
export const toGame = () => ui().closeAll();
/** Phone open on the app grid (or on an app id such as 'hustles'). */
export const toPhone = (app = 'home') => ui().openPhone(app);
/** The Sim sheet on a tab. */
export const toSim = (tab: SimTab) => ui().openSim(tab);

export const TOUR_STEPS: TourStep[] = [
  {
    id: 'welcome',
    target: null,
    title: 'Welcome to Benin Life',
    body: 'Na your city now. This quick tour takes about a minute and shows you where everything is. Tap Next, or skip any time.',
    before: toGame,
  },
  {
    id: 'needs',
    target: '[data-tour="needs"]',
    title: 'Your needs',
    body: 'These bars are your Sim’s mood: hunger, energy, fun, social, hygiene and toilet. Tap them for the full picture.',
    points: [
      'Hungry? Eat at home, from your Bag, or order on Chowdeck.',
      'Tired? Sleep in your bed. Toilet? Use the bathroom.',
      'Bored? Have fun: TV, games, friends, a night out.',
    ],
    placement: 'top',
    before: toGame,
  },
  {
    id: 'money',
    target: '[data-tour="cash"]',
    title: 'Cash, bank and top-up',
    body: 'Cash is in your pocket. Bank money is safe from street thieves. Tap the green + to open your wallet.',
    points: [
      'Move money between cash and bank at Bronze Bank, a PoS stand or the Bank app.',
      'Top-ups are paid securely with Paystack when they are switched on.',
    ],
    placement: 'bottom',
    before: toGame,
  },
  {
    id: 'place',
    target: '[data-tour="place-acts"], [data-tour="place-card"], [data-tour="home-things"]',
    title: 'Things to do',
    body: 'Every place has activity cards. Tap a card and it joins your queue: your Sim walks over, then does it.',
    points: [
      'Cards show the time, the cost and what you get.',
      'Closed? The card tells you when it opens.',
      'The pill at the top left shows what is running.',
    ],
    placement: 'top',
    before: toGame,
  },
  {
    id: 'chat',
    target: '[data-tour="place-say"], [data-tour="place-say-box"]',
    title: 'Chat with people nearby',
    body: 'In any place, tap the chat bubble to say something to everyone there. Tap People to see who is around and add friends.',
    points: ['Be nice. You can report or block anyone from the chat.'],
    placement: 'bottom',
    before: toGame,
  },
  {
    id: 'map',
    target: '[data-tour="dock-map"]',
    title: 'The Map',
    body: 'Tap Map, pick a place, then choose how to go: walk, keke or Bolt. Each shows the price, the time and the risk.',
    points: [
      'Places have opening hours. Closed ones show when they open.',
      'Clubs only open at night.',
    ],
    placement: 'top',
    before: toGame,
  },
  {
    id: 'home',
    target: '[data-tour="dock-home"]',
    title: 'Home',
    body: 'Tap Home to go back to your place any time. It is where you rest and recharge.',
    points: [
      'Tap your bed to sleep, the kitchen to cook, the bathroom to freshen up.',
      'Arrange furniture from Buy, then Arrange.',
    ],
    placement: 'top',
    before: toGame,
  },
  {
    id: 'buy',
    target: '[data-tour="dock-buy"]',
    title: 'Buy',
    body: 'Furniture for your home lives here, with your Bag and food. Cars are in the Cars app, and clothes in the Boutique app.',
    points: ['Prices can change, so check the app for the latest.'],
    placement: 'top',
    before: toGame,
  },
  {
    id: 'phone',
    target: '[data-tour="app-messages"]',
    title: 'Your phone: Messages & Friends',
    body: 'Messages is where you add friends, chat in private and invite them home. The rest of your phone is full of apps.',
    points: [
      'Bank & Invest, Jobs, Hustles, School, Yahoo, Ranks.',
      'Houses, Cars, Chowdeck for food, and Help.',
    ],
    before: () => toPhone('home'),
  },
  {
    id: 'bank',
    target: '[data-tour="app-bank"]',
    title: 'Bank & Invest',
    body: 'Send money to a friend, see your history, save and invest. Bank money cannot be stolen on the street.',
    points: ['Transfers have a small fee and daily limits, and new accounts wait a while before sending.'],
    before: () => toPhone('home'),
  },
  {
    id: 'jobs',
    target: '[data-tour="app-jobs"]',
    title: 'Jobs and careers',
    body: 'Pick a job, start at the bottom and work shifts. You are paid at the end of each shift, and good shifts get you promoted.',
    points: ['Higher levels can ask for a certificate. Get them at School.'],
    before: () => toPhone('home'),
  },
  {
    id: 'hustles',
    target: '[data-tour="app-hustles"]',
    title: 'Hustles',
    body: 'Side money: drive Bolt, be a PoS agent, sell food, go fishing, DJ a club. Each one has a cost, a wait and a daily limit.',
    points: [
      'School gives certificates that boost your pay.',
      'Yahoo pays big but EFCC can catch you. Be careful.',
    ],
    isNew: true,
    before: () => toPhone('home'),
  },
  {
    id: 'skills',
    target: '[data-tour="sim-tab-skills"]',
    title: 'Skills',
    body: 'Hustles, jobs, classes and activities train your skills. Higher levels open better jobs and raise your pay.',
    points: ['Open your Sim, then the Skills tab, to see your levels and where to train.'],
    placement: 'bottom',
    isNew: true,
    before: () => toSim('skills'),
  },
  {
    id: 'today',
    target: '[data-tour="today"]',
    title: 'Today and Challenges',
    body: 'The Today pill gathers your tips and daily rewards. Open it to see your Challenges.',
    points: [
      'Three daily and three weekly goals pay cash and prizes.',
      'A red dot means something is ready to collect.',
    ],
    placement: 'bottom',
    isNew: true,
    before: toGame,
  },
  {
    id: 'nightlife',
    target: null,
    title: 'Clubs at night, the Lounge by day',
    body: 'Clubs open at night, around 9 or 10 PM until 5 AM. Each club shows its hours.',
    points: [
      'Spray money: you choose the amount, the MC hypes you up.',
      'In the day, The Lounge in GRA is open with a pass: drinks, pool and good company.',
    ],
    isNew: true,
    before: toGame,
  },
  {
    id: 'business',
    target: '[data-tour="app-business"]',
    title: 'Business: four tabs',
    body: 'One app for everything you own. My companies: start an online company with no plot. Map plots: shops, bukas and bars on the map. Discover: every company, plus Rankings. Real business: put your real shop on the map.',
    points: [
      'A company settles every evening at 6 PM into your till, so cash out often.',
      'Discover shows real Benin businesses marked Verified.',
      'A real shop in Benin? List it for 30 days from the Real business tab.',
    ],
    isNew: true,
    before: () => toPhone('home'),
  },
  {
    id: 'houses',
    target: '[data-tour="app-houses"]',
    title: 'Upgrade the home you have',
    body: 'No need to move to get more space. Open Houses to add a room, a garage, power, water, a wall and gate, a fresh finish, or even turn your room into a bigger home at the same address.',
    points: [
      'Builders work for real minutes. A scaffold shows on your house until they finish.',
      'Furniture stays where it is. Fill the new space from Buy.',
    ],
    isNew: true,
    before: () => toPhone('home'),
  },
  {
    id: 'crew',
    target: '[data-tour="app-crew"]',
    title: 'Start a gang',
    body: 'Start a gang with your own name, tag and emblem, invite friends, and pull group jobs together from the Gang app. Big loot, but the police can catch the whole gang.',
    points: [
      'Your gang tag shows next to your name: [TAG] @you.',
      'Jobs run at a meeting spot. Check the app for the places and the prices.',
    ],
    isNew: true,
    before: () => toPhone('home'),
  },
  {
    id: 'politics',
    target: '[data-tour="app-politics"]',
    title: 'Run for office, or vote',
    body: 'Benin Votes is the city election. Declare for Councillor, Chairman or Governor, campaign with rallies and posters, and vote at your ward polling unit on voting day. All parties are made up.',
    points: [
      'Winners get a title next to their name (Hon., Gov.), a daily salary and small powers.',
      'Polling units open on voting day only. Check the app for the dates and the fees.',
      'Vote buying is not allowed: there is a report button.',
    ],
    isNew: true,
    before: () => toPhone('home'),
  },
  {
    id: 'family',
    target: '[data-tour="app-family"]',
    title: 'Family: ask somebody out',
    body: 'Open to link-ups? Other players can ask you out, and you can ask them. Say yes, send flirts from a menu, go on dates together, and become a couple.',
    points: [
      'Only players who switch on "Open to link-ups" can see or ask each other.',
      'Flirts and dates cost a little money and build your level together.',
      'You can break up or report anytime. Check the app for the current rules.',
    ],
    isNew: true,
    before: () => toPhone('home'),
  },
  {
    id: 'help',
    target: '[data-tour="app-help"]',
    title: 'Help is on your phone',
    body: 'Stuck? Open the Help app. Search any topic, read a short guide and tap Show me. You can replay this tour from Help or Settings.',
    isNew: true,
    before: () => toPhone('home'),
  },
];

/** The steps flagged for "What's new". */
export const NEW_STEP_IDS = TOUR_STEPS.filter((s) => s.isNew).map((s) => s.id);

export function stepsById(ids: string[]): TourStep[] {
  const out: TourStep[] = [];
  for (const id of ids) {
    const s = TOUR_STEPS.find((x) => x.id === id);
    if (s) out.push(s);
  }
  return out;
}
