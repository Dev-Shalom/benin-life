// Two phone apps share this screen (docs/GIST.md):
//   Messages (mode 'messages'): Chats (the M4 DMs: docs/CHAT.md "M4") · Groups (group chats, Discover, "chat where you are") · Friends.
//   Benin Gist (mode 'gist'):   Feed (gists: like, comment, tip, For you / Following) · Groups.
// Header with the alerts bell, then the active tab. A gist opens its post page, a name opens a profile, a group opens its chat.
// Old links keep working: the phone app id 'messages' is an alias of 'gist', and messages:dm:<id> / messages:house / messages:requests.
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
import { useUi } from '../../../state/ui';
import { Button, Icon, Spinner, toast } from '../../../ui';
import { SocialPlayerButton } from '../SocialPlayerButton';
import ChatPanel from '../../../panels/ChatPanel';
import { DmConversation, MiniSheet, MONEY_PREFIX } from './DmConversation';
import { FriendsTab } from './FriendsTab';
import { FeedTab, PostPage, ProfilePage, type FeedNav } from './gist/GistFeed';
import { GroupsTab } from './gist/GistGroups';
import { GroupChat } from './gist/GroupChat';
import { useGist } from '../../../state/gist';
import type { FriendCard } from '../../../api/friends';
import { usePollMode } from '../../../lib/realtime';

interface SocialAppProps {
  state: GameState;
  onGoHome: () => void;
  /** M4: the app draws its own header (back to the phone home, bell to Alerts). */
  onBack?: () => void;
  onOpenAlerts?: () => void;
  alertsUnread?: number;
  /** Which phone app this is: Messages (chats, groups, friends) or Benin Gist (feed, groups). */
  mode?: 'messages' | 'gist';
}

type Filter = 'all' | 'unread' | 'read';
/** A full page over the tabs (post, profile, group chat). Back pops it; the tab underneath keeps its place. */
type Route = { t: 'post'; id: number } | { t: 'profile'; id: string | null; name?: string } | { t: 'group'; id: number };

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

