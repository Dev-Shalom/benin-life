// Free roam, live players: the HUD pieces (docs/ROAM.md "Live players"). Kept small and out of the way: a chip top-left, two round buttons
// above Run (emote, say), name tags and bubbles over the heads, and two modal cards (the player, the live settings). Tokens only.
import { useEffect, useMemo, useRef, useState, useSyncExternalStore } from 'react';
import { roamReport, roamSetShow } from '../../../api/roam';
import { chatBlock } from '../../../api/chat';
import { socialAddFriend } from '../../../api/social';
import { errorMessage } from '../../../lib/api';
import { supabase } from '../../../lib/supabase';
import { CrewTag, Icon, OfficeTag, Switch, toast } from '../../../ui';
import type { LiveBridge } from './bridge';
import { LiveClient, type Remote } from './client';
import { EMOTE_LABEL, EMOTES, type EmoteName } from './protocol';

const MUTE_KEY = 'bl.roam.nobubbles';
const loadMute = () => {
  try {
    return localStorage.getItem(MUTE_KEY) === '1';
  } catch {
    return false;
  }
};
const saveMute = (m: boolean) => {
  try {
    localStorage.setItem(MUTE_KEY, m ? '1' : '0');
  } catch {
    /* storage blocked */
  }
};

/** Create the network client while the street is open. `enabled` false (or the server says off) = free roam alone. */
export function useLive(enabled: boolean, low: boolean, getPose: () => { x: number; y: number }, bridge: LiveBridge): LiveClient | null {
  const [client, setClient] = useState<LiveClient | null>(null);
  const poseRef = useRef(getPose);
  poseRef.current = getPose;
  useEffect(() => {
    if (!enabled) return;
    const c = new LiveClient(supabase, { low, getPose: () => poseRef.current(), muteBubbles: loadMute() });
    bridge.client = c;
    setClient(c);
    void c.start();
    return () => {
      c.stop();
      if (bridge.client === c) bridge.client = null;
      setClient(null);
    };
  }, [enabled, low, bridge]);
  return client;
}

function useVersion(client: LiveClient | null): number {
  return useSyncExternalStore(
    (cb) => (client ? client.on(cb) : () => undefined),
    () => (client ? client.version : 0),
  );
}

const EMOTE_ICON: Record<Exclude<EmoteName, ''>, string> = { wave: '👋', nod: '🙂', laugh: '😂', dance: '💃', thumbs: '👍', callover: '🫴' };

/* ------------------------------------------------------------------ chip */
export function LiveChip({ client, onOpen }: { client: LiveClient | null; onOpen: () => void }) {
  useVersion(client);
  if (!client) return null;
  const n = [...client.remotes.values()].filter((r) => r.leaving === 0).length;
  let text: string;
  let cls = '';
  if (client.status === 'off') {
    text = 'Live players off';
    cls = ' is-off';
  } else if (client.status === 'connecting' || client.status === 'idle') {
    text = 'Connecting…';
    cls = ' is-wait';
  } else if (!client.visible && client.hiddenWhy) {
    text = n > 0 ? `${n} nearby · hidden` : 'Hidden from others';
    cls = ' is-hide';
  } else {
    text = n === 0 ? 'No one near' : `${n} nearby`;
  }
  return (
    <button type="button" className={`roam-livechip${cls}`} onClick={onOpen} data-testid="roam-livechip" aria-label={`${text}. Live players settings`}>
      <i aria-hidden />
      <span>{text}</span>
    </button>
  );
}

