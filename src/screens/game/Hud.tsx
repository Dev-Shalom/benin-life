// R4 HUD (Lagos Life-style layout, Benin content):
//   top     one white pill: day + weekday + time, mood, players online, mute, cash with a green "+"
//   left    wish chips (tips from low needs), Dad's allowance, protection, "Clean screen"
//   b-left  round cached portrait + 6 tiny need bars -> Sim sheet
//   bottom  dock: Home · Buy · Map · Phone (badge = unread alerts)
import { useEffect, useLayoutEffect, useRef, useState } from 'react';
import { AvatarPortrait } from '../../art/avatar3d';
import { weekdayOf } from '../../lib/clock';
import { clockTime, countdown, nairaShort } from '../../lib/format';
import { rpc, errorMessage } from '../../lib/api';
import { lowNeeds, moodOf, needValue } from '../../lib/mood';
import { HUD_NEEDS, NEED_META, ORIGIN_UI, WEEKDAYS_SHORT, originCopy, type NeedKey } from '../../lib/pidgin';
import { usePrefs } from '../../lib/prefs';
import type { ClaimAllowanceResult, GameClock, GameState, PlayersOnline } from '../../lib/types';
import { useGame } from '../../state/game';
import { useUi } from '../../state/ui';
import { Icon, toast } from '../../ui';
import type { PlayerStatus } from './status';

function usePlayersOnline(): number | null {
  const [n, setN] = useState<number | null>(null);
  useEffect(() => {
    let alive = true;
    const load = async () => {
      if (document.visibilityState !== 'visible') return;
      try {
        const r = await rpc<PlayersOnline>('players_online');
        if (alive) setN(Number(r?.count ?? 0));
      } catch {
        if (alive) setN(null); // older server or offline: hide the count
      }
    };
    void load();
    const id = window.setInterval(load, 60_000);
    return () => {
      alive = false;
      window.clearInterval(id);
    };
  }, []);
  return n;
}

export function TopPill({ state, clock }: { state: GameState; clock: GameClock }) {
  const p = state.profile;
  const openPanel = useUi((s) => s.openPanel);
  const openSim = useUi((s) => s.openSim);
  const muted = usePrefs((s) => s.muted);
  const toggle = usePrefs((s) => s.toggle);
  const online = usePlayersOnline();
  const mood = moodOf(p);
  const ref = useRef<HTMLDivElement>(null);

  // Publish the pill's bottom edge so toasts sit just below it (see .bl-toaster in game.css).
  useLayoutEffect(() => {
    const el = ref.current;
    if (!el) return;
    const root = document.documentElement;
    const sync = () => root.style.setProperty('--hud-bottom', `${Math.round(el.getBoundingClientRect().bottom)}px`);
    sync();
    const ro = new ResizeObserver(sync);
    ro.observe(el);
    window.addEventListener('resize', sync);
    return () => {
      ro.disconnect();
      window.removeEventListener('resize', sync);
      root.style.removeProperty('--hud-bottom');
    };
  }, []);

  return (
    <div className="pill-bar" ref={ref}>
      <div className="pill-bar__time" title={`Day ${clock.day}`}>
        <span className="pill-bar__sun" aria-hidden>{clock.is_night ? '🌙' : '☀️'}</span>
        <span className="pill-bar__day">{WEEKDAYS_SHORT[weekdayOf(clock)]} {clock.day}</span>
        <span className="pill-bar__dot" aria-hidden>·</span>
        <span className="pill-bar__clock">{clockTime(clock.hour, clock.minute)}</span>
      </div>
      <span className="pill-bar__sep" aria-hidden />
      <button type="button" className={`pill-bar__mood is-${mood.tone}`} onClick={() => openSim('needs')} aria-label={`Mood: ${mood.label}. Open needs`}>
        <span aria-hidden>{mood.emoji}</span>
        <span className="pill-bar__mood-label">{mood.label}</span>
      </button>
      {online !== null && (
        <>
          <span className="pill-bar__sep pill-bar__sep--online" aria-hidden />
          <span className="pill-bar__online" title="Players online now">
            <span className="pill-bar__live" aria-hidden />
            {online.toLocaleString()} <span className="pill-bar__online-label">online</span>
          </span>
        </>
      )}
      <span className="grow" />
      <button type="button" className="pill-bar__mute" onClick={() => toggle('muted')} aria-pressed={muted}
        aria-label={muted ? 'Sound is off. Turn it on' : 'Sound is on. Mute'} title={muted ? 'Unmute' : 'Mute'}>
        <SpeakerIcon muted={muted} />
      </button>
      <button type="button" className="pill-bar__cash" onClick={() => openPanel('wallet')} aria-label={`Cash ${nairaShort(p.cash)}. Open wallet`}>
        <span className="pill-bar__amount">{nairaShort(p.cash)}</span>
        <span className="pill-bar__plus" aria-hidden><Icon name="plus" size={16} stroke={3} /></span>
      </button>
    </div>
  );
}