export default function SocialApp({ state, onGoHome, onBack, onOpenAlerts, alertsUnread = 0, mode = 'messages' }: SocialAppProps) {
  const me = state.profile;
  const [friends, setFriends] = useState<SocialFriend[] | null>(null);
  const [requests, setRequests] = useState<FriendRequest[] | null>(null);
  const [invites, setInvites] = useState<HouseInvite[] | null>(null);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [tab, setTab] = useState<'feed' | 'groups' | 'chats' | 'friends'>(mode === 'gist' ? 'feed' : 'chats');
  const [route, setRoute] = useState<Route | null>(null);
  const [tag, setTag] = useState<string | null>(null);
  const [groupsKey, setGroupsKey] = useState(0);
  const summary = useGist((g) => g.summary);
  const unreadGroups = useGist((g) => g.unreadGroups);
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
  const pollMode = usePollMode();

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
    // S1 scaling: requests/knocks/DMs already arrive via the events channel; this is only a safety net
    // F1: every 30 s while the tab polls instead of using Realtime (the events poll still brings DMs/requests)
    const timer = window.setInterval(() => { if (document.visibilityState === 'visible') void reload(); }, pollMode ? 30_000 : 60_000);
    return () => window.clearInterval(timer);
  }, [reload, pollMode]);
  // Friend requests, knocks and new DMs arrive through the existing per-player events channel.
  useEffect(() => { if (eventsRevision) void reload(); }, [eventsRevision, reload]);

  // P1: a tapped notification asks for a screen: messages:dm:<conversation>, messages:house, messages:requests,
  // and the Benin Gist links gist:post:<id>, gist:group:<id>, gist:feed|groups|chats|friends
  const phoneApp = useUi((s) => s.phoneApp);
  useEffect(() => { void useGist.getState().load(); }, []);
  useEffect(() => {
    if (!phoneApp || !phoneApp.startsWith(`${mode}:`) && !(mode === 'messages' && /^gist:(chats|friends)$/.test(phoneApp))) return;
    const gist = phoneApp.startsWith('gist:');
    const want = phoneApp.slice(gist ? 'gist:'.length : 'messages:'.length);
    const done = () => useUi.setState({ phoneApp: mode });
    if (gist) {
      if (want.startsWith('post:')) { setRoute({ t: 'post', id: Number(want.slice(5)) }); setTab('feed'); }
      else if (want.startsWith('group:')) { setRoute({ t: 'group', id: Number(want.slice(6)) }); setTab('groups'); }
      else if (want === 'feed' || want === 'groups' || want === 'chats' || want === 'friends') { setRoute(null); setTab(want); }
      done();
    } else if (want === 'house') {
      if (!state.travel) { setTab('groups'); setView('group'); }
      done();
    } else if (want === 'requests') {
      if (!requests || !invites) return; // wait for the lists
      const waiting = requests.some((r) => r.direction === 'incoming') || invites.some((i) => (i.role === 'host' && i.status === 'knocking') || (i.role === 'guest' && i.status === 'invited'));
      setTab(waiting ? 'chats' : 'friends');
      if (waiting) setView('requests');
      done();
    } else if (want.startsWith('dm:')) {
      if (!friends) return;
      const friend = friends.find((f) => f.conversation_id === Number(want.slice(3)));
      done();
      setTab('chats');
      if (friend) void openConversation(friend);
    } else done();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [phoneApp, friends, requests, invites]);

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

  // R7: Message from a Friends-tab card (the chat list may not have loaded this friend yet)
  const openFromCard = async (c: FriendCard) => {
    const known = friends?.find((f) => f.id === c.id);
    await openConversation(known ?? {
      id: c.id, username: c.username, avatar: c.avatar, at_home: c.at_home, last_seen: c.last_seen ?? '', conversation_id: c.conversation_id,
      last_message: null, last_message_at: null, last_sender_id: null, unread: c.unread,
    });
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

  const nav: FeedNav = {
    openPost: (id) => setRoute({ t: 'post', id }),
    openProfile: (id) => setRoute({ t: 'profile', id }),
    openProfileByName: (name) => setRoute({ t: 'profile', id: null, name }),
    openTag: (t) => { setTag(t); setTab('feed'); setRoute(null); },
  };
  const messageUser = (userId: string) => {
    const friend = friends?.find((f) => f.id === userId);
    if (!friend) { toast('Add them as a friend first, then you can message.', 'info'); return; }
    setRoute(null);
    if (mode === 'messages') setTab('chats');
    void openConversation(friend);
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

  const mainHidden = route !== null;
  return (
    <>
    {route?.t === 'post' && <PostPage state={state} id={route.id} nav={nav} onBack={() => setRoute(null)} />}
    {route?.t === 'profile' && <ProfilePage state={state} userId={route.id} username={route.name} nav={nav} onBack={() => setRoute(null)} onMessage={messageUser} onChanged={() => void reload()} />}
    {route?.t === 'group' && <GroupChat key={route.id} state={state} groupId={route.id} nav={nav} onBack={() => { setRoute(null); setGroupsKey((k) => k + 1); }} onChanged={() => setGroupsKey((k) => k + 1)} />}
    <div className="phone-app__body social-app msgs gist-app" style={mainHidden ? { display: 'none' } : undefined}>
      <header className="msgs-head">
        {onBack && (
          <button type="button" className="msgs-iconbtn msgs-iconbtn--bare" onClick={onBack} aria-label="Back to apps">
            <Icon name="back" size={22} stroke={2.6} />
          </button>
        )}
        <h2 className="msgs-head__title">{mode === 'gist' ? 'Benin Gist' : 'Messages'}</h2>
        {onOpenAlerts && (
          <button type="button" className="msgs-iconbtn msgs-bell" onClick={onOpenAlerts} aria-label={`Alerts${alertsUnread ? `, ${alertsUnread} new` : ''}`}>
            <Icon name="bell" size={21} />
            {alertsUnread > 0 && <span className="msgs-badge msgs-bell__badge">{alertsUnread > 9 ? '9+' : alertsUnread}</span>}
          </button>
        )}
      </header>

      <div className="msgs-tabs gist-tabs" role="tablist">
        {mode === 'gist' && <button type="button" role="tab" aria-selected={tab === 'feed'} className={tab === 'feed' ? 'is-on' : ''} onClick={() => setTab('feed')}>Feed</button>}
        {mode === 'messages' && <button type="button" role="tab" aria-selected={tab === 'chats'} className={tab === 'chats' ? 'is-on' : ''} onClick={() => setTab('chats')}>
          Chats <Badge n={unreadChats} />
        </button>}
        <button type="button" role="tab" aria-selected={tab === 'groups'} className={tab === 'groups' ? 'is-on' : ''} onClick={() => setTab('groups')}>
          Groups <Badge n={unreadGroups} />
        </button>
        {mode === 'messages' && <button type="button" role="tab" aria-selected={tab === 'friends'} className={tab === 'friends' ? 'is-on' : ''} onClick={() => setTab('friends')}>
          Friends <Badge n={incoming.length} />
        </button>}
      </div>

      {mode === 'gist' && <div hidden={tab !== 'feed'}>
        <FeedTab state={state} summary={summary} nav={nav} tag={tag} setTag={setTag} refreshKey={0} />
      </div>}

      {loadError && <div className="social-error" role="alert">{loadError}<Button size="sm" variant="ghost" onClick={() => void reload()}>Retry</Button></div>}

      {tab === 'feed' ? null : tab === 'friends' ? (
        <FriendsTab onMessage={(c) => void openFromCard(c)} onRefreshAll={() => void reload()} />
      ) : tab === 'groups' ? (
        <GroupsTab state={state} summary={summary} homeNow={homeNow} refreshKey={groupsKey} onOpenGroup={(id) => setRoute({ t: 'group', id })} onOpenPlaceChat={() => setView('group')} />
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
    </>
  );
}
