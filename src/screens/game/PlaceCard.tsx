// L2 place card (docs/PLACES.md): the bottom card while the Sim is inside a place.
// Name · district, a rotating mood line, Share / Map / Home, "Say something out loud…" (location chat),
// zone chips + People N, and the selected zone's action cards (duration, price / Free / Earns ₦, effect
// chips, Risky, why it's locked). Every card goes through the M2 queue: the Sim walks to the zone, then
// the action starts (activities, shifts, purchases); tabs (bank counter, PoS, the whole shop) open the
// place sheet on that tab. The server stays authoritative (hours, cash, night only...).
import { useEffect, useMemo, useRef, useState } from 'react';
import { placeInterior, type PlaceInterior, type PlaceZone, type ZoneAction } from '../../api/places';
import { chatSend } from '../../api/chat';
import { errorMessage, rpc } from '../../lib/api';
import { serverNow } from '../../lib/clock';
import { districtName, naira, nairaShort } from '../../lib/format';
import { activitySeconds, useActionConfig } from '../../lib/live';
import { NEED_META, type NeedKey } from '../../lib/pidgin';
import type { GameState, PanelId, PublicPlayer } from '../../lib/types';
import { usePresenceStore, usePresentAt } from '../../state/presence';
import { useTasks } from '../../state/tasks';
import { useUi } from '../../state/ui';
import { Icon, toast } from '../../ui';
import { placeEmoji } from '../../art/city3d';
import { deriveStatus } from './status';
import { queueTask } from './TaskRunner';

/* ------------------------------------------------------------------ */
/* Data hooks                                                          */
/* ------------------------------------------------------------------ */

/** place_interior for a place; reloads when the place, the hour or `bump` changes. */
export function usePlaceInterior(locationId: string | null, hour: number, bump: unknown) {
  const [data, setData] = useState<PlaceInterior | null>(null);
  const [error, setError] = useState<string | null>(null);
  const hourKey = Math.floor(hour);
  useEffect(() => {
    if (!locationId) return;
    let alive = true;
    placeInterior(locationId)
      .then((d) => {
        if (alive) {
          setData(d);
          setError(null);
        }
      })
      .catch((e) => alive && setError(errorMessage(e)));
    return () => {
      alive = false;
    };
  }, [locationId, hourKey, bump]);
  // drop the old place's data at once when the place changes
  const shown = data && data.location.id === locationId ? data : null;
  return { data: shown, error };
}

/** Real players connected at a place (Realtime Presence ids -> players_here for names), me excluded. */
export function usePlayersAt(locationId: string | null, meId: string): { id: string; username: string }[] {
  const ids = usePresentAt(locationId);
  const live = usePresenceStore((s) => s.online !== null);
  const [list, setList] = useState<PublicPlayer[]>([]);
  useEffect(() => {
    if (!locationId) return;
    let alive = true;
    const t = window.setTimeout(async () => {
      try {
        const r = await rpc<PublicPlayer[]>('players_here', { p_location: locationId });
        if (alive) setList((r ?? []).filter((x) => x.id !== meId));
      } catch {
        if (alive) setList([]);
      }
    }, 250);
    return () => {
      alive = false;
      window.clearTimeout(t);
    };
  }, [locationId, meId, ids]);
  return useMemo(() => {
    const on = new Set(ids);
    return list.filter((p) => !live || on.has(p.id)).map((p) => ({ id: p.id, username: p.username }));
  }, [list, ids, live]);
}

/* ------------------------------------------------------------------ */
/* Card                                                                */
/* ------------------------------------------------------------------ */

const WALK_LABEL = (z: PlaceZone) => {
  const l = z.label.replace(/^the /i, '');
  return /^[A-Z][a-z]+ [A-Z]/.test(l) || /'s\b/.test(l) ? l : `the ${l.charAt(0).toLowerCase()}${l.slice(1)}`;
};

