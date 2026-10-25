// Benin Gist -> one group chat (docs/GIST.md). The DM bubbles from src/panels/chatKit.tsx (reply, delete, quote, voice notes), plus
// sender names, a money bubble, a pinned message, member roles and a settings page. Realtime is ONE channel for THIS group
// (INSERT + UPDATE on gist_messages, RLS: members only, blocked pairs hidden); in poll mode gist_group_after() every ~10 s instead.
import { Fragment, useCallback, useEffect, useMemo, useRef, useState } from 'react';
import type { RealtimeChannel } from '@supabase/supabase-js';
import {
  discardVoiceUpload,
} from '../../../../api/social';
import {
  gistGroupAdd, gistGroupAfter, gistGroupDelete, gistGroupDeleteMessage, gistGroupGet, gistGroupHistory, gistGroupJoin, gistGroupLeave,
  gistGroupMarkRead, gistGroupMembers, gistGroupMute, gistGroupPin, gistGroupRemove, gistGroupSend, gistGroupSendMoney, gistGroupSetRole,
  gistGroupUpdate, uploadGroupVoice, type GistGroup, type GroupMember, type GroupMessage,
} from '../../../../api/gist';
import { socialFriends, type SocialFriend } from '../../../../api/social';
import { errorMessage } from '../../../../lib/api';
import { useConfig } from '../../../../lib/config';
import { naira, timeAgo } from '../../../../lib/format';
import { supabase } from '../../../../lib/supabase';
import { startPoller, trackSubscribe, usePollMode } from '../../../../lib/realtime';
import type { AvatarConfig, GameState } from '../../../../lib/types';
import { useGist } from '../../../../state/gist';
import { AmountBox } from '../../../../panels/bank/BankUI';
import { realWait, useBankInfo } from '../../../../panels/bank/bankHooks';
import {
  canDeleteForEveryone, DaySep, flashMessage, MessageMenu, MessageRow, previewOf, ReplyBar, resolveReply, useThreadScroll, useViewportVars,
  type MenuAction, type ThreadMessage,
} from '../../../../panels/chatKit';
import { Button, EmptyState, Icon, Spinner, Switch, toast } from '../../../../ui';
import { useEscape } from '../../../../ui/presence';
import { EMOJI, MiniSheet } from '../DmConversation';
import { FeeLine, useFeeQuote } from '../FeeLine';
import { Face, GroupTile, PageHead, ReportSheet } from './gistKit';

const PAGE = 40;
type Sheet = null | 'money' | 'report-group' | { report: number };

function toThread(m: GroupMessage, avatars: Map<string, AvatarConfig | null>): ThreadMessage {
  return {
    id: m.id, mine: m.mine, name: m.username, createdAt: m.created_at, body: m.body, audioPath: m.audio_path, deletedAt: m.deleted_at,
    replyTo: m.reply_to, reply: m.reply, avatar: m.avatar ?? avatars.get(m.user_id) ?? null,
    money: m.kind === 'money' && m.amount ? { amount: m.amount, to: m.to_username ?? '', note: m.body } : null,
  };
}

function durationLabel(seconds: number) {
  return `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, '0')}`;
}

