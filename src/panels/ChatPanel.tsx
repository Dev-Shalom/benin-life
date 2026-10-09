// "Chat" tab in the location sheet (V1-6, docs/CHAT.md). Every place has its own room; you only see the
// room of the place you are at. Messages arrive live (src/state/chat.ts keeps the subscription), the list
// is capped, and sending goes through chat_send (rate limit, profanity filter, spam checks on the server).
// Tap someone's message (or its ⋯ button) to report or block them.
import { useEffect, useLayoutEffect, useRef, useState } from 'react';
import { AvatarPortrait } from '../art/avatar3d';
import { chatBlock, chatReport, chatSend, chatSendVoice } from '../api/chat';
import { discardVoiceUpload, socialVoiceUrl, uploadHouseVoiceMessage } from '../api/social';
import { errorMessage, GameError } from '../lib/api';
import { useConfig } from '../lib/config';
import type { ChatMessage, PanelProps } from '../lib/types';
import { useChat } from '../state/chat';
import { useHype, type Announcement } from '../state/hype';
import { Button, EmptyState, Icon, Spinner, toast } from '../ui';
import { VoicePlayer } from '../ui/VoicePlayer';

const REASONS = ['Insults', 'Spam', 'Scam', 'Sexual', 'Other'];

function timeOf(iso: string) {
  try {
    return new Date(iso).toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' });
  } catch {
    return '';
  }
}

function VoiceNote({ path, mine }: { path: string; mine: boolean }) {
  const [url, setUrl] = useState<string | null>(null);
  const [failed, setFailed] = useState(false);
  useEffect(() => {
    let alive = true;
    socialVoiceUrl(path).then((value) => alive && setUrl(value)).catch(() => alive && setFailed(true));
    return () => { alive = false; };
  }, [path]);
  if (failed) return <span className="social-voice-error">Voice message unavailable</span>;
  return url ? <VoicePlayer src={url} mine={mine} /> : <span className="social-voice-loading"><Spinner size={14} /> Loading voice…</span>;
}

function mergeHype(msgs: ChatMessage[], hype: Announcement[]): (ChatMessage | Announcement)[] {
  if (!hype.length) return msgs;
  return [...msgs, ...hype].sort((a, b) => Date.parse(a.created_at) - Date.parse(b.created_at));
}