function EffectChips({ effects }: { effects?: Record<string, number> | null }) {
  if (!effects) return null;
  const list = Object.entries(effects).filter(([k, v]) => typeof v === 'number' && v !== 0 && k !== 'bladder').slice(0, 3);
  if (!list.length) return null;
  return (
    <span className="pc-act__fx">
      {list.map(([k, v]) => {
        const meta = (NEED_META as Record<string, (typeof NEED_META)[NeedKey]>)[k];
        const good = meta?.inverted ? v < 0 : v > 0;
        const label = meta ? meta.short : k === 'street_cred' ? 'Street cred' : k.replace(/_/g, ' ');
        return (
          <span key={k} className={`pc-fx${good ? '' : ' is-bad'}`} style={meta ? { ['--fx' as string]: meta.inverted ? '#12924f' : meta.color } : undefined}>
            {v > 0 ? '+' : '−'}{label}
          </span>
        );
      })}
    </span>
  );
}

function ActionCard({ a, zone, state, locId, idle, blocked }: {
  a: ZoneAction; zone: PlaceZone; state: GameState; locId: string; idle: boolean; blocked: string | null;
}) {
  const cfg = useActionConfig();
  const select = useUi((s) => s.select);
  const [armed, setArmed] = useState(false);
  const p = state.profile;
  const secs = a.kind === 'activity' ? Math.round(activitySeconds({ game_minutes: a.game_minutes ?? 30, effects: a.effects ?? null, max_seconds: a.max_seconds, min_seconds: a.min_seconds, scale_by_need: a.scale_by_need }, p, cfg)) : null;
  const car = a.kind === 'shop' && a.category === 'vehicle';
  const cost = a.cost ?? 0;
  const money = car ? p.cash + p.bank : p.cash;
  const broke = (a.kind === 'activity' || a.kind === 'shop') && cost > money;
  const owned = car && (a.owned ?? 0) > 0;
  const lock = a.locked ?? (owned ? 'You own this one' : broke ? (car ? 'Not enough money' : 'Not enough cash') : null) ?? blocked;
  useEffect(() => {
    if (!armed) return;
    const t = window.setTimeout(() => setArmed(false), 4000);
    return () => window.clearTimeout(t);
  }, [armed]);

  const go = () => {
    if (a.kind === 'panel') {
      select(locId, a.ref as PanelId);
      return;
    }
    if (a.kind === 'job' && !a.mine) {
      select(locId, 'jobs');
      return;
    }
    if (lock) {
      toast(lock, 'info');
      return;
    }
    if (car && !armed) {
      setArmed(true);
      return;
    }
    setArmed(false);
    const walkTo = WALK_LABEL(zone);
    if (a.kind === 'job') queueTask({ id: a.ref, name: 'Work a shift' }, locId, { kind: 'shift', zone: zone.key, walkTo, icon: a.icon });
    else if (a.kind === 'shop') queueTask({ id: a.ref, name: `Buy ${a.name}` }, locId, { kind: 'buy', zone: zone.key, walkTo, icon: a.icon, qty: 1 });
    else queueTask({ id: a.ref, name: a.name, home_only: a.home_only }, locId, { zone: zone.key, walkTo, icon: a.icon });
  };

  let price: React.ReactNode = null;
  if (a.kind === 'job') price = a.pay ? <span className="pc-act__earn">Earns {nairaShort(a.pay)}</span> : null;
  else if (a.kind === 'panel') price = null;
  else price = cost > 0 ? <span className="pc-act__price" title={naira(cost)}>{car ? nairaShort(cost) : naira(cost)}</span> : <span className="pc-act__free">Free</span>;

  const verb = a.kind === 'panel' || (a.kind === 'job' && !a.mine) ? 'Choose' : armed ? `Tap again · ${nairaShort(cost)}` : idle ? null : 'Add to queue';
  return (
    <button type="button" className={`pc-act${lock && a.kind !== 'panel' && !(a.kind === 'job' && !a.mine) ? ' is-locked' : ''}${armed ? ' is-armed' : ''}`} onClick={go}
      aria-label={`${a.name}${secs ? `, ${secs} seconds` : ''}${cost ? `, ${naira(cost)}` : ''}${lock ? `, ${lock}` : ''}`}>
      <span className="pc-act__top">
        <span className="pc-act__icon" aria-hidden>{a.icon}</span>
        <span className="pc-act__meta">
          {secs !== null && <span className="pc-act__time"><Icon name="clock" size={11} /> {secs}s</span>}
          {a.risky && <span className="pc-act__risky">Risky</span>}
          {price}
        </span>
      </span>
      <span className="pc-act__name">{a.name}</span>
      {a.kind === 'job' && a.title && <span className="pc-act__sub">{a.mine ? a.title : `Start as ${a.title}`}</span>}
      {car && <span className="pc-act__sub">{owned ? 'In your Bag' : 'Unlocks "Your car" rides'}</span>}
      {a.kind === 'shop' && !car && (a.owned ?? 0) > 0 && <span className="pc-act__sub">{a.owned} in your Bag</span>}
      <EffectChips effects={a.kind === 'activity' || (a.kind === 'shop' && !car) ? a.effects : null} />
      {lock && a.kind !== 'panel' && !(a.kind === 'job' && !a.mine) ? <span className="pc-act__lock">{lock}</span>
        : verb ? <span className="pc-act__verb">{verb} <Icon name="chevronRight" size={12} /></span> : null}
    </button>
  );
}