// ---------------------------------------------------------------------------------------------------------------
// Send money to a member of this group
// ---------------------------------------------------------------------------------------------------------------
function GroupMoneySheet({ state, group, preset, onClose, onSent }: {
  state: GameState; group: GistGroup; preset: string | null; onClose: () => void; onSent: (m: GroupMessage) => void;
}) {
  const { info, err } = useBankInfo();
  const [members, setMembers] = useState<GroupMember[] | null>(null);
  const [to, setTo] = useState<string | null>(preset);
  const [find, setFind] = useState('');
  const [amount, setAmount] = useState('');
  const [note, setNote] = useState('');
  const [busy, setBusy] = useState(false);
  useEffect(() => {
    let alive = true;
    gistGroupMembers(group.id).then((m) => alive && setMembers(m.filter((x) => x.id !== state.profile.id))).catch(() => alive && setMembers([]));
    return () => { alive = false; };
  }, [group.id, state.profile.id]);
  const t = info?.transfer;
  const n = Number(amount) || 0;
  const quote = useFeeQuote(n, t?.min_amount ?? 0);
  const fee = quote?.fee ?? t?.fee ?? 0;
  const bank = state.profile.bank;
  const maxSend = t ? Math.max(0, Math.min(bank - (t.fee_rules?.enabled ? 0 : fee), t.left_today)) : 0;
  const wait = t?.new_account_wait_real_seconds ?? 0;
  const blocked = !to ? 'Pick who gets it' : !t ? (err ?? 'Loading…') : wait > 0 ? `New accounts can send in ${realWait(wait)}`
    : n < t.min_amount ? `At least ${naira(t.min_amount)}` : n > t.left_today ? `Daily limit: ${naira(t.left_today)} left` : n + fee > bank ? 'Not enough in the bank' : null;
  const shown = (members ?? []).filter((m) => !find || m.username.toLowerCase().includes(find.replace(/^@/, '').toLowerCase())).slice(0, 30);
  const send = async () => {
    if (!to) return;
    setBusy(true);
    try {
      const r = await gistGroupSendMoney(group.id, to, n, note.trim() || null);
      toast(`💸 ${r.transfer.message}`, 'good');
      onSent(r.message);
      onClose();
    } catch (e) { toast(errorMessage(e), 'bad'); setBusy(false); }
  };
  return (
    <MiniSheet title="Send money in the group" onClose={onClose}>
      <div className="dm-sheet__body stack">
        {to ? (
          <div className="gist-pick is-chosen">
            <span>To <b>@{to}</b></span>
            <button type="button" onClick={() => setTo(null)}>Change</button>
          </div>
        ) : (
          <div className="gist-pick">
            <input className="input" value={find} placeholder="Find a member" aria-label="Find a member" onChange={(e) => setFind(e.target.value)} />
            <div className="gist-pick__list">
              {members === null ? <Spinner size={16} /> : shown.length === 0 ? <small>No member found.</small>
                : shown.map((m) => (
                  <button key={m.id} type="button" onClick={() => setTo(m.username)}><Face user={m} size={30} /><span>@{m.username}</span></button>
                ))}
            </div>
          </div>
        )}
        <p className="dm-sheet__lead">From your bank · balance <b>{naira(bank)}</b>{t && !t.fee_rules?.enabled ? ` · fee ${naira(fee)}` : ''}</p>
        {t && <AmountBox value={amount} onChange={setAmount} max={maxSend} min={t.min_amount} />}
        <FeeLine quote={quote} />
        <input className="input" value={note} maxLength={80} placeholder="Note (optional)" aria-label="Note" onChange={(e) => setNote(e.target.value)} />
        <Button variant="green" block loading={busy} disabled={Boolean(blocked) || busy} onClick={() => void send()}>{blocked ?? `Send ${naira(n)}${to ? ` to @${to}` : ''}`}</Button>
      </div>
    </MiniSheet>
  );
}

