// "Chat" tab in the location sheet (V1-6, docs/CHAT.md). Every place has its own room; you only see the
// room of the place you are at. Messages arrive live (src/state/chat.ts keeps the subscription), the list
// is capped, and sending goes through chat_send (rate limit, profanity filter, spam checks on the server).
// M3 (chatKit): swipe right / hover Reply to quote a message; long-press, right-click or ⋯ opens the menu
// (Reply, Copy, Delete for me, Delete for everyone on your own recent messages, Report, Block). Scrolling up
// loads older pages (14 days max).
import { Fragment, useEffect, useMemo, useRef, useState } from 'react';
import { chatBlock, chatDeleteForEveryone, chatDeleteForMe, chatReport, chatSend, chatSendVoice } from '../api/chat';
import { discardVoiceUpload, uploadHouseVoiceMessage } from '../api/social';
import { errorMessage, GameError } from '../lib/api';
import { useConfig } from '../lib/config';
import type { ChatMessage, PanelProps } from '../lib/types';
import { useChat } from '../state/chat';
import { useHype, type Announcement } from '../state/hype';
import { Button, EmptyState, Icon, Spinner, toast } from '../ui';
import { useEscape } from '../ui/presence';
import {
  canDeleteForEveryone, DaySep, flashMessage, MessageMenu, MessageRow, previewOf, ReplyBar, resolveReply, timeOf,
  useThreadScroll, useViewportVars, type MenuAction, type ThreadMessage,
} from './chatKit';

const REASONS = ['Insults', 'Spam', 'Scam', 'Sexual', 'Other'];

function toThread(m: ChatMessage): ThreadMessage {
  return {
    id: m.id, mine: Boolean(m.mine), name: m.username, createdAt: m.created_at, body: m.body,
    audioPath: m.audio_path ?? null, deletedAt: m.deleted_at ?? null, replyTo: m.reply_to ?? null,
    reply: m.reply ?? null, avatar: m.avatar,
  };
}

function mergeHype(msgs: ChatMessage[], hype: Announcement[]): (ChatMessage | Announcement)[] {
  if (!hype.length) return msgs;
  return [...msgs, ...hype].sort((a, b) => Date.parse(a.created_at) - Date.parse(b.created_at));
}

