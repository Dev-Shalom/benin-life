// R4 HUD (Lagos Life-style layout, Benin content):
//   top     one white pill: day + weekday + time, mood, players online, mute, cash with a green "+"
//   left    task pill + queue, then one "Today" pill (tips, Dad's allowance, daily reward/gems, protection) that
//           opens into a list (UI1), then a small "Clean screen · Beta" row
//   b-left  round cached portrait + 6 tiny need bars -> Sim sheet
//   bottom  dock: Home · Buy · Map · Phone (badge = unread alerts)
import { useEffect, useLayoutEffect, useRef, useState } from 'react';
import { AvatarPortrait } from '../../art/avatar3d';
import { dateLabel, useGameClock, weekdayOf } from '../../lib/clock';
import { useLiveProfile } from '../../lib/live';
import { getCfg } from '../../lib/config';
import { clockTime, countdown, isShortened, naira, nairaShort } from '../../lib/format';
import { rpc, errorMessage } from '../../lib/api';
import { lowNeeds, moodOf, needValue } from '../../lib/mood';
import { HUD_NEEDS, NEED_META, ORIGIN_UI, WEEKDAYS_SHORT, originCopy, type NeedKey } from '../../lib/pidgin';
import { usePrefs } from '../../lib/prefs';
import { devHourOverride, looksNight } from '../../lib/daylight';
import type { ClaimAllowanceResult, GameClock, GameState } from '../../lib/types';
import { useGame } from '../../state/game';
import { useUi } from '../../state/ui';
import { usePresenceStore } from '../../state/presence';
import { Icon, Logo, toast } from '../../ui';
import type { PlayerStatus } from './status';
import { nearestWorkplace } from '../../api/careers';
import { bestFood } from '../../api/shops';
import { TaskPill } from './TaskPill';
import { DailyChips, DailySheets, useDailyChipIcons } from './Daily';

/** Players online (S1 scaling): world_counts() polled once a minute by state/presence.ts; null hides the pill. */
function usePlayersOnline(): number | null {
  return usePresenceStore((s) => s.online);
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
      <div className="pill-bar__time" title={clock.mode === 'real' ? `Benin time · Day ${clock.day} of Benin Life` : `Day ${clock.day}`}>
        <span className="pill-bar__sun" aria-hidden>{looksNight(devHourOverride() ?? clock.hour + clock.minute / 60) ? '🌙' : '☀️'}</span>
        <span className="pill-bar__day">{WEEKDAYS_SHORT[weekdayOf(clock)]} {clock.date ? dateLabel(clock) : clock.day}</span>
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
      <CashPill cash={p.cash} onOpen={() => openPanel('wallet')} />
    </div>
  );
}

/** Cash in the top pill. Short scale (₦1.5T); tapping the amount flips to the full figure for a few
 *  seconds (hover shows it too). Small amounts are already full, so their tap opens the wallet. */