// ---------------------------------------------------------------------------------------------------------------
// Settings: info, members and what an owner / admin can do
// ---------------------------------------------------------------------------------------------------------------
function GroupSettings({ state, group, onBack, onChanged, onLeft, nav, onMoney }: {
  state: GameState; group: GistGroup; onBack: () => void; onChanged: (g: GistGroup) => void; onLeft: () => void;
  nav: { openProfile: (id: string) => void }; onMoney: (username: string) => void;
}) {
  const me = state.profile;
  const manage = Boolean(group.can_manage);
  const owner = Boolean(group.is_owner) || me.is_admin === true;
  const [members, setMembers] = useState<GroupMember[] | null>(null);
  const [editing, setEditing] = useState(false);
  const [name, setName] = useState(group.name);
  const [emoji, setEmoji] = useState(group.emoji);
  const [desc, setDesc] = useState(group.description);
  const [pick, setPick] = useState<GroupMember | null>(null);
  const [adding, setAdding] = useState(false);
  const [reporting, setReporting] = useState(false);
  const [busy, setBusy] = useState(false);

  const loadMembers = useCallback(async () => {
    try { setMembers(await gistGroupMembers(group.id)); } catch (e) { toast(errorMessage(e), 'bad'); setMembers([]); }
  }, [group.id]);
  useEffect(() => { void loadMembers(); }, [loadMembers]);
  const refreshGroup = async () => onChanged(await gistGroupGet(group.id));

  const run = async (fn: () => Promise<unknown>, after?: () => void | Promise<void>) => {
    setBusy(true);
    try { await fn(); await after?.(); } catch (e) { toast(errorMessage(e), 'bad'); }
    finally { setBusy(false); }
  };
  const save = () => run(async () => {
    const g = await gistGroupUpdate(group.id, { name, emoji, description: desc });
    onChanged({ ...group, ...g });
    setEditing(false);
    toast('Group saved.', 'good');
  });
  const togglePublic = (v: boolean) => run(async () => { const g = await gistGroupUpdate(group.id, { isPublic: v }); onChanged({ ...group, ...g }); });
  const leave = () => run(async () => { await gistGroupLeave(group.id); toast('You left the group.', 'info'); onLeft(); });
  const del = () => run(async () => { await gistGroupDelete(group.id); toast('Group deleted.', 'info'); onLeft(); });

  const memberAction = (m: GroupMember) => {
    const isMe = m.id === me.id;
    const canAct = manage && !isMe && m.role !== 'owner' && (m.role === 'member' || owner);
    const muted = m.muted_until && Date.parse(m.muted_until) > Date.now();
    return (
      <MiniSheet title={`@${m.username}`} onClose={() => setPick(null)}>
        <div className="dm-sheet__body gist-menu">
          <button type="button" className="msg-menu__item" onClick={() => { setPick(null); nav.openProfile(m.id); }}><Icon name="user" size={18} /> View profile</button>
          {!isMe && <button type="button" className="msg-menu__item" onClick={() => { setPick(null); onMoney(m.username); }}><Icon name="cash" size={18} /> Send money</button>}
          {owner && !isMe && m.role !== 'owner' && (
            <button type="button" className="msg-menu__item" onClick={() => void run(() => gistGroupSetRole(group.id, m.id, m.role === 'admin' ? 'member' : 'admin'), async () => { setPick(null); await loadMembers(); })}>
              <Icon name="shield" size={18} /> {m.role === 'admin' ? 'Remove as admin' : 'Make admin'}
            </button>
          )}
          {canAct && (
            <button type="button" className="msg-menu__item" onClick={() => void run(() => gistGroupMute(group.id, m.id, muted ? 0 : 60), async () => { setPick(null); await loadMembers(); })}>
              <Icon name="ban" size={18} /> {muted ? 'Unmute' : 'Mute for 1 hour'}
            </button>
          )}
          {canAct && (
            <button type="button" className="msg-menu__item is-danger" onClick={() => void run(() => gistGroupRemove(group.id, m.id), async () => { setPick(null); await loadMembers(); await refreshGroup(); toast('Removed from the group.', 'info'); })}>
              <Icon name="trash" size={18} /> Remove from group
            </button>
          )}
        </div>
      </MiniSheet>
    );
  };

  return (
    <div className="phone-app__body social-app msgs gist-page">
      <PageHead title="Group info" onBack={onBack} />
      <section className="gist-ginfo">
        <GroupTile id={group.id} emoji={editing ? emoji : group.emoji} size={84} />
        {editing ? (
          <div className="gist-ginfo__edit">
            <input className="input" value={name} maxLength={32} aria-label="Group name" onChange={(e) => setName(e.target.value)} />
            <div className="gist-emojis" role="group" aria-label="Group icon">
              {['💬', '🎓', '💼', '🪩', '🏷️', '⚽', '🍲', '🎵', '🚗', '🏠', '📚', '🎮', '🙏🏾', '💸', '🌍', '🔥'].map((e) => <button key={e} type="button" className={e === emoji ? 'is-on' : ''} onClick={() => setEmoji(e)} aria-label={e}>{e}</button>)}
            </div>
            <textarea className="input" rows={2} maxLength={200} value={desc} aria-label="Description" onChange={(e) => setDesc(e.target.value)} />
            <div className="row">
              <Button variant="ghost" onClick={() => setEditing(false)}>Cancel</Button>
              <Button variant="green" className="grow" loading={busy} onClick={() => void save()}>Save</Button>
            </div>
          </div>
        ) : (
          <>
            <h3>{group.name}</h3>
            <small>{group.is_public ? 'Public group' : 'Private group'} · {group.members} / {group.cap} members</small>
            {group.description && <p>{group.description}</p>}
            {manage && <Button size="sm" variant="ghost" icon="gear" onClick={() => setEditing(true)}>Edit group</Button>}
          </>
        )}
      </section>

      {group.is_owner && !group.system && (
        <Switch checked={group.is_public} onChange={(v) => void togglePublic(v)} disabled={busy} label={group.is_public ? 'Public group' : 'Private group'}
          hint={group.is_public ? 'Anyone can find it in Discover and join.' : 'Invite only. Only owner and admins add people.'} />
      )}

      <div className="gist-membershead">
        <h3 className="msgs-sub">Members</h3>
        {manage && <Button size="sm" variant="green" icon="plus" onClick={() => setAdding(true)}>Add</Button>}
      </div>
      {members === null ? <div className="social-loading"><Spinner size={18} /></div> : (
        <div className="gist-members">
          {members.map((m) => (
            <button key={m.id} type="button" className="gist-member" onClick={() => setPick(m)}>
              <Face user={m} size={44} />
              <span className="gist-member__main"><b>@{m.username}{m.id === me.id ? ' (you)' : ''}</b>
                <small>{m.muted_until && Date.parse(m.muted_until) > Date.now() ? 'Muted' : `Joined ${timeAgo(m.joined_at)}`}</small></span>
              {m.role !== 'member' && <span className={`gist-role gist-role--${m.role}`}>{m.role}</span>}
            </button>
          ))}
          {group.members > members.length && <p className="gist-fine">Showing the first {members.length} members.</p>}
        </div>
      )}

      <div className="gist-danger">
        <Button variant="ghost" icon="warning" onClick={() => setReporting(true)}>Report group</Button>
        {group.role && <Button variant="ghost" icon="logout" loading={busy} onClick={() => void leave()}>Leave group</Button>}
        {group.is_owner && !group.system && <Button variant="danger" icon="trash" onClick={() => { if (window.confirm('Delete this group and all its messages for everyone?')) void del(); }}>Delete group</Button>}
      </div>

      {pick && memberAction(pick)}
      {adding && <AddMembers group={group} members={members ?? []} onClose={() => setAdding(false)} onAdded={async () => { await loadMembers(); await refreshGroup(); }} />}
      {reporting && <ReportSheet kind="group" id={group.id} onClose={() => setReporting(false)} />}
    </div>
  );
}