/* ------------------------------------------------------------------ tags and bubbles over heads */
export function LiveTags({ bridge, client, onPick }: { bridge: LiveBridge; client: LiveClient | null; onPick: (id: string) => void }) {
  useVersion(client);
  const els = useRef(new Map<string, HTMLElement>());
  const mine = useRef<HTMLDivElement | null>(null);
  useEffect(() => {
    let raf = 0;
    const loop = () => {
      const seen = new Set<string>();
      for (const t of bridge.tags) {
        const el = els.current.get(t.id);
        if (!el) continue;
        el.style.display = '';
        el.style.transform = `translate3d(${Math.round(t.x)}px, ${Math.round(t.y)}px, 0) translate(-50%, -100%) scale(${t.s.toFixed(2)})`;
        el.style.opacity = t.a.toFixed(2);
        seen.add(t.id);
      }
      for (const [id, el] of els.current) if (!seen.has(id)) el.style.display = 'none';
      const m = mine.current;
      if (m) {
        const t = bridge.myTag;
        if (t) {
          m.style.display = '';
          m.style.transform = `translate3d(${Math.round(t.x)}px, ${Math.round(t.y)}px, 0) translate(-50%, -100%)`;
        } else m.style.display = 'none';
      }
      raf = requestAnimationFrame(loop);
    };
    raf = requestAnimationFrame(loop);
    return () => cancelAnimationFrame(raf);
  }, [bridge]);
  if (!client || client.status === 'off') return null;
  const list = [...client.remotes.values()].slice(0, 24);
  return (
    <div className="roam-tags" aria-hidden={list.length === 0}>
      {list.map((r) => (
        <div key={r.id} className="roam-tag-wrap" style={{ display: 'none' }} ref={(el) => { if (el) els.current.set(r.id, el); else els.current.delete(r.id); }}>
          {r.bubble && <div className="roam-bubble" role="status" key={r.bubble.until}>{r.bubble.text}</div>}
          <button type="button" className="roam-tag" onClick={() => onPick(r.id)} data-testid="roam-tag" data-name={r.name} aria-label={`${r.name}, open player card`}>
            <span className="roam-tag__name">{r.name}</span>
            {r.mode === 'car' && <Icon name="car" size={12} />}
          </button>
        </div>
      ))}
      <div className="roam-tag-wrap" style={{ display: 'none' }} ref={mine}>
        {client.myBubble && <div className="roam-bubble roam-bubble--me" role="status" key={client.myBubble.until}>{client.myBubble.text}</div>}
      </div>
    </div>
  );
}

/* ------------------------------------------------------------------ emote + say */
export function LiveControls({ client, driving }: { client: LiveClient | null; driving: boolean }) {
  useVersion(client);
  const [tray, setTray] = useState<null | 'emote' | 'say'>(null);
  const [text, setText] = useState('');
  const [busy, setBusy] = useState(false);
  const input = useRef<HTMLInputElement>(null);
  useEffect(() => {
    if (tray === 'say') {
      const t = window.setTimeout(() => input.current?.focus({ preventScroll: true }), 80);
      return () => window.clearTimeout(t);
    }
  }, [tray]);
  if (!client || client.status !== 'on' || !client.info) return null;
  const info = client.info;
  const canSay = info.bubble && client.visible;
  const send = async (t: string) => {
    const v = t.trim();
    if (!v || busy) return;
    setBusy(true);
    const r = await client.say(v);
    setBusy(false);
    if (r.ok) {
      setText('');
      setTray(null);
    } else toast(r.message.replace(/^[A-Z_]+:\s*/, ''), 'bad');
  };
  return (
    <>
      <div className="roam-livebtns">
        {info.emotes && !driving && (
          <button type="button" className={`roam-btn roam-btn--round${tray === 'emote' ? ' is-on' : ''}`} aria-label="Wave and emotes" aria-expanded={tray === 'emote'} data-testid="roam-emote-btn" onClick={() => setTray(tray === 'emote' ? null : 'emote')}>
            <span className="roam-emoji" aria-hidden>👋</span>
          </button>
        )}
        {canSay && (
          <button type="button" className={`roam-btn roam-btn--round${tray === 'say' ? ' is-on' : ''}`} aria-label="Say something" aria-expanded={tray === 'say'} data-testid="roam-say-btn" onClick={() => setTray(tray === 'say' ? null : 'say')}>
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.1" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
              <path d="M5 5h14a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2h-7l-4.5 3.5V17H5a2 2 0 0 1-2-2V7a2 2 0 0 1 2-2z" />
            </svg>
          </button>
        )}
      </div>
      {tray === 'emote' && (
        <div className="roam-tray" role="menu" aria-label="Emotes">
          {(EMOTES.slice(1) as Exclude<EmoteName, ''>[]).map((e) => (
            <button key={e} type="button" role="menuitem" className="roam-tray__item" data-testid={`roam-emote-${e}`} onClick={() => { client.emote(e); setTray(null); }}>
              <span className="roam-emoji" aria-hidden>{EMOTE_ICON[e]}</span>
              <small>{EMOTE_LABEL[e]}</small>
            </button>
          ))}
        </div>
      )}
      {tray === 'say' && (
        <form className="roam-say-bar" onSubmit={(e) => { e.preventDefault(); void send(text); }}>
          <div className="roam-say-bar__row">
            <input ref={input} value={text} maxLength={info.bubble_len} onChange={(e) => setText(e.target.value)} placeholder="Say something nearby…" aria-label="Chat bubble text" autoComplete="off" enterKeyHint="send" data-testid="roam-say-input" />
            <button type="submit" disabled={busy || !text.trim()} className="roam-say-bar__send">Say</button>
          </div>
          <div className="roam-say-bar__quick">
            {['Hello!', 'How far?', 'Nice ride!', 'Let us go!'].map((q) => (
              <button key={q} type="button" disabled={busy} onClick={() => void send(q)}>{q}</button>
            ))}
            <small>{text.length}/{info.bubble_len}</small>
          </div>
        </form>
      )}
    </>
  );
}

