// M4: one private conversation in Phone → Messages (docs/CHAT.md "M4"). Header with @name and ⋯ (unfriend / block),
// the privacy line, the streak card, Invite / Visit / Send money chips, the thread (day separators, "New messages"
// divider, blue bubbles with ✓ / ✓✓ receipts, M3 reply / menu / delete / 14-day paging), quick replies, and the
// composer (emoji picker, text, voice note).
import { Fragment, useCallback, useEffect, useMemo, useRef, useState } from 'react';
import type { ReactNode, RefObject } from 'react';
import type { RealtimeChannel } from '@supabase/supabase-js';
import { bankTransfer } from '../../../api/bank';
import { chatBlock, chatDeleteForEveryone, chatDeleteForMe } from '../../../api/chat';
import {
  discardVoiceUpload, socialHomeAdmit, socialMarkRead, socialMessageHistory, socialRemoveFriend,
  socialRespondHouseInvite, socialSendHouseInvite, socialSendMessage, socialStreak, uploadVoiceMessage,
  type DirectMessage, type HouseInvite, type SocialFriend, type SocialStreak,
} from '../../../api/social';
import { errorMessage } from '../../../lib/api';
import { pushPromptAfterDm } from '../PushPrompt';
import { useConfig } from '../../../lib/config';
import { naira } from '../../../lib/format';
import { supabase } from '../../../lib/supabase';
import { startPoller, trackSubscribe, usePollMode } from '../../../lib/realtime';
import type { GameState } from '../../../lib/types';
import { useGame } from '../../../state/game';
import { Button, EmptyState, Icon, Spinner, toast } from '../../../ui';
import { useEscape } from '../../../ui/presence';
import { AmountBox } from '../../../panels/bank/BankUI';
import { realWait, useBankInfo } from '../../../panels/bank/bankHooks';
import {
  canDeleteForEveryone, DaySep, flashMessage, MessageMenu, MessageRow, previewOf, ReplyBar, resolveReply,
  useThreadScroll, useViewportVars, type MenuAction, type Receipt, type ThreadMessage,
} from '../../../panels/chatKit';

const PAGE_SIZE = 50;
const QUICK_REPLIES = ['How far? 👋', 'I dey o 😄', 'Wetin dey happen?', 'Where you dey?', 'Come my house 🏠', 'LOL 😂', 'On my way 🚶🏾', 'Thank you o 🙏🏾'];
const EMOJI = ['😀', '😂', '🤣', '😊', '😍', '😘', '😎', '🤔', '😅', '😭', '😡', '🥺', '🙄', '😴', '🤗', '👍', '👎', '👋', '🙏🏾', '👏🏾',
  '💪🏾', '🔥', '❤️', '💯', '🎉', '🏠', '🚗', '💸', '🍲', '⚽'];
/** Prefix of the DM sent after a Send money transfer; the list turns it into "@x sent you ₦…". */
export const MONEY_PREFIX = '💸 Sent you ';

function durationLabel(seconds: number) {
  const mins = Math.floor(seconds / 60);
  return `${mins}:${String(seconds % 60).padStart(2, '0')}`;
}

function toThread(m: DirectMessage): ThreadMessage {
  return {
    id: m.id, mine: m.mine, name: m.sender_username, createdAt: m.created_at, body: m.body, audioPath: m.audio_path,
    deletedAt: m.deleted_at ?? null, replyTo: m.reply_to ?? null, reply: m.reply ?? null,
  };
}

/** Small sheet over the app (in-phone, so it stays inside the phone frame). */
export function MiniSheet({ title, onClose, children }: { title: string; onClose: () => void; children: ReactNode }) {
  useEscape(true, onClose);
  return (
    <div className="msg-menu dm-sheet" role="dialog" aria-label={title}>
      <div className="msg-menu__backdrop" onClick={onClose} />
      <div className="msg-menu__card dm-sheet__card">
        <div className="dm-sheet__head">
          <b>{title}</b>
          <button type="button" className="dm-sheet__x" aria-label="Close" onClick={onClose}><Icon name="close" size={16} stroke={2.6} /></button>
        </div>
        {children}
      </div>
    </div>
  );
}

