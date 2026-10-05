// "Chat" tab in the location sheet (V1-6, docs/CHAT.md). Every place has its own room; you only see the
// room of the place you are at. Messages arrive live (src/state/chat.ts keeps the subscription), the list
// is capped, and sending goes through chat_send (rate limit, profanity filter, spam checks on the server).
// Tap someone's message (or its ⋯ button) to report or block them.
import { useEffect, useLayoutEffect, useRef, useState } from 'react';
import { AvatarPortrait } from '../art/avatar3d';
import { chatBlock, chatReport, chatSend } from '../api/chat';
import { errorMessage, GameError } from '../lib/api';
import { useConfig } from '../lib/config';
import type { ChatMessage, PanelProps } from '../lib/types';
import { useChat } from '../state/chat';
import { Button, EmptyState, Icon, Spinner, toast } from '../ui';

const REASONS = ['Insults', 'Spam', 'Scam', 'Sexual', 'Other'];

function timeOf(iso: string) {
  try {
    return new Date(iso).toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' });
  } catch {
    return '';
  }
}

export default function ChatPanel({ state, location }: PanelProps) {
  const { cfg } = useConfig();
  const maxLen = cfg('chat.max_len', 200);
  const rateSec = cfg('chat.rate_seconds', 3);
  const enabled = cfg('chat.enabled', true);
  const messages = useChat((s) => s.messages);
  const status = useChat((s) => s.status);
  const error = useChat((s) => s.error);
  const chatLoc = useChat((s) => s.locationId);
  const setViewing = useChat((s) => s.setViewing);
  const add = useChat((s) => s.add);
  const reload = useChat((s) => s.reload);
  const dropUser = useChat((s) => s.dropUser);
  const dropMessage = useChat((s) => s.dropMessage);
  const [text, setText] = useState('');
  const [sending, setSending] = useState(false);
  const [waitUntil, setWaitUntil] = useState(0);
  const [now, setNow] = useState(() => Date.now());
  const [note, setNote] = useState<string | null>(null);
  const [menu, setMenu] = useState<number | null>(null);
  const [reporting, setReporting] = useState(false);
  const listRef = useRef<HTMLDivElement>(null);
  const stick = useRef(true);
  const here = state.location.id === location.id && !state.travel;

  // While this tab is on screen, new messages don't count as unread.
  useEffect(() => {
    setViewing(true);
    return () => setViewing(false);
  }, [setViewing]);

  // Countdown for the rate limit.
  useEffect(() => {
    if (waitUntil <= Date.now()) return;
    const id = window.setInterval(() => {
      setNow(Date.now());
      if (Date.now() >= waitUntil) window.clearInterval(id);
    }, 250);
    return () => window.clearInterval(id);
  }, [waitUntil]);

  // Follow new messages when the list is scrolled to the bottom.
  useLayoutEffect(() => {
    const el = listRef.current;
    if (el && stick.current) el.scrollTop = el.scrollHeight;
  }, [messages.length]);

  if (!here || chatLoc !== location.id) {
    return <EmptyState icon="chat" title="Chat is for people here" body="Go to this place to chat with the people around." />;
  }

  const wait = Math.max(0, Math.ceil((waitUntil - now) / 1000));
  const trimmed = text.trim();
  const tooLong = trimmed.length > maxLen;

  const send = async () => {
    if (!trimmed || tooLong || sending || wait > 0) return;
    setSending(true);
    setNote(null);
    try {
      const r = await chatSend(trimmed);
      add(r);
      setText('');
      stick.current = true;
      if (r.masked) setNote('Some words were hidden. Keep it clean.');
      const t = Date.now() + rateSec * 1000;
      setWaitUntil(t);
      setNow(Date.now());
    } catch (e) {
      const hint = e instanceof GameError ? e.hint : undefined;
      const m = errorMessage(e).match(/Wait (\d+) sec/);
      if (hint === 'too_fast' && m) {
        setWaitUntil(Date.now() + Number(m[1]) * 1000);
        setNow(Date.now());
      }
      setNote(errorMessage(e));
    } finally {
      setSending(false);
    }
  };

  const report = async (msg: ChatMessage, reason: string) => {
    try {
      const r = await chatReport(msg.id, reason);
      toast(r.message, 'good');
      dropMessage(msg.id);
    } catch (e) {
      toast(errorMessage(e), 'bad');
    }
    setMenu(null);
    setReporting(false);
  };

  const block = async (msg: ChatMessage) => {
    try {
      const r = await chatBlock(msg.user_id);
      toast(r.message, 'good');
      dropUser(msg.user_id);
    } catch (e) {
      toast(errorMessage(e), 'bad');
    }
    setMenu(null);
  };

  const openMenu = (m: ChatMessage) => {
    if (m.mine) return;
    setReporting(false);
    setMenu(menu === m.id ? null : m.id);
  };

  return (
    <div className="chat">
      <p className="chat__rules"><Icon name="shield" size={14} /> Be respectful — 18+ only. Tap a message to report or block.</p>
      <div className="chat__list" ref={listRef} role="log" aria-live="polite" aria-label={`Chat at ${location.name}`}
        onScroll={(e) => {
          const el = e.currentTarget;
          stick.current = el.scrollHeight - el.scrollTop - el.clientHeight < 40;
        }}>
        {status === 'loading' && messages.length === 0 && <div className="chat__empty"><Spinner size={20} /></div>}
        {status === 'error' && messages.length === 0 && (
          <div className="chat__empty">
            <p>{error ?? 'Chat is not loading.'}</p>
            <Button size="sm" variant="ghost" icon="refresh" onClick={() => void reload()}>Try again</Button>
          </div>
        )}
        {status === 'ready' && messages.length === 0 && (
          <div className="chat__empty"><p>It's quiet here. Say hello to the people around!</p></div>
        )}
        {messages.map((m) => (
          <div key={m.id} className={`chat-msg${m.mine ? ' is-mine' : ''}${menu === m.id ? ' is-open' : ''}`}>
            <span className="chat-msg__face" aria-hidden>
              {m.avatar ? <AvatarPortrait config={m.avatar} size={32} /> : <span className="chat-msg__initial">{m.username.slice(0, 1).toUpperCase()}</span>}
            </span>
            <div className="chat-msg__main">
              <button type="button" className="chat-msg__bubble" onClick={() => openMenu(m)} disabled={m.mine}
                aria-label={m.mine ? undefined : `Message from ${m.username}. Options`}>
                <span className="chat-msg__meta">
                  <b>{m.mine ? 'You' : m.username}</b>
                  <span>{timeOf(m.created_at)}</span>
                </span>
                <span className="chat-msg__body">{m.body}</span>
              </button>
              {menu === m.id && (
                <div className="chat-msg__menu">
                  {!reporting ? (
                    <>
                      <Button size="sm" variant="ghost" icon="warning" onClick={() => setReporting(true)}>Report</Button>
                      <Button size="sm" variant="danger" icon="eyeOff" onClick={() => void block(m)}>Block @{m.username}</Button>
                      <Button size="sm" variant="ghost" onClick={() => setMenu(null)}>Cancel</Button>
                    </>
                  ) : (
                    <>
                      <span className="chat-msg__why">Why?</span>
                      {REASONS.map((r) => (
                        <button key={r} type="button" className="chip" onClick={() => void report(m, r)}>{r}</button>
                      ))}
                    </>
                  )}
                </div>
              )}
            </div>
            {!m.mine && (
              <button type="button" className="chat-msg__more" aria-label={`More for ${m.username}'s message`} onClick={() => openMenu(m)}>⋯</button>
            )}
          </div>
        ))}
      </div>
      {note && <p className="chat__note" role="status">{note}</p>}
      <form className="chat__form" onSubmit={(e) => { e.preventDefault(); void send(); }}>
        <input className="chat__input" value={text} maxLength={maxLen + 50} enterKeyHint="send" autoComplete="off"
          placeholder={enabled ? `Talk to people at ${location.name}…` : 'Chat is switched off for now'}
          disabled={!enabled} aria-label="Message" onChange={(e) => { setText(e.target.value); if (note) setNote(null); }} />
        <span className={`chat__count${tooLong ? ' is-over' : ''}`} aria-live="off">{trimmed.length}/{maxLen}</span>
        <Button type="submit" size="sm" variant="green" className="chat__send" loading={sending}
          disabled={!enabled || !trimmed || tooLong || wait > 0}>
          {wait > 0 ? `${wait}s` : 'Send'}
        </Button>
      </form>
    </div>
  );
}
