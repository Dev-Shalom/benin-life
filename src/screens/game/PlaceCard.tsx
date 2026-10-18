// L2 place card (docs/PLACES.md): the bottom card while the Sim is inside a place.
// Name · district, a rotating mood line, Share / Map / Home, "Say something out loud…" (location chat),
// zone chips + People N, and the selected zone's action cards (duration, price / Free / Earns ₦, effect
// chips, Risky, why it's locked). Every card goes through the M2 queue: the Sim walks to the zone, then
// the action starts (activities, shifts, purchases); tabs (bank counter, PoS, the whole shop) open the
// place sheet on that tab. The server stays authoritative (hours, cash, night only...).
import { LoungeStrip } from './Lounge';
import { BusinessStrip } from './BusinessStrip';
import { useLounge } from '../../state/lounge';
import { useEffect, useMemo, useRef, useState } from 'react';
import { placeInterior, placePeople, type PlaceInterior, type PlaceNpc, type PlacePeople, type PlaceZone, type ZoneAction } from '../../api/places';
import { chatSend } from '../../api/chat';
import { SocialPlayerButton } from './SocialPlayerButton';
import { errorMessage, rpc } from '../../lib/api';
import { serverNow } from '../../lib/clock';
import { districtName, naira, nairaShort } from '../../lib/format';
import { activitySeconds, useActionConfig } from '../../lib/live';
import { NEED_META, type NeedKey } from '../../lib/pidgin';
import type { AvatarConfig, GameState, PanelId, PublicPlayer } from '../../lib/types';
import { usePresenceLiveAt, usePresentAt } from '../../state/presence';
import { useTasks } from '../../state/tasks';
import { useUi } from '../../state/ui';
import { Icon, Sheet, toast } from '../../ui';
import { AvatarPortrait } from '../../art/avatar3d';
import { npcAvatar } from '../../art/place3d/model';
import { placeEmoji } from '../../art/city3d';
import { deriveStatus } from './status';
import { queueTask } from './TaskRunner';
import { useShrine } from '../../state/shrine';
import { hustleBuy } from '../../api/hustles';
import { useGame } from '../../state/game';
import { useHustles } from '../../state/hustles';
import { courseEnrol } from '../../api/school';
import { useSchool } from '../../state/school';
import { useSpray } from '../../state/spray';
import { getCfg } from '../../lib/config';

/** B2 offering icons for the shrine cards (same as the items' icons). */
const OFFER_ICON: Record<string, string> = {
  kola_nut: '🌰', alligator_pepper: '🌶️', cowries: '🐚', white_cloth: '🏳️', palm_oil: '🫙', schnapps: '🍾', white_chicken: '🐓', goat: '🐐', cow: '🐄',
};

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

/**
 * L3: the named background people at a place this hour (place_people). undefined while loading, null when the
 * call failed (the 3D then falls back to unnamed people). `hour` = the visual hour override (dev) or null = now.
 */
export function usePlacePeople(locationId: string | null, hourKey: number, override: number | null): PlacePeople | null | undefined {
  const [data, setData] = useState<PlacePeople | null | undefined>(undefined);
  useEffect(() => {
    if (!locationId) return;
    let alive = true;
    placePeople(locationId, override == null ? null : ((Math.floor(override) % 24) + 24) % 24)
      .then((d) => alive && setData(d))
      .catch(() => alive && setData(null));
    return () => {
      alive = false;
    };
  }, [locationId, hourKey, override]);
  return data && data.location !== locationId ? undefined : data;
}