function AddMembers({ group, members, onClose, onAdded }: { group: GistGroup; members: GroupMember[]; onClose: () => void; onAdded: () => Promise<void> }) {
  const [friends, setFriends] = useState<SocialFriend[] | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [added, setAdded] = useState<Set<string>>(new Set());
  useEffect(() => { let alive = true; socialFriends().then((f) => alive && setFriends(f ?? [])).catch(() => alive && setFriends([])); return () => { alive = false; }; }, []);
  const inGroup = new Set(members.map((m) => m.id));
  const add = async (f: SocialFriend) => {
    setBusy(f.id);
    try {
      await gistGroupAdd(group.id, f.username);
      setAdded((s) => new Set(s).add(f.id));
      await onAdded();
    } catch (e) { toast(errorMessage(e), 'bad'); }
    finally { setBusy(null); }
  };
  return (
    <MiniSheet title="Add friends" onClose={onClose}>
      <div className="dm-sheet__body gist-addlist">
        {friends === null ? <Spinner size={18} /> : friends.length === 0 ? <p className="dm-sheet__lead">You have no friends to add yet. Add friends first, then bring them in.</p>
          : friends.map((f) => (
            <div key={f.id} className="gist-addrow">
              <Face user={f} size={38} /><b>@{f.username}</b>
              {inGroup.has(f.id) || added.has(f.id) ? <span className="gist-fine">In the group</span>
                : <Button size="sm" variant="green" loading={busy === f.id} onClick={() => void add(f)}>Add</Button>}
            </div>
          ))}
      </div>
    </MiniSheet>
  );
}