/* ------------------------------------------------------------------ the player card */
const REASONS = ['Insults', 'Spam', 'Scam', 'Sexual', 'Other'];

export function PlayerCard({ client, id, onClose }: { client: LiveClient; id: string; onClose: () => void }) {
  useVersion(client);
  const r: Remote | undefined = client.remotes.get(id);
  const [step, setStep] = useState<'' | 'block' | 'report'>('');
  const [busy, setBusy] = useState(false);
  useEffect(() => {
    if (!r) onClose();
  }, [r, onClose]);
  if (!r) return null;
  const act = async (fn: () => Promise<string | void>) => {
    if (busy) return;
    setBusy(true);
    try {
      const m = await fn();
      if (m) toast(m, 'good');
    } catch (e) {
      toast(errorMessage(e), 'bad');
    } finally {
      setBusy(false);
    }
  };
  return (
    <div className="roam-modal" role="dialog" aria-label={`${r.name}`} data-testid="roam-card">
      <button type="button" className="roam-modal__scrim" aria-label="Close" onClick={onClose} />
      <div className="roam-modal__card">
        <div className="roam-card__head">
          <div className="roam-card__who">
            <b>
              <CrewTag tag={r.crew?.tag} color={r.crew?.color} emblem={r.crew?.emblem} />
              <OfficeTag title={r.title} />
              @{r.name}
            </b>
            <small>{r.mode === 'car' ? 'Driving' : 'On foot'} · {Math.round(r.dist)} m away{r.streetCred > 0 ? ` · Street cred ${r.streetCred}` : ''}</small>
          </div>
          <button type="button" className="roam-btn roam-btn--round" onClick={onClose} aria-label="Close" style={{ width: 34, height: 34, minWidth: 34 }}>
            <Icon name="close" size={16} />
          </button>
        </div>
        {step === '' && (
          <div className="roam-card__acts">
            {client.info?.emotes && (
              <button type="button" disabled={busy} data-testid="roam-card-wave" onClick={() => { client.emote('wave'); onClose(); }}>
                <span className="roam-emoji" aria-hidden>👋</span> Wave
              </button>
            )}
            <button type="button" disabled={busy} data-testid="roam-card-friend" onClick={() => void act(async () => (await socialAddFriend(r.id)).message)}>
              <Icon name="user" size={16} /> Add friend
            </button>
            <button type="button" disabled={busy} className="is-warn" data-testid="roam-card-block" onClick={() => setStep('block')}>
              <Icon name="ban" size={16} /> Block
            </button>
            <button type="button" disabled={busy} className="is-warn" data-testid="roam-card-report" onClick={() => setStep('report')}>
              <Icon name="warning" size={16} /> Report
            </button>
          </div>
        )}
        {step === 'block' && (
          <div className="roam-card__confirm">
            <p>Block @{r.name}? You will not see each other here, and your messages stay apart.</p>
            <div>
              <button type="button" onClick={() => setStep('')}>Cancel</button>
              <button
                type="button"
                className="is-danger"
                disabled={busy}
                data-testid="roam-card-block-yes"
                onClick={() => void act(async () => {
                  const res = await chatBlock(r.id);
                  client.blockLocal(r.id);
                  onClose();
                  return res.message;
                })}
              >
                Block
              </button>
            </div>
          </div>
        )}
        {step === 'report' && (
          <div className="roam-card__confirm">
            <p>Why are you reporting @{r.name}? A moderator reads it.</p>
            <div className="roam-card__reasons">
              {REASONS.map((x) => (
                <button key={x} type="button" disabled={busy} onClick={() => void act(async () => { const res = await roamReport(r.id, x); onClose(); return res.message; })}>{x}</button>
              ))}
            </div>
            <div>
              <button type="button" onClick={() => setStep('')}>Back</button>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}

/* ------------------------------------------------------------------ the live settings sheet */
export function LiveSheet({ client, onClose, onPick }: { client: LiveClient; onClose: () => void; onPick: (id: string) => void }) {
  useVersion(client);
  const info = client.info;
  const [show, setShow] = useState<boolean>(info?.show_me ?? true);
  const [mute, setMute] = useState(loadMute());
  const [busy, setBusy] = useState(false);
  const near = useMemo(() => [...client.remotes.values()].filter((r) => r.leaving === 0).sort((a, b) => a.dist - b.dist), [client.remotes, client.version]); // eslint-disable-line react-hooks/exhaustive-deps
  const offText: Record<string, string> = {
    server: 'Live players are switched off for now.',
    poll: 'Your connection is on the slow, saving mode, so live players are paused. Free roam works as usual.',
    connection: 'The live connection dropped. Trying again in a little while. Free roam works as usual.',
    unsupported: 'Live players are not available here.',
    error: 'Could not reach the live service. Trying again soon.',
  };
  return (
    <div className="roam-modal" role="dialog" aria-label="Live players" data-testid="roam-livesheet">
      <button type="button" className="roam-modal__scrim" aria-label="Close" onClick={onClose} />
      <div className="roam-modal__card">
        <div className="roam-card__head">
          <div className="roam-card__who">
            <b>Live players</b>
            <small>{client.status === 'off' ? 'Off' : client.status === 'on' ? `${near.length} near you` : 'Connecting…'}</small>
          </div>
          <button type="button" className="roam-btn roam-btn--round" onClick={onClose} aria-label="Close" style={{ width: 34, height: 34, minWidth: 34 }}>
            <Icon name="close" size={16} />
          </button>
        </div>
        {client.status === 'off' && <p className="roam-card__note">{offText[client.off] ?? offText.error}</p>}
        <Switch
          checked={show}
          disabled={busy}
          label="Show me to others in free roam"
          hint={info?.location_hidden ? 'Your location is hidden in Friends settings, so others cannot see you here either.' : 'Other players in the street see your name tag and can wave. You still see them if this is off.'}
          onChange={(v) => {
            setShow(v);
            setBusy(true);
            roamSetShow(v)
              .then((r) => { toast(r.message, 'good'); if (info) info.show_me = v; })
              .catch((e) => { setShow(!v); toast(errorMessage(e), 'bad'); })
              .finally(() => setBusy(false));
          }}
        />
        <Switch
          checked={!mute}
          label="Show chat bubbles"
          hint="Short messages over players' heads, within about 25 m."
          onChange={(v) => { setMute(!v); saveMute(!v); client.setMuteBubbles(!v); }}
        />
        {near.length > 0 && (
          <ul className="roam-card__near">
            {near.slice(0, 8).map((r) => (
              <li key={r.id}>
                <button type="button" onClick={() => onPick(r.id)}>
                  <span>@{r.name}</span>
                  <small>{r.mode === 'car' ? 'Driving' : 'On foot'} · {Math.round(r.dist)} m</small>
                </button>
              </li>
            ))}
          </ul>
        )}
      </div>
    </div>
  );
}
