// The phone (R4): lock screen with the game clock -> app grid of fictional Benin apps.
// Built: Ride (destination list -> the existing travel picker), Jobs (V1-3), ChopNow + Houses (V1-4, lazy),
// Wallet, Alerts, Bank balances, Settings (Sim sheet). Everything else opens a "Coming soon" screen.
// Esc closes the phone.
import { lazy, Suspense, useMemo, useRef, useState } from 'react';
import { createPortal } from 'react-dom';
import { clockTime, naira, districtName } from '../../lib/format';
import { WEEKDAYS } from '../../lib/pidgin';
import type { GameClock, GameState, Location } from '../../lib/types';
import { useGame } from '../../state/game';
import { useUi } from '../../state/ui';
import { Button, Icon, usePresence } from '../../ui';
import { useEscape } from '../../ui/presence';
import { weekdayOf } from '../../lib/clock';
import { AlertsList } from './Overlays';
import { nearestWorkplace } from '../../api/careers';
import { JobCard, PerfBar, Promotion, QuitButton, ShiftStats, TrackList } from '../../panels/careers/CareerUI';
import { useCareerActions, useJobsCatalog } from '../../panels/careers/careerHooks';

const FoodApp = lazy(() => import('./phone/FoodApp'));
const HousesApp = lazy(() => import('./phone/HousesApp'));

interface App {
  id: string;
  name: string;
  emoji: string;
  bg: string;
  /** What it will do (coming-soon screen). */
  pitch: string;
}

const APPS: App[] = [
  { id: 'jobs', name: 'Jobs', emoji: '💼', bg: 'linear-gradient(160deg,#34c77f,#0e874e)', pitch: 'Find work across Benin City: shop hands, PoS agents, nurses, tech interns and more.' },
  { id: 'messages', name: 'Messages', emoji: '💬', bg: 'linear-gradient(160deg,#5aa8ff,#2f6fd6)', pitch: 'Chat with friends, neighbours and the people you meet around town.' },
  { id: 'bank', name: 'Bank', emoji: '🏦', bg: 'linear-gradient(160deg,#9b8cff,#5b4fd6)', pitch: '' },
  { id: 'contacts', name: 'Contacts', emoji: '📇', bg: 'linear-gradient(160deg,#4fd28a,#1f9a57)', pitch: 'Everyone you know, with how close you are.' },
  { id: 'ride', name: 'KekeGo', emoji: '🛺', bg: 'linear-gradient(160deg,#ffd45c,#f0a316)', pitch: '' },
  { id: 'food', name: 'ChopNow', emoji: '🍲', bg: 'linear-gradient(160deg,#ff8a6b,#e2452c)', pitch: 'Order rice, swallow and small chops to your door, from bukas all over Benin.' },
  { id: 'houses', name: 'Houses', emoji: '🔑', bg: 'linear-gradient(160deg,#f2a65a,#c96a1f)', pitch: 'Rent a bigger place, from a self-contain in Uselu to a duplex in GRA.' },
  { id: 'cars', name: 'Cars', emoji: '🚗', bg: 'linear-gradient(160deg,#4aa3ff,#1f62c9)', pitch: 'Buy a tokunbo or a brand-new ride. Fuel money not included.' },
  { id: 'health', name: 'Health', emoji: '💊', bg: 'linear-gradient(160deg,#ff7aa2,#e0457b)', pitch: 'Book a clinic visit, buy drugs and keep an eye on your health.' },
  { id: 'invest', name: 'Invest', emoji: '📈', bg: 'linear-gradient(160deg,#3fd0b5,#0f8f7a)', pitch: 'Grow your money slowly with savings and investments.' },
  { id: 'bet', name: 'EdoBet', emoji: '⚽', bg: 'linear-gradient(160deg,#2b2f3a,#11141b)', pitch: 'Football predictions with fake game money. 18+ only, and the house usually wins.' },
  { id: 'family', name: 'Family', emoji: '👪', bg: 'linear-gradient(160deg,#ffb36b,#f07b2a)', pitch: 'Partners, children and family meetings. Your village people will call.' },
  { id: 'hustle', name: 'Hustle', emoji: '🧰', bg: 'linear-gradient(160deg,#a3b86a,#5f7a2a)', pitch: 'Side gigs and quick jobs for when the month is long.' },
  { id: 'gov', name: 'Edo Gov', emoji: '🏛️', bg: 'linear-gradient(160deg,#2fa36b,#13603c)', pitch: 'Pay levies, register a business and follow city news.' },
  { id: 'police', name: 'Police', emoji: '🚓', bg: 'linear-gradient(160deg,#4f6bd8,#26388f)', pitch: 'Report a robbery, check your case file and pay bail.' },
  { id: 'wallet', name: 'Wallet', emoji: '👛', bg: 'linear-gradient(160deg,#34c77f,#0a6f40)', pitch: '' },
  { id: 'alerts', name: 'Alerts', emoji: '🔔', bg: 'linear-gradient(160deg,#ff9d5c,#e2552c)', pitch: '' },
  { id: 'settings', name: 'Settings', emoji: '⚙️', bg: 'linear-gradient(160deg,#a9b2bf,#6b7686)', pitch: '' },
];

