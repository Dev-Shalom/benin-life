import { Fragment, useCallback, useEffect, useMemo, useRef, useState } from 'react';
import type { FormEvent, RefObject } from 'react';
import type { RealtimeChannel } from '@supabase/supabase-js';
import { AvatarPortrait } from '../../../art/avatar3d';
import { chatBlock, chatDeleteForEveryone, chatDeleteForMe } from '../../../api/chat';
import {
  discardVoiceUpload, socialCancelFriendRequest, socialCancelHouseInvite,
  socialFriendRequests, socialFriends, socialHomeAdmit, socialHouseInvites, socialMessageHistory,
  socialMarkRead, socialOpenConversation, socialRemoveFriend, socialRespondFriend,
  socialRespondHouseInvite, socialSearchPlayers, socialSendHouseInvite, socialSendMessage,
  uploadVoiceMessage,
  type DirectMessage, type FriendRequest, type HouseInvite, type SocialFriend, type SocialPlayer,
} from '../../../api/social';
import { errorMessage } from '../../../lib/api';
import { useConfig } from '../../../lib/config';
import { supabase } from '../../../lib/supabase';
import type { GameState } from '../../../lib/types';
import { useGame } from '../../../state/game';
import { Button, EmptyState, Icon, Spinner, toast } from '../../../ui';
import { useEscape } from '../../../ui/presence';
import { SocialPlayerButton } from '../SocialPlayerButton';
import ChatPanel from '../../../panels/ChatPanel';
import {
  canDeleteForEveryone, DaySep, flashMessage, MessageMenu, MessageRow, previewOf, ReplyBar, resolveReply,
  useThreadScroll, useViewportVars, type MenuAction, type ThreadMessage,
} from '../../../panels/chatKit';

const PAGE_SIZE = 50;

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

/** The conversation thread; hooks live here so they run only while a conversation is open. */
function DmThread({ messages, listRef, hasOlder, loadingOlder, loadOlder, initialLoading, friendName, onReply, onMenu }: {
  messages: DirectMessage[]; listRef: RefObject<HTMLDivElement | null>; hasOlder: boolean; loadingOlder: boolean;
  loadOlder: () => Promise<boolean>; initialLoading: boolean; friendName: string;
  onReply: (m: ThreadMessage) => void; onMenu: (m: ThreadMessage) => void;
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
    <div className="social-message-list" ref={listRef} role="log" aria-live="polite" aria-label={`Messages with ${friendName}`} onScroll={onScroll}>
      {loadingOlder && <div className="msg-older"><Spinner size={16} /></div>}
      {!hasOlder && !initialLoading && messages.length > 0 && <div className="msg-older msg-older--end">Messages from the last 14 days</div>}
      {initialLoading && messages.length === 0 ? <div className="social-loading"><Spinner size={20} /></div>
        : messages.length === 0 ? <EmptyState icon="chat" title="Say hello" body={`Your private conversation with @${friendName} starts here.`} />
          : thread.map((m, i) => (
            <Fragment key={m.id}>
              <DaySep iso={m.createdAt} prevIso={thread[i - 1]?.createdAt ?? null} />
              <MessageRow m={m} reply={resolveReply(m, byId)} onReply={onReply} onMenu={onMenu} onQuote={(id) => void jumpTo(id)} />
            </Fragment>
          ))}
    </div>
  );
}

interface SocialAppProps {
  state: GameState;
  onGoHome: () => void;
}

