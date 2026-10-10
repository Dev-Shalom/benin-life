// M4 Phone → Messages (docs/CHAT.md "M4", docs/SOCIAL.md). List screen: header with the alerts bell, Chats / Groups
// tabs, the pinned "Benin Life team" news card, "Message someone: @username", All / Unread / Read filters,
// Message requests, chat search and conversation rows. A row opens DmConversation; Groups opens the place / house chat.
import { useCallback, useEffect, useMemo, useState } from 'react';
import type { FormEvent } from 'react';
import { AvatarPortrait } from '../../../art/avatar3d';
import {
  socialCancelFriendRequest, socialCancelHouseInvite, socialFriendRequests, socialFriends, socialHomeAdmit,
  socialHouseInvites, socialMarkRead, socialOpenConversation, socialRespondFriend, socialRespondHouseInvite, socialSearchPlayers,
  type FriendRequest, type HouseInvite, type SocialFriend, type SocialPlayer,
} from '../../../api/social';
import { errorMessage } from '../../../lib/api';
import { useConfig } from '../../../lib/config';
import type { GameState } from '../../../lib/types';
import { useGame } from '../../../state/game';
import { Button, Icon, Spinner, toast } from '../../../ui';
import { SocialPlayerButton } from '../SocialPlayerButton';
import ChatPanel from '../../../panels/ChatPanel';
import { DmConversation, MiniSheet, MONEY_PREFIX } from './DmConversation';

interface SocialAppProps {
  state: GameState;
  onGoHome: () => void;
  /** M4: the app draws its own header (back to the phone home, bell to Alerts). */
  onBack?: () => void;
  onOpenAlerts?: () => void;
  alertsUnread?: number;
}

type Filter = 'all' | 'unread' | 'read';

/** "14:05" today, "Yesterday", else "6 Oct". */
function rowDate(iso: string | null) {
  if (!iso) return '';
  const d = new Date(iso);
  const now = new Date();
  const y = new Date(now); y.setDate(now.getDate() - 1);
  if (d.toDateString() === now.toDateString()) return d.toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit' });
  if (d.toDateString() === y.toDateString()) return 'Yesterday';
  return d.toLocaleDateString('en-GB', { day: 'numeric', month: 'short' });
}

function preview(f: SocialFriend, meId: string) {
  if (!f.conversation_id || !f.last_message_at) return f.at_home ? 'At home · say hi' : 'Around Benin · say hi';
  const mine = f.last_sender_id === meId;
  if (f.last_deleted) return 'This message was deleted';
  if (f.last_voice) return mine ? 'You: Voice note' : 'Voice note';
  const body = f.last_message ?? '';
  if (body.startsWith(MONEY_PREFIX)) {
    const rest = body.slice(MONEY_PREFIX.length);
    return mine ? `You sent ${rest}` : `${f.username} sent you ${rest}`;
  }
  return mine ? `You: ${body}` : body;
}

function Badge({ n }: { n: number }) {
  if (n <= 0) return null;
  return <span className="msgs-badge">{n > 9 ? '9+' : n}</span>;
}