export default function ChatPanel({ state, location }: PanelProps) {
  const { cfg } = useConfig();
  const rateSec = cfg('chat.rate_seconds', 3);
  const enabled = cfg('chat.enabled', true);
  const deleteHours = cfg('chat.delete_everyone_hours', 48);
  useViewportVars();
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
  const patch = useChat((s) => s.patch);
  const hasOlder = useChat((s) => s.hasOlder);
  const loadingOlder = useChat((s) => s.loadingOlder);
  const loadOlder = useChat((s) => s.loadOlder);
  const [replyTo, setReplyTo] = useState<ThreadMessage | null>(null);
  useEscape(Boolean(replyTo), () => setReplyTo(null));
  const inputRef = useRef<HTMLTextAreaElement>(null);
  const rootRef = useRef<HTMLDivElement>(null);
  const [text, setText] = useState('');
  const [sending, setSending] = useState(false);
  const [waitUntil, setWaitUntil] = useState(0);
  const [now, setNow] = useState(() => Date.now());
  const [note, setNote] = useState<string | null>(null);
  const [menu, setMenu] = useState<ThreadMessage | null>(null);
  const [reporting, setReporting] = useState(false);
  const [recording, setRecording] = useState(false);
  const [recordingBusy, setRecordingBusy] = useState(false);
  const discardOnStop = useRef(false);
  const replyRef = useRef<ThreadMessage | null>(null);
  const recorderRef = useRef<MediaRecorder | null>(null);
  const streamRef = useRef<MediaStream | null>(null);
  const chunksRef = useRef<Blob[]>([]);
  const listRef = useRef<HTMLDivElement>(null);
  const here = state.location.id === location.id && !state.travel;
  const thread = useMemo(() => messages.map(toThread), [messages]);
  const byId = useMemo(() => new Map(thread.map((m) => [m.id, m])), [thread]);
  const { onScroll, stickToBottom } = useThreadScroll(listRef, {
    firstId: messages[0]?.id ?? null, lastId: (messages[messages.length - 1]?.id ?? 0) + hypeRows.length,
    hasOlder, loadingOlder, loadOlder: () => void loadOlder(),
  });
  // In a scrolling sheet, bring the composer into view when the tab opens.
  useEffect(() => { rootRef.current?.scrollIntoView({ block: 'nearest' }); }, []);

  useEffect(() => { replyRef.current = replyTo; }, [replyTo]);

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
      const r = await chatSend(trimmed, replyTo?.id ?? null);
      add(r);
      setText('');
      setReplyTo(null);
      stickToBottom();
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
            const result = await chatSendVoice(uploaded.path, uploaded.mime, replyRef.current?.id ?? null);
            add(result);
            setReplyTo(null);
            stickToBottom();
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

  const report = async (msg: ThreadMessage, reason: string) => {
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

  const block = async (msg: ThreadMessage) => {
    const userId = messages.find((x) => x.id === msg.id)?.user_id;
    if (!userId) return;
    try {
      const r = await chatBlock(userId);
      toast(r.message, 'good');
      dropUser(userId);
    } catch (e) {
      toast(errorMessage(e), 'bad');
    }
    setMenu(null);
  };

  const deleteForMe = async (msg: ThreadMessage) => {
    setMenu(null);
    try {
      await chatDeleteForMe('place', msg.id);
      dropMessage(msg.id);
      if (replyTo?.id === msg.id) setReplyTo(null);
    } catch (e) { toast(errorMessage(e), 'bad'); }
  };

  const deleteForEveryone = async (msg: ThreadMessage) => {
    setMenu(null);
    try {
      const r = await chatDeleteForEveryone('place', msg.id);
      patch({ id: msg.id, body: null, audio_path: null, audio_mime: null, deleted_at: r.deleted_at });
      if (r.audio_path) void discardVoiceUpload(r.audio_path).catch(() => undefined);
      if (replyTo?.id === msg.id) setReplyTo(null);
    } catch (e) { toast(errorMessage(e), 'bad'); }
  };

  const startReply = (m: ThreadMessage) => {
    setMenu(null);
    setReplyTo(m);
    inputRef.current?.focus({ preventScroll: true });
  };

  const jumpTo = async (id: number) => {
    for (let i = 0; i < 6; i++) {
      if (flashMessage(listRef.current, id)) return;
      const s = useChat.getState();
      if (!s.hasOlder) break;
      await s.loadOlder();
      await new Promise((r) => requestAnimationFrame(r));
    }
    toast('That message is no longer available.', 'info');
  };

  const menuActions = (m: ThreadMessage): MenuAction[] => {
    const acts: MenuAction[] = [];
    if (!m.deletedAt) acts.push({ label: 'Reply', icon: 'reply', onSelect: () => startReply(m) });
    if (m.body) acts.push({ label: 'Copy text', icon: 'copy', onSelect: () => { void navigator.clipboard?.writeText(m.body ?? '').then(() => toast('Copied.', 'good')).catch(() => undefined); setMenu(null); } });
    acts.push({ label: 'Delete for me', icon: 'trash', onSelect: () => void deleteForMe(m) });
    if (canDeleteForEveryone(m, deleteHours)) acts.push({ label: 'Delete for everyone', icon: 'trash', tone: 'danger', onSelect: () => void deleteForEveryone(m) });
    if (!m.mine && !m.deletedAt) acts.push({ label: 'Report…', icon: 'warning', onSelect: () => setReporting(true) });
    if (!m.mine) acts.push({ label: `Block @${m.name}`, icon: 'eyeOff', tone: 'danger', onSelect: () => void block(m) });
    return acts;
  };
  const closeMenu = () => { setMenu(null); setReporting(false); };

  return (
    <div className="chat" ref={rootRef}>
      <p className="chat__rules"><Icon name="shield" size={14} /> Be respectful — 18+ only. Swipe a message to reply, hold it for more.</p>
      <div className="chat__thread">
        <div className="chat__list" ref={listRef} role="log" aria-live="polite" aria-label={`Chat at ${location.name}`} onScroll={onScroll}>
          {loadingOlder && <div className="msg-older"><Spinner size={16} /></div>}
          {!hasOlder && status === 'ready' && messages.length > 0 && <div className="msg-older msg-older--end">Messages from the last 14 days</div>}
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
          {mergeHype(messages, hypeLoc === location.id ? hypeRows : []).map((m, i, all) => 'kind' in m ? (
            <div key={`h${m.id}`} className="chat-hype" role="note">
              <span className="chat-hype__who">🎤 Hype man · {timeOf(m.created_at)}</span>
              {m.text}
            </div>
          ) : (() => {
            const t = byId.get(m.id)!;
            return (
              <Fragment key={m.id}>
                <DaySep iso={t.createdAt} prevIso={all[i - 1]?.created_at ?? null} />
                <MessageRow m={t} reply={resolveReply(t, byId)} showFace onReply={startReply}
                  onMenu={(x) => { setReporting(false); setMenu(x); }} onQuote={(id) => void jumpTo(id)} />
              </Fragment>
            );
          })())}
        </div>
        {menu && (
          <MessageMenu m={menu} actions={menuActions(menu)} onClose={closeMenu}>
            {reporting ? (
              <div className="msg-menu__reasons">
                <span className="chat-msg__why">Why are you reporting this?</span>
                {REASONS.map((r) => (
                  <button key={r} type="button" className="chip" onClick={() => void report(menu, r)}>{r}</button>
                ))}
              </div>
            ) : undefined}
          </MessageMenu>
        )}
      </div>
      {note && <p className="chat__note" role="status">{note}</p>}
      {recording && <div className="chat__recording" role="status"><span className="social-recording__dot" /> Recording voice message</div>}
      <div className="chat__composer kb-composer">
        {replyTo && <ReplyBar reply={previewOf(replyTo)} onClear={() => setReplyTo(null)} />}
        <form className="chat__form" onSubmit={(e) => { e.preventDefault(); void send(); }}>
          <textarea ref={inputRef} className="chat__input" value={text} rows={1} enterKeyHint="send" autoComplete="off"
            placeholder={enabled ? `Message people at ${location.name}…` : 'Chat is switched off for now'}
            disabled={!enabled} readOnly={recording || recordingBusy || sending} aria-label="Message"
            onKeyDown={(e) => {
              if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); void send(); }
            }}
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
    </div>
  );
}