export interface PlaceCardProps {
  state: GameState;
  data: PlaceInterior | null;
  error: string | null;
  zone: string | null;
  onZone: (key: string | null) => void;
  peopleCount: number;
  moodSeconds: number;
  onMap: () => void;
  onHome: () => void;
  atHome: boolean;
}

export function PlaceCard({ state, data, error, zone, onZone, peopleCount, moodSeconds, onMap, onHome, atHome }: PlaceCardProps) {
  const select = useUi((s) => s.select);
  const loc = state.location;
  const queued = useTasks((s) => (s.current ? 1 : 0) + s.queue.length);
  const [open, setOpen] = useState(true);
  const [say, setSay] = useState('');
  const [sayOpen, setSayOpen] = useState(false);
  const [sending, setSending] = useState(false);
  const status = deriveStatus(state, serverNow());
  const idle = status.free && queued === 0;
  const blocked = status.traveling ? 'On the road' : status.jailLeft > 0 ? 'In jail' : status.hospLeft > 0 ? 'In hospital' : null;

  // rotating mood line (cross-fade); starts on a random line
  const moods = data?.moods ?? [];
  const [mi, setMi] = useState(() => Math.floor(Math.random() * 7));
  useEffect(() => {
    if (moods.length < 2) return;
    const id = window.setInterval(() => setMi((i) => i + 1), Math.max(3, moodSeconds) * 1000);
    return () => window.clearInterval(id);
  }, [moods.length, moodSeconds]);
  const mood = moods.length ? moods[mi % moods.length] : null;

  const zones = data?.zones ?? [];
  const current = zones.find((z) => z.key === zone) ?? null;
  const chipsRef = useRef<HTMLDivElement>(null);
  useEffect(() => {
    // keep the picked chip in view (tapping a zone in 3D)
    if (!zone || !chipsRef.current) return;
    const el = chipsRef.current.querySelector<HTMLElement>(`[data-zone="${CSS.escape(zone)}"]`);
    el?.scrollIntoView({ block: 'nearest', inline: 'nearest', behavior: 'smooth' });
  }, [zone]);

  const share = async () => {
    const text = `Meet me at ${loc.name} in Benin Life!`;
    try {
      if (navigator.share) await navigator.share({ title: loc.name, text, url: `${location.origin}/play` });
      else {
        await navigator.clipboard.writeText(`${text} ${location.origin}/play`);
        toast('Link copied. Send it to a friend!', 'good');
      }
    } catch {
      /* cancelled */
    }
  };
  const send = async () => {
    const body = say.trim();
    if (!body || sending) return;
    setSending(true);
    try {
      await chatSend(body);
      setSay('');
      toast('Said out loud at ' + loc.name.replace(/\s*\(.*\)\s*$/, ''), 'info');
    } catch (e) {
      toast(errorMessage(e), 'bad');
    } finally {
      setSending(false);
    }
  };

  const name = loc.name.replace(/\s*\(.*\)\s*$/, '');
  return (
    <section className={`place-card${open ? ' is-open' : ''}`} aria-label={`Inside ${loc.name}`}>
      <header className="place-card__head">
        <span className="place-card__emoji" aria-hidden>{placeEmoji(loc)}</span>
        <div className="place-card__title">
          <h2><span className="place-card__name">{name}</span> <span className="place-card__district">· {districtName(loc.district)}</span></h2>
          <p className="place-card__mood" key={mi} aria-live="polite">
            {data && !data.open ? <><span aria-hidden>🔒</span> Closed now · {data.opens}{data.hours ? ` (open ${data.hours})` : ''}</>
              : mood ? <><span aria-hidden>{mood.icon}</span> {mood.line}</> : <span className="muted">{loc.blurb}</span>}
          </p>
        </div>
        <div className="place-card__btns">
          <button type="button" className="pc-iconbtn pc-iconbtn--say" onClick={() => setSayOpen((o) => !o)} aria-label="Say something out loud" aria-expanded={sayOpen} title="Say something"><Icon name="chat" size={17} /></button>
          <button type="button" className="pc-iconbtn" onClick={() => void share()} aria-label="Share this place" title="Share"><Icon name="mail" size={17} /></button>
          <button type="button" className="pc-iconbtn" onClick={onMap} aria-label="Open the map" title="Map"><Icon name="map" size={17} /></button>
          <button type="button" className="pc-iconbtn" onClick={onHome} aria-label={atHome ? 'Home' : 'Go home'} title="Home"><Icon name="home" size={17} /></button>
        </div>
      </header>

      {open && (
        <form className={`place-card__say${sayOpen ? ' is-open' : ''}`} onSubmit={(e) => { e.preventDefault(); void send(); }}>
          <input value={say} autoFocus={sayOpen} onChange={(e) => setSay(e.target.value)} maxLength={280} enterKeyHint="send"
            placeholder={peopleCount > 1 ? `Say something to the ${peopleCount} people here…` : 'Say something out loud…'} aria-label="Say something out loud" />
          <button type="submit" className="pc-send" disabled={!say.trim() || sending} aria-label="Send"><Icon name="chevronRight" size={18} /></button>
        </form>
      )}

      <div className="place-card__chips" ref={chipsRef} role="tablist" aria-label="Zones">
        <button type="button" className="pc-fold" onClick={() => setOpen((o) => !o)} aria-label={open ? 'Fold the card' : 'Show the actions'} aria-expanded={open}>
          <Icon name={open ? 'chevronDown' : 'chevronUp'} size={16} />
        </button>
        {!data && !error && <span className="pc-chip is-skel" aria-hidden>Loading…</span>}
        {error && <span className="pc-chip is-skel">{error}</span>}
        {zones.map((z) => (
          <button key={z.key} type="button" role="tab" aria-selected={z.key === zone} data-zone={z.key}
            className={`pc-chip${z.key === zone ? ' is-on' : ''}`}
            onClick={() => { if (z.key === zone && open) setOpen(false); else { onZone(z.key); setOpen(true); } }}>
            <span aria-hidden>{z.icon}</span> {z.label}
          </button>
        ))}
        <button type="button" className="pc-chip is-people" onClick={() => select(loc.id)} aria-label={`People here: ${peopleCount}. Open the place sheet`}>
          <span aria-hidden>👥</span> People <b>{peopleCount}</b>
        </button>
      </div>

      {open && current && (
        <div className="place-card__acts" key={current.key}>
          {current.actions.map((a) => (
            <ActionCard key={a.id} a={a} zone={current} state={state} locId={loc.id} idle={idle} blocked={blocked} />
          ))}
        </div>
      )}
      {open && current?.note && <p className="place-card__note"><span aria-hidden>🎩</span> {current.note}</p>}
      {open && current && current.actions.length === 0 && (
        <p className="place-card__hint">Nothing to do here right now. Tap the floor to walk around.</p>
      )}
    </section>
  );
}
