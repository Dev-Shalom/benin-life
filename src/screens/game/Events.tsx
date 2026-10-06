// L4 events UI (docs/EVENTS.md): the "On today" cards (map place sheet + people sheet) and the slim top banner
// for LIVE / upcoming events. Data: src/state/events.ts (events_on_today, server-computed in WAT).
import { useEffect, useMemo, useState } from 'react';
import { buyTicket, type PlaceEvent } from '../../api/events';
import { errorMessage } from '../../lib/api';
import { useConfig } from '../../lib/config';
import { useNow } from '../../lib/clock';
import { naira } from '../../lib/format';
import { current, dismissEvent, occKey, patchEvent, reloadEvents, startsIn, useEvents } from '../../state/events';
import { useGame } from '../../state/game';
import { useHype } from '../../state/hype';
import { Icon, toast } from '../../ui';

/** Today's events at one place, live-flag kept fresh. */
export function useEventsAt(locId: string | null | undefined): PlaceEvent[] {
  const list = useEvents((s) => s.list);
  const now = useNow(15_000);
  return useMemo(() => (locId ? current(list, now).filter((e) => e.location_id === locId) : []), [list, now, locId]);
}

/** Map pin badges: place id -> 'live' | 'today'. */
export function useEventBadges(): Record<string, 'live' | 'today'> {
  const list = useEvents((s) => s.list);
  const now = useNow(30_000);
  return useMemo(() => {
    const o: Record<string, 'live' | 'today'> = {};
    for (const e of current(list, now)) if (e.live || !o[e.location_id]) o[e.location_id] = e.live ? 'live' : 'today';
    return o;
  }, [list, now]);
}

export function OnToday({ locId, title = 'On today' }: { locId: string; title?: string }) {
  const events = useEventsAt(locId);
  if (!events.length) return null;
  return (
    <section className="ev-today" aria-label={title}>
      <h4 className="ev-today__title">{title}</h4>
      <div className="ev-today__list">
        {events.map((e) => <EventCard key={occKey(e)} e={e} />)}
      </div>
    </section>
  );
}

function EventCard({ e }: { e: PlaceEvent }) {
  const refresh = useGame((s) => s.refresh);
  const profile = useGame((s) => s.state?.profile);
  const [busy, setBusy] = useState(false);
  const now = useNow(30_000);
  const soldOut = e.capacity !== null && e.sold >= e.capacity && !e.has_ticket;
  const money = (profile?.cash ?? 0) + (profile?.bank ?? 0);
  const broke = !e.free && !e.has_ticket && money < e.ticket_price;
  const left = e.capacity !== null ? e.capacity - e.sold : null;

  const buy = async () => {
    setBusy(true);
    try {
      const r = await buyTicket(e.id);
      if (r.event) patchEvent(r.event);
      toast(r.message, 'good');
      void refresh();
    } catch (err) {
      toast(errorMessage(err), 'bad');
      void reloadEvents();
    } finally {
      setBusy(false);
    }
  };

  return (
    <article className={`ev-card${e.live ? ' is-live' : ''}`}>
      <div className="ev-card__top">
        <span className="ev-card__icon" aria-hidden>{e.icon}</span>
        <div className="ev-card__main">
          <div className="ev-card__when">
            {e.live ? <span className="ev-live"><span className="ev-live__dot" aria-hidden />LIVE</span>
              : <span className="ev-soon">Starts {startsIn(e, now)}</span>}
            <span className="ev-card__time">{e.time_label}</span>
          </div>
          <h5 className="ev-card__name">{e.title}</h5>
          {e.description && <p className="ev-card__desc">{e.description}</p>}
          {e.actions.length > 0 && (
            <p className="ev-card__perks"><span className="muted">Inside:</span> {e.actions.join(' · ')}</p>
          )}
        </div>
      </div>
      <div className="ev-card__foot">
        <span className="ev-card__price">
          {e.free ? 'Free entry' : naira(e.ticket_price)}
          {left !== null && !e.free && left <= 50 && left > 0 && <span className="ev-card__left"> · {left} left</span>}
        </span>
        {e.free ? (
          <span className="ev-card__ok"><Icon name="check" size={14} /> No ticket needed</span>
        ) : e.has_ticket ? (
          <span className="ev-card__ok"><Icon name="check" size={14} /> You have a ticket</span>
        ) : (
          <button type="button" className="ev-buy" onClick={() => void buy()} disabled={busy || soldOut || broke}
            aria-busy={busy || undefined} title={broke ? 'Not enough money (bank + cash)' : undefined}>
            {soldOut ? 'Sold out' : broke ? 'Not enough money' : busy ? 'Buying…' : <>Buy ticket <span aria-hidden>🎟️</span></>}
          </button>
        )}
      </div>
    </article>
  );
}

/**
 * The slim top banner: "LIVE: Bendel Insurance vs Enyimba at Ogbemudia Stadium" / "Amapiano Night at
 * 360 Signature starts in 2h". Rotates every 6 s when several, × closes one for this session, tap opens the
 * place's sheet. The P2 hype ticker has the same slot and wins: the banner hides while a ticker shows.
 */
export function EventBanner({ top, hereId, onOpen }: { top: number; hereId: string | null; onOpen: (locId: string) => void }) {
  const { cfg } = useConfig();
  const enabled = cfg<boolean>('events.banner_enabled', true as boolean) !== false;
  const lead = Math.max(0, Number(cfg('events.banner_lead_hours', 3)) || 0);
  const list = useEvents((s) => s.list);
  const dismissed = useEvents((s) => s.dismissed);
  const ticker = useHype((s) => s.ticker);
  const hypeBanner = useHype((s) => s.banner);
  const now = useNow(15_000);
  const items = useMemo(
    () => current(list, now)
      .filter((e) => !dismissed.includes(occKey(e)) && e.location_id !== hereId
        && (e.live || Date.parse(e.starts_at) - now <= lead * 3_600_000))
      .sort((a, b) => Number(b.live) - Number(a.live) || Date.parse(a.starts_at) - Date.parse(b.starts_at)),
    [list, now, dismissed, lead, hereId],
  );
  const [i, setI] = useState(0);
  useEffect(() => {
    if (items.length < 2) return;
    const id = window.setInterval(() => setI((n) => n + 1), 6000);
    return () => window.clearInterval(id);
  }, [items.length]);
  if (!enabled || ticker || hypeBanner || !items.length) return null;
  const e = items[i % items.length];
  const place = e.location_name.replace(/\s*\(.*\)\s*$/, '');
  return (
    <div className="ev-banner-wrap" style={{ top }}>
      <div className={`ev-banner${e.live ? ' is-live' : ''}`} key={occKey(e)}>
        <button type="button" className="ev-banner__main" onClick={() => onOpen(e.location_id)}
          aria-label={`${e.live ? 'Live now' : 'Coming up'}: ${e.title} at ${place}. Open the place`}>
          {e.live ? <span className="ev-live"><span className="ev-live__dot" aria-hidden />LIVE</span>
            : <span className="ev-banner__icon" aria-hidden>{e.icon}</span>}
          <span className="ev-banner__text">
            {e.live ? <><b>{e.title}</b> at {place}</> : <><b>{e.title}</b> at {place} starts {startsIn(e, now)}</>}
          </span>
          {items.length > 1 && <span className="ev-banner__count" aria-hidden>{(i % items.length) + 1}/{items.length}</span>}
        </button>
        <button type="button" className="ev-banner__x" onClick={() => dismissEvent(e)} aria-label="Hide this event">
          <Icon name="close" size={14} />
        </button>
      </div>
    </div>
  );
}
