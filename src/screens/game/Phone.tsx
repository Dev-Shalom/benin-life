// The phone (R4): lock screen with the game clock -> app grid of fictional Benin apps.
// Built: Ride (S1: book keke/bus/drop/car with price, time and risk, lazy), Jobs (V1-3), Chowdeck + Houses (V1-4, lazy),
// Bank (V1-5), Ranks (PAY), Messages (friend requests, private text/voice chat and house visits), Wallet, Alerts and Settings.
// Apps without working features stay hidden.
// Esc closes the phone.
import { lazy, Suspense, useRef, useState } from 'react';
import { createPortal } from 'react-dom';
import { clockTime } from '../../lib/format';
import { WEEKDAYS } from '../../lib/pidgin';
import type { GameClock, GameState } from '../../lib/types';
import { useChat } from '../../state/chat';
import { useGame } from '../../state/game';
import { useUi } from '../../state/ui';
import { Button, Icon, toast, usePresence } from '../../ui';
import { useEscape } from '../../ui/presence';
import { dateLabel, weekdayOf } from '../../lib/clock';
import { AlertsList } from './Overlays';
import { nearestWorkplace } from '../../api/careers';
import { JobCard, PerfBar, Promotion, QuitButton, ShiftStats, TrackList } from '../../panels/careers/CareerUI';
import { useCareerActions, useJobsCatalog } from '../../panels/careers/careerHooks';
const SocialApp = lazy(() => import('./phone/SocialApp'));

const FoodApp = lazy(() => import('./phone/FoodApp'));
const HousesApp = lazy(() => import('./phone/HousesApp'));
const BankApp = lazy(() => import('./phone/BankApp'));
const RideApp = lazy(() => import('./phone/RideApp'));
const RanksApp = lazy(() => import('./phone/RanksApp'));
const CarsApp = lazy(() => import('./phone/CarsApp'));
const StoriesApp = lazy(() => import('./phone/StoriesApp'));
const PoliceApp = lazy(() => import('./phone/PoliceApp'));

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
  { id: 'messages', name: 'Messages', emoji: '💬', bg: 'linear-gradient(160deg,#5aa8ff,#2f6fd6)', pitch: 'Add friends, message them, and invite them over.' },
  { id: 'stories', name: 'Stories', emoji: '📖', bg: 'linear-gradient(160deg,#f0a45a,#d66830)', pitch: 'Weekly stories shaped by everyday Benin City life.' },
  { id: 'bank', name: 'Bank', emoji: '🏦', bg: 'linear-gradient(160deg,#9b8cff,#5b4fd6)', pitch: '' },
  { id: 'ranks', name: 'Ranks', emoji: '🏆', bg: 'linear-gradient(160deg,#ffd76a,#c9851a)', pitch: '' },
  { id: 'ride', name: 'Ride', emoji: '🛺', bg: 'linear-gradient(160deg,#ffd45c,#f0a316)', pitch: '' },
  { id: 'food', name: 'Chowdeck', emoji: '🍲', bg: 'linear-gradient(160deg,#4fc98a,#0f7a4c)', pitch: 'Order rice, swallow and small chops to your door, from bukas all over Benin.' },
  { id: 'houses', name: 'Houses', emoji: '🔑', bg: 'linear-gradient(160deg,#f2a65a,#c96a1f)', pitch: 'Rent a bigger place, from a self-contain in Uselu to a duplex in GRA.' },
  { id: 'cars', name: 'Cars', emoji: '🚗', bg: 'linear-gradient(160deg,#4aa3ff,#1f62c9)', pitch: 'Buy a tokunbo or a brand-new ride. Fuel money not included.' },
  { id: 'police', name: 'Police', emoji: '🚓', bg: 'linear-gradient(160deg,#4f6bd8,#26388f)', pitch: 'Report a robbery, check your case file and pay bail.' },
  { id: 'wallet', name: 'Wallet', emoji: '👛', bg: 'linear-gradient(160deg,#34c77f,#0a6f40)', pitch: '' },
  { id: 'alerts', name: 'Alerts', emoji: '🔔', bg: 'linear-gradient(160deg,#ff9d5c,#e2552c)', pitch: '' },
  { id: 'settings', name: 'Settings', emoji: '⚙️', bg: 'linear-gradient(160deg,#a9b2bf,#6b7686)', pitch: '' },
];

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

export function Phone({ state, clock }: { state: GameState; clock: GameClock }) {
  const overlay = useUi((s) => s.overlay);
  const phoneApp = useUi((s) => s.phoneApp);
  const setOverlay = useUi((s) => s.setOverlay);
  const openPanel = useUi((s) => s.openPanel);
  const openSim = useUi((s) => s.openSim);
  const select = useUi((s) => s.select);
  const setMapOpen = useUi((s) => s.setMapOpen);
  const unread = useGame((s) => s.unread);
  const chatUnread = useChat((s) => s.unread);
  const events = useGame((s) => s.events);
  const lastReadEventId = useGame((s) => s.lastReadEventId);
  const socialUnread = events.filter((e) => ['friend_request', 'house_invite', 'house_knock', 'private_message'].includes(e.kind) && e.id > lastReadEventId).length;
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
  const pickOnMap = () => {
    close();
    setMapOpen(true);
    toast('Tap a place on the map, then choose how to go.');
  };
  const booked = () => {
    close();
    setMapOpen(true);
  };
  const goWork = (id: string) => {
    close();
    setMapOpen(true);
    select(id, 'jobs');
  };
  const goToPlace = (id: string) => {
    close();
    setMapOpen(true);
    select(id);
  };
  const goHome = () => {
    close();
    setMapOpen(true);
    select(state.profile.home_location_id);
  };
  const app = APPS.find((a) => a.id === screen);
  const latest = events[0];
  const date = `${WEEKDAYS[weekdayOf(clock)]} · ${dateLabel(clock, true)} · Benin City`;

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
                      {a.id === 'messages' && chatUnread + socialUnread > 0 && <span className="app-icon__badge">{chatUnread + socialUnread > 9 ? '9+' : chatUnread + socialUnread}</span>}
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
              {app.id === 'jobs' ? <JobsApp state={state} onGo={goWork} />
                : app.id === 'messages' ? <Suspense fallback={<div className="phone-app__body"><div className="panel-skel"><span /><span /></div></div>}><SocialApp state={state} onGoHome={goHome} /></Suspense>
                : app.id === 'alerts' ? <div className="phone-app__body"><AlertsList active={open && screen === 'alerts'} /></div>
                  : app.id === 'cars' || app.id === 'police' || app.id === 'stories' || app.id === 'food' || app.id === 'houses' || app.id === 'bank' || app.id === 'ride' || app.id === 'ranks' ? (
                      <Suspense fallback={<div className="phone-app__body"><div className="panel-skel"><span /><span /></div></div>}>
                        {app.id === 'ranks' ? <RanksApp /> : app.id === 'ride' ? <RideApp state={state} onPickOnMap={pickOnMap} onBooked={booked} />
                          : app.id === 'cars' ? <CarsApp state={state} onGo={goToPlace} />
                            : app.id === 'police' ? <PoliceApp state={state} onGo={goToPlace} />
                              : app.id === 'stories' ? <StoriesApp />
                                : app.id === 'food' ? <FoodApp state={state} /> : app.id === 'bank' ? <BankApp state={state} /> : <HousesApp state={state} />}
                      </Suspense>
                    )
                      : null}
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
