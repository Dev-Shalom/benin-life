// P1: where a tapped notification goes (docs/NOTIFICATIONS.md). The server writes links like /play?go=dm:12.
//   go=dm:<conversation id>  that DM          go=house        the house chat       go=friends   friend requests / invites
//   go=bank                  the Bank app     go=alerts       the Alerts app       go=ranks     the Ranks app
//   go=hustles               Hustles app      go=place:<id>   a place on the map
//   go=yahoo                 the Yahoo app (a group mission invite)
//   go=market                the Benin Market app (an offer, a sale)
//   go=business              the Business app on its Map plots tab (takings ready); go=company opens My companies (go=business:discover / :real pick a tab)
//   go=crew / go=gang        the Gang app (an invite, a job lobby); gang is an alias, the app id stays crew
//   go=politics              the Benin Votes app (registration, voting day, results); go=politics:vote opens the Vote tab
//   go=family                the Family app (Link-ups); go=family:us / go=family:family open that tab (asks, flirts, dates, a new couple)
//   go=gist                  Benin Gist (the old Messages app); go=gist:post:<id> opens that gist, go=gist:group:<id> that group chat,
//                            go=gist:feed|groups|chats|friends a tab. Old go=dm:, go=house and go=friends links keep working.
//   go=food                  the Chowdeck app; go=food:kitchen / go=food:prices open the Kitchen and today's grocery prices
//   go=help                  the Help app          go=help:<article id>  that article (src/onboarding/helpArticles.ts)
// Cold start: main.tsx captures ?go= (it survives the login redirect in sessionStorage) and the game runs it once the
// Sim is ready. Game already open: the service worker posts { type: 'bl-go', go } and the same code runs.
import { useUi } from '../state/ui';

const KEY = 'bl.go';
const SAFE = /^(dm:\d{1,12}|house|friends|gist(?::(?:feed|groups|chats|friends|post:\d{1,12}|group:\d{1,12}))?|bank|alerts|ranks|hustles|school|yahoo|market|business(?::(?:mine|plots|discover|real))?|company(?::(?:plots|discover|real))?|crew|gang|politics(?::(?:gov|elect|vote|results))?|family(?::(?:linkups|us|family))?|food(?::(?:kitchen|prices))?|help(?::[a-z0-9-]{1,40})?|place:[a-z0-9_]{1,40})$/;

/** Remember ?go= from the address bar and clean the URL. Call once at startup. */
export function captureDeepLink(): void {
  try {
    const u = new URL(window.location.href);
    const go = u.searchParams.get('go');
    if (!go) return;
    if (SAFE.test(go)) sessionStorage.setItem(KEY, go);
    u.searchParams.delete('go');
    window.history.replaceState(null, '', u.pathname + u.search + u.hash);
  } catch {
    /* storage blocked: the notification still opens the game */
  }
}

/** The pending deep link (and forget it). */
export function takeDeepLink(): string | null {
  try {
    const go = sessionStorage.getItem(KEY);
    sessionStorage.removeItem(KEY);
    return go && SAFE.test(go) ? go : null;
  } catch {
    return null;
  }
}

/** Open the right screen. Unknown links are ignored. */
export function runDeepLink(go: string): void {
  if (!SAFE.test(go)) return;
  const ui = useUi.getState();
  const i = go.indexOf(':');
  const kind = i < 0 ? go : go.slice(0, i);
  const arg = i < 0 ? '' : go.slice(i + 1);
  ui.closeAll();
  if (kind === 'dm') ui.openPhone(`messages:dm:${arg}`);
  else if (kind === 'house') ui.openPhone('messages:house');
  else if (kind === 'friends') ui.openPhone('messages:requests');
  else if (kind === 'place') {
    ui.setMapOpen(true);
    ui.select(arg);
  } else if (kind === 'help' || kind === 'food' || kind === 'politics' || kind === 'family' || kind === 'business' || kind === 'company') ui.openPhone(go); // 'help:<article id>', 'politics:vote', 'business:discover', 'family:us'
  else if (kind === 'gist') ui.openPhone(go); // 'gist', 'gist:post:12', 'gist:group:3'
  else if (kind === 'gang') ui.openPhone('crew'); // alias of go=crew
  else ui.openPhone(kind); // bank, alerts, ranks, hustles are phone apps
}