function useKm(state: GameState, locations: Location[]) {
  return useMemo(() => {
    const here = locations.find((l) => l.id === state.location.id) ?? state.location;
    return locations
      .filter((l) => l.id !== here.id)
      .map((l) => ({ l, km: (Math.hypot(l.x - here.x, l.y - here.y) / 1000) * 18 + (l.remote_km || 0) }))
      .sort((a, b) => a.km - b.km);
  }, [state.location, locations]);
}

function StatusBar({ clock }: { clock: GameClock }) {
  return (
    <div className="phone__status">
      <span>{clockTime(clock.hour, clock.minute)}</span>
      <span className="phone__notch" aria-hidden />
      <span className="phone__signal">
        <span aria-hidden>▂▄▆</span> 4G
        <span className="phone__battery" aria-hidden><span /></span>
      </span>
    </div>
  );
}

function RideApp({ state, onPick }: { state: GameState; onPick: (id: string) => void }) {
  const locations = useGame((s) => s.locations);
  const rows = useKm(state, locations);
  const homeId = state.profile.home_location_id;
  return (
    <div className="phone-app__body">
      <p className="phone-app__lead">Where to? Pick a place, then choose keke, bus, drop or your feet.</p>
      <ul className="ride-list">
        {rows.map(({ l, km }) => (
          <li key={l.id}>
            <button type="button" className="ride-row" onClick={() => onPick(l.id)}>
              <span className="ride-row__pin" aria-hidden>{l.id === homeId ? '🏠' : '📍'}</span>
              <span className="grow">
                <span className="ride-row__name">{l.id === homeId ? 'Home' : l.name}</span>
                <span className="ride-row__sub">{districtName(l.district)}</span>
              </span>
              <span className="ride-row__km">{km < 1 ? `${Math.round(km * 1000)} m` : `${km.toFixed(1)} km`}</span>
            </button>
          </li>
        ))}
      </ul>
    </div>
  );
}

function BankApp({ state }: { state: GameState }) {
  return (
    <div className="phone-app__body">
      <div className="bank-card">
        <span className="bank-card__label">Bank balance</span>
        <span className="bank-card__amt">{naira(state.profile.bank)}</span>
        <span className="bank-card__sub">Bronze Bank · safe from thieves</span>
      </div>
      <div className="bank-row"><span>Cash in pocket</span><b>{naira(state.profile.cash)}</b></div>
      <p className="phone-app__lead">Deposits and withdrawals open soon, here and at the Bronze Bank counter in GRA. Until then, your bank balance is safe from thieves.</p>
    </div>
  );
}

function JobsApp({ state, onGo }: { state: GameState; onGo: (id: string) => void }) {
  const { cat, err } = useJobsCatalog();
  const { busy, apply, quit } = useCareerActions();
  const byId = useGame((s) => s.locationsById);
  const job = state.career?.job ?? null;
  const work = nearestWorkplace(state, byId);
  const atWork = Boolean(job?.locations.some((l) => l.id === state.profile.location_id)) && !state.travel;
  return (
    <div className="phone-app__body jobs-app">
      {job ? (
        <>
          <JobCard job={job} />
          <PerfBar perf={job.perf_now} />
          <Promotion job={job} />
          <ShiftStats job={job} />
          <div className="row jobs-app__actions">
            {work && (
              <Button variant="green" icon={atWork ? 'clock' : 'pin'} className="grow" onClick={() => onGo(work)}>
                {atWork ? 'Start a shift' : 'Go to work'}
              </Button>
            )}
            <QuitButton busy={busy === 'quit'} onQuit={() => void quit()} />
          </div>
        </>
      ) : (
        <p className="phone-app__lead">Pick a job and start at the bottom. You get paid at the end of every shift, and good shifts get you promoted.</p>
      )}
      <h4 className="jobs-app__head">{job ? 'Other jobs' : 'Who is hiring'}</h4>
      {!cat && !err && <div className="panel-skel"><span /><span /></div>}
      {err && <p className="phone-app__lead">{err}</p>}
      {cat && <TrackList tracks={cat.tracks.filter((t) => t.id !== cat.current)} current={cat.current} busy={busy} onApply={(id) => void apply(id)} />}
    </div>
  );
}

function ComingSoon({ app }: { app: App }) {
  return (
    <div className="phone-soon">
      <span className="phone-soon__icon" style={{ background: app.bg }} aria-hidden>{app.emoji}</span>
      <h3>{app.name}</h3>
      <p>{app.pitch}</p>
      <span className="soon-pill soon-pill--lg">Coming soon</span>
    </div>
  );
}