export default function ChatPanel({ state, location }: PanelProps) {
  const { cfg } = useConfig();
  const rateSec = cfg('chat.rate_seconds', 3);
  const enabled = cfg('chat.enabled', true);
  const messages = useChat((s) => s.messages);
  // P2: the hype man's announcements in this club show in the chat as hype lines
  const hypeLoc = useHype((s) => s.locationId);
  const hypeRows = useHype((s) => s.recent);
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
  const [recording, setRecording] = useState(false);
  const [recordingBusy, setRecordingBusy] = useState(false);
  const discardOnStop = useRef(false);
  const recorderRef = useRef<MediaRecorder | null>(null);
  const streamRef = useRef<MediaStream | null>(null);
  const chunksRef = useRef<Blob[]>([]);
  const listRef = useRef<HTMLDivElement>(null);
  const stick = useRef(true);
  const here = state.location.id === location.id && !state.travel;

  useEffect(() => () => {
    discardOnStop.current = true;
    if (recorderRef.current?.state === 'recording') recorderRef.current.stop();
    streamRef.current?.getTracks().forEach((track) => track.stop());
  }, []);

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
  }, [messages.length, hypeRows.length]);

  if (!here || chatLoc !== location.id) {
    return <EmptyState icon="chat" title="Chat is for people here" body="Go to this place to chat with the people around." />;
  }

  const wait = Math.max(0, Math.ceil((waitUntil - now) / 1000));
  const trimmed = text.trim();

  const send = async () => {
    if (!trimmed || sending || wait > 0 || recording || recordingBusy) return;
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

  const stopRecording = () => {
    if (recorderRef.current?.state === 'recording') {
      setRecordingBusy(true);
      recorderRef.current.stop();
    }
  };

  const startRecording = async () => {
    if (!enabled || sending || wait > 0 || recording || recordingBusy) return;
    if (!navigator.mediaDevices?.getUserMedia || typeof MediaRecorder === 'undefined') {
      setNote('Voice recording is not supported by this browser.');
      return;
    }
    setRecordingBusy(true);
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      streamRef.current = stream;
      const preferred = ['audio/webm;codecs=opus', 'audio/mp4', 'audio/ogg;codecs=opus'];
      const mimeType = preferred.find((type) => MediaRecorder.isTypeSupported(type));
      const recorder = mimeType ? new MediaRecorder(stream, { mimeType }) : new MediaRecorder(stream);
      recorderRef.current = recorder;
      discardOnStop.current = false;
      chunksRef.current = [];
      recorder.ondataavailable = (event) => { if (event.data.size) chunksRef.current.push(event.data); };
      recorder.onerror = () => {
        stream.getTracks().forEach((track) => track.stop());
        setRecording(false);
        setRecordingBusy(false);
        setNote('The voice note stopped unexpectedly. Please try again.');
      };
      recorder.onstop = () => {
        stream.getTracks().forEach((track) => track.stop());
        streamRef.current = null;
        recorderRef.current = null;
        setRecording(false);
        if (discardOnStop.current) { chunksRef.current = []; return; }
        const blob = new Blob(chunksRef.current, { type: recorder.mimeType || 'audio/webm' });
        chunksRef.current = [];
        void (async () => {
          if (!blob.size) throw new Error('No audio was recorded.');
          const uploaded = await uploadHouseVoiceMessage(location.id, state.profile.id, blob, blob.type);
          try {
            const result = await chatSendVoice(uploaded.path, uploaded.mime);
            add(result);
            stick.current = true;
            setWaitUntil(Date.now() + rateSec * 1000);
            setNow(Date.now());
          } catch (error) {
            await discardVoiceUpload(uploaded.path).catch(() => undefined);
            throw error;
          }
        })().catch((error) => setNote(errorMessage(error))).finally(() => setRecordingBusy(false));
      };
      recorder.start(1000);
      setRecording(true);
      setRecordingBusy(false);
    } catch {
      streamRef.current?.getTracks().forEach((track) => track.stop());
      streamRef.current = null;
      setRecordingBusy(false);
      setNote('Microphone access was not allowed. Enable it in your browser settings and try again.');
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
        {mergeHype(messages, hypeLoc === location.id ? hypeRows : []).map((m) => 'kind' in m ? (
          <div key={`h${m.id}`} className="chat-hype" role="note">
            <span className="chat-hype__who">🎤 Hype man · {timeOf(m.created_at)}</span>
            {m.text}
          </div>
        ) : (
          <div key={m.id} className={`chat-msg${m.mine ? ' is-mine' : ''}${menu === m.id ? ' is-open' : ''}`}>
            <span className="chat-msg__face" aria-hidden>
              {m.avatar ? <AvatarPortrait config={m.avatar} size={32} /> : <span className="chat-msg__initial">{m.username.slice(0, 1).toUpperCase()}</span>}
            </span>
            <div className="chat-msg__main">
              <div className="chat-msg__bubble" onClick={() => openMenu(m)} role={m.mine ? undefined : 'button'} tabIndex={m.mine ? undefined : 0}
                onKeyDown={(event) => { if (!m.mine && (event.key === 'Enter' || event.key === ' ')) { event.preventDefault(); openMenu(m); } }}>
                <span className="chat-msg__meta">
                  <b>{m.mine ? 'You' : m.username}</b>
                  <span>{timeOf(m.created_at)}</span>
                </span>
                {m.body !== null && <span className="chat-msg__body">{m.body}</span>}
                {m.audio_path && <VoiceNote path={m.audio_path} mine={Boolean(m.mine)} />}
              </div>
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
      {recording && <div className="chat__recording" role="status"><span className="social-recording__dot" /> Recording voice message</div>}
      <form className="chat__form" onSubmit={(e) => { e.preventDefault(); void send(); }}>
        <textarea className="chat__input" value={text} rows={1} enterKeyHint="send" autoComplete="off"
          placeholder={enabled ? `Message people at ${location.name}…` : 'Chat is switched off for now'}
          disabled={!enabled || recording || recordingBusy || sending} aria-label="Message"
          onKeyDown={(e) => { if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); void send(); } }}
          onChange={(e) => { setText(e.target.value); if (note) setNote(null); }} />
        <Button type={trimmed ? 'submit' : 'button'} size="sm" variant="green" className={`chat__send${recording ? ' is-recording' : ''}`}
          aria-label={recording ? 'Send voice message' : trimmed ? 'Send message' : 'Record voice message'}
          title={recording ? 'Send voice message' : trimmed ? 'Send message' : 'Record voice message'}
          loading={sending || (recordingBusy && !recording)} disabled={!enabled || sending || recordingBusy || (!trimmed && !recording && wait > 0)}
          onClick={() => { if (recording) stopRecording(); else if (!trimmed) void startRecording(); }}>
          {wait > 0 && !recording ? `${wait}s` : <Icon name={trimmed || recording ? 'send' : 'mic'} size={18} />}
        </Button>
      </form>
    </div>
  );
}