function CashPill({ cash, onOpen }: { cash: number; onOpen: () => void }) {
  const [full, setFull] = useState(false);
  const shortened = isShortened(cash);
  useEffect(() => {
    if (!full) return;
    const t = window.setTimeout(() => setFull(false), 4000);
    return () => window.clearTimeout(t);
  }, [full, cash]);
  const whole = naira(cash);
  return (
    <span className={`pill-bar__cash${full && shortened ? ' is-full' : ''}`}>
      <button type="button" className="pill-bar__amount" title={shortened ? whole : undefined}
        aria-label={shortened ? `Cash ${whole}. Tap to ${full ? 'shorten' : 'show the full amount'}` : `Cash ${whole}. Open wallet`}
        onClick={() => (shortened ? setFull((v) => !v) : onOpen())}>
        {full && shortened ? whole : nairaShort(cash)}
      </button>
      <button type="button" className="pill-bar__plus" onClick={onOpen} aria-label="Open wallet" title="Wallet">
        <Icon name="plus" size={16} stroke={3} />
      </button>
    </span>
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
 * V1-5 tip: at night, carrying more cash than `bank.tip_cash_threshold` -> the nearest PoS stand
 * (or the bank counter if it is open). Street thieves take cash, never bank money.
 */
function useBankTip(state: GameState, free: boolean): { id: string; name: string; tab: 'bank' | 'pos' } | null {
  const { clock } = useGameClock(15_000);
  const locations = useGame((s) => s.locations);
  const threshold = Number(getCfg('bank.tip_cash_threshold', 20000));
  if (!free || !clock.is_night || threshold <= 0 || state.profile.cash <= threshold) return null;
  const o = Number(getCfg('bank.open_hour', 8));
  const c = Number(getCfg('bank.close_hour', 16));
  const h = clock.hour;
  const bankOpen = o === c || (o < c ? h >= o && h < c : h >= o || h < c);
  const here = locations.find((l) => l.id === state.profile.location_id) ?? state.location;
  let best: { id: string; name: string; tab: 'bank' | 'pos'; d: number } | null = null;
  for (const l of locations) {
    const tab = bankOpen && l.actions.includes('bank') ? 'bank' : l.actions.includes('pos') ? 'pos' : null;
    if (!tab) continue;
    const d = Math.hypot(l.x - here.x, l.y - here.y);
    if (!best || d < best.d) best = { id: l.id, name: l.name, tab, d };
  }
  return best && { id: best.id, name: best.name, tab: best.tab };
}

/** UI1: the "Today" list starts open on roomy screens (desktop) and folded on phones, tablets and the map. */
const todayRoomy = () => typeof window !== 'undefined' && window.matchMedia('(min-width: 1280px) and (min-height: 760px)').matches;

/**
 * Left rail (UI1). Task pill + queue on top (never folds), then ONE compact "Today" pill that sums up the
 * tips and daily chips as small icons (red dot when something is ready to collect). Tapping it opens the
 * list; tapping outside folds it again. Desktop starts open; phones, tablets and the map (`compact`)
 * start folded. "Clean screen" + "Beta" sit in a small row under it.
 */
export function LeftRail({ state, status, atHome, compact = false }: { state: GameState; status: PlayerStatus; atHome: boolean; compact?: boolean }) {
  const p = state.profile;
  const origin = state.origin ?? null;
  const refresh = useGame((s) => s.refresh);
  const pickHome = useUi((s) => s.pickHome);
  const select = useUi((s) => s.select);
  const setMapOpen = useUi((s) => s.setMapOpen);
  const openPanel = useUi((s) => s.openPanel);
  const openPhone = useUi((s) => s.openPhone);
  const byId = useGame((s) => s.locationsById);
  const clean = usePrefs((s) => s.clean);
  const setPrefs = usePrefs((s) => s.set);
  const [claiming, setClaiming] = useState(false);
  // 'auto' follows the screen (open on roomy desktops outside the map); a tap pins it open or shut.
  const [mode, setMode] = useState<'auto' | 'open' | 'shut'>('auto');
  const [roomy, setRoomy] = useState(todayRoomy);
  const todayRef = useRef<HTMLDivElement>(null);
  const tips = lowNeeds(p, 2);
  const food = bestFood(state);
  // "Eat something": food in the Bag first, then the home kitchen, else Chowdeck (V1-4).
  const eatSub = food ? `${food.icon ?? ''} ${food.name} in your Bag`.trim() : atHome ? null : 'Order on Chowdeck';
  const dadReady = Boolean(origin?.allowance_claimable);
  const protectedNow = status.protLeft > 0;
  const job = state.career?.job ?? null;
  const workAt = job && status.free && !job.pending && job.shifts_today < job.max_shifts_per_day ? nearestWorkplace(state, byId) : null;
  const bankAt = useBankTip(state, status.free);
  const dailyIcons = useDailyChipIcons();
  const count = tips.length + (dadReady ? 1 : 0) + (protectedNow ? 1 : 0) + (workAt ? 1 : 0) + (bankAt ? 1 : 0) + dailyIcons.length;
  const ready = dadReady || dailyIcons.includes('🎁');
  const open = !clean && count > 0 && (mode === 'open' || (mode === 'auto' && roomy && !compact));

  useEffect(() => {
    const mq = window.matchMedia('(min-width: 1280px) and (min-height: 760px)');
    const on = () => setRoomy(mq.matches);
    mq.addEventListener('change', on);
    return () => mq.removeEventListener('change', on);
  }, []);
  // Switching between home / place / map goes back to the screen's default.
  useEffect(() => setMode('auto'), [compact]);
  // Tap outside folds a list the player opened (a desktop list that is open by default stays put).
  useEffect(() => {
    if (mode !== 'open') return;
    const onDown = (e: PointerEvent) => {
      const el = todayRef.current;
      if (!el || el.contains(e.target as Node)) return;
      if ((e.target as HTMLElement).closest?.('.bl-sheet-root, .bl-modal-root')) return;
      setMode('auto');
    };
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') setMode('auto'); };
    window.addEventListener('pointerdown', onDown, true);
    window.addEventListener('keydown', onKey);
    return () => { window.removeEventListener('pointerdown', onDown, true); window.removeEventListener('keydown', onKey); };
  }, [mode]);

  const fold = () => { if (mode === 'open') setMode('auto'); };
  const toggle = () => setMode(open ? 'shut' : 'open');

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
    fold();
    if (k === 'hunger' && food) return openPanel('inventory');
    if (k === 'hunger' && !atHome) return openPhone('food');
    const g = NEED_GROUP[k];
    if (atHome && g) pickHome({ id: null, group: g });
    else select(p.location_id);
  };

  const icons = [...tips.map((t) => t.emoji), ...(workAt ? ['💼'] : []), ...(bankAt ? ['🏦'] : []), ...(dadReady ? ['💸'] : []), ...dailyIcons, ...(protectedNow ? ['🛡️'] : [])];
  const shown = icons.slice(0, 4);

  return (
    <div className={`left-rail${clean ? ' is-clean' : ''}${compact ? ' is-compact' : ''}`}>
      <TaskPill state={state} status={status} />
      {!clean && count > 0 && (
        <div className={`today${open ? ' is-open' : ''}`} ref={todayRef}>
          <button type="button" className={`today-pill${ready ? ' is-ready' : ''}`} onClick={toggle} aria-expanded={open}
            aria-controls="today-list" aria-label={`Today: ${count} tip${count === 1 ? '' : 's'}${ready ? ', something to collect' : ''}. ${open ? 'Hide' : 'Show'}`}>
            <span className="today-pill__label">Today</span>
            <span className="today-pill__icons" aria-hidden>
              {shown.map((e, i) => <span key={i} className="today-pill__icon">{e}</span>)}
              {icons.length > shown.length && <span className="today-pill__more">+{icons.length - shown.length}</span>}
            </span>
            {ready && <span className="today-pill__dot" aria-hidden />}
            <Icon name="chevronDown" size={14} stroke={2.6} className="today-pill__chev" />
          </button>
          {open && (
            <div className="today-list" id="today-list">
              {tips.map((t) => (
                <button key={t.key} type="button" className="wish-chip" onClick={() => onTip(t.key)}>
                  <span className="wish-chip__icon" style={{ background: `${NEED_META[t.key].color}22` }} aria-hidden>{t.emoji}</span>
                  <span className="wish-chip__text">
                    <span className="wish-chip__title">{t.text}</span>
                    {t.key === 'hunger' && eatSub && <span className="wish-chip__sub">{eatSub}</span>}
                    <span className="wish-chip__bar"><span style={{ width: `${t.value}%`, background: NEED_META[t.key].color }} /></span>
                  </span>
                </button>
              ))}
              {workAt && job && (
                <button type="button" className="wish-chip wish-chip--work"
                  onClick={() => { fold(); if (workAt !== p.location_id) setMapOpen(true); select(workAt, 'jobs'); }}>
                  <span className="wish-chip__icon" aria-hidden>{job.emoji}</span>
                  <span className="wish-chip__text">
                    <span className="wish-chip__title">Go to work</span>
                    <span className="wish-chip__sub" title={naira(job.pay_per_shift)}>{job.title} · {nairaShort(job.pay_per_shift)}</span>
                  </span>
                </button>
              )}
              {bankAt && (
                <button type="button" className="wish-chip wish-chip--bank"
                  onClick={() => { fold(); if (bankAt.id !== p.location_id) setMapOpen(true); select(bankAt.id, bankAt.tab); }}>
                  <span className="wish-chip__icon" aria-hidden>🏦</span>
                  <span className="wish-chip__text">
                    <span className="wish-chip__title">Bank your cash</span>
                    <span className="wish-chip__sub" title={naira(p.cash)}>{nairaShort(p.cash)} on you at night · {bankAt.name}</span>
                  </span>
                </button>
              )}
              {dadReady && origin && (
                <button type="button" className="wish-chip wish-chip--dad" onClick={() => void claimDad()} disabled={claiming}
                  aria-label={`${ORIGIN_UI.collectDad} (${nairaShort(origin.allowance_daily)})`}>
                  <span className="wish-chip__icon" aria-hidden>💸</span>
                  <span className="wish-chip__text">
                    <span className="wish-chip__title">{ORIGIN_UI.collectDad}</span>
                    <span className="wish-chip__sub" title={naira(origin.allowance_daily)}>{nairaShort(origin.allowance_daily)} from {ORIGIN_UI.dadChip}</span>
                  </span>
                  <span className="daily-dot" aria-hidden />
                </button>
              )}
              <DailyChips onPick={fold} />
              {protectedNow && (
                <div className="wish-chip wish-chip--protect" title="New player protection: nobody can rob you yet">
                  <span className="wish-chip__icon" aria-hidden>🛡️</span>
                  <span className="wish-chip__text">
                    <span className="wish-chip__title">Protected</span>
                    <span className="wish-chip__sub">{countdown(status.protLeft)} left</span>
                  </span>
                </div>
              )}
            </div>
          )}
        </div>
      )}
      {(!compact || open || clean) && (
        <div className="rail-foot">
          <button type="button" className="clean-toggle" onClick={() => setPrefs({ clean: !clean })} aria-pressed={clean}>
            <Icon name={clean ? 'chevronDown' : 'chevronUp'} size={13} stroke={2.6} />
            {clean ? 'Show HUD' : 'Clean screen'}
          </button>
          {!clean && <span className="beta-badge beta-badge--hud" title="Benin Life is in beta: new features land often"><Logo size={14} title="" />Beta</span>}
        </div>
      )}
      <DailySheets />
    </div>
  );
}

export function NeedsCard({ state }: { state: GameState }) {
  const p = useLiveProfile(state.profile);
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