export default function SocialApp({ state, onGoHome }: SocialAppProps) {
  const [friends, setFriends] = useState<SocialFriend[] | null>(null);
  const [requests, setRequests] = useState<FriendRequest[] | null>(null);
  const [invites, setInvites] = useState<HouseInvite[] | null>(null);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [query, setQuery] = useState('');
  const [searching, setSearching] = useState(false);
  const [results, setResults] = useState<SocialPlayer[] | null>(null);
  const [selected, setSelected] = useState<string[]>([]);
  const [busy, setBusy] = useState<string | null>(null);
  const [conversation, setConversation] = useState<{ id: number; friend: SocialFriend } | null>(null);
  const [messages, setMessages] = useState<DirectMessage[]>([]);
  const [messagesLoading, setMessagesLoading] = useState(false);
  const [hasOlder, setHasOlder] = useState(false);
  const [loadingOlder, setLoadingOlder] = useState(false);
  const [replyTo, setReplyTo] = useState<ThreadMessage | null>(null);
  useEscape(Boolean(replyTo), () => setReplyTo(null));
  const [menu, setMenu] = useState<ThreadMessage | null>(null);
  const [headMenu, setHeadMenu] = useState(false);
  const replyRef = useRef<ThreadMessage | null>(null);
  const draftRef = useRef<HTMLTextAreaElement>(null);
  const messagesRef = useRef<DirectMessage[]>([]);
  const { cfg } = useConfig();
  const deleteHours = cfg('chat.delete_everyone_hours', 48);
  const [draft, setDraft] = useState('');
  const [sending, setSending] = useState(false);
  const [recording, setRecording] = useState(false);
  const [audioBusy, setAudioBusy] = useState(false);
  const [recordSeconds, setRecordSeconds] = useState(0);
  const eventsRevision = useGame((s) => s.events[0]?.id ?? 0);
  const refreshGame = useGame((s) => s.refresh);
  const [houseChat, setHouseChat] = useState(false);
  const listRef = useRef<HTMLDivElement>(null);
  const recorderRef = useRef<MediaRecorder | null>(null);
  const streamRef = useRef<MediaStream | null>(null);
  const chunksRef = useRef<Blob[]>([]);
  const recordingStartedRef = useRef(0);
  const discardOnStopRef = useRef(false);
  const channelRef = useRef<RealtimeChannel | null>(null);

  const reload = useCallback(async () => {
    try {
      const [nextFriends, nextRequests, nextInvites] = await Promise.all([
        socialFriends(), socialFriendRequests(), socialHouseInvites(),
      ]);
      setFriends(nextFriends ?? []);
      setRequests(nextRequests ?? []);
      setInvites(nextInvites ?? []);
      setLoadError(null);
    } catch (e) {
      setLoadError(errorMessage(e));
    }
  }, []);

  useEffect(() => {
    void reload();
    const timer = window.setInterval(() => void reload(), 20_000);
    return () => window.clearInterval(timer);
  }, [reload]);

  // Friend requests and door knocks arrive through the existing per-player events channel.
  useEffect(() => { if (eventsRevision) void reload(); }, [eventsRevision, reload]);

  useEffect(() => {
    if (!recording) return;
    const timer = window.setInterval(() => setRecordSeconds(Math.floor((Date.now() - recordingStartedRef.current) / 1000)), 1000);
    return () => window.clearInterval(timer);
  }, [recording]);

  const appendMessage = useCallback((message: DirectMessage) => {
    setMessages((old) => old.some((m) => m.id === message.id) ? old : [...old, message].sort((a, b) => a.id - b.id));
  }, []);
  useEffect(() => { replyRef.current = replyTo; }, [replyTo]);
  useEffect(() => { messagesRef.current = messages; }, [messages]);

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
    if (!conversation) return;
    let alive = true;
    setMessages([]);
    setHasOlder(false);
    setReplyTo(null);
    setMenu(null);
    setHeadMenu(false);
    setMessagesLoading(true);
    const conversationId = conversation.id;
    const loadLatest = async () => {
      try {
        const rows = await socialMessageHistory(conversationId, null, PAGE_SIZE);
        if (!alive) return;
        setMessages(rows ?? []);
        setHasOlder((rows ?? []).length === PAGE_SIZE);
        await socialMarkRead(conversationId);
        if (alive) void reload();
      } catch (e) {
        if (alive) toast(errorMessage(e), 'bad');
      } finally {
        if (alive) setMessagesLoading(false);
      }
    };
    const channel = supabase
      .channel(`dm-${conversationId}-${state.profile.id}`)
      .on('postgres_changes', {
        event: 'INSERT', schema: 'public', table: 'player_messages', filter: `conversation_id=eq.${conversationId}`,
      }, (payload) => {
        const raw = payload.new as Omit<DirectMessage, 'sender_username' | 'mine'>;
        const mine = raw.sender_id === state.profile.id;
        appendMessage({ ...raw, sender_username: mine ? state.profile.username : conversation.friend.username, mine });
        if (!mine) void socialMarkRead(conversationId).then(() => reload()).catch(() => undefined);
      })
      .on('postgres_changes', {
        event: 'UPDATE', schema: 'public', table: 'player_messages', filter: `conversation_id=eq.${conversationId}`,
      }, (payload) => patchMessage(payload.new as DirectMessage))
      .subscribe((status) => { if (status === 'SUBSCRIBED') void loadLatest(); });
    channelRef.current = channel;
    return () => {
      alive = false;
      if (channelRef.current === channel) channelRef.current = null;
      void supabase.removeChannel(channel);
    };
  }, [conversation, state.profile.id, state.profile.username, appendMessage, patchMessage, reload]);

  useEffect(() => () => {
    discardOnStopRef.current = true;
    if (recorderRef.current?.state === 'recording') recorderRef.current.stop();
    streamRef.current?.getTracks().forEach((track) => track.stop());
    if (channelRef.current) void supabase.removeChannel(channelRef.current);
  }, []);

  const pendingKnocks = useMemo(() => (invites ?? []).filter((i) => i.role === 'host' && i.status === 'knocking'), [invites]);
  const pendingRequests = useMemo(() => (requests ?? []).filter((r) => r.direction === 'incoming'), [requests]);
  const sentRequests = useMemo(() => (requests ?? []).filter((r) => r.direction === 'outgoing'), [requests]);
  const homeNow = !state.travel && state.profile.location_id === state.location.id
    && (state.profile.location_id === state.profile.home_location_id || Boolean(state.profile.home_visit_host_id));
  useEffect(() => { if (!homeNow) setHouseChat(false); }, [homeNow]);

  const search = async (event: FormEvent) => {
    event.preventDefault();
    const value = query.trim();
    if (value.length < 3) { setResults([]); return; }
    setSearching(true);
    try { setResults(await socialSearchPlayers(value)); }
    catch (e) { toast(errorMessage(e), 'bad'); }
    finally { setSearching(false); }
  };

  const requestAction = async (r: FriendRequest, accept: boolean) => {
    setBusy(`request:${r.id}`);
    try {
      const result = r.direction === 'incoming'
        ? await socialRespondFriend(r.id, accept)
        : await socialCancelFriendRequest(r.id);
      toast(result.message, accept ? 'good' : 'info');
      await reload();
    } catch (e) { toast(errorMessage(e), 'bad'); }
    finally { setBusy(null); }
  };

  const houseAction = async (invite: HouseInvite, action: 'accept' | 'decline' | 'cancel' | 'admit' | 'turn-away') => {
    setBusy(`invite:${invite.id}`);
    try {
      if (action === 'accept') await socialRespondHouseInvite(invite.id, true);
      else if (action === 'decline') await socialRespondHouseInvite(invite.id, false);
      else if (action === 'admit') await socialHomeAdmit(invite.id, true);
      else if (action === 'turn-away') await socialHomeAdmit(invite.id, false);
      else await socialCancelHouseInvite(invite.id);
      await reload();
      if (action === 'admit') toast(`@${invite.guest_username} is inside your home.`, 'good');
      else if (action === 'accept') toast(`You are at @${invite.host_username}'s door.`, 'good');
    } catch (e) { toast(errorMessage(e), 'bad'); }
    finally { setBusy(null); }
  };

  const inviteSelected = async () => {
    if (!selected.length) return;
    setBusy('bulk-invite');
    const results = await Promise.allSettled(selected.map((id) => socialSendHouseInvite(id)));
    const sent = results.filter((r) => r.status === 'fulfilled').length;
    const failed = results.length - sent;
    if (sent) toast(`${sent} house invite${sent === 1 ? '' : 's'} sent.`, 'good');
    if (failed) toast(`${failed} invite${failed === 1 ? '' : 's'} could not be sent.`, 'bad');
    setSelected([]);
    await reload();
    setBusy(null);
  };

  const openConversation = async (friend: SocialFriend) => {
    setBusy(`message:${friend.id}`);
    try {
      const opened = await socialOpenConversation(friend.id);
      setConversation({ id: opened.id, friend });
    } catch (e) { toast(errorMessage(e), 'bad'); }
    finally { setBusy(null); }
  };

  const closeConversation = () => {
    if (recorderRef.current?.state === 'recording') {
      discardOnStopRef.current = true;
      recorderRef.current.stop();
      streamRef.current?.getTracks().forEach((track) => track.stop());
      recorderRef.current = null;
      setRecording(false);
    }
    setConversation(null);
    setMessages([]);
    setDraft('');
    setReplyTo(null);
  };

  const sendText = async () => {
    const body = draft.trim();
    if (!conversation || !body || sending || recording || audioBusy) return;
    setSending(true);
    try {
      appendMessage(await socialSendMessage(conversation.id, body, null, null, replyTo?.id ?? null));
      setDraft('');
      setReplyTo(null);
      const el = listRef.current;
      if (el) requestAnimationFrame(() => { el.scrollTop = el.scrollHeight; });
      void reload();
    } catch (e) { toast(errorMessage(e), 'bad'); }
    finally { setSending(false); }
  };

  const stopRecording = () => {
    if (recorderRef.current?.state === 'recording') {
      setAudioBusy(true);
      recorderRef.current.stop();
    }
  };

  const startRecording = async () => {
    if (!conversation || audioBusy || recording) return;
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
        const activeConversation = conversation;
        void (async () => {
          if (!activeConversation || blob.size === 0) throw new Error('No audio was recorded.');
          const uploaded = await uploadVoiceMessage(activeConversation.id, state.profile.id, blob, blob.type);
          try {
            appendMessage(await socialSendMessage(activeConversation.id, null, uploaded.path, uploaded.mime, replyRef.current?.id ?? null));
            setReplyTo(null);
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

  const removeFriend = async () => {
    if (!conversation) return;
    setBusy('remove-friend');
    try {
      const result = await socialRemoveFriend(conversation.friend.id);
      toast(result.message, 'info');
      closeConversation();
      await reload();
    } catch (e) { toast(errorMessage(e), 'bad'); }
    finally { setBusy(null); }
  };

  const blockFriend = async () => {
    if (!conversation) return;
    setBusy('block-friend');
    try {
      const result = await chatBlock(conversation.friend.id);
      toast(result.message, 'info');
      closeConversation();
      await reload();
    } catch (e) { toast(errorMessage(e), 'bad'); }
    finally { setBusy(null); }
  };

  /** Load the next older page; resolves true when rows were added. */
  const loadOlder = async () => {
    const current = messagesRef.current;
    if (!conversation || !current.length || messagesLoading || loadingOlder || !hasOlder) return false;
    setLoadingOlder(true);
    try {
      const older = (await socialMessageHistory(conversation.id, current[0].id, PAGE_SIZE)) ?? [];
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

  if (conversation) {
    const hasText = Boolean(draft.trim());
    return (
      <div className="phone-app__body social-app social-app--conversation">
        <div className="social-conversation-head">
          <button type="button" className="social-conversation-head__back" onClick={closeConversation} aria-label="Back to people">
            <Icon name="back" size={18} stroke={2.6} />
          </button>
          <span className="social-conversation-head__who">
            <span className="social-avatar">{conversation.friend.avatar && <AvatarPortrait config={conversation.friend.avatar} size={34} />}</span>
            <b>@{conversation.friend.username}</b>
          </span>
          <button type="button" className="social-conversation-head__more" aria-label="Conversation options" aria-expanded={headMenu}
            onClick={() => setHeadMenu((v) => !v)}><Icon name="more" size={20} stroke={3} /></button>
          {headMenu && (
            <div className="social-conversation-head__menu" role="menu">
              <Button size="sm" variant="ghost" loading={busy === 'remove-friend'} onClick={() => void removeFriend()}>Unfriend</Button>
              <Button size="sm" variant="danger" loading={busy === 'block-friend'} onClick={() => void blockFriend()}>Block</Button>
            </div>
          )}
        </div>
        <div className="social-thread">
          <DmThread messages={messages} listRef={listRef} hasOlder={hasOlder} loadingOlder={loadingOlder} loadOlder={loadOlder}
            initialLoading={messagesLoading} friendName={conversation.friend.username} onReply={startReply} onMenu={setMenu} />
          {menu && <MessageMenu m={menu} actions={menuActions(menu)} onClose={() => setMenu(null)} />}
        </div>
        {recording && <div className="social-recording" role="status"><span className="social-recording__dot" /> Recording voice note · {durationLabel(recordSeconds)}</div>}
        <div className="social-composer">
          {replyTo && <ReplyBar reply={previewOf(replyTo)} onClear={() => setReplyTo(null)} />}
          <form className="social-compose" onSubmit={(e) => { e.preventDefault(); void sendText(); }}>
            <textarea ref={draftRef} value={draft} rows={1} placeholder="Message" aria-label="Private message" enterKeyHint="send"
              onKeyDown={(e) => {
                if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); void sendText(); }
                }}
              disabled={sending || recording || audioBusy} onChange={(e) => setDraft(e.target.value)} />
            <div className="social-compose__actions">
              <Button type={hasText ? 'submit' : 'button'} className={`social-compose__primary${recording ? ' is-recording' : ''}`} variant="green"
                aria-label={recording ? `Send voice note, ${durationLabel(recordSeconds)}` : hasText ? 'Send message' : 'Record voice message'}
                title={recording ? `Send voice note · ${durationLabel(recordSeconds)}` : hasText ? 'Send message' : 'Record voice message'}
                disabled={audioBusy || sending} loading={sending || (audioBusy && !recording)}
                onClick={() => { if (recording) stopRecording(); else if (!hasText) void startRecording(); }}>
                <Icon name={recording || hasText ? 'send' : 'mic'} size={18} />
              </Button>
            </div>
          </form>
          <span className="social-compose__hint">Enter to send · Shift+Enter for a new line</span>
        </div>
      </div>
    );
  }

  if (houseChat && homeNow) {
    return (
      <div className="phone-app__body social-app social-app--house-chat">
        <div className="social-conversation-head">
          <Button size="sm" variant="ghost" onClick={() => setHouseChat(false)}>‹ Messages</Button>
          <b className="grow">House chat · everyone inside</b>
        </div>
        <ChatPanel state={state} location={state.location} refresh={refreshGame} close={() => setHouseChat(false)} />
      </div>
    );
  }

  return (
    <div className="phone-app__body social-app">
      {loadError && <div className="social-error" role="alert">{loadError}<Button size="sm" variant="ghost" onClick={() => void reload()}>Retry</Button></div>}

      {homeNow && (
        <button type="button" className="social-house-chat" onClick={() => setHouseChat(true)}>
          <span className="social-house-chat__icon"><Icon name="chat" size={19} /></span>
          <span className="grow"><b>House chat</b><small>Talk with everyone currently inside</small></span>
          <Icon name="chevronRight" size={17} />
        </button>
      )}

      <section className="social-section">
        <div className="social-section__title"><h3>Find a player</h3><span>Search by username</span></div>
        <form className="social-search" onSubmit={(e) => void search(e)}>
          <input value={query} minLength={3} maxLength={20} placeholder="Type at least 3 letters" aria-label="Player username"
            onChange={(e) => { setQuery(e.target.value); setResults(null); }} />
          <Button type="submit" size="sm" variant="green" disabled={query.trim().length < 3 || searching} loading={searching}>Find</Button>
        </form>
        {results && <div className="social-list">
          {results.length === 0 ? <p className="social-muted">No players found. Check the spelling and try again.</p>
            : results.map((player) => (
              <div className="social-player" key={player.id}>
                <span className="social-avatar">{player.avatar && <AvatarPortrait config={player.avatar} size={36} />}</span>
                <b className="grow">@{player.username}</b>
                <SocialPlayerButton userId={player.id} onChanged={() => void reload()} />
              </div>
            ))}
        </div>}
      </section>

      <section className="social-section">
        <div className="social-section__title"><h3>Friend requests</h3><span>{pendingRequests.length} waiting for you</span></div>
        {requests === null ? <div className="social-loading"><Spinner size={18} /></div>
          : pendingRequests.length ? <div className="social-list">
            {pendingRequests.map((r) => <div className="social-player" key={r.id}>
              <span className="social-avatar">{r.avatar && <AvatarPortrait config={r.avatar} size={36} />}</span>
              <b className="grow">@{r.username}</b>
              <Button size="sm" variant="ghost" disabled={busy === `request:${r.id}`} onClick={() => void requestAction(r, false)}>Decline</Button>
              <Button size="sm" variant="green" loading={busy === `request:${r.id}`} onClick={() => void requestAction(r, true)}>Accept</Button>
            </div>)}
          </div> : <p className="social-muted">No new friend requests.</p>}
        {sentRequests.length > 0 && <div className="social-list social-list--sent">
          {sentRequests.map((r) => <div className="social-player" key={r.id}>
            <span className="social-avatar">{r.avatar && <AvatarPortrait config={r.avatar} size={32} />}</span>
            <span className="grow">Waiting for <b>@{r.username}</b></span>
            <Button size="sm" variant="ghost" loading={busy === `request:${r.id}`} onClick={() => void requestAction(r, false)}>Cancel</Button>
          </div>)}
        </div>}
      </section>

      <section className="social-section">
        <div className="social-section__title"><h3>House visits</h3><span>Guests knock before they enter</span></div>
        {invites === null ? <div className="social-loading"><Spinner size={18} /></div>
          : invites.length === 0 ? <p className="social-muted">No pending house invites. Choose friends below to invite people over together.</p>
            : <div className="social-list">
              {invites.map((invite) => {
                const waitingAtDoor = invite.role === 'host' && invite.status === 'knocking';
                const incoming = invite.role === 'guest' && invite.status === 'invited';
                const guestKnocking = invite.role === 'guest' && invite.status === 'knocking';
                return <div className={`social-invite${waitingAtDoor ? ' is-knock' : ''}`} key={invite.id}>
                  <div className="social-invite__copy">
                    <b>{waitingAtDoor ? `@${invite.guest_username} is at your door` : incoming ? `@${invite.host_username} invited you home`
                      : guestKnocking ? `Waiting outside @${invite.host_username}'s home` : `Invite sent to @${invite.guest_username}`}</b>
                    <span>{invite.home_name} · {waitingAtDoor ? homeNow ? 'You are home; answer the door.' : 'Go home to let your guest in.'
                      : incoming ? 'Accept to knock and wait for them to answer.' : guestKnocking ? 'The host must let you in.' : 'Waiting for your friend to accept.'}</span>
                  </div>
                  {incoming && <>
                    <Button size="sm" variant="ghost" loading={busy === `invite:${invite.id}`} onClick={() => void houseAction(invite, 'decline')}>Decline</Button>
                    <Button size="sm" variant="green" loading={busy === `invite:${invite.id}`} onClick={() => void houseAction(invite, 'accept')}>Accept &amp; knock</Button>
                  </>}
                  {waitingAtDoor && <>
                    {homeNow
                      ? <Button size="sm" variant="green" loading={busy === `invite:${invite.id}`} onClick={() => void houseAction(invite, 'admit')}>Let in</Button>
                      : <Button size="sm" variant="green" onClick={onGoHome}>Go home</Button>}
                    <Button size="sm" variant="ghost" loading={busy === `invite:${invite.id}`} onClick={() => void houseAction(invite, 'turn-away')}>Decline</Button>
                  </>}
                  {(guestKnocking || (invite.role === 'host' && invite.status === 'invited')) &&
                    <Button size="sm" variant="ghost" loading={busy === `invite:${invite.id}`} onClick={() => void houseAction(invite, 'cancel')}>Cancel</Button>}
                </div>;
              })}
            </div>}
        {pendingKnocks.length > 0 && !homeNow && <p className="social-door-note"><Icon name="home" size={15} /> Your guests are waiting. You must be at your home to let them in.</p>}
      </section>

      <section className="social-section">
        <div className="social-section__title"><h3>Your friends</h3><span>{friends?.length ?? 0}</span></div>
        {friends === null ? <div className="social-loading"><Spinner size={18} /></div>
          : friends.length === 0 ? <EmptyState icon="people" title="Build your circle" body="Find a player above or add someone you meet around Benin." />
            : <div className="social-list">
              {friends.map((friend) => {
                const activeInvite = invites?.find((i) => i.role === 'host' && i.guest_id === friend.id);
                return <div className="social-friend" key={friend.id}>
                  <label className="social-friend__pick" title={`Select ${friend.username} for a group house invite`}>
                    <input type="checkbox" checked={selected.includes(friend.id)} disabled={Boolean(activeInvite)}
                      onChange={(e) => setSelected((old) => e.target.checked ? [...old, friend.id] : old.filter((id) => id !== friend.id))} />
                  </label>
                  <span className="social-avatar">{friend.avatar && <AvatarPortrait config={friend.avatar} size={40} />}</span>
                  <div className="social-friend__main">
                    <b>@{friend.username}</b>
                    <span>{friend.unread > 0 ? `${friend.unread} unread message${friend.unread === 1 ? '' : 's'}`
                      : friend.last_message ? `${friend.last_sender_id === state.profile.id ? 'You: ' : ''}${friend.last_message}`
                      : friend.at_home ? 'At home' : 'Around Benin'}</span>
                  </div>
                  <Button size="sm" variant="ghost" loading={busy === `message:${friend.id}`} onClick={() => void openConversation(friend)}>
                    {friend.unread > 0 ? 'Open' : 'Message'}
                  </Button>
                  {activeInvite && <span className="social-invite-tag">{activeInvite.status === 'knocking' ? 'At door' : 'Invited'}</span>}
                </div>;
              })}
              <div className="social-group-invite">
                <Button variant="green" block disabled={!selected.length || busy === 'bulk-invite'} loading={busy === 'bulk-invite'} onClick={() => void inviteSelected()}>
                  Invite {selected.length || ''} friend{selected.length === 1 ? '' : 's'} to my home
                </Button>
                {!homeNow && <small>You can send invites from anywhere. You must be home before guests can enter.</small>}
              </div>
            </div>}
      </section>
    </div>
  );
}
