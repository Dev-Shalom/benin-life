// M3 messaging kit shared by place chat, house chat (ChatPanel) and DMs (phone SocialApp).
// One bubble component (mine right / others left, name + time, quote block, tombstone), swipe-right-to-reply
// on touch, long-press / right-click / hover "⋯" for the message menu, the composer's reply preview, the
// in-thread action sheet, scroll helpers (keep position when older pages load, jump to a quoted message) and
// the visualViewport vars (--vvh, --kb) that keep composers clear of the on-screen keyboard.
import { useEffect, useLayoutEffect, useRef, useState, type ReactNode, type RefObject } from 'react';
import { AvatarPortrait } from '../art/avatar3d';
import { socialVoiceUrl } from '../api/social';
import type { AvatarConfig, ReplyPreview } from '../lib/types';
import { Icon, Spinner } from '../ui';
import { VoicePlayer } from '../ui/VoicePlayer';
import { useEscape } from '../ui/presence';

export type { ReplyPreview };

export interface ThreadMessage {
  id: number;
  mine: boolean;
  name: string;
  createdAt: string;
  body: string | null;
  audioPath: string | null;
  deletedAt: string | null;
  replyTo: number | null;
  reply: ReplyPreview | null;
  avatar?: AvatarConfig | null;
}

export function timeOf(iso: string) {
  try { return new Date(iso).toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' }); } catch { return ''; }
}

/** 24-hour "19:05" stamp used inside DM bubbles. */
export function stampOf(iso: string) {
  try { return new Date(iso).toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit' }); } catch { return ''; }
}

/** "Today" / "Yesterday" / "Wed 7 Oct" for the day separators. */
export function dayLabel(iso: string) {
  const d = new Date(iso);
  const today = new Date();
  const y = new Date(today); y.setDate(today.getDate() - 1);
  if (d.toDateString() === today.toDateString()) return 'Today';
  if (d.toDateString() === y.toDateString()) return 'Yesterday';
  return d.toLocaleDateString('en-GB', { weekday: 'short', day: 'numeric', month: 'short' });
}

/** Day separator before `iso` when it starts a new day after `prevIso`. */
export function DaySep({ iso, prevIso }: { iso: string; prevIso: string | null }) {
  if (prevIso && new Date(prevIso).toDateString() === new Date(iso).toDateString()) return null;
  return <div className="msg-day" role="separator">{dayLabel(iso)}</div>;
}

/** Build a quote preview for `m` (used for the composer and for live rows the server didn't decorate). */
export function previewOf(m: ThreadMessage): ReplyPreview {
  return { id: m.id, username: m.name, snippet: m.body ? m.body.slice(0, 140) : null, voice: Boolean(m.audioPath), deleted: Boolean(m.deletedAt) };
}

/** Server preview, else one built from the loaded list, else a bare "earlier message". */
export function resolveReply(m: ThreadMessage, byId: Map<number, ThreadMessage>): ReplyPreview | null {
  if (m.replyTo == null) return null;
  const orig = byId.get(m.replyTo);
  if (orig) return previewOf(orig);
  return m.reply ?? { id: m.replyTo, username: null, snippet: null, voice: false, deleted: false, unavailable: true };
}

export function canDeleteForEveryone(m: ThreadMessage, hours: number) {
  return m.mine && !m.deletedAt && Date.now() - Date.parse(m.createdAt) < hours * 3600_000;
}

function quoteText(r: ReplyPreview) {
  if (r.deleted) return 'This message was deleted';
  if (r.unavailable && !r.snippet && !r.voice) return 'Earlier message';
  if (r.voice) return 'Voice note';
  return r.snippet ?? '';
}

export function VoiceNote({ path, mine }: { path: string; mine: boolean }) {
  const [url, setUrl] = useState<string | null>(null);
  const [failed, setFailed] = useState(false);
  useEffect(() => {
    let alive = true;
    socialVoiceUrl(path).then((value) => alive && setUrl(value)).catch(() => alive && setFailed(true));
    return () => { alive = false; };
  }, [path]);
  if (failed) return <span className="social-voice-error">Voice note unavailable</span>;
  return url ? <VoicePlayer src={url} mine={mine} /> : <span className="social-voice-loading"><Spinner size={14} /> Loading voice…</span>;
}

const SWIPE_TRIGGER = 56;
const SWIPE_MAX = 76;
const LONG_PRESS_MS = 450;

/** M4 DM receipt: ✓ sent, ✓✓ delivered (grey), ✓✓ read (blue). */
export type Receipt = 'sent' | 'delivered' | 'read';

export function Ticks({ state }: { state: Receipt }) {
  const label = state === 'read' ? 'Read' : state === 'delivered' ? 'Delivered' : 'Sent';
  return (
    <svg className={`msg-ticks is-${state}`} width={state === 'sent' ? 12 : 17} height="11" viewBox={state === 'sent' ? '0 0 12 11' : '0 0 17 11'}
      fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" role="img" aria-label={label}>
      <path d="M1.5 6.2 4.6 9.2 10.5 1.8" />
      {state !== 'sent' && <path d="M8.2 8.4 9 9.2 15 1.8" />}
    </svg>
  );
}

interface RowProps {
  m: ThreadMessage;
  reply: ReplyPreview | null;
  showFace?: boolean;
  /** M4 DM look: no name line, time (and receipt on mine) inside the bubble at the bottom right. */
  dm?: boolean;
  receipt?: Receipt | null;
  onReply: (m: ThreadMessage) => void;
  onMenu: (m: ThreadMessage) => void;
  onQuote: (id: number) => void;
}

/** One message: bubble with name + time, optional quote, body / voice / tombstone, swipe + long-press. */
export function MessageRow({ m, reply, showFace, dm, receipt, onReply, onMenu, onQuote }: RowProps) {
  const bubbleRef = useRef<HTMLDivElement>(null);
  const hintRef = useRef<HTMLSpanElement>(null);
  const g = useRef<{ x: number; y: number; dx: number; lock: 'x' | 'y' | null; id: number; timer: number; long: boolean } | null>(null);
  const suppressClick = useRef(false);
  const canReply = !m.deletedAt;

  const setDx = (dx: number, animate: boolean) => {
    const el = bubbleRef.current;
    if (!el) return;
    el.style.transition = animate ? 'transform 220ms cubic-bezier(0.23, 1, 0.32, 1)' : 'none';
    el.style.transform = dx ? `translateX(${dx}px)` : '';
    if (hintRef.current) {
      hintRef.current.style.opacity = String(Math.min(1, dx / SWIPE_TRIGGER));
      hintRef.current.style.transform = `scale(${dx >= SWIPE_TRIGGER ? 1 : 0.7 + 0.3 * (dx / SWIPE_TRIGGER)})`;
    }
  };

  const end = (commit: boolean) => {
    const s = g.current;
    if (!s) return;
    window.clearTimeout(s.timer);
    if (commit && s.lock === 'x' && s.dx >= SWIPE_TRIGGER && canReply) onReply(m);
    if (s.lock === 'x') suppressClick.current = true;
    setDx(0, true);
    g.current = null;
  };

  return (
    <div className={`msg-row${m.mine ? ' is-mine' : ''}${m.deletedAt ? ' is-deleted' : ''}${dm ? ' is-dm' : ''}`} data-mid={m.id}>
      {showFace && (
        <span className="msg-row__face" aria-hidden>
          {m.avatar ? <AvatarPortrait config={m.avatar} size={30} /> : <span className="msg-row__initial">{m.name.slice(0, 1).toUpperCase()}</span>}
        </span>
      )}
      <div className="msg-row__main">
        <div className="msg-row__wrap">
        {canReply && <span className="msg-row__swipe" ref={hintRef} aria-hidden><Icon name="reply" size={16} /></span>}
        <div ref={bubbleRef} className="msg-bubble" tabIndex={0}
          aria-label={`${m.mine ? 'You' : m.name}, ${timeOf(m.createdAt)}: ${m.deletedAt ? 'This message was deleted' : m.body ?? 'Voice note'}`}
          onContextMenu={(e) => { e.preventDefault(); onMenu(m); }}
          onKeyDown={(e) => {
            if (e.key === 'Enter' || e.key === ' ' || e.key === 'ContextMenu') { e.preventDefault(); onMenu(m); }
            else if (e.key === 'r' && canReply) { e.preventDefault(); onReply(m); }
          }}
          onPointerDown={(e) => {
            if (e.pointerType === 'mouse' && e.button !== 0) return;
            const touch = e.pointerType !== 'mouse';
            const timer = touch ? window.setTimeout(() => {
              if (g.current && !g.current.lock) {
                g.current.long = true;
                suppressClick.current = true;
                navigator.vibrate?.(8);
                onMenu(m);
              }
            }, LONG_PRESS_MS) : 0;
            g.current = touch ? { x: e.clientX, y: e.clientY, dx: 0, lock: null, id: e.pointerId, timer, long: false } : null;
          }}
          onPointerMove={(e) => {
            const s = g.current;
            if (!s || s.id !== e.pointerId || s.long) return;
            const dx = e.clientX - s.x;
            const dy = e.clientY - s.y;
            if (!s.lock) {
              if (Math.abs(dx) < 8 && Math.abs(dy) < 8) return;
              window.clearTimeout(s.timer);
              s.lock = canReply && dx > 0 && Math.abs(dx) > Math.abs(dy) ? 'x' : 'y';
              if (s.lock === 'x') bubbleRef.current?.setPointerCapture?.(e.pointerId);
            }
            if (s.lock !== 'x') return;
            const raw = Math.max(0, dx);
            const eased = raw > SWIPE_MAX ? SWIPE_MAX + (raw - SWIPE_MAX) * 0.15 : raw;
            if (s.dx < SWIPE_TRIGGER && eased >= SWIPE_TRIGGER) navigator.vibrate?.(6);
            s.dx = eased;
            setDx(eased, false);
          }}
          onPointerUp={() => end(true)}
          onPointerCancel={() => end(false)}
          onClick={() => { if (suppressClick.current) { suppressClick.current = false; } }}>
          {!dm && (
            <span className="msg-bubble__meta">
              <b>{m.mine ? 'You' : m.name}</b>
              <time dateTime={m.createdAt}>{timeOf(m.createdAt)}</time>
            </span>
          )}
          {reply && !m.deletedAt && (
            <button type="button" className={`msg-quote${reply.deleted || reply.unavailable ? ' is-muted' : ''}`}
              onClick={(e) => { e.stopPropagation(); onQuote(reply.id); }}
              onPointerDown={(e) => e.stopPropagation()}
              aria-label={`Reply to ${reply.username ?? 'an earlier message'}. Show the original`}>
              <b>{reply.username ?? 'Message'}</b>
              <span>{reply.voice && !reply.deleted && <Icon name="mic" size={12} />}{quoteText(reply)}</span>
            </button>
          )}
          {m.deletedAt ? <span className="msg-bubble__deleted"><Icon name="ban" size={14} /> This message was deleted</span>
            : m.body !== null ? <span className="msg-bubble__body">{m.body}</span>
              : m.audioPath ? <VoiceNote path={m.audioPath} mine={m.mine} /> : null}
          {dm && (
            <span className="msg-bubble__stamp">
              <time dateTime={m.createdAt}>{stampOf(m.createdAt)}</time>
              {m.mine && receipt && !m.deletedAt && <Ticks state={receipt} />}
            </span>
          )}
        </div>
        </div>
        <span className="msg-row__tools">
          {canReply && <button type="button" className="msg-row__tool" aria-label="Reply" title="Reply" onClick={() => onReply(m)}><Icon name="reply" size={15} /></button>}
          <button type="button" className="msg-row__tool" aria-label="More actions" title="More" onClick={() => onMenu(m)}><Icon name="more" size={17} stroke={3} /></button>
        </span>
      </div>
    </div>
  );
}

/** Composer reply preview ("Replying to @x" + snippet, × to clear). */
export function ReplyBar({ reply, onClear }: { reply: ReplyPreview; onClear: () => void }) {
  return (
    <div className="msg-replybar" role="status">
      <Icon name="reply" size={15} />
      <div className="msg-replybar__text">
        <b>Replying to {reply.username ?? 'message'}</b>
        <span>{reply.voice && <Icon name="mic" size={12} />}{quoteText(reply)}</span>
      </div>
      <button type="button" className="msg-replybar__x" aria-label="Cancel reply" onClick={onClear}><Icon name="close" size={16} stroke={2.6} /></button>
    </div>
  );
}

export interface MenuAction {
  label: string;
  icon: string;
  tone?: 'danger';
  onSelect: () => void;
}

/** In-thread action sheet (long-press / right-click / ⋯). Escape or the backdrop closes it. */
export function MessageMenu({ m, actions, onClose, children }: { m: ThreadMessage; actions: MenuAction[]; onClose: () => void; children?: ReactNode }) {
  const first = useRef<HTMLButtonElement>(null);
  useEscape(true, onClose); // top of the shared Escape stack: closes the menu, not the phone / sheet
  useEffect(() => { first.current?.focus({ preventScroll: true }); }, []);
  return (
    <div className="msg-menu" role="dialog" aria-label="Message actions">
      <div className="msg-menu__backdrop" onClick={onClose} />
      <div className="msg-menu__card">
        <p className="msg-menu__preview"><b>{m.mine ? 'You' : m.name}</b> {m.deletedAt ? 'This message was deleted' : m.body ?? 'Voice note'}</p>
        {children ?? actions.map((a, i) => (
          <button key={a.label} ref={i === 0 ? first : undefined} type="button" className={`msg-menu__item${a.tone === 'danger' ? ' is-danger' : ''}`}
            onClick={a.onSelect}>
            <Icon name={a.icon} size={18} /> {a.label}
          </button>
        ))}
        <button type="button" className="msg-menu__item msg-menu__cancel" onClick={onClose}>Cancel</button>
      </div>
    </div>
  );
}

/** Scroll the list to a message and flash it. Returns false when it isn't loaded. */
export function flashMessage(list: HTMLElement | null, id: number) {
  const el = list?.querySelector<HTMLElement>(`[data-mid="${id}"]`);
  if (!el) return false;
  el.scrollIntoView({ block: 'center', behavior: 'smooth' });
  el.classList.remove('is-flash');
  void el.offsetWidth;
  el.classList.add('is-flash');
  window.setTimeout(() => el.classList.remove('is-flash'), 1600);
  return true;
}

/**
 * Infinite scroll upward: calls `loadOlder` when the list nears the top, keeps the reading position when
 * the older page lands (anchor = first row id), and follows new messages only while at the bottom.
 */
export function useThreadScroll(listRef: RefObject<HTMLDivElement | null>, opts: {
  firstId: number | null; lastId: number | null; hasOlder: boolean; loadingOlder: boolean; loadOlder: () => void;
}) {
  const { firstId, lastId, hasOlder, loadingOlder, loadOlder } = opts;
  const atBottom = useRef(true);
  const anchor = useRef<{ first: number | null; height: number; top: number } | null>(null);

  // older page prepended -> keep the same message under the finger
  useLayoutEffect(() => {
    const el = listRef.current;
    const a = anchor.current;
    if (!el || !a) return;
    if (a.first !== firstId) {
      el.scrollTop = el.scrollHeight - a.height + a.top;
      anchor.current = null;
    }
  }, [firstId, listRef]);

  // new message at the bottom -> follow if we were at the bottom
  useLayoutEffect(() => {
    const el = listRef.current;
    if (el && atBottom.current) el.scrollTop = el.scrollHeight;
  }, [lastId, listRef]);

  // composer grows (reply bar, multi-line text) or the keyboard opens -> keep the newest message in view
  useEffect(() => {
    const el = listRef.current;
    if (!el || typeof ResizeObserver === 'undefined') return;
    const ro = new ResizeObserver(() => { if (atBottom.current) el.scrollTop = el.scrollHeight; });
    ro.observe(el);
    return () => ro.disconnect();
  }, [listRef]);

  const onScroll = () => {
    const el = listRef.current;
    if (!el) return;
    atBottom.current = el.scrollHeight - el.scrollTop - el.clientHeight < 48;
    if (el.scrollTop < 120 && hasOlder && !loadingOlder && firstId != null) {
      anchor.current = { first: firstId, height: el.scrollHeight, top: el.scrollTop };
      loadOlder();
    }
  };
  const stickToBottom = () => {
    atBottom.current = true;
    const el = listRef.current;
    if (el) requestAnimationFrame(() => { el.scrollTop = el.scrollHeight; });
  };
  return { onScroll, stickToBottom };
}

/**
 * Publish the visual viewport as CSS vars on <html>: --vvh (visible height) and --kb (the part of the
 * layout viewport the on-screen keyboard covers). Composers and their sheets use them to stay above the
 * keyboard on iOS/Android, where 100dvh does not shrink for the keyboard.
 */
export function useViewportVars() {
  useEffect(() => {
    const vv = window.visualViewport;
    const root = document.documentElement;
    if (!vv) return;
    let raf = 0;
    const apply = () => {
      cancelAnimationFrame(raf);
      raf = requestAnimationFrame(() => {
        const kb = Math.max(0, Math.round(window.innerHeight - vv.height - vv.offsetTop));
        root.style.setProperty('--vvh', `${Math.round(vv.height)}px`);
        root.style.setProperty('--kb', `${kb > 60 ? kb : 0}px`);
        root.classList.toggle('has-kb', kb > 60);
      });
    };
    apply();
    vv.addEventListener('resize', apply);
    vv.addEventListener('scroll', apply);
    return () => {
      cancelAnimationFrame(raf);
      vv.removeEventListener('resize', apply);
      vv.removeEventListener('scroll', apply);
      root.style.removeProperty('--vvh');
      root.style.removeProperty('--kb');
      root.classList.remove('has-kb');
    };
  }, []);
}