/** Real players connected at a place (Realtime Presence ids -> players_here for names), me excluded. */
export function usePlayersAt(locationId: string | null, meId: string): { id: string; username: string; avatar: PublicPlayer['avatar'] | null; gold?: boolean }[] {
  const ids = usePresentAt(locationId);
  const live = usePresenceLiveAt(locationId);
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
    return list.filter((p) => !live || on.has(p.id)).map((p) => ({ id: p.id, username: p.username, avatar: p.avatar ?? null, gold: Boolean((p as { gold?: boolean }).gold) }));
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
  const shrine = a.kind === 'shrine';
  const hustle = a.kind === 'hustle';
  // R4: a course card: 'new' = instant Enrol (pays the fee), 'enrolled' = a class that queues like any action, 'completed'
  const klass = a.kind === 'class';
  const klassNew = klass && a.class_state === 'new';
  // SP1: the spray card opens the Spray money sheet (choose the amount); VIP section = VIP spray
  const spray = a.kind === 'activity' && a.ref === 'spray_money';
  const sprayVip = spray && zone.key === 'vip';
  const sprayMin = Number(getCfg(sprayVip ? 'club.vip_spray_min' : 'club.spray_min', sprayVip ? 100000 : 1000)) || 1000;
  const secs = spray ? null : shrine || (hustle && !a.instant) || (klass && !klassNew) ? (a.seconds ?? null) : a.kind === 'activity' ? Math.round(activitySeconds({ game_minutes: a.game_minutes ?? 30, effects: a.effects ?? null, max_seconds: a.max_seconds, min_seconds: a.min_seconds, scale_by_need: a.scale_by_need }, p, cfg)) : null;
  const car = a.kind === 'shop' && a.category === 'vehicle';
  const cost = a.cost ?? 0;
  const money = car || hustle || klass ? p.cash + p.bank : p.cash;
  const broke = (a.kind === 'activity' || a.kind === 'shop' || shrine || hustle || klassNew) && (spray ? sprayMin > money : cost > money);
  const owned = car && (a.owned ?? 0) > 0;
  // B2: a charm of that kind still works / offerings missing from the Bag
  const missing = shrine ? (a.missing ?? []) : [];
  const charmLock = shrine && a.charm_until ? (a.ref === 'money_charm' ? 'You carry one already' : 'Your charm is still working') : null;
  const lock = a.locked ?? (owned ? 'You own this one' : charmLock ?? (missing.length ? `Missing ${missing.map((m) => `${m.need - m.have} ${m.name.toLowerCase()}`).join(', ')}`
    : broke ? (car ? 'Not enough money' : 'Not enough cash') : null)) ?? blocked;
  const cooling = hustle && a.cooldown_until && Date.parse(a.cooldown_until) > serverNow();
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
    if (spray && (!lock || (broke && lock === 'Not enough cash'))) {
      useSpray.getState().show(locId, sprayVip);
      return;
    }
    // B2: a locked shrine card opens Baba's tab on that service (what is missing, time left)
    if (shrine && lock && lock !== blocked) {
      useShrine.getState().setFocus(a.ref);
      select(locId, 'babalawo');
      return;
    }
    if (a.kind === 'job' && !a.mine) {
      select(locId, 'jobs');
      return;
    }
    // E2: stall rent / car service are instant buys; other hustles line up like any action
    if (hustle && !lock) {
      if (a.instant) {
        void hustleBuy(a.ref).then((r) => { toast(r.message, 'good'); void useGame.getState().refresh(); void useHustles.getState().load(); }).catch((e) => toast(errorMessage(e), 'bad'));
        return;
      }
    }
    // R4: enrol (instant buy) or attend a class
    if (klassNew && !lock) {
      void courseEnrol(a.ref).then((r) => { toast(r.message, 'good'); void useGame.getState().refresh(); void useSchool.getState().load(); })
        .catch((e) => toast(errorMessage(e), 'bad'));
      return;
    }
    // R7: a lounge card without a pass opens the membership sheet
    if (lock === 'Members only') {
      useLounge.getState().show();
      return;
    }
    if (lock) {
      // L4: an event card without a ticket opens the place sheet (On today → Buy ticket)
      if (a.event?.state === 'ticket') {
        select(locId);
        return;
      }
      toast(lock, 'info');
      return;
    }
    if ((car || shrine) && !armed) {
      setArmed(true);
      return;
    }
    setArmed(false);
    const walkTo = WALK_LABEL(zone);
    if (shrine) queueTask({ id: a.ref, name: a.name }, locId, { kind: 'shrine', zone: zone.key, walkTo, icon: a.icon });
    else if (hustle) queueTask({ id: a.ref, name: a.name }, locId, { kind: 'hustle', zone: zone.key, walkTo, icon: a.icon });
    else if (klass) queueTask({ id: a.ref, name: a.name }, locId, { kind: 'class', zone: zone.key, walkTo, icon: a.icon });
    else if (a.kind === 'job') queueTask({ id: a.ref, name: 'Work a shift' }, locId, { kind: 'shift', zone: zone.key, walkTo, icon: a.icon });
    else if (a.kind === 'shop') queueTask({ id: a.ref, name: `Buy ${a.name}` }, locId, { kind: 'buy', zone: zone.key, walkTo, icon: a.icon, qty: 1 });
    else queueTask({ id: a.ref, name: a.name, home_only: a.home_only }, locId, { zone: zone.key, walkTo, icon: a.icon });
  };

  let price: React.ReactNode = null;
  if (a.kind === 'job') price = a.pay ? <span className="pc-act__earn">Earns {nairaShort(a.pay)}</span> : null;
  else if (a.kind === 'panel') price = null;
  else if (hustle) price = a.instant ? <span className="pc-act__price" title={naira(cost)}>{naira(cost)}</span>
    : (a.pay_max ?? 0) > 0 ? <span className="pc-act__earn" title={`${naira(a.pay_min ?? 0)} to ${naira(a.pay_max ?? 0)}`}>Earns {nairaShort(a.pay_min ?? 0)}–{nairaShort(a.pay_max ?? 0)}</span>
    : <span className="pc-act__earn">Catch fish</span>;
  else if (klass) price = klassNew ? <span className="pc-act__price" title={naira(cost)}>Enrol {naira(cost)}</span>
    : a.class_state === 'completed' ? <span className="pc-act__free">Certified</span> : <span className="pc-act__earn">Class {Math.min((a.done ?? 0) + 1, a.classes ?? 1)}/{a.classes}</span>;
  else if (spray) price = <span className="pc-act__price" title={`From ${naira(sprayMin)}`}>From {nairaShort(sprayMin)}</span>;
  else price = cost > 0 ? <span className="pc-act__price" title={naira(cost)}>{car || (shrine && cost >= 100000) ? nairaShort(cost) : naira(cost)}</span> : <span className="pc-act__free">Free</span>;

  const verb = spray ? 'Choose amount' : a.kind === 'panel' || (a.kind === 'job' && !a.mine) ? 'Choose' : hustle && a.instant ? 'Tap to buy' : klassNew ? 'Tap to enrol' : klass && a.class_state === 'completed' ? null : armed ? `Tap again · ${nairaShort(cost)}` : idle ? null : 'Add to queue';
  return (
    <button type="button" className={`pc-act${a.event ? ' is-event' : ''}${lock && a.kind !== 'panel' && !(a.kind === 'job' && !a.mine) ? ' is-locked' : ''}${armed ? ' is-armed' : ''}`} onClick={go}
      aria-label={`${a.name}${secs ? `, ${secs} seconds` : ''}${spray ? `, from ${naira(sprayMin)}` : cost ? `, ${naira(cost)}` : ''}${lock ? `, ${lock}` : ''}`}>
      <span className="pc-act__top">
        <span className="pc-act__icon" aria-hidden>{a.icon}</span>
        <span className="pc-act__meta">
          {secs !== null && <span className="pc-act__time"><Icon name="clock" size={11} /> {secs}s</span>}
          {a.risky && <span className="pc-act__risky">Risky</span>}
          {a.weekend && cost > 0 && !spray && <span className="pc-act__weekend" title="Friday and Saturday nights cost more at the clubs">Weekend price</span>}
          {price}
        </span>
      </span>
      {a.event && <span className={`pc-act__event${a.event.state === 'ok' ? ' is-on' : ''}`}>{a.event.state === 'later' ? 'Event' : 'LIVE'} · {a.event.title}</span>}
      <span className="pc-act__name">{a.name}</span>
      {a.kind === 'job' && a.title && <span className="pc-act__sub">{a.mine ? a.title : `Start as ${a.title}`}</span>}
      {car && <span className="pc-act__sub">{owned ? 'In your Bag' : 'Unlocks "Your car" rides'}</span>}
      {hustle && !a.instant && (cost > 0 || a.cap_left != null) && (
        <span className="pc-act__sub">{cost > 0 ? `Costs ${naira(cost)}` : 'No cost'}{a.cap_left != null ? ` · ${a.cap_left} left today` : ''}{cooling ? ' · cooling down' : ''}</span>
      )}
      {klass && (
        <span className="pc-act__sub">
          {a.class_state === 'completed' ? `${a.cert_name ?? 'Certificate'} earned` : `${a.done ?? 0}/${a.classes} classes${a.module ? ` · ${a.module}` : ''}${a.exam_next ? ' · exam today' : ''}`}
        </span>
      )}
      {klass && a.class_state !== 'completed' && a.class_skill && <span className="pc-act__sub pc-act__skill">{a.class_skill.icon} +{a.class_skill.xp} {a.class_skill.name} XP a class{a.cert_name ? ` · ${a.cert_name} certificate` : ''}</span>}
      {hustle && a.cert_bonus_pct != null && a.cert_bonus_pct > 0 && !a.instant && <span className="pc-act__sub pc-act__skill">🎓 +{Math.round(a.cert_bonus_pct)}% from certificate</span>}
      {hustle && !a.instant && !lock && a.skill && a.skill.pay_boost_pct > 0 && <span className="pc-act__sub pc-act__skill">{a.skill.icon} +{Math.round(a.skill.pay_boost_pct)}% from skill</span>}
      {hustle && a.note && !lock && <span className="pc-act__sub">{a.note}</span>}
      {a.kind === 'shop' && !car && (a.owned ?? 0) > 0 && <span className="pc-act__sub">{a.owned} in your Bag</span>}
      {shrine && a.effect && <span className="pc-act__sub">{a.effect} · {a.duration}</span>}
      {shrine && a.offerings && (
        <span className="pc-act__fx pc-act__offer" aria-label="Offerings">
          {Object.entries(a.offerings).map(([id, n]) => (
            <span key={id} className={`pc-fx${missing.some((m) => m.item === id) ? ' is-bad' : ''}`}>{OFFER_ICON[id] ?? '🎁'}×{n}</span>
          ))}
        </span>
      )}
      <EffectChips effects={a.kind === 'activity' || (a.kind === 'shop' && !car) ? a.effects : null} />
      {lock && a.event?.state === 'ticket' ? <span className="pc-act__verb">Buy a ticket ({naira(a.event.price)}) <Icon name="chevronRight" size={12} /></span>
        : lock && a.kind !== 'panel' && !(a.kind === 'job' && !a.mine) ? <span className="pc-act__lock">{lock}</span>
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
  /** L3 People list: players here (me excluded), the named people present, and everyone counted. */
  players?: { id: string; username: string; avatar: AvatarConfig | null }[];
  npcs?: PlaceNpc[];
  me?: { username: string; avatar: AvatarConfig };
}

/** L3 "People N": real players first (portraits), then the people present with their role and a line. */
function PeopleSheet({ open, onClose, total, players, npcs, me, placeName, onSheet }: {
  open: boolean; onClose: () => void; total: number; players: NonNullable<PlaceCardProps['players']>; npcs: PlaceNpc[];
  me?: PlaceCardProps['me']; placeName: string; onSheet: () => void;
}) {
  const looks = useMemo(() => new Map(npcs.map((n) => [n.id, npcAvatar(n.avatar)])), [npcs]);
  const [talking, setTalking] = useState<PlaceNpc | null>(null);
  const [reply, setReply] = useState<string | null>(null);
  useEffect(() => {
    const onTalk = (e: Event) => {
      const id = (e as CustomEvent<{ id: string }>).detail?.id;
      const npc = npcs.find((person) => person.id === id);
      if (npc) { setTalking(npc); setReply(null); }
    };
    window.addEventListener('bl:npc-talk', onTalk);
    return () => window.removeEventListener('bl:npc-talk', onTalk);
  }, [npcs]);
  const more = Math.max(0, total - players.length - npcs.length - (me ? 1 : 0));
  const speak = (id: string) => {
    const npc = npcs.find((n) => n.id === id);
    if (npc) { setTalking(npc); setReply(null); }
    onClose();
    window.setTimeout(() => window.dispatchEvent(new CustomEvent('bl:npc-say', { detail: { id } })), 120);
  };
  const talk = (kind: 'hello' | 'day' | 'tip') => {
    if (!talking) return;
    const role = talking.role.toLowerCase();
    const response = kind === 'hello'
      ? `“${talking.line || 'You’re welcome here. How your day dey go?'}”`
      : kind === 'day'
        ? `“${talking.name} says the day has been ${role.includes('trader') || role.includes('seller') ? 'busy with customers' : 'moving at its own pace'}. ${talking.line || 'Make you take am easy.'}”`
        : `“For around here, ask someone local before you move. ${talking.line || 'You go find your way.'}”`;
    setReply(response);
  };
  return (
    <>
      <Sheet open={open} onClose={onClose} title={`People here · ${total}`} subtitle={placeName} size="tall"
        footer={<button type="button" className="bl-btn bl-btn--ghost" onClick={() => { onClose(); onSheet(); }}>Place details &amp; chat</button>}>
        <div className="people-list">
        <h3 className="people-list__h">Players</h3>
        {me && (
          <div className="people-row">
            <span className="people-row__av"><AvatarPortrait config={me.avatar} size={40} /></span>
            <span className="people-row__main"><span className="people-row__name"><span className="people-row__dot" aria-hidden />@{me.username} (you)</span></span>
          </div>
        )}
        {players.map((pl) => (
          <div key={pl.id} className="people-row">
            <span className="people-row__av">{pl.avatar ? <AvatarPortrait config={pl.avatar} size={40} /> : '🙂'}</span>
            <span className="people-row__main"><span className="people-row__name"><span className="people-row__dot" aria-label="online" />@{pl.username}</span></span>
            <SocialPlayerButton userId={pl.id} />
          </div>
        ))}
        {!players.length && <p className="people-row__role">No other players here right now. Share the place to bring friends.</p>}
        {npcs.length > 0 && <h3 className="people-list__h">Around you</h3>}
        {npcs.map((n) => (
          <button key={n.id} type="button" className="people-row" onClick={() => speak(n.id)} aria-label={`${n.name}, ${n.role}. Tap to talk`}>
            <span className="people-row__av"><AvatarPortrait config={looks.get(n.id)!} size={40} /></span>
            <span className="people-row__main">
              <span className="people-row__name">{n.name} <span className="people-row__role">· {n.role}</span></span>
              {n.line && <span className="people-row__line">“{n.line}”</span>}
            </span>
          </button>
        ))}
        {more > 0 && <p className="people-list__more">+{more} more people here</p>}
        </div>
      </Sheet>
      <Sheet open={Boolean(talking)} onClose={() => { setTalking(null); setReply(null); }}
        title={talking ? `Chat with ${talking.name}` : 'Chat'} subtitle={talking?.role}>
        {talking && <div className="npc-dialogue">
          <p className="npc-dialogue__line">{talking.line ? `“${talking.line}”` : `${talking.name} looks over and greets you.`}</p>
          {reply ? <><p className="npc-dialogue__reply">{reply}</p><button type="button" className="bl-btn bl-btn--ghost" onClick={() => { setTalking(null); setReply(null); }}>Finish chat</button></>
            : <div className="npc-dialogue__choices">
              <button type="button" className="bl-btn bl-btn--green" onClick={() => talk('hello')}>Say hello</button>
              <button type="button" className="bl-btn bl-btn--green" onClick={() => talk('day')}>Ask how their day is</button>
              <button type="button" className="bl-btn bl-btn--green" onClick={() => talk('tip')}>Ask for a local tip</button>
            </div>}
          <small>NPC conversations are roleplay. For live player chat, open the place Chat tab.</small>
        </div>}
      </Sheet>
    </>
  );
}

export function PlaceCard({ state, data, error, zone, onZone, peopleCount, moodSeconds, onMap, onHome, atHome, players = [], npcs = [], me }: PlaceCardProps) {
  const select = useUi((s) => s.select);
  const [peopleOpen, setPeopleOpen] = useState(false);
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
  // L4: an event on here today → a strip that jumps to its zone (event-only cards)
  const evZone = zones.find((z) => z.actions.some((a) => a.event));
  const evAct = evZone?.actions.find((a) => a.event);
  const evLive = data?.events?.find((e) => e.live) ?? data?.events?.[0];
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
    <section className={`place-card${open ? ' is-open' : ''}`} aria-label={`Inside ${loc.name}`} data-tour="place-card">
      <header className="place-card__head">
        <span className="place-card__emoji" aria-hidden>{placeEmoji(loc)}</span>
        <div className="place-card__title">
          <h2><span className="place-card__name">{name}</span> <span className="place-card__district">· {districtName(loc.district)}</span></h2>
          <p className="place-card__mood" key={mi} aria-live="polite">
            {data && data.active === false ? <><span aria-hidden>🔒</span> Closed for now · check back soon</>
              : data && !data.open ? <><span aria-hidden>🔒</span> Closed now · {data.opens}{data.hours ? ` (open ${data.hours})` : ''}</>
              : mood ? <><span aria-hidden>{mood.icon}</span> {mood.line}</> : <span className="muted">{loc.blurb}</span>}
          </p>
        </div>
        <div className="place-card__btns">
          <button type="button" className="pc-iconbtn pc-iconbtn--say" data-tour="place-say" onClick={() => setSayOpen((o) => !o)} aria-label="Say something out loud" aria-expanded={sayOpen} title="Say something"><Icon name="chat" size={17} /></button>
          <button type="button" className="pc-iconbtn" onClick={() => void share()} aria-label="Share this place" title="Share"><Icon name="mail" size={17} /></button>
          <button type="button" className="pc-iconbtn" onClick={onMap} aria-label="Open the map" title="Map"><Icon name="map" size={17} /></button>
          <button type="button" className="pc-iconbtn" onClick={onHome} aria-label={atHome ? 'Home' : 'Go home'} title="Home"><Icon name="home" size={17} /></button>
        </div>
      </header>

      {open && (
        <form className={`place-card__say${sayOpen ? ' is-open' : ''}`} data-tour="place-say-box" onSubmit={(e) => { e.preventDefault(); void send(); }}>
          <input value={say} autoFocus={sayOpen} onChange={(e) => setSay(e.target.value)} maxLength={280} enterKeyHint="send"
            placeholder={peopleCount > 1 ? `Say something to the ${peopleCount} people here…` : 'Say something out loud…'} aria-label="Say something out loud" />
          <button type="submit" className="pc-send" disabled={!say.trim() || sending} aria-label="Send"><Icon name="chevronRight" size={18} /></button>
        </form>
      )}

      {evLive && (
        <button type="button" className={`pc-event${evLive.live ? ' is-live' : ''}`}
          onClick={() => { if (evZone) { onZone(evZone.key); setOpen(true); } else select(loc.id); }}>
          {evLive.live ? <span className="ev-live"><span className="ev-live__dot" aria-hidden />LIVE</span> : <span aria-hidden>{evLive.icon}</span>}
          <span className="pc-event__text"><b>{evLive.title}</b> {evLive.live ? '' : `· ${evLive.starts_label}`}</span>
          <span className="pc-event__go">{evAct ? `${evAct.icon} ${evZone?.label}` : 'Tickets'} <Icon name="chevronRight" size={12} /></span>
        </button>
      )}
      <div className="place-card__chips" ref={chipsRef} role="tablist" aria-label="Zones" data-tour="place-zones">
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
        <button type="button" className="pc-chip is-people" onClick={() => setPeopleOpen(true)} aria-label={`People here: ${peopleCount}. Open the people list`}>
          <span aria-hidden>👥</span> People <b>{peopleCount}</b>
        </button>
      </div>

      {open && current && (
        <div className="place-card__acts" key={current.key} data-tour="place-acts">
          {current.actions.map((a) => (
            <ActionCard key={a.id} a={a} zone={current} state={state} locId={loc.id} idle={idle} blocked={blocked} />
          ))}
        </div>
      )}
      <PeopleSheet open={peopleOpen} onClose={() => setPeopleOpen(false)} total={peopleCount} players={players} npcs={npcs} me={me}
        placeName={name} onSheet={() => select(loc.id)} />
      {open && current?.note && <p className="place-card__note"><span aria-hidden>{data?.location.scene === 'shrine' ? current.icon : '🎩'}</span> {current.note}</p>}
      {open && data?.lounge && <LoungeStrip card={data.lounge} />}
      {open && <BusinessStrip locId={loc.id} />}
      {open && data?.open && data.weekend_price && <p className="place-card__note"><span aria-hidden>🥂</span> Weekend prices tonight: Friday and Saturday nights cost more.</p>}
      {open && current && current.actions.length === 0 && (
        <p className="place-card__hint">Nothing to do here right now. Tap the floor to walk around.</p>
      )}
    </section>
  );
}