function DmThread({ messages, listRef, hasOlder, loadingOlder, loadOlder, initialLoading, friendName, newFromId, receiptOf, onReply, onMenu }: {
  messages: DirectMessage[]; listRef: RefObject<HTMLDivElement | null>; hasOlder: boolean; loadingOlder: boolean;
  loadOlder: () => Promise<boolean>; initialLoading: boolean; friendName: string; newFromId: number | null;
  receiptOf: (m: DirectMessage) => Receipt; onReply: (m: ThreadMessage) => void; onMenu: (m: ThreadMessage) => void;
}) {
  useViewportVars();
  const thread = useMemo(() => messages.map(toThread), [messages]);
  const byId = useMemo(() => new Map(thread.map((m) => [m.id, m])), [thread]);
  const { onScroll } = useThreadScroll(listRef, {
    firstId: messages[0]?.id ?? null, lastId: messages[messages.length - 1]?.id ?? null,
    hasOlder, loadingOlder, loadOlder: () => void loadOlder(),
  });
  const jumpTo = async (id: number) => {
    for (let i = 0; i < 6; i++) {
      if (flashMessage(listRef.current, id)) return;
      if (!(await loadOlder())) break;
      await new Promise((r) => requestAnimationFrame(r));
    }
    toast('That message is no longer available.', 'info');
  };
  return (
    <div className="social-message-list dm-list" ref={listRef} role="log" aria-live="polite" aria-label={`Messages with ${friendName}`} onScroll={onScroll}>
      {loadingOlder && <div className="msg-older"><Spinner size={16} /></div>}
      {!hasOlder && !initialLoading && messages.length > 0 && <div className="msg-older msg-older--end">Messages from the last 14 days</div>}
      {initialLoading && messages.length === 0 ? <div className="social-loading"><Spinner size={20} /></div>
        : messages.length === 0 ? <EmptyState icon="chat" title="Say hello" body={`Your private conversation with @${friendName} starts here.`} />
          : thread.map((m, i) => (
            <Fragment key={m.id}>
              <DaySep iso={m.createdAt} prevIso={thread[i - 1]?.createdAt ?? null} />
              {m.id === newFromId && <div className="dm-new" role="separator"><span>New messages</span></div>}
              <MessageRow m={m} dm receipt={m.mine ? receiptOf(messages[i]) : null} reply={resolveReply(m, byId)}
                onReply={onReply} onMenu={onMenu} onQuote={(id) => void jumpTo(id)} />
            </Fragment>
          ))}
    </div>
  );
}

function SendMoneySheet({ state, friend, onClose, onSent }: {
  state: GameState; friend: SocialFriend; onClose: () => void; onSent: (amount: number, note: string) => void;
}) {
  const refresh = useGame((s) => s.refresh);
  const { info, err } = useBankInfo();
  const [amount, setAmount] = useState('');
  const [note, setNote] = useState('');
  const [busy, setBusy] = useState(false);
  const t = info?.transfer;
  const n = Number(amount) || 0;
  const fee = t?.fee ?? 0;
  const bank = state.profile.bank;
  const maxSend = t ? Math.max(0, Math.min(bank - fee, t.left_today)) : 0;
  const wait = t?.new_account_wait_real_seconds ?? 0;
  const blocked = !t ? (err ?? 'Loading…') : wait > 0 ? `New accounts can send in ${realWait(wait)}`
    : n < t.min_amount ? `At least ${naira(t.min_amount)}` : n > t.left_today ? `Daily limit: ${naira(t.left_today)} left`
      : n + fee > bank ? 'Not enough in the bank' : null;
  const send = async () => {
    setBusy(true);
    try {
      const r = await bankTransfer(friend.username, n, note);
      toast(`💸 ${r.message}`, 'good');
      void refresh();
      onSent(n, note.trim());
    } catch (e) { toast(errorMessage(e), 'bad'); }
    finally { setBusy(false); }
  };
  return (
    <MiniSheet title={`Send money to @${friend.username}`} onClose={onClose}>
      <div className="dm-sheet__body stack">
        <p className="dm-sheet__lead">From your bank · balance <b>{naira(bank)}</b>{t ? ` · fee ${naira(fee)}` : ''}</p>
        {t && <AmountBox value={amount} onChange={setAmount} max={maxSend} min={t.min_amount} />}
        <input className="input" value={note} maxLength={80} placeholder="Note (optional): for chop, rent, thank you…" aria-label="Note"
          onChange={(e) => setNote(e.target.value)} />
        <Button variant="green" block loading={busy} disabled={Boolean(blocked) || busy} onClick={() => void send()}>
          {blocked ?? `Send ${naira(n)}`}
        </Button>
      </div>
    </MiniSheet>
  );
}