// ---------------------------------------------------------------------------------------------------------------
// The chat
// ---------------------------------------------------------------------------------------------------------------
export function GroupChat({ state, groupId, nav, onBack, onChanged }: {
  state: GameState; groupId: number; nav: { openProfile: (id: string) => void }; onBack: () => void; onChanged: () => void;
}) {
  const me = state.profile;
  const pollMode = usePollMode();
  const { cfg } = useConfig();
  const deleteHours = cfg<number>('chat.delete_everyone_hours', 48);
  const [group, setGroup] = useState<GistGroup | null>(null);
  const [gone, setGone] = useState<string | null>(null);
  const [page, setPage] = useState<'chat' | 'settings'>('chat');
  const [messages, setMessages] = useState<GroupMessage[]>([]);
  const [loading, setLoading] = useState(true);
  const [hasOlder, setHasOlder] = useState(false);
  const [loadingOlder, setLoadingOlder] = useState(false);
  const [replyTo, setReplyTo] = useState<ThreadMessage | null>(null);
  const [menu, setMenu] = useState<ThreadMessage | null>(null);
  const [sheet, setSheet] = useState<Sheet>(null);
  const [moneyTo, setMoneyTo] = useState<string | null>(null);
  const [draft, setDraft] = useState('');
  const [sending, setSending] = useState(false);
  const [emojiOpen, setEmojiOpen] = useState(false);
  const [recording, setRecording] = useState(false);
  const [audioBusy, setAudioBusy] = useState(false);
  const [recordSeconds, setRecordSeconds] = useState(0);
  const [joining, setJoining] = useState(false);
  useEscape(Boolean(replyTo), () => setReplyTo(null));
  useEscape(emojiOpen, () => setEmojiOpen(false));
  useViewportVars();

  const listRef = useRef<HTMLDivElement>(null);
  const draftRef = useRef<HTMLTextAreaElement>(null);
  const messagesRef = useRef<GroupMessage[]>([]);
  const replyRef = useRef<ThreadMessage | null>(null);
  const avatars = useRef(new Map<string, AvatarConfig | null>());
  const recorderRef = useRef<MediaRecorder | null>(null);
  const streamRef = useRef<MediaStream | null>(null);
  const chunksRef = useRef<Blob[]>([]);
  const startedRef = useRef(0);
  const discardRef = useRef(false);
  const hadUnread = useRef(0);
  const readTimer = useRef(0);
  useEffect(() => { replyRef.current = replyTo; }, [replyTo]);
  useEffect(() => { messagesRef.current = messages; }, [messages]);

  const joined = Boolean(group?.joined);

  const loadGroup = useCallback(async () => {
    try {
      const g = await gistGroupGet(groupId);
      hadUnread.current = hadUnread.current || 0;
      setGroup(g);
      return g;
    } catch (e) { setGone(errorMessage(e)); return null; }
  }, [groupId]);
  useEffect(() => { void loadGroup().finally(() => undefined); }, [loadGroup]);

  const remember = useCallback((rows: GroupMessage[]) => { for (const r of rows) if (r.avatar) avatars.current.set(r.user_id, r.avatar); }, []);
  const markRead = useCallback(() => {
    window.clearTimeout(readTimer.current);
    readTimer.current = window.setTimeout(() => {
      void gistGroupMarkRead(groupId).then(() => {
        if (hadUnread.current > 0) { hadUnread.current = 0; useGist.getState().groupRead(); }
        onChanged();
      }).catch(() => undefined);
    }, 1200);
  }, [groupId, onChanged]);
  useEffect(() => () => window.clearTimeout(readTimer.current), []);

  const append = useCallback((m: GroupMessage) => {
    remember([m]);
    setMessages((old) => (old.some((x) => x.id === m.id) ? old : [...old, m].sort((a, b) => a.id - b.id)));
  }, [remember]);
  const patch = useCallback((row: Partial<GroupMessage> & { id: number }) => {
    setMessages((old) => old.map((m) => (m.id === row.id ? { ...m, body: row.body ?? null, audio_path: row.audio_path ?? null, deleted_at: row.deleted_at ?? m.deleted_at } : m)));
  }, []);

  // live: ONE channel for this group (members only through RLS), or the poll fallback
  useEffect(() => {
    if (!joined) return;
    let alive = true;
    const rawToMessage = (raw: Record<string, unknown>): GroupMessage => ({
      id: raw.id as number, group_id: raw.group_id as number, user_id: raw.user_id as string, username: raw.username as string,
      avatar: avatars.current.get(raw.user_id as string) ?? null, kind: raw.kind as GroupMessage['kind'], body: (raw.body as string | null) ?? null,
      audio_path: (raw.audio_path as string | null) ?? null, audio_mime: (raw.audio_mime as string | null) ?? null, amount: (raw.money_amount as number | null) ?? null,
      to_user: (raw.money_to as string | null) ?? null, to_username: (raw.money_to_username as string | null) ?? null, reply_to: (raw.reply_to as number | null) ?? null,
      reply: null, created_at: raw.created_at as string, deleted_at: (raw.deleted_at as string | null) ?? null, mine: raw.user_id === me.id,
    });
    const loadLatest = async () => {
      try {
        const rows = (await gistGroupHistory(groupId, null, PAGE)) ?? [];
        if (!alive) return;
        remember(rows);
        setMessages((old) => {
          const have = new Map(old.map((m) => [m.id, m]));
          for (const r of rows) have.set(r.id, r);
          return [...have.values()].sort((a, b) => a.id - b.id);
        });
        setHasOlder((h) => h || rows.length === PAGE);
        markRead();
      } catch (e) { if (alive) toast(errorMessage(e), 'bad'); }
      finally { if (alive) setLoading(false); }
    };
    if (pollMode) {
      void loadLatest();
      const poller = startPoller(async () => {
        const after = messagesRef.current.reduce((m, x) => Math.max(m, x.id), 0);
        const rows = await gistGroupAfter(groupId, after);
        if (!alive || !rows?.length) return;
        for (const r of rows) append(r);
        markRead();
      }, () => 10_000);
      return () => { alive = false; poller.stop(); };
    }
    const channel: RealtimeChannel = supabase
      .channel(`gist-group-${groupId}-${me.id}`)
      .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'gist_messages', filter: `group_id=eq.${groupId}` }, (payload) => {
        const m = rawToMessage(payload.new as Record<string, unknown>);
        if (messagesRef.current.some((x) => x.id === m.id)) return;
        append(m);
        if (!m.mine) markRead();
      })
      .on('postgres_changes', { event: 'UPDATE', schema: 'public', table: 'gist_messages', filter: `group_id=eq.${groupId}` }, (payload) => {
        patch(payload.new as Partial<GroupMessage> & { id: number });
      });
    trackSubscribe(channel, 'gist-group', (status) => { if (status === 'SUBSCRIBED') void loadLatest(); });
    return () => { alive = false; void supabase.removeChannel(channel); };
  }, [groupId, joined, me.id, pollMode, append, patch, remember, markRead]);

  useEffect(() => {
    if (group && !group.joined) setLoading(false);
    if (group && hadUnread.current === 0 && group.unread > 0) hadUnread.current = group.unread;
  }, [group]);

  useEffect(() => {
    if (!recording) return;
    const t = window.setInterval(() => setRecordSeconds(Math.floor((Date.now() - startedRef.current) / 1000)), 1000);
    return () => window.clearInterval(t);
  }, [recording]);
  useEffect(() => () => {
    discardRef.current = true;
    if (recorderRef.current?.state === 'recording') recorderRef.current.stop();
    streamRef.current?.getTracks().forEach((t) => t.stop());
  }, []);

  const thread = useMemo(() => messages.map((m) => toThread(m, avatars.current)), [messages]);
  const byId = useMemo(() => new Map(thread.map((m) => [m.id, m])), [thread]);
  const { onScroll } = useThreadScroll(listRef, {
    firstId: messages[0]?.id ?? null, lastId: messages[messages.length - 1]?.id ?? null, hasOlder, loadingOlder, loadOlder: () => void loadOlder(),
  });

  const loadOlder = async () => {
    const first = messagesRef.current[0];
    if (!first || loadingOlder || !hasOlder) return false;
    setLoadingOlder(true);
    try {
      const older = (await gistGroupHistory(groupId, first.id, PAGE)) ?? [];
      remember(older);
      setMessages((rows) => [...older.filter((o) => !rows.some((r) => r.id === o.id)), ...rows]);
      setHasOlder(older.length === PAGE);
      await new Promise((r) => requestAnimationFrame(r));
      return older.length > 0;
    } catch (e) { toast(errorMessage(e), 'bad'); return false; }
    finally { setLoadingOlder(false); }
  };
  const jumpTo = async (id: number) => {
    for (let i = 0; i < 6; i++) {
      if (flashMessage(listRef.current, id)) return;
      if (!(await loadOlder())) break;
      await new Promise((r) => requestAnimationFrame(r));
    }
    toast('That message is no longer available.', 'info');
  };
  const scrollDown = () => { const el = listRef.current; if (el) requestAnimationFrame(() => { el.scrollTop = el.scrollHeight; }); };

  const sendText = async () => {
    const body = draft.trim();
    if (!body || sending || recording || audioBusy) return;
    setSending(true);
    try {
      append(await gistGroupSend(groupId, body, null, null, replyRef.current?.id ?? null));
      setDraft(''); setReplyTo(null); scrollDown(); onChanged();
    } catch (e) { toast(errorMessage(e), 'bad'); }
    finally { setSending(false); }
  };

  const insertEmoji = (e: string) => {
    const el = draftRef.current;
    const a = el?.selectionStart ?? draft.length;
    const b = el?.selectionEnd ?? draft.length;
    setDraft(draft.slice(0, a) + e + draft.slice(b));
    requestAnimationFrame(() => { el?.focus({ preventScroll: true }); el?.setSelectionRange(a + e.length, a + e.length); });
  };

  const startRecording = async () => {
    if (audioBusy || recording) return;
    if (!navigator.mediaDevices?.getUserMedia || typeof MediaRecorder === 'undefined') { toast('Voice recording is not supported by this browser.', 'bad'); return; }
    setAudioBusy(true);
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      streamRef.current = stream;
      const mimeType = ['audio/webm;codecs=opus', 'audio/mp4', 'audio/ogg;codecs=opus'].find((t) => MediaRecorder.isTypeSupported(t));
      const recorder = mimeType ? new MediaRecorder(stream, { mimeType }) : new MediaRecorder(stream);
      chunksRef.current = [];
      discardRef.current = false;
      recorderRef.current = recorder;
      recorder.ondataavailable = (e) => { if (e.data.size > 0) chunksRef.current.push(e.data); };
      recorder.onerror = () => { toast('The voice note stopped unexpectedly. Please try again.', 'bad'); stream.getTracks().forEach((t) => t.stop()); setRecording(false); setAudioBusy(false); };
      recorder.onstop = () => {
        stream.getTracks().forEach((t) => t.stop());
        if (recorderRef.current === recorder) recorderRef.current = null;
        setRecording(false);
        if (discardRef.current) { chunksRef.current = []; setAudioBusy(false); return; }
        const blob = new Blob(chunksRef.current, { type: recorder.mimeType || 'audio/webm' });
        chunksRef.current = [];
        void (async () => {
          if (blob.size === 0) throw new Error('No audio was recorded.');
          const up = await uploadGroupVoice(groupId, me.id, blob, blob.type);
          try {
            append(await gistGroupSend(groupId, null, up.path, up.mime, replyRef.current?.id ?? null));
            setReplyTo(null); scrollDown(); onChanged();
          } catch (e) { await discardVoiceUpload(up.path).catch(() => undefined); throw e; }
        })().catch((e) => toast(errorMessage(e), 'bad')).finally(() => setAudioBusy(false));
      };
      recorder.start(1000);
      startedRef.current = Date.now();
      setRecordSeconds(0); setRecording(true); setAudioBusy(false);
    } catch {
      streamRef.current?.getTracks().forEach((t) => t.stop());
      setAudioBusy(false);
      toast('Microphone access was not allowed. Enable it in your browser settings and try again.', 'bad');
    }
  };
  const stopRecording = () => { if (recorderRef.current?.state === 'recording') { setAudioBusy(true); recorderRef.current.stop(); } };

  const join = async () => {
    setJoining(true);
    try { const g = await gistGroupJoin(groupId); setGroup(await gistGroupGet(g.id)); onChanged(); toast(`You joined ${g.name}.`, 'good'); }
    catch (e) { toast(errorMessage(e), 'bad'); }
    finally { setJoining(false); }
  };

  const startReply = (m: ThreadMessage) => { setMenu(null); setReplyTo(m); draftRef.current?.focus({ preventScroll: true }); };
  const removeMsg = async (m: ThreadMessage) => {
    setMenu(null);
    try {
      const r = await gistGroupDeleteMessage(m.id);
      patch({ id: m.id, body: null, audio_path: null, deleted_at: r.deleted_at });
      if (r.audio_path) void discardVoiceUpload(r.audio_path).catch(() => undefined);
      if (replyTo?.id === m.id) setReplyTo(null);
      void loadGroup();
    } catch (e) { toast(errorMessage(e), 'bad'); }
  };
  const pin = async (m: ThreadMessage | null) => {
    setMenu(null);
    try { const r = await gistGroupPin(groupId, m?.id ?? null); toast(r.message, 'info'); await loadGroup(); } catch (e) { toast(errorMessage(e), 'bad'); }
  };

  const manage = Boolean(group?.can_manage);
  const menuActions = (m: ThreadMessage): MenuAction[] => {
    const acts: MenuAction[] = [];
    if (!m.deletedAt) acts.push({ label: 'Reply', icon: 'reply', onSelect: () => startReply(m) });
    if (m.body) acts.push({ label: 'Copy text', icon: 'copy', onSelect: () => { void navigator.clipboard?.writeText(m.body ?? '').then(() => toast('Copied.', 'good')).catch(() => undefined); setMenu(null); } });
    if (!m.deletedAt && !m.mine) {
      const who = messages.find((x) => x.id === m.id);
      if (who) acts.push({ label: `Send money to @${who.username}`, icon: 'cash', onSelect: () => { setMenu(null); setMoneyTo(who.username); setSheet('money'); } });
    }
    if (manage && !m.deletedAt) acts.push({ label: group?.pinned?.id === m.id ? 'Unpin message' : 'Pin message', icon: 'pin', onSelect: () => void pin(group?.pinned?.id === m.id ? null : m) });
    const src = messages.find((x) => x.id === m.id);
    const canDel = !m.deletedAt && src?.kind !== 'money' && (manage || canDeleteForEveryone(m, deleteHours));
    if (canDel) acts.push({ label: m.mine ? 'Delete for everyone' : 'Delete message', icon: 'trash', tone: 'danger', onSelect: () => void removeMsg(m) });
    if (!m.mine && !m.deletedAt) acts.push({ label: 'Report message', icon: 'warning', tone: 'danger', onSelect: () => { setMenu(null); setSheet({ report: m.id }); } });
    return acts;
  };

  if (gone) {
    return (
      <div className="phone-app__body social-app msgs gist-page">
        <PageHead title="Group" onBack={onBack} />
        <p className="msgs-empty">{gone}</p>
      </div>
    );
  }
  if (!group) {
    return (
      <div className="phone-app__body social-app msgs gist-page">
        <PageHead title="Group" onBack={onBack} />
        <div className="social-loading"><Spinner size={20} /></div>
      </div>
    );
  }
  if (page === 'settings') {
    return (
      <GroupSettings state={state} group={group} onBack={() => setPage('chat')} onChanged={(g) => { setGroup(g); onChanged(); }} onLeft={() => { onChanged(); onBack(); }}
        nav={nav} onMoney={(u) => { setPage('chat'); setMoneyTo(u); setSheet('money'); }} />
    );
  }

  const mutedUntil = group.muted_until && Date.parse(group.muted_until) > Date.now() ? group.muted_until : null;
  const hasText = Boolean(draft.trim());
  return (
    <div className="phone-app__body social-app social-app--conversation dm gist-gchat">
      <header className="dm-head gist-gchat__head">
        <button type="button" className="msgs-iconbtn msgs-iconbtn--bare" onClick={onBack} aria-label="Back"><Icon name="back" size={22} stroke={2.6} /></button>
        <button type="button" className="gist-gchat__title" onClick={() => setPage('settings')} aria-label="Group info">
          <GroupTile id={group.id} emoji={group.emoji} size={40} />
          <span><b>{group.name}</b><small>{group.members} member{group.members === 1 ? '' : 's'}{!group.is_public ? ' · private' : ''}</small></span>
        </button>
        <button type="button" className="msgs-iconbtn" aria-label="Group info" onClick={() => setPage('settings')}><Icon name="more" size={20} stroke={3} /></button>
      </header>

      {group.pinned && (
        <button type="button" className="gist-pinned" onClick={() => void jumpTo(group.pinned!.id)}>
          <Icon name="pin" size={15} />
          <span><b>Pinned</b>{group.pinned.kind === 'voice' ? '🎤 Voice note' : group.pinned.kind === 'money' ? `💸 ${naira(group.pinned.amount ?? 0)} to @${group.pinned.to_username}` : group.pinned.body}</span>
        </button>
      )}

      {!joined ? (
        <div className="gist-joinbox">
          <GroupTile id={group.id} emoji={group.emoji} size={88} />
          <h3>{group.name}</h3>
          <small>{group.members} / {group.cap} members</small>
          {group.description && <p>{group.description}</p>}
          {group.banned ? <p className="gist-fine">You were removed from this group.</p>
            : group.members >= group.cap ? <p className="gist-fine">This group is full.</p>
              : <Button variant="green" loading={joining} onClick={() => void join()}>Join group</Button>}
        </div>
      ) : (
        <>
          <div className="social-thread">
            <div className="social-message-list dm-list" ref={listRef} role="log" aria-live="polite" aria-label={`Messages in ${group.name}`} onScroll={onScroll}>
              {loadingOlder && <div className="msg-older"><Spinner size={16} /></div>}
              {loading && messages.length === 0 ? <div className="social-loading"><Spinner size={20} /></div>
                : messages.length === 0 ? <EmptyState icon="chat" title="Say hello" body={`Be the first to write in ${group.name}.`} />
                  : thread.map((m, i) => (
                    <Fragment key={m.id}>
                      <DaySep iso={m.createdAt} prevIso={thread[i - 1]?.createdAt ?? null} />
                      <MessageRow m={m} dm senderName showFace={!m.mine} reply={resolveReply(m, byId)} onReply={startReply} onMenu={setMenu} onQuote={(id) => void jumpTo(id)} />
                    </Fragment>
                  ))}
            </div>
            {menu && <MessageMenu m={menu} actions={menuActions(menu)} onClose={() => setMenu(null)} />}
          </div>
          {recording && <div className="social-recording" role="status"><span className="social-recording__dot" /> Recording voice note · {durationLabel(recordSeconds)}</div>}
          <div className="social-composer dm-composer kb-composer">
            {mutedUntil ? <p className="gist-note"><Icon name="ban" size={16} /> An admin muted you here until {new Date(mutedUntil).toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit' })}.</p> : (
              <>
                {replyTo && <ReplyBar reply={previewOf(replyTo)} onClear={() => setReplyTo(null)} />}
                <div className="gist-gchips">
                  <button type="button" className="dm-chip dm-chip--gold" onClick={() => { setMoneyTo(null); setSheet('money'); }}><span aria-hidden>💸</span> Send money</button>
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
                    <textarea ref={draftRef} value={draft} rows={1} placeholder="Message the group…" aria-label="Group message" enterKeyHint="send"
                      onKeyDown={(e) => { if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); void sendText(); } }}
                      onFocus={() => setEmojiOpen(false)} readOnly={sending || recording || audioBusy} onChange={(e) => setDraft(e.target.value)} />
                  </div>
                  <Button type={hasText ? 'submit' : 'button'} className={`social-compose__primary dm-compose__primary${recording ? ' is-recording' : ''}`} variant="green"
                    aria-label={recording ? `Send voice note, ${durationLabel(recordSeconds)}` : hasText ? 'Send message' : 'Record voice message'}
                    disabled={audioBusy || sending} loading={sending || (audioBusy && !recording)}
                    onClick={() => { if (recording) stopRecording(); else if (!hasText) void startRecording(); }}>
                    <Icon name={recording || hasText ? 'send' : 'mic'} size={20} />
                  </Button>
                </form>
              </>
            )}
          </div>
        </>
      )}
      {sheet === 'money' && <GroupMoneySheet state={state} group={group} preset={moneyTo} onClose={() => { setSheet(null); setMoneyTo(null); }}
        onSent={(m) => { append(m); scrollDown(); onChanged(); void loadGroup(); }} />}
      {sheet && typeof sheet === 'object' && <ReportSheet kind="message" id={sheet.report} onClose={() => setSheet(null)}
        onDone={(hidden) => { if (hidden) setMessages((rows) => rows.filter((r) => r.id !== (sheet as { report: number }).report)); }} />}
    </div>
  );
}