function SpeakerIcon({ muted }: { muted: boolean }) {
  return (
    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
      <path d="M4 9h4l5-4v14l-5-4H4z" />
      {muted ? <path d="M17 9l5 5M22 9l-5 5" /> : <path d="M16.5 8.5a5 5 0 0 1 0 7M19 6a8.5 8.5 0 0 1 0 12" />}
    </svg>
  );
}

const NEED_GROUP: Partial<Record<NeedKey, 'kitchen' | 'bed' | 'bath' | 'toilet' | 'media'>> = {
  hunger: 'kitchen',
  energy: 'bed',
  hygiene: 'bath',
  bladder: 'toilet',
  fun: 'media',
};

/**
 * Left rail. On the map (`compact`) the chips fold into one small summary chip so they do not cover
 * the city on phones; tapping it opens the full list (and "Clean screen") until a chip is used.
 */
export function LeftRail({ state, status, atHome, compact = false }: { state: GameState; status: PlayerStatus; atHome: boolean; compact?: boolean }) {
  const p = state.profile;
  const origin = state.origin ?? null;
  const refresh = useGame((s) => s.refresh);
  const pickHome = useUi((s) => s.pickHome);
  const select = useUi((s) => s.select);
  const clean = usePrefs((s) => s.clean);
  const setPrefs = usePrefs((s) => s.set);
  const [claiming, setClaiming] = useState(false);
  const [open, setOpen] = useState(false);
  const tips = lowNeeds(p, 2);
  const dadReady = Boolean(origin?.allowance_claimable);
  const protectedNow = status.protLeft > 0;
  const count = tips.length + (dadReady ? 1 : 0) + (protectedNow ? 1 : 0);
  const folded = compact && !open && !clean;

  // Leaving the map (or switching to clean screen) folds the list again.
  if (open && (!compact || clean)) setOpen(false);

  const claimDad = async () => {
    if (claiming) return;
    setClaiming(true);
    try {
      const r = await rpc<ClaimAllowanceResult>('claim_allowance');
      toast(r.message, 'good');
      await refresh();
    } catch (e) {
      toast(errorMessage(e), 'bad');
    } finally {
      setClaiming(false);
    }
  };

  const onTip = (k: NeedKey) => {
    setOpen(false);
    const g = NEED_GROUP[k];
    if (atHome && g) pickHome({ id: null, group: g });
    else select(p.location_id);
  };

  if (folded && count > 0) {
    const icons = [...tips.map((t) => t.emoji), ...(dadReady ? ['💸'] : []), ...(protectedNow ? ['🛡️'] : [])];
    return (
      <div className="left-rail is-compact">
        <button type="button" className={`rail-summary${dadReady ? ' has-dad' : ''}`} onClick={() => setOpen(true)} aria-expanded={false}
          aria-label={`Tips and status (${count}). Show`}>
          <span className="rail-summary__icons" aria-hidden>
            {icons.map((e, i) => <span key={i} className="rail-summary__icon">{e}</span>)}
          </span>
          <Icon name="chevronDown" size={14} stroke={2.6} />
        </button>
      </div>
    );
  }

  return (
    <div className={`left-rail${clean ? ' is-clean' : ''}${compact ? ' is-compact' : ''}`}>
      {compact && open && !clean && (
        <button type="button" className="rail-summary is-open" onClick={() => setOpen(false)} aria-expanded aria-label="Hide tips and status">
          <span className="rail-summary__label">Hide</span>
          <Icon name="chevronUp" size={14} stroke={2.6} />
        </button>
      )}
      {!clean && (
        <>
          {tips.map((t) => (
            <button key={t.key} type="button" className="wish-chip" onClick={() => onTip(t.key)}>
              <span className="wish-chip__icon" style={{ background: `${NEED_META[t.key].color}22` }} aria-hidden>{t.emoji}</span>
              <span className="wish-chip__text">
                <span className="wish-chip__title">{t.text}</span>
                <span className="wish-chip__bar"><span style={{ width: `${t.value}%`, background: NEED_META[t.key].color }} /></span>
              </span>
            </button>
          ))}
          {dadReady && origin && (
            <button type="button" className="wish-chip wish-chip--dad" onClick={() => void claimDad()} disabled={claiming}
              aria-label={`${ORIGIN_UI.collectDad} (${nairaShort(origin.allowance_daily)})`}>
              <span className="wish-chip__icon" aria-hidden>💸</span>
              <span className="wish-chip__text">
                <span className="wish-chip__title">{ORIGIN_UI.collectDad}</span>
                <span className="wish-chip__sub">{nairaShort(origin.allowance_daily)} from {ORIGIN_UI.dadChip}</span>
              </span>
            </button>
          )}
          {protectedNow && (
            <div className="wish-chip wish-chip--protect" title="New player protection: nobody can rob you yet">
              <span className="wish-chip__icon" aria-hidden>🛡️</span>
              <span className="wish-chip__text">
                <span className="wish-chip__title">Protected</span>
                <span className="wish-chip__sub">{countdown(status.protLeft)} left</span>
              </span>
            </div>
          )}
        </>
      )}
      <button type="button" className="clean-toggle" onClick={() => setPrefs({ clean: !clean })} aria-pressed={clean}>
        <Icon name={clean ? 'chevronDown' : 'chevronUp'} size={14} stroke={2.6} />
        {clean ? 'Show HUD' : 'Clean screen'}
      </button>
    </div>
  );
}