export function DmConversation({ state, friend, conversationId, invites, homeNow, reload, onClose, onGoHome }: {
  state: GameState; friend: SocialFriend; conversationId: number; invites: HouseInvite[]; homeNow: boolean;
  reload: () => Promise<void>; onClose: () => void; onGoHome: () => void;
}) {
  const me = state.profile;
  const pollMode = usePollMode(); // F1: Realtime full / off: poll this chat instead
  const [messages, setMessages] = useState<DirectMessage[]>([]);
  const [messagesLoading, setMessagesLoading] = useState(true);
  const [hasOlder, setHasOlder] = useState(false);
  const [loadingOlder, setLoadingOlder] = useState(false);
  const [newFromId, setNewFromId] = useState<number | null>(null);
  const [replyTo, setReplyTo] = useState<ThreadMessage | null>(null);
  useEscape(Boolean(replyTo), () => setReplyTo(null));
  const [menu, setMenu] = useState<ThreadMessage | null>(null);
  const [headMenu, setHeadMenu] = useState(false);
  const [sheet, setSheet] = useState<'streak' | 'money' | null>(null);
  const [emojiOpen, setEmojiOpen] = useState(false);
  useEscape(emojiOpen, () => setEmojiOpen(false));
  useEscape(headMenu, () => setHeadMenu(false));
  const [streak, setStreak] = useState<SocialStreak | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [draft, setDraft] = useState('');
  const [sending, setSending] = useState(false);
  const [recording, setRecording] = useState(false);
  const [audioBusy, setAudioBusy] = useState(false);
  const [recordSeconds, setRecordSeconds] = useState(0);
  const [quickShift, setQuickShift] = useState(() => (conversationId + new Date().getDate()) % QUICK_REPLIES.length);
  const { cfg } = useConfig();
  const deleteHours = cfg('chat.delete_everyone_hours', 48);
  const replyRef = useRef<ThreadMessage | null>(null);
  const draftRef = useRef<HTMLTextAreaElement>(null);
  const messagesRef = useRef<DirectMessage[]>([]);
  const listRef = useRef<HTMLDivElement>(null);
  const recorderRef = useRef<MediaRecorder | null>(null);
  const streamRef = useRef<MediaStream | null>(null);
  const chunksRef = useRef<Blob[]>([]);
  const recordingStartedRef = useRef(0);
  const discardOnStopRef = useRef(false);
  useEffect(() => { replyRef.current = replyTo; }, [replyTo]);
  useEffect(() => { messagesRef.current = messages; }, [messages]);

  const loadStreak = useCallback(() => {
    socialStreak(friend.id).then(setStreak).catch(() => undefined);
  }, [friend.id]);
  useEffect(() => { loadStreak(); }, [loadStreak]);

  const appendMessage = useCallback((message: DirectMessage) => {
    setMessages((old) => old.some((m) => m.id === message.id) ? old : [...old, message].sort((a, b) => a.id - b.id));
  }, []);

  /** Realtime UPDATE (read receipts, delete-for-everyone tombstones). */
  const patchMessage = useCallback((row: Partial<DirectMessage> & { id: number }) => {
    setMessages((old) => old.map((m) => {
      if (m.id === row.id) {
        return { ...m, body: row.body ?? null, audio_path: row.audio_path ?? null, audio_mime: row.audio_mime ?? null,
          read_at: row.read_at ?? m.read_at, deleted_at: row.deleted_at ?? m.deleted_at ?? null };
      }
      if (row.deleted_at && m.reply_to === row.id && m.reply) return { ...m, reply: { ...m.reply, deleted: true, snippet: null, voice: false } };
      return m;
    }));
  }, []);

  useEffect(() => {
    let alive = true;
    const loadLatest = async () => {
      try {
        const rows = (await socialMessageHistory(conversationId, null, PAGE_SIZE)) ?? [];
        if (!alive) return;
        setMessages(rows);
        setHasOlder(rows.length === PAGE_SIZE);
        setNewFromId(rows.find((r) => !r.mine && !r.read_at && !r.deleted_at)?.id ?? null);
        await socialMarkRead(conversationId);
        if (alive) void reload();
      } catch (e) {
        if (alive) toast(errorMessage(e), 'bad');
      } finally {
        if (alive) setMessagesLoading(false);
      }
    };
    const onInsert = (raw: Omit<DirectMessage, 'sender_username' | 'mine'>) => {
      if (messagesRef.current.some((m) => m.id === raw.id)) return;
      const mine = raw.sender_id === me.id;
      appendMessage({ ...raw, sender_username: mine ? me.username : friend.username, mine });
      if (!mine) {
        void socialMarkRead(conversationId).then(() => reload()).catch(() => undefined);
        loadStreak();
      }
    };
    if (pollMode) {
      // F1 poll mode: new messages in this chat every ~10 s while it is open (visible tab only)
      void loadLatest();
      const poller = startPoller(async () => {
        const after = messagesRef.current.reduce((m, x) => Math.max(m, x.id), 0);
        if (!after) return;
        const { data, error } = await supabase.from('player_messages').select('*')
          .eq('conversation_id', conversationId).gt('id', after).order('id', { ascending: true }).limit(30);
        if (!alive || error) return;
        for (const row of (data ?? []) as Omit<DirectMessage, 'sender_username' | 'mine'>[]) onInsert(row);
      }, () => 10_000);
      return () => { alive = false; poller.stop(); };
    }
    const channel: RealtimeChannel = supabase
      .channel(`dm-${conversationId}-${me.id}`)
      .on('postgres_changes', {
        event: 'INSERT', schema: 'public', table: 'player_messages', filter: `conversation_id=eq.${conversationId}`,
      }, (payload) => onInsert(payload.new as Omit<DirectMessage, 'sender_username' | 'mine'>))
      .on('postgres_changes', {
        event: 'UPDATE', schema: 'public', table: 'player_messages', filter: `conversation_id=eq.${conversationId}`,
      }, (payload) => patchMessage(payload.new as DirectMessage));
    trackSubscribe(channel, 'dm', (status) => { if (status === 'SUBSCRIBED') void loadLatest(); });
    return () => {
      alive = false;
      void supabase.removeChannel(channel);
    };
  }, [conversationId, me.id, me.username, friend.username, appendMessage, patchMessage, reload, loadStreak, pollMode]);

  useEffect(() => {
    if (!recording) return;
    const timer = window.setInterval(() => setRecordSeconds(Math.floor((Date.now() - recordingStartedRef.current) / 1000)), 1000);
    return () => window.clearInterval(timer);
  }, [recording]);

  useEffect(() => () => {
    discardOnStopRef.current = true;
    if (recorderRef.current?.state === 'recording') recorderRef.current.stop();
    streamRef.current?.getTracks().forEach((track) => track.stop());
  }, []);

  const lastSeen = Date.parse(friend.last_seen ?? '') || 0;
  const receiptOf = useCallback((m: DirectMessage): Receipt => {
    if (m.read_at) return 'read';
    return lastSeen >= Date.parse(m.created_at) ? 'delivered' : 'sent';
  }, [lastSeen]);

  const scrollDown = () => {
    const el = listRef.current;
    if (el) requestAnimationFrame(() => { el.scrollTop = el.scrollHeight; });
  };

  const sendBody = async (raw: string) => {
    const body = raw.trim();
    if (!body || sending || recording || audioBusy) return false;
    setSending(true);
    try {
      appendMessage(await socialSendMessage(conversationId, body, null, null, replyRef.current?.id ?? null));
      pushPromptAfterDm(); // P1: the best moment to offer notifications (once per device)
      setReplyTo(null);
      scrollDown();
      loadStreak();
      void reload();
      return true;
    } catch (e) { toast(errorMessage(e), 'bad'); return false; }
    finally { setSending(false); }
  };

  const sendText = async () => { if (await sendBody(draft)) setDraft(''); };

  const sendQuick = async (line: string) => {
    if (await sendBody(line)) setQuickShift((s) => (s + 1) % QUICK_REPLIES.length);
  };

  const insertEmoji = (e: string) => {
    const el = draftRef.current;
    const start = el?.selectionStart ?? draft.length;
    const end = el?.selectionEnd ?? draft.length;
    setDraft(draft.slice(0, start) + e + draft.slice(end));
    requestAnimationFrame(() => {
      el?.focus({ preventScroll: true });
      el?.setSelectionRange(start + e.length, start + e.length);
    });
  };

  const stopRecording = () => {
    if (recorderRef.current?.state === 'recording') {
      setAudioBusy(true);
      recorderRef.current.stop();
    }
  };

  const startRecording = async () => {
    if (audioBusy || recording) return;
    if (!navigator.mediaDevices?.getUserMedia || typeof MediaRecorder === 'undefined') {
      toast('Voice recording is not supported by this browser.', 'bad');
      return;
    }
    setAudioBusy(true);
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      streamRef.current = stream;
      const preferred = ['audio/webm;codecs=opus', 'audio/mp4', 'audio/ogg;codecs=opus'];
      const mimeType = preferred.find((type) => MediaRecorder.isTypeSupported(type));
      const recorder = mimeType ? new MediaRecorder(stream, { mimeType }) : new MediaRecorder(stream);
      chunksRef.current = [];
      discardOnStopRef.current = false;
      recorderRef.current = recorder;
      recorder.ondataavailable = (event) => { if (event.data.size > 0) chunksRef.current.push(event.data); };
      recorder.onerror = () => {
        toast('The voice note stopped unexpectedly. Please try again.', 'bad');
        stream.getTracks().forEach((track) => track.stop());
        setRecording(false);
        setAudioBusy(false);
      };
      recorder.onstop = () => {
        stream.getTracks().forEach((track) => track.stop());
        if (recorderRef.current === recorder) recorderRef.current = null;
        setRecording(false);
        if (discardOnStopRef.current) { chunksRef.current = []; setAudioBusy(false); return; }
        const blob = new Blob(chunksRef.current, { type: recorder.mimeType || 'audio/webm' });
        chunksRef.current = [];
        void (async () => {
          if (blob.size === 0) throw new Error('No audio was recorded.');
          const uploaded = await uploadVoiceMessage(conversationId, me.id, blob, blob.type);
          try {
            appendMessage(await socialSendMessage(conversationId, null, uploaded.path, uploaded.mime, replyRef.current?.id ?? null));
            setReplyTo(null);
            loadStreak();
            void reload();
          } catch (e) {
            await discardVoiceUpload(uploaded.path).catch(() => undefined);
            throw e;
          }
        })().catch((e) => toast(errorMessage(e), 'bad')).finally(() => setAudioBusy(false));
      };
      recorder.start(1000);
      recordingStartedRef.current = Date.now();
      setRecordSeconds(0);
      setRecording(true);
      setAudioBusy(false);
    } catch {
      streamRef.current?.getTracks().forEach((track) => track.stop());
      streamRef.current = null;
      setAudioBusy(false);
      toast('Microphone access was not allowed. Enable it in your browser settings and try again.', 'bad');
    }
  };

  const run = async (key: string, fn: () => Promise<void>) => {
    setBusy(key);
    try { await fn(); } catch (e) { toast(errorMessage(e), 'bad'); } finally { setBusy(null); }
  };

  const removeFriend = () => run('remove-friend', async () => {
    const result = await socialRemoveFriend(friend.id);
    toast(result.message, 'info');
    onClose();
    await reload();
  });
  const blockFriend = () => run('block-friend', async () => {
    const result = await chatBlock(friend.id);
    toast(result.message, 'info');
    onClose();
    await reload();
  });

  // Invite / Visit state for this friend
  const hostInvite = invites.find((i) => i.role === 'host' && i.guest_id === friend.id);
  const guestInvite = invites.find((i) => i.role === 'guest' && i.host_id === friend.id);
  const invite = () => run('invite', async () => {
    const r = await socialSendHouseInvite(friend.id);
    toast(r.message || `House invite sent to @${friend.username}.`, 'good');
    await reload();
  });
  const visit = () => run('visit', async () => {
    if (guestInvite?.status === 'invited') {
      await socialRespondHouseInvite(guestInvite.id, true);
      toast(`You are at @${friend.username}'s door. Wait for them to let you in.`, 'good');
      await reload();
    } else if (await sendBody('Can I come and visit? 🚪')) {
      toast(`Asked @${friend.username} for an invite. You can knock once they invite you.`, 'info');
    }
  });
  const admit = () => run('admit', async () => {
    if (!hostInvite) return;
    await socialHomeAdmit(hostInvite.id, true);
    toast(`@${friend.username} is inside your home.`, 'good');
    await reload();
  });

  const loadOlder = async () => {
    const current = messagesRef.current;
    if (!current.length || messagesLoading || loadingOlder || !hasOlder) return false;
    setLoadingOlder(true);
    try {
      const older = (await socialMessageHistory(conversationId, current[0].id, PAGE_SIZE)) ?? [];
      setMessages((rows) => [...older.filter((o) => !rows.some((r) => r.id === o.id)), ...rows]);
      setHasOlder(older.length === PAGE_SIZE);
      await new Promise((r) => requestAnimationFrame(r));
      return older.length > 0;
    } catch (e) { toast(errorMessage(e), 'bad'); return false; }
    finally { setLoadingOlder(false); }
  };

  const startReply = (m: ThreadMessage) => {
    setMenu(null);
    setReplyTo(m);
    draftRef.current?.focus({ preventScroll: true });
  };
  const deleteForMe = async (m: ThreadMessage) => {
    setMenu(null);
    try {
      await chatDeleteForMe('dm', m.id);
      setMessages((rows) => rows.filter((r) => r.id !== m.id));
      if (replyTo?.id === m.id) setReplyTo(null);
    } catch (e) { toast(errorMessage(e), 'bad'); }
  };
  const deleteForEveryone = async (m: ThreadMessage) => {
    setMenu(null);
    try {
      const r = await chatDeleteForEveryone('dm', m.id);
      patchMessage({ id: m.id, body: null, audio_path: null, audio_mime: null, deleted_at: r.deleted_at });
      if (r.audio_path) void discardVoiceUpload(r.audio_path).catch(() => undefined);
      if (replyTo?.id === m.id) setReplyTo(null);
      void reload();
    } catch (e) { toast(errorMessage(e), 'bad'); }
  };
  const menuActions = (m: ThreadMessage): MenuAction[] => {
    const acts: MenuAction[] = [];
    if (!m.deletedAt) acts.push({ label: 'Reply', icon: 'reply', onSelect: () => startReply(m) });
    if (m.body) acts.push({ label: 'Copy text', icon: 'copy', onSelect: () => { void navigator.clipboard?.writeText(m.body ?? '').then(() => toast('Copied.', 'good')).catch(() => undefined); setMenu(null); } });
    acts.push({ label: 'Delete for me', icon: 'trash', onSelect: () => void deleteForMe(m) });
    if (canDeleteForEveryone(m, deleteHours)) acts.push({ label: 'Delete for everyone', icon: 'trash', tone: 'danger', onSelect: () => void deleteForEveryone(m) });
    return acts;
  };

  const close = () => {
    if (recorderRef.current?.state === 'recording') {
      discardOnStopRef.current = true;
      recorderRef.current.stop();
      streamRef.current?.getTracks().forEach((track) => track.stop());
    }
    onClose();
  };

  const hasText = Boolean(draft.trim());
  const quick = [...QUICK_REPLIES.slice(quickShift), ...QUICK_REPLIES.slice(0, quickShift)];
  const n = streak?.streak ?? 0;
  const streakLine = n > 0
    ? streak?.today_me && streak.today_them ? 'You both showed up today. Keep it going tomorrow.'
      : streak?.today_me ? `Waiting for @${friend.username} today to keep it alive`
        : 'Do something together today to keep it alive'
    : streak?.today_me ? `You're in for today. Now @${friend.username} needs to reply.`
      : 'Both of you do something together on the same day, every day';

  return (
    <div className="phone-app__body social-app social-app--conversation dm">
      <header className="dm-head">
        <button type="button" className="msgs-iconbtn msgs-iconbtn--bare" onClick={close} aria-label="Back to messages">
          <Icon name="back" size={22} stroke={2.6} />
        </button>
        <h2 className="dm-head__name">@{friend.username}</h2>
        <button type="button" className="msgs-iconbtn" aria-label="Conversation options" aria-expanded={headMenu}
          onClick={() => setHeadMenu((v) => !v)}><Icon name="more" size={20} stroke={3} /></button>
        {headMenu && (
          <div className="social-conversation-head__menu dm-head__menu" role="menu">
            <Button size="sm" variant="ghost" loading={busy === 'remove-friend'} onClick={() => void removeFriend()}>Unfriend</Button>
            <Button size="sm" variant="danger" loading={busy === 'block-friend'} onClick={() => void blockFriend()}>Block</Button>
          </div>
        )}
      </header>
      <p className="dm-private"><span aria-hidden>🔒</span> Private · only you and @{friend.username} can see this</p>
      <div className={`dm-streak${n > 0 ? ' is-on' : ''}`}>
        <div className="dm-streak__text">
          <b><span aria-hidden>🔥</span> {n > 0 ? `${n}-day streak` : 'Start a streak'}</b>
          <span>{streakLine}</span>
        </div>
        <button type="button" className="dm-link" onClick={() => setSheet('streak')}>What counts?</button>
      </div>
      <div className="dm-chips">
        <button type="button" className="dm-chip dm-chip--green" disabled={busy === 'invite' || (Boolean(hostInvite) && !(hostInvite?.status === 'knocking' && homeNow))}
          onClick={() => void (hostInvite?.status === 'knocking' ? admit() : invite())}>
          <span aria-hidden>🏠</span> {hostInvite ? hostInvite.status === 'knocking' ? homeNow ? 'Let in' : 'At your door' : 'Invited' : 'Invite'}
        </button>
        {hostInvite?.status === 'knocking' && !homeNow
          ? <button type="button" className="dm-chip dm-chip--blue" onClick={onGoHome}><span aria-hidden>🏠</span> Go home</button>
          : <button type="button" className="dm-chip dm-chip--blue" disabled={busy === 'visit' || guestInvite?.status === 'knocking'} onClick={() => void visit()}>
            <span aria-hidden>🚪</span> {guestInvite?.status === 'invited' ? 'Knock' : guestInvite?.status === 'knocking' ? 'Knocking…' : 'Visit'}
          </button>}
        <button type="button" className="dm-chip dm-chip--gold" onClick={() => setSheet('money')}><span aria-hidden>💸</span> Send money</button>
      </div>
      <div className="social-thread">
        <DmThread messages={messages} listRef={listRef} hasOlder={hasOlder} loadingOlder={loadingOlder} loadOlder={loadOlder}
          initialLoading={messagesLoading} friendName={friend.username} newFromId={newFromId} receiptOf={receiptOf}
          onReply={startReply} onMenu={setMenu} />
        {menu && <MessageMenu m={menu} actions={menuActions(menu)} onClose={() => setMenu(null)} />}
      </div>
      {recording && <div className="social-recording" role="status"><span className="social-recording__dot" /> Recording voice note · {durationLabel(recordSeconds)}</div>}
      <div className="social-composer dm-composer kb-composer">
        {replyTo && <ReplyBar reply={previewOf(replyTo)} onClear={() => setReplyTo(null)} />}
        <div className="dm-quick" role="group" aria-label="Quick replies">
          {quick.map((line) => (
            <button key={line} type="button" className="dm-quick__chip" disabled={sending || recording} onClick={() => void sendQuick(line)}>{line}</button>
          ))}
        </div>
        {emojiOpen && (
          <div className="dm-emoji" role="dialog" aria-label="Emoji">
            {EMOJI.map((e) => <button key={e} type="button" onClick={() => insertEmoji(e)} aria-label={e}>{e}</button>)}
          </div>
        )}
        <form className="dm-compose" onSubmit={(e) => { e.preventDefault(); void sendText(); }}>
          <div className="dm-compose__field">
            <button type="button" className="dm-compose__emoji" aria-label="Emoji" aria-expanded={emojiOpen} onClick={() => setEmojiOpen((v) => !v)}>
              <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" aria-hidden>
                <circle cx="12" cy="12" r="9.2" /><path d="M8.2 14.2c.9 1.3 2.2 2 3.8 2s2.9-.7 3.8-2" /><circle cx="9" cy="9.8" r=".6" fill="currentColor" /><circle cx="15" cy="9.8" r=".6" fill="currentColor" />
              </svg>
            </button>
            <textarea ref={draftRef} value={draft} rows={1} placeholder={`Message @${friend.username}…`} aria-label="Private message" enterKeyHint="send"
              onKeyDown={(e) => { if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); void sendText(); } }}
              onFocus={() => setEmojiOpen(false)}
              readOnly={sending || recording || audioBusy} onChange={(e) => setDraft(e.target.value)} />
          </div>
          <Button type={hasText ? 'submit' : 'button'} className={`social-compose__primary dm-compose__primary${recording ? ' is-recording' : ''}`} variant="green"
            aria-label={recording ? `Send voice note, ${durationLabel(recordSeconds)}` : hasText ? 'Send message' : 'Record voice message'}
            title={recording ? `Send voice note · ${durationLabel(recordSeconds)}` : hasText ? 'Send message' : 'Record voice message'}
            disabled={audioBusy || sending} loading={sending || (audioBusy && !recording)}
            onClick={() => { if (recording) stopRecording(); else if (!hasText) void startRecording(); }}>
            <Icon name={recording || hasText ? 'send' : 'mic'} size={20} />
          </Button>
        </form>
      </div>
      {sheet === 'streak' && (
        <MiniSheet title="What counts for a streak?" onClose={() => setSheet(null)}>
          <div className="dm-sheet__body">
            <p className="dm-sheet__lead">A day counts when <b>both</b> of you show up for each other on the same day (WAT, midnight to midnight):</p>
            <ul className="dm-sheet__list">
              <li><span aria-hidden>💬</span> You both send each other a message (text or voice note).</li>
              <li><span aria-hidden>🏠</span> One of you visits the other's home (the door is opened).</li>
            </ul>
            <p className="dm-sheet__fine">Keep it going every day. Miss a full day and the streak starts again from zero.</p>
          </div>
        </MiniSheet>
      )}
      {sheet === 'money' && (
        <SendMoneySheet state={state} friend={friend} onClose={() => setSheet(null)}
          onSent={(amount, note) => { setSheet(null); void sendBody(`${MONEY_PREFIX}${naira(amount)}${note ? ` · ${note}` : ''}`); }} />
      )}
    </div>
  );
}
