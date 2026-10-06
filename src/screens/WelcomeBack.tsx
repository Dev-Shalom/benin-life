// S2 welcome back (docs/HUD_HOME.md "S2 welcome back"). Shown before the game HUD when a player
// opens the game in a new tab or after being away (src/lib/welcome.ts decides).
//
// Background: the player's own 3D home (their furniture, their Sim walking in) in the low-walled
// dollhouse view, the camera circling the island once every ~50 s (still under reduced motion), lit
// for the real time of day. One canvas, lazy (three.js loads with HomeView), drawn only while it
// orbits and the tab is visible. Card: portrait, name, where they are, money, Continue / New life /
// Log out. The card is plain DOM, so it shows at once while the 3D loads and if WebGL fails.
import { useEffect, useLayoutEffect, useMemo, useRef, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { AvatarPortrait } from '../art/avatar3d';
import { HomeView, LAYOUTS, activityGroup, furnishLayout, homeLayoutFor } from '../art/home3d';
import { rpc, errorMessage, GameError } from '../lib/api';
import { serverNow, useGameClock } from '../lib/clock';
import { useConfig } from '../lib/config';
import { devHourOverride, looksNight } from '../lib/daylight';
import { naira, nairaShort, timeAgo } from '../lib/format';
import { simPosture } from '../lib/mood';
import { originCopy } from '../lib/pidgin';
import { homeLight } from '../art/home3d/engine/light';
import { useCatalog } from '../state/catalog';
import { useGame } from '../state/game';
import { Button, Icon, Modal, toast } from '../ui';

const ORBIT_SECONDS = 52;

function useReducedMotion(): boolean {
  const [reduced, setReduced] = useState(() => {
    try {
      return window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    } catch {
      return false;
    }
  });
  useEffect(() => {
    let mq: MediaQueryList;
    try {
      mq = window.matchMedia('(prefers-reduced-motion: reduce)');
    } catch {
      return;
    }
    const on = () => setReduced(mq.matches);
    mq.addEventListener?.('change', on);
    return () => mq.removeEventListener?.('change', on);
  }, []);
  return reduced;
}

function useWide(): boolean {
  const [wide, setWide] = useState(() => window.innerWidth >= 900);
  useEffect(() => {
    const on = () => setWide(window.innerWidth >= 900);
    window.addEventListener('resize', on);
    return () => window.removeEventListener('resize', on);
  }, []);
  return wide;
}

export interface WelcomeBackProps {
  /** Last time this player had the game open here (ms), for "Last played 3 hrs ago". */
  lastSeenAt: number | null;
  onContinue: () => void;
}

export default function WelcomeBack({ lastSeenAt, onContinue }: WelcomeBackProps) {
  const state = useGame((s) => s.state);
  const byId = useGame((s) => s.locationsById);
  const signOut = useGame((s) => s.signOut);
  const furniture = useCatalog((s) => s.furniture);
  const furnitureOf = useCatalog((s) => s.furnitureOf);
  const loadFurniture = useCatalog((s) => s.loadFurniture);
  const activities = useCatalog((s) => s.activities);
  const loadActivities = useCatalog((s) => s.loadActivities);
  const { cfg } = useConfig();
  const { clock } = useGameClock(15_000);
  const reduced = useReducedMotion();
  const wide = useWide();
  const nav = useNavigate();
  const card = useRef<HTMLDivElement>(null);
  const [cardBox, setCardBox] = useState({ w: 0, h: 0 });
  const [step, setStep] = useState<0 | 1 | 2>(0);
  const [typed, setTyped] = useState('');
  const [busy, setBusy] = useState<'restart' | 'logout' | null>(null);
  const [gone, setGone] = useState(false);

  const p = state?.profile;
  const hour = devHourOverride() ?? clock.hour + clock.minute / 60;
  const night = looksNight(hour);
  const sky = homeLight(hour).bg;

  // the house: same layout + own furniture as the game
  useEffect(() => {
    if (p) void loadFurniture(p.id);
    void loadActivities();
  }, [p, loadFurniture, loadActivities]);
  const homeScene = (p && byId[p.home_location_id]?.scene) || (p && state?.location.id === p.home_location_id ? state.location.scene : null);
  const layoutId = homeLayoutFor(p?.housing_id, homeScene);
  const furnished = useMemo(() => furnishLayout(LAYOUTS[layoutId], furniture), [layoutId, furniture]);

  // a home activity still running (asleep in bed, watching TV...) shows in the house
  const busyUntil = p?.busy_until ?? null;
  const busyLabel = p?.busy_label ?? null;
  const busyGroup = useMemo(() => {
    if (!busyUntil || !busyLabel || Date.parse(busyUntil) <= serverNow()) return null;
    const a = activities?.find((x) => x.name === busyLabel && x.home_only);
    return a ? { group: activityGroup(a.id), key: busyUntil, activity: a.id, seconds: (Date.parse(busyUntil) - serverNow()) / 1000 } : null;
  }, [busyUntil, busyLabel, activities]);

  // the sky behind the page follows the time of day (status bar too)
  useEffect(() => {
    const root = document.documentElement;
    root.dataset.theme = night ? 'night' : 'day';
    document.querySelector('meta[name="theme-color"]')?.setAttribute('content', night ? '#1d2542' : '#e4f0fa');
  }, [night]);
  useEffect(
    () => () => {
      delete document.documentElement.dataset.theme;
    },
    [],
  );

  // frame the island in the space the card leaves free
  useLayoutEffect(() => {
    const el = card.current;
    if (!el) return;
    const measure = () => setCardBox({ w: el.offsetWidth, h: el.offsetHeight });
    measure();
    if (typeof ResizeObserver === 'undefined') return;
    const ro = new ResizeObserver(measure);
    ro.observe(el);
    return () => ro.disconnect();
  }, []);

  // warm the game while the player looks at their house
  useEffect(() => {
    const t = window.setTimeout(() => void import('./Game'), 600);
    return () => window.clearTimeout(t);
  }, []);

  // Enter = Continue (when no dialog is open)
  useEffect(() => {
    const on = (e: KeyboardEvent) => {
      if (e.key === 'Enter' && step === 0 && !(e.target instanceof HTMLInputElement) && !(e.target instanceof HTMLButtonElement)) onContinue();
    };
    window.addEventListener('keydown', on);
    return () => window.removeEventListener('keydown', on);
  }, [step, onContinue]);

  if (!state || !p) return null;

  const total = p.cash + p.bank;
  const origin = state.origin ?? null;
  const tier = origin?.id ?? p.origin;
  const badge = tier ? originCopy(tier, origin?.name ?? tier, origin?.tagline ?? '').badge : null;
  const home = byId[p.home_location_id];
  const atHome = !state.travel && p.location_id === p.home_location_id;
  const where = state.travel
    ? `On the way to ${byId[state.travel.to]?.name ?? 'somewhere'}`
    : atHome
      ? `At home${home ? `, ${home.name.replace(/ \(.*\)$/, '')}` : ''}`
      : `Out at ${state.location.name.replace(/ \(.*\)$/, '')}`;
  const away = lastSeenAt && Date.now() - lastSeenAt > 5 * 60_000 ? timeAgo(new Date(lastSeenAt).toISOString()) : null;
  const restartOn = cfg('life.restart_enabled', true);
  const confirmWord = p.username;
  const typedOk = typed.trim().toLowerCase() === confirmWord.toLowerCase();

  const restart = async () => {
    if (!typedOk) return;
    setBusy('restart');
    try {
      await rpc('life_restart');
      setGone(true);
      setStep(0);
      useCatalog.setState({ furniture: null, furnitureOf: null });
      useGame.setState({ state: null, status: 'noprofile', events: [], unread: 0, error: null });
      toast('Your old life is saved in the archive. Make your new Sim.', 'info');
      nav('/create', { replace: true });
    } catch (e) {
      toast(errorMessage(e), 'bad');
      if (e instanceof GameError && (e.hint === 'restart_disabled' || e.hint === 'restart_cooldown')) setStep(0);
    } finally {
      setBusy(null);
    }
  };

  const logout = async () => {
    setBusy('logout');
    try {
      await signOut();
      nav('/', { replace: true });
    } finally {
      setBusy(null);
    }
  };

  const insetTop = wide ? 40 : 28;
  const insetBottom = wide ? 40 : cardBox.h + 12;
  const insetLeft = wide ? cardBox.w + 48 : 0;

  return (
    <div className={`welcome${night ? ' is-night' : ''}${reduced ? ' is-reduced' : ''}`} style={{ background: sky }}>
      <div className="welcome__stage" aria-hidden>
        {!gone && furnitureOf === p.id && (cardBox.h > 0 || wide) && (
          <HomeView
            layoutId={layoutId}
            layout={furnished}
            avatar={p.avatar}
            busy={busyGroup}
            mood={simPosture(p)}
            hour={hour}
            orbit={reduced ? 0 : ORBIT_SECONDS}
            dollhouse
            interactive={false}
            paused={step !== 0}
            insetTop={insetTop}
            insetBottom={insetBottom}
            insetLeft={insetLeft}
            fallbackScene={home?.scene ?? 'home_face_me'}
          />
        )}
      </div>

      <section ref={card} className="welcome__card" aria-labelledby="welcome-name">
        <div className="welcome__who">
          <span className="welcome__face">
            <AvatarPortrait config={p.avatar} size={72} alt="" />
            {badge && (
              <span className={`origin-chip origin-chip--${tier === 'nepo' ? 'nepo' : tier === 'lapo' ? 'lapo' : 'other'}`} title={origin?.name}>
                {badge}
              </span>
            )}
          </span>
          <span className="welcome__id">
            <span className="welcome__eyebrow">Welcome back</span>
            <h1 id="welcome-name" className="welcome__name">{p.username}</h1>
            <span className="welcome__where">{where}</span>
            {away && <span className="welcome__away">Last played {away}</span>}
          </span>
        </div>

        <div className="welcome__money">
          <span className="welcome__money-label">Your money</span>
          <span className="welcome__total" title={naira(total)}>{nairaShort(total)}</span>
          <span className="welcome__split">
            <span title={naira(p.cash)}><Icon name="cash" size={15} /> Cash {nairaShort(p.cash)}</span>
            <span title={naira(p.bank)}><Icon name="bank" size={15} /> Bank {nairaShort(p.bank)}</span>
          </span>
        </div>

        <div className="welcome__actions">
          <Button size="lg" block onClick={onContinue} className="welcome__go">
            Continue
          </Button>
          {restartOn && (
            <Button variant="ghost" block onClick={() => { setTyped(''); setStep(1); }}>
              New life
            </Button>
          )}
          <button type="button" className="welcome__logout" onClick={() => void logout()} disabled={busy !== null}>
            <Icon name="logout" size={15} /> Log out
          </button>
        </div>
      </section>

      <Modal
        open={step === 1}
        onClose={() => setStep(0)}
        tone="bad"
        art={<span aria-hidden className="welcome__modal-art">🧳</span>}
        title={`Start a new life?`}
        actions={
          <>
            <Button variant="danger" block onClick={() => setStep(2)}>Yes, start over</Button>
            <Button variant="ghost" block onClick={() => setStep(0)}>Keep {p.username}</Button>
          </>
        }
      >
        <p>{p.username} and everything they have will be gone from the game:</p>
        <ul className="welcome__lose">
          <li><strong>{naira(total)}</strong> in cash and bank</li>
          <li>Your home, furniture and everything in your Bag</li>
          <li>Your job, career progress, traits and dream</li>
        </ul>
        <p>Your account stays and your old life is kept in an archive, but you can't play it again. You'll make a new Sim and your birth (LAPO or Nepo) is rolled again.</p>
      </Modal>

      <Modal
        open={step === 2}
        onClose={() => busy === null && setStep(0)}
        dismissable={busy === null}
        tone="bad"
        title="Confirm your new life"
        actions={
          <>
            <Button variant="danger" block disabled={!typedOk} loading={busy === 'restart'} onClick={() => void restart()}>
              Start a new life
            </Button>
            <Button variant="ghost" block disabled={busy !== null} onClick={() => setStep(0)}>Cancel</Button>
          </>
        }
      >
        <p>Type <strong className="welcome__word">{confirmWord}</strong> to confirm. This can't be undone.</p>
        <input
          className="input"
          value={typed}
          onChange={(e) => setTyped(e.target.value)}
          onKeyDown={(e) => { if (e.key === 'Enter') void restart(); }}
          placeholder={confirmWord}
          aria-label={`Type ${confirmWord} to confirm`}
          autoCapitalize="none"
          autoCorrect="off"
          spellCheck={false}
          autoFocus
        />
      </Modal>
    </div>
  );
}