export function NeedsCard({ state }: { state: GameState }) {
  const p = state.profile;
  const openSim = useUi((s) => s.openSim);
  const origin = state.origin ?? null;
  const tier = origin?.id ?? p.origin;
  const badge = tier ? originCopy(tier, origin?.name ?? tier, origin?.tagline ?? '').badge : null;
  return (
    <button type="button" className="needs-card" onClick={() => openSim('needs')} aria-label="Your Sim: needs and profile">
      <span className="needs-card__face">
        <AvatarPortrait config={p.avatar} size={56} />
        {badge && (
          <span className={`origin-chip origin-chip--${tier === 'nepo' ? 'nepo' : tier === 'lapo' ? 'lapo' : 'other'}`} title={origin?.name}>
            {badge}
          </span>
        )}
      </span>
      <span className="needs-card__bars">
        {HUD_NEEDS.map((k) => {
          const v = needValue(p, k);
          const meta = NEED_META[k];
          return (
            <span key={k} className={`mini-need${v < 25 ? ' is-low' : ''}`} title={`${meta.label}: ${Math.round(v)}%`}>
              <span className="mini-need__icon" aria-hidden>{meta.emoji}</span>
              <span className="mini-need__track" role="meter" aria-label={meta.label} aria-valuemin={0} aria-valuemax={100} aria-valuenow={Math.round(v)}>
                <span className="mini-need__fill" style={{ width: `${v}%`, background: v < 25 ? 'var(--red-500)' : v < 50 ? 'var(--amber-500)' : 'var(--green-500)' }} />
              </span>
            </span>
          );
        })}
      </span>
    </button>
  );
}

export type DockId = 'home' | 'buy' | 'map' | 'phone';

export function Dock({ active, unread, onPick }: { active: DockId | null; unread: number; onPick: (id: DockId) => void }) {
  const items: { id: DockId; label: string; icon: React.ReactNode }[] = [
    { id: 'home', label: 'Home', icon: <Icon name="home" size={22} stroke={2.1} /> },
    { id: 'buy', label: 'Buy', icon: <SofaIcon /> },
    { id: 'map', label: 'Map', icon: <Icon name="map" size={22} stroke={2.1} /> },
    { id: 'phone', label: 'Phone', icon: <PhoneIcon /> },
  ];
  return (
    <nav className="dock" aria-label="Game menu">
      {items.map((it) => (
        <button key={it.id} type="button" className={`dock__btn${active === it.id ? ' is-active' : ''}`} onClick={() => onPick(it.id)}
          aria-current={active === it.id ? 'page' : undefined}
          aria-label={it.id === 'phone' && unread > 0 ? `Phone, ${unread} unread` : undefined}>
          <span className="dock__icon">
            {it.icon}
            {it.id === 'phone' && unread > 0 && <span className="dock__badge">{unread > 99 ? '99+' : unread}</span>}
          </span>
          <span className="dock__label">{it.label}</span>
        </button>
      ))}
    </nav>
  );
}

function SofaIcon() {
  return (
    <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.1" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
      <path d="M5 11V8a2 2 0 0 1 2-2h10a2 2 0 0 1 2 2v3" />
      <path d="M3 13a2 2 0 0 1 4 0v1h10v-1a2 2 0 0 1 4 0v4H3z" />
      <path d="M5 17v2M19 17v2" />
    </svg>
  );
}

function PhoneIcon() {
  return (
    <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.1" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
      <rect x="6.5" y="2.5" width="11" height="19" rx="2.5" />
      <path d="M11 18.5h2" />
    </svg>
  );
}

export function KeyboardButton({ onClick }: { onClick: () => void }) {
  return (
    <button type="button" className="kbd-btn" onClick={onClick} aria-label="Keyboard shortcuts" title="Keyboard shortcuts (?)">
      <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" aria-hidden>
        <rect x="2.5" y="6" width="19" height="12" rx="2" />
        <path d="M6 10h.01M9 10h.01M12 10h.01M15 10h.01M18 10h.01M7 14h10" />
      </svg>
    </button>
  );
}