export function Phone({ state, clock }: { state: GameState; clock: GameClock }) {
  const overlay = useUi((s) => s.overlay);
  const phoneApp = useUi((s) => s.phoneApp);
  const setOverlay = useUi((s) => s.setOverlay);
  const openPanel = useUi((s) => s.openPanel);
  const openSim = useUi((s) => s.openSim);
  const select = useUi((s) => s.select);
  const setMapOpen = useUi((s) => s.setMapOpen);
  const unread = useGame((s) => s.unread);
  const events = useGame((s) => s.events);
  const open = overlay === 'phone';
  const { mounted, closing } = usePresence(open, 200);
  const [screen, setScreen] = useState<'lock' | 'home' | string>('lock');
  const [wasOpen, setWasOpen] = useState(open);
  const touch = useRef<number | null>(null);
  if (open !== wasOpen) {
    setWasOpen(open);
    if (open) setScreen(phoneApp ?? 'lock');
  }
  const close = () => setOverlay(null);
  useEscape(open, close);

  if (!mounted) return null;

  const launch = (id: string) => {
    if (id === 'wallet') {
      openPanel('wallet');
      close();
    } else if (id === 'settings') {
      openSim('settings');
    } else setScreen(id);
  };
  const pickRide = (id: string) => {
    close();
    setMapOpen(true);
    select(id);
  };
  const goWork = (id: string) => {
    close();
    setMapOpen(true);
    select(id, 'jobs');
  };
  const app = APPS.find((a) => a.id === screen);
  const latest = events[0];
  const date = `${WEEKDAYS[weekdayOf(clock)]} · Day ${clock.day} · Benin City`;

  return createPortal(
    <div className={`phone-root${closing ? ' is-closing' : ''}`} role="dialog" aria-modal="true" aria-label="Phone">
      <div className="phone-backdrop" onClick={close} />
      <button type="button" className="phone-close" onClick={close}><Icon name="close" size={18} stroke={2.6} /> Close</button>
      <div className="phone">
        <div className={`phone__screen phone__screen--${screen === 'lock' ? 'lock' : screen === 'home' ? 'home' : 'app'}`}>
          <StatusBar clock={clock} />
          {screen === 'lock' && (
            <button type="button" className="phone-lock" onClick={() => setScreen('home')}
              onTouchStart={(e) => { touch.current = e.touches[0].clientY; }}
              onTouchEnd={(e) => { if (touch.current !== null && touch.current - e.changedTouches[0].clientY > 40) setScreen('home'); touch.current = null; }}>
              <span className="phone-lock__time">{clockTime(clock.hour, clock.minute).replace(/\s?[AP]M$/i, '')}</span>
              <span className="phone-lock__date">{date}</span>
              {latest && unread > 0 && (
                <span className="phone-lock__note">
                  <span className="phone-lock__note-app" aria-hidden>🔔</span>
                  <span className="grow">
                    <span className="phone-lock__note-title">{latest.title}</span>
                    {latest.body && <span className="phone-lock__note-body">{latest.body}</span>}
                  </span>
                  {unread > 1 && <span className="phone-lock__note-more">+{unread - 1}</span>}
                </span>
              )}
              <span className="phone-lock__hint">Tap or swipe up to open</span>
            </button>
          )}
          {screen === 'home' && (
            <div className="phone-home">
              <div className="phone-home__grid">
                {APPS.map((a) => (
                  <button key={a.id} type="button" className="app-icon" onClick={() => launch(a.id)}>
                    <span className="app-icon__tile" style={{ background: a.bg }} aria-hidden>
                      {a.emoji}
                      {a.id === 'alerts' && unread > 0 && <span className="app-icon__badge">{unread > 99 ? '99+' : unread}</span>}
                      {a.id === 'houses' && (state.rent?.owed ?? 0) > 0 && <span className="app-icon__badge">!</span>}
                    </span>
                    <span className="app-icon__name">{a.name}</span>
                  </button>
                ))}
              </div>
            </div>
          )}
          {app && (
            <div className="phone-app">
              <div className="phone-app__bar">
                <button type="button" className="phone-app__back" onClick={() => setScreen('home')} aria-label="Back to apps">
                  <Icon name="back" size={20} stroke={2.6} />
                </button>
                <span className="phone-app__title"><span aria-hidden>{app.emoji}</span> {app.name}</span>
              </div>
              {app.id === 'ride' ? <RideApp state={state} onPick={pickRide} />
                : app.id === 'jobs' ? <JobsApp state={state} onGo={goWork} />
                : app.id === 'alerts' ? <div className="phone-app__body"><AlertsList active={open && screen === 'alerts'} /></div>
                  : app.id === 'bank' ? <BankApp state={state} />
                    : app.id === 'food' || app.id === 'houses' ? (
                      <Suspense fallback={<div className="phone-app__body"><div className="panel-skel"><span /><span /></div></div>}>
                        {app.id === 'food' ? <FoodApp state={state} /> : <HousesApp state={state} />}
                      </Suspense>
                    )
                      : <ComingSoon app={app} />}
            </div>
          )}
          <button type="button" className="phone__home-bar" onClick={() => setScreen(screen === 'home' ? 'lock' : 'home')}
            aria-label={screen === 'home' ? 'Lock the phone' : 'Go to the home screen'}><span /></button>
        </div>
      </div>
    </div>,
    document.body,
  );
}