export default function SocialApp({ state, onGoHome, onBack, onOpenAlerts, alertsUnread = 0 }: SocialAppProps) {
  const me = state.profile;
  const [friends, setFriends] = useState<SocialFriend[] | null>(null);
  const [requests, setRequests] = useState<FriendRequest[] | null>(null);
  const [invites, setInvites] = useState<HouseInvite[] | null>(null);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [tab, setTab] = useState<'chats' | 'groups'>('chats');
  const [filter, setFilter] = useState<Filter>('all');
  const [chatSearch, setChatSearch] = useState('');
  const [who, setWho] = useState('');
  const [searching, setSearching] = useState(false);
  const [results, setResults] = useState<SocialPlayer[] | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [view, setView] = useState<'list' | 'requests' | 'group'>('list');
  const [sheet, setSheet] = useState<'news' | 'more' | null>(null);
  const [conversation, setConversation] = useState<{ id: number; friendId: string; friend: SocialFriend } | null>(null);
  const eventsRevision = useGame((s) => s.events[0]?.id ?? 0);
  const refreshGame = useGame((s) => s.refresh);
  const { cfg } = useConfig();
  const newsTitle = cfg('news.latest_title', '').trim();
  const newsBody = cfg('news.latest_body', '').trim();

  const reload = useCallback(async () => {
    try {
      const [nextFriends, nextRequests, nextInvites] = await Promise.all([socialFriends(), socialFriendRequests(), socialHouseInvites()]);
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
  // Friend requests, knocks and new DMs arrive through the existing per-player events channel.
  useEffect(() => { if (eventsRevision) void reload(); }, [eventsRevision, reload]);

  const homeNow = !state.travel && me.location_id === state.location.id
    && (me.location_id === me.home_location_id || Boolean(me.home_visit_host_id));
  useEffect(() => { if (view === 'group' && state.travel) setView('list'); }, [view, state.travel]);

  const incoming = useMemo(() => (requests ?? []).filter((r) => r.direction === 'incoming'), [requests]);
  const outgoing = useMemo(() => (requests ?? []).filter((r) => r.direction === 'outgoing'), [requests]);
  const doorItems = useMemo(() => (invites ?? []).filter((i) => (i.role === 'host' && i.status === 'knocking') || (i.role === 'guest' && i.status === 'invited')), [invites]);
  const unreadChats = (friends ?? []).filter((f) => f.unread > 0).length;
  const requestCount = incoming.length + doorItems.length;

  const rows = useMemo(() => {
    const q = chatSearch.trim().toLowerCase().replace(/^@/, '');
    return (friends ?? []).filter((f) => (filter === 'all' || (filter === 'unread' ? f.unread > 0 : f.unread === 0))
      && (!q || f.username.toLowerCase().includes(q) || (f.last_message ?? '').toLowerCase().includes(q)));
  }, [friends, filter, chatSearch]);

  const openConversation = async (friend: SocialFriend) => {
    setBusy(`message:${friend.id}`);
    try {
      const opened = await socialOpenConversation(friend.id);
      setConversation({ id: opened.id, friendId: friend.id, friend });
    } catch (e) { toast(errorMessage(e), 'bad'); }
    finally { setBusy(null); }
  };

  const findPlayer = async (event: FormEvent) => {
    event.preventDefault();
    const value = who.trim().replace(/^@+/, '');
    if (value.length < 3) { toast('Type at least 3 letters of their @username.', 'info'); return; }
    const friend = (friends ?? []).find((f) => f.username.toLowerCase() === value.toLowerCase());
    if (friend) { setWho(''); setResults(null); void openConversation(friend); return; }
    setSearching(true);
    try { setResults((await socialSearchPlayers(value)).filter((p) => p.id !== me.id)); }
    catch (e) { toast(errorMessage(e), 'bad'); }
    finally { setSearching(false); }
  };

  const requestAction = async (r: FriendRequest, accept: boolean) => {
    setBusy(`request:${r.id}`);
    try {
      const result = r.direction === 'incoming' ? await socialRespondFriend(r.id, accept) : await socialCancelFriendRequest(r.id);
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

  const markAllRead = async () => {
    setSheet(null);
    const open = (friends ?? []).filter((f) => f.unread > 0 && f.conversation_id);
    await Promise.allSettled(open.map((f) => socialMarkRead(f.conversation_id!)));
    await reload();
    toast(open.length ? 'All chats marked as read.' : 'You have no unread chats.', 'info');
  };

  if (conversation) {
    const fresh = friends?.find((f) => f.id === conversation.friendId) ?? conversation.friend;
    return (
      <DmConversation key={conversation.id} state={state} friend={fresh} conversationId={conversation.id} invites={invites ?? []}
        homeNow={homeNow} reload={reload} onGoHome={onGoHome} onClose={() => { setConversation(null); void reload(); }} />
    );
  }

  if (view === 'group' && !state.travel) {
    return (
      <div className="phone-app__body social-app social-app--house-chat msgs">
        <header className="dm-head">
          <button type="button" className="msgs-iconbtn msgs-iconbtn--bare" onClick={() => setView('list')} aria-label="Back to messages">
            <Icon name="back" size={22} stroke={2.6} />
          </button>
          <h2 className="dm-head__name dm-head__name--sm">{homeNow ? 'House chat' : state.location.name}</h2>
        </header>
        <ChatPanel state={state} location={state.location} refresh={refreshGame} close={() => setView('list')} />
      </div>
    );
  }

  if (view === 'requests') {
    return (
      <div className="phone-app__body social-app msgs">
        <header className="msgs-head">
          <button type="button" className="msgs-iconbtn msgs-iconbtn--bare" onClick={() => setView('list')} aria-label="Back to messages">
            <Icon name="back" size={22} stroke={2.6} />
          </button>
          <h2 className="msgs-head__title msgs-head__title--sm">Message requests</h2>
        </header>
        <p className="msgs-muted">People who want to be your friend. Only friends can message you, visit and start a streak.</p>
        {requests === null ? <div className="social-loading"><Spinner size={18} /></div>
          : incoming.length === 0 ? <p className="msgs-empty">No friend requests right now.</p>
            : incoming.map((r) => (
              <div className="msgs-req" key={r.id}>
                <span className="msgs-face msgs-face--sm">{r.avatar && <AvatarPortrait config={r.avatar} size={44} />}</span>
                <b className="grow">@{r.username}</b>
                <Button size="sm" variant="ghost" disabled={busy === `request:${r.id}`} onClick={() => void requestAction(r, false)}>Decline</Button>
                <Button size="sm" variant="green" loading={busy === `request:${r.id}`} onClick={() => void requestAction(r, true)}>Accept</Button>
              </div>
            ))}
        {doorItems.length > 0 && <h3 className="msgs-sub">At the door</h3>}
        {doorItems.map((invite) => {
          const knock = invite.role === 'host';
          return (
            <div className="msgs-req" key={`i${invite.id}`}>
              <span className="msgs-req__icon" aria-hidden>{knock ? '🚪' : '🏠'}</span>
              <span className="grow msgs-req__copy">
                <b>{knock ? `@${invite.guest_username} is at your door` : `@${invite.host_username} invited you home`}</b>
                <small>{knock ? homeNow ? 'You are home. Open the door?' : 'Go home to let them in.' : 'Accept to knock on their door.'}</small>
              </span>
              {knock ? <>
                <Button size="sm" variant="ghost" disabled={busy === `invite:${invite.id}`} onClick={() => void houseAction(invite, 'turn-away')}>Decline</Button>
                {homeNow ? <Button size="sm" variant="green" loading={busy === `invite:${invite.id}`} onClick={() => void houseAction(invite, 'admit')}>Let in</Button>
                  : <Button size="sm" variant="green" onClick={onGoHome}>Go home</Button>}
              </> : <>
                <Button size="sm" variant="ghost" disabled={busy === `invite:${invite.id}`} onClick={() => void houseAction(invite, 'decline')}>Decline</Button>
                <Button size="sm" variant="green" loading={busy === `invite:${invite.id}`} onClick={() => void houseAction(invite, 'accept')}>Knock</Button>
              </>}
            </div>
          );
        })}
        {(outgoing.length > 0 || (invites ?? []).some((i) => i.role === 'host' && i.status === 'invited') || (invites ?? []).some((i) => i.role === 'guest' && i.status === 'knocking')) && <h3 className="msgs-sub">Waiting on others</h3>}
        {outgoing.map((r) => (
          <div className="msgs-req" key={r.id}>
            <span className="msgs-face msgs-face--sm">{r.avatar && <AvatarPortrait config={r.avatar} size={44} />}</span>
            <span className="grow">Friend request to <b>@{r.username}</b></span>
            <Button size="sm" variant="ghost" loading={busy === `request:${r.id}`} onClick={() => void requestAction(r, false)}>Cancel</Button>
          </div>
        ))}
        {(invites ?? []).filter((i) => (i.role === 'host' && i.status === 'invited') || (i.role === 'guest' && i.status === 'knocking')).map((invite) => (
          <div className="msgs-req" key={`w${invite.id}`}>
            <span className="msgs-req__icon" aria-hidden>{invite.role === 'host' ? '✉️' : '🚪'}</span>
            <span className="grow">{invite.role === 'host' ? <>House invite to <b>@{invite.guest_username}</b></> : <>Knocking at <b>@{invite.host_username}</b>'s door</>}</span>
            <Button size="sm" variant="ghost" loading={busy === `invite:${invite.id}`} onClick={() => void houseAction(invite, 'cancel')}>Cancel</Button>
          </div>
        ))}
      </div>
    );
  }

  return (
    <div className="phone-app__body social-app msgs">
      <header className="msgs-head">
        {onBack && (
          <button type="button" className="msgs-iconbtn msgs-iconbtn--bare" onClick={onBack} aria-label="Back to apps">
            <Icon name="back" size={22} stroke={2.6} />
          </button>
        )}
        <h2 className="msgs-head__title">Messages</h2>
        {onOpenAlerts && (
          <button type="button" className="msgs-iconbtn msgs-bell" onClick={onOpenAlerts} aria-label={`Alerts${alertsUnread ? `, ${alertsUnread} new` : ''}`}>
            <Icon name="bell" size={21} />
            {alertsUnread > 0 && <span className="msgs-badge msgs-bell__badge">{alertsUnread > 9 ? '9+' : alertsUnread}</span>}
          </button>
        )}
      </header>

      <div className="msgs-tabs" role="tablist">
        <button type="button" role="tab" aria-selected={tab === 'chats'} className={tab === 'chats' ? 'is-on' : ''} onClick={() => setTab('chats')}>
          Chats <Badge n={unreadChats} />
        </button>
        <button type="button" role="tab" aria-selected={tab === 'groups'} className={tab === 'groups' ? 'is-on' : ''} onClick={() => setTab('groups')}>
          Groups
        </button>
      </div>

      {loadError && <div className="social-error" role="alert">{loadError}<Button size="sm" variant="ghost" onClick={() => void reload()}>Retry</Button></div>}

      {tab === 'groups' ? (
        <div className="msgs-groups">
          {state.travel ? <p className="msgs-empty">You're on the move. Group chats open when you arrive.</p> : (
            <button type="button" className="msgs-row" onClick={() => setView('group')}>
              <span className="msgs-face msgs-face--group" aria-hidden>{homeNow ? '🏠' : '📍'}</span>
              <span className="msgs-row__main">
                <b>{homeNow ? 'House chat' : `Chat at ${state.location.name}`}</b>
                <span>{homeNow ? 'Everyone inside the house right now' : 'Everyone at this place right now'}</span>
              </span>
              <Icon name="chevronRight" size={18} />
            </button>
          )}
          <p className="msgs-muted">Group chats follow where you are: the house you're in, or the place you're visiting.</p>
        </div>
      ) : <>
        {newsTitle && (
          <button type="button" className="msgs-news" onClick={() => setSheet('news')}>
            <span className="msgs-news__icon" aria-hidden>📣</span>
            <span className="msgs-news__text"><b>Benin Life team</b><span>{newsTitle}</span></span>
          </button>
        )}

        <form className="msgs-input msgs-input--who" onSubmit={(e) => void findPlayer(e)}>
          <span aria-hidden>✏️</span>
          <input value={who} maxLength={21} placeholder="Message someone: @username" aria-label="Message someone by username"
            autoCapitalize="none" autoCorrect="off" spellCheck={false} enterKeyHint="search"
            onChange={(e) => { setWho(e.target.value); setResults(null); }} />
          {who.trim().length > 0 && <Button type="submit" size="sm" variant="green" loading={searching}>Go</Button>}
        </form>
        {results && (
          <div className="msgs-results">
            {results.length === 0 ? <p className="msgs-muted">No players found. Check the spelling and try again.</p>
              : results.map((p) => {
                const friend = (friends ?? []).find((f) => f.id === p.id);
                return (
                  <div className="msgs-req" key={p.id}>
                    <span className="msgs-face msgs-face--sm">{p.avatar && <AvatarPortrait config={p.avatar} size={44} />}</span>
                    <span className="grow msgs-req__copy"><b>@{p.username}</b>{!friend && <small>Add them as a friend to chat</small>}</span>
                    {friend
                      ? <Button size="sm" variant="green" loading={busy === `message:${p.id}`} onClick={() => { setResults(null); setWho(''); void openConversation(friend); }}>Message</Button>
                      : <SocialPlayerButton userId={p.id} onChanged={() => void reload()} />}
                  </div>
                );
              })}
          </div>
        )}

        <div className="msgs-filters" role="group" aria-label="Filter chats">
          {(['all', 'unread', 'read'] as const).map((f) => (
            <button key={f} type="button" className={`msgs-pill${filter === f ? ' is-on' : ''}`} aria-pressed={filter === f} onClick={() => setFilter(f)}>
              {f === 'all' ? 'All' : f === 'unread' ? <>Unread <Badge n={unreadChats} /></> : 'Read'}
            </button>
          ))}
          <button type="button" className="msgs-iconbtn msgs-iconbtn--bare msgs-filters__more" aria-label="More options" onClick={() => setSheet('more')}>
            <Icon name="more" size={20} stroke={3} />
          </button>
        </div>

        <button type="button" className="msgs-requests" onClick={() => setView('requests')}>
          <span className="msgs-requests__icon" aria-hidden><Icon name="mail" size={26} /></span>
          <span className="msgs-requests__text">
            <b>Message requests {requestCount > 0 && <Badge n={requestCount} />}</b>
            <span>{incoming.length > 0
              ? `${incoming.length} ${incoming.length === 1 ? 'person' : 'people'} you haven't chatted with want to connect`
              : doorItems.length > 0 ? 'Someone is at the door or invited you over' : "People you haven't chatted with yet"}</span>
          </span>
          <span className="msgs-requests__see">See</span>
        </button>

        <label className="msgs-input">
          <input value={chatSearch} placeholder="Search your chats" aria-label="Search your chats" onChange={(e) => setChatSearch(e.target.value)} />
        </label>

        <div className="msgs-list">
          {friends === null ? <div className="social-loading"><Spinner size={18} /></div>
            : friends.length === 0 ? <p className="msgs-empty">No chats yet. Type a @username above to find someone, or add people you meet around Benin.</p>
              : rows.length === 0 ? <p className="msgs-empty">{filter === 'unread' ? "You're all caught up." : 'No chats match.'}</p>
                : rows.map((f) => (
                  <button key={f.id} type="button" className={`msgs-row${f.unread > 0 ? ' is-unread' : ''}`} disabled={busy === `message:${f.id}`}
                    onClick={() => void openConversation(f)}>
                    <span className="msgs-face">{f.avatar && <AvatarPortrait config={f.avatar} size={56} />}</span>
                    <span className="msgs-row__main">
                      <b>@{f.username}</b>
                      <span>{preview(f, me.id)}</span>
                    </span>
                    <span className="msgs-row__side">
                      <time>{rowDate(f.last_message_at)}</time>
                      {f.unread > 0 && <span className="msgs-badge">{f.unread > 99 ? '99+' : f.unread}</span>}
                    </span>
                  </button>
                ))}
        </div>
      </>}

      {sheet === 'news' && (
        <MiniSheet title="Benin Life team" onClose={() => setSheet(null)}>
          <div className="dm-sheet__body">
            <p className="msgs-news__title"><span aria-hidden>📣</span> {newsTitle}</p>
            {newsBody && <p className="dm-sheet__lead msgs-news__body">{newsBody}</p>}
          </div>
        </MiniSheet>
      )}
      {sheet === 'more' && (
        <MiniSheet title="Chats" onClose={() => setSheet(null)}>
          <button type="button" className="msg-menu__item" onClick={() => void markAllRead()}><Icon name="check" size={18} /> Mark all read</button>
        </MiniSheet>
      )}
    </div>
  );
}
