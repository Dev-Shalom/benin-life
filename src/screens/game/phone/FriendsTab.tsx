// R7 Friends tab inside Phone -> Messages (docs/LOUNGE.md "Friends"). ONE read, friends_overview(), feeds everything: requests on
// top (Accept / Decline), online friends first (green dot = active in the last ~2 minutes, else "last seen 3h ago"), where they are
// (unless they hide it) and quick actions: Message, Join them, Invite to my place / house, Yahoo group, bring to the Lounge.
// The overview is polled ONLY while this tab is mounted (startPoller: visible tab, jittered), and on a new alert.
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import type { FormEvent } from 'react';
import { AvatarPortrait } from '../../../art/avatar3d';
import {
  friendInvitePlace, friendJoinCheck, friendsOverview, friendsSetPrivacy, lastSeenLabel, type FriendCard, type FriendsOverview,
} from '../../../api/friends';
import { loungeBringGuest } from '../../../api/lounge';
import { socialCancelFriendRequest, socialRespondFriend, socialSearchPlayers, socialSendHouseInvite, type SocialPlayer } from '../../../api/social';
import { errorMessage, GameError } from '../../../lib/api';
import { startPoller } from '../../../lib/realtime';
import { useGame } from '../../../state/game';
import { useLounge } from '../../../state/lounge';
import { useUi } from '../../../state/ui';
import { Button, Spinner, Switch, toast } from '../../../ui';
import { SocialPlayerButton } from '../SocialPlayerButton';
import './FriendsTab.css';

function where(c: FriendCard): string {
  if (!c.online) return `last seen ${lastSeenLabel(c.last_seen)}`;
  if (c.location_hidden) return 'Location hidden';
  if (!c.location) return 'Online';
  return c.location.traveling ? 'On the road' : c.location.private ? 'At home' : c.location.name;
}

export function FriendsTab({ onMessage, onRefreshAll }: { onMessage: (c: FriendCard) => void; onRefreshAll?: () => void }) {
  const [data, setData] = useState<FriendsOverview | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [who, setWho] = useState('');
  const [searching, setSearching] = useState(false);
  const [results, setResults] = useState<SocialPlayer[] | null>(null);
  const periodRef = useRef(20_000);
  const pollRef = useRef<ReturnType<typeof startPoller> | null>(null);
  const eventsRevision = useGame((s) => s.events[0]?.id ?? 0);
  const showLounge = useLounge((s) => s.show);

  const load = useCallback(async () => {
    try {
      const r = await friendsOverview();
      periodRef.current = Math.max(10, r.poll_seconds ?? 20) * 1000;
      setData(r);
      setError(null);
    } catch (e) {
      setError(errorMessage(e));
    }
  }, []);

  // poll only while this tab is open (unmount stops it); startPoller also pauses while the browser tab is hidden
  useEffect(() => {
    const p = startPoller(load, () => periodRef.current, { immediate: true });
    pollRef.current = p;
    return () => { p.stop(); pollRef.current = null; };
  }, [load]);
  // a friend request / invite alert arrived: refresh now
  useEffect(() => { if (eventsRevision) pollRef.current?.kick(600); }, [eventsRevision]);

  const run = async (key: string, fn: () => Promise<void>) => {
    setBusy(key);
    try { await fn(); } catch (e) { toast(errorMessage(e), 'bad'); } finally { setBusy(null); }
  };

  const join = (c: FriendCard) => run(`join:${c.id}`, async () => {
    try {
      const r = await friendJoinCheck(c.id);
      const ui = useUi.getState();
      ui.closeAll();
      ui.setMapOpen(true);
      ui.select(r.dest);
      toast(`Heading to @${c.username} at ${r.name}. Pick how to go.`, 'info');
    } catch (e) {
      if (e instanceof GameError && e.hint === 'no_membership') { showLounge(); return; }
      throw e;
    }
  });

  const respond = (id: string, accept: boolean, outgoing: boolean) => run(`req:${id}`, async () => {
    const r = outgoing ? await socialCancelFriendRequest(id) : await socialRespondFriend(id, accept);
    toast(r.message, accept ? 'good' : 'info');
    await load();
    onRefreshAll?.();
  });

  const search = async (e: FormEvent) => {
    e.preventDefault();
    const v = who.trim().replace(/^@+/, '');
    if (v.length < 3) { toast('Type at least 3 letters of their @username.', 'info'); return; }
    setSearching(true);
    try { setResults(await socialSearchPlayers(v)); } catch (err) { toast(errorMessage(err), 'bad'); } finally { setSearching(false); }
  };

  const togglePrivacy = (show: boolean) => run('privacy', async () => {
    setData((d) => (d ? { ...d, me: { ...d.me, share_location: show } } : d));
    const r = await friendsSetPrivacy(show);
    toast(r.message, 'info');
    await load();
  });

  const online = useMemo(() => (data?.friends ?? []).filter((f) => f.online), [data]);
  const offline = useMemo(() => (data?.friends ?? []).filter((f) => !f.online), [data]);
  const incoming = (data?.requests ?? []).filter((r) => r.direction === 'incoming');
  const outgoing = (data?.requests ?? []).filter((r) => r.direction === 'outgoing');
  const me = data?.me;

  const row = (c: FriendCard) => {
    const joinable = c.can_join;
    const lounge = c.join_hint === 'no_membership';
    return (
      <li key={c.id} className={`fr-card${c.online ? ' is-online' : ''}`}>
        <div className="fr-card__top">
          <span className="fr-face">
            {c.avatar && <AvatarPortrait config={c.avatar} size={52} />}
            <i className={`fr-dot${c.online ? ' is-on' : ''}`} aria-label={c.online ? 'Online' : 'Offline'} />
          </span>
          <span className="fr-card__main">
            <b>@{c.username}{c.unread > 0 && <span className="msgs-badge fr-unread">{c.unread > 9 ? '9+' : c.unread}</span>}</b>
            <span className={`fr-where${c.online && c.location && !c.location_hidden ? ' is-place' : ''}`}>
              {c.online && c.location && !c.location_hidden && !c.location.private && !c.location.traveling && <span aria-hidden>📍 </span>}
              {where(c)}
            </span>
          </span>
        </div>
        <div className="fr-actions">
          <button type="button" className="dm-chip dm-chip--blue" onClick={() => onMessage(c)}><span aria-hidden>💬</span> Message</button>
          {c.online && (joinable || lounge) && (
            <button type="button" className="dm-chip dm-chip--green" disabled={busy === `join:${c.id}`} onClick={() => void join(c)}>
              <span aria-hidden>{lounge ? '🔒' : '🚶'}</span> {lounge ? 'Get pass to join' : 'Join them'}
            </button>
          )}
          {c.online && !joinable && !lounge && c.join_hint && c.join_hint !== 'same' && c.join_hint !== 'offline' && (
            <span className="fr-why" title={c.join_reason ?? ''}>{c.join_hint === 'hidden' ? 'Location hidden' : c.join_hint === 'closed' || c.join_hint === 'inactive' ? 'Place closed' : c.join_hint === 'private' ? 'At home' : 'Cannot join'}</span>
          )}
          {me?.place.can_invite && (
            <button type="button" className="dm-chip dm-chip--gold" disabled={busy === `inv:${c.id}`}
              onClick={() => void run(`inv:${c.id}`, async () => { const r = await friendInvitePlace(c.id); toast(r.message, 'good'); })}>
              <span aria-hidden>📍</span> Invite here
            </button>
          )}
          {me?.home_chosen && (
            <button type="button" className="dm-chip dm-chip--gold" disabled={busy === `home:${c.id}` || Boolean(c.house_invite)}
              onClick={() => void run(`home:${c.id}`, async () => { const r = await socialSendHouseInvite(c.id); toast(r.message || 'House invite sent.', 'good'); await load(); })}>
              <span aria-hidden>🏠</span> {c.house_invite ? 'Invited' : 'Invite home'}
            </button>
          )}
          {c.yahoo_ready && (
            <button type="button" className="dm-chip dm-chip--blue" onClick={() => useUi.getState().openPhone('yahoo')}><span aria-hidden>💻</span> Yahoo group</button>
          )}
          {c.online && me && me.lounge_guest_slots > me.lounge_guests_active && (
            <button type="button" className="dm-chip dm-chip--gold" disabled={busy === `guest:${c.id}`}
              onClick={() => void run(`guest:${c.id}`, async () => { const r = await loungeBringGuest(c.id); toast(r.message, 'good'); await load(); })}>
              <span aria-hidden>👑</span> Bring to Lounge
            </button>
          )}
        </div>
      </li>
    );
  };

  return (
    <div className="fr">
      <form className="msgs-input fr-search" onSubmit={(e) => void search(e)}>
        <span aria-hidden>➕</span>
        <input value={who} maxLength={21} placeholder="Add a friend: @username" aria-label="Add a friend by username"
          autoCapitalize="none" autoCorrect="off" spellCheck={false} enterKeyHint="search"
          onChange={(e) => { setWho(e.target.value); setResults(null); }} />
        {who.trim().length > 0 && <Button type="submit" size="sm" variant="green" loading={searching}>Find</Button>}
      </form>
      {results && (
        <div className="msgs-results">
          {results.length === 0 ? <p className="msgs-muted">No players found. Check the spelling and try again.</p>
            : results.map((p) => (
              <div className="msgs-req" key={p.id}>
                <span className="msgs-face msgs-face--sm">{p.avatar && <AvatarPortrait config={p.avatar} size={44} />}</span>
                <span className="grow msgs-req__copy"><b>@{p.username}</b></span>
                <SocialPlayerButton userId={p.id} onChanged={() => { void load(); onRefreshAll?.(); }} />
              </div>
            ))}
        </div>
      )}

      {error && <div className="social-error" role="alert">{error}<Button size="sm" variant="ghost" onClick={() => void load()}>Retry</Button></div>}
      {!data && !error && <div className="social-loading"><Spinner size={18} /></div>}

      {incoming.length > 0 && (
        <section aria-label="Friend requests">
          <h3 className="msgs-sub">Requests</h3>
          {incoming.map((r) => (
            <div className="msgs-req" key={r.id}>
              <span className="msgs-face msgs-face--sm">{r.avatar && <AvatarPortrait config={r.avatar} size={44} />}</span>
              <b className="grow">@{r.username}</b>
              <Button size="sm" variant="ghost" disabled={busy === `req:${r.id}`} onClick={() => void respond(r.id, false, false)}>Decline</Button>
              <Button size="sm" variant="green" loading={busy === `req:${r.id}`} onClick={() => void respond(r.id, true, false)}>Accept</Button>
            </div>
          ))}
        </section>
      )}

      {data && data.friends.length === 0 && (
        <p className="msgs-empty">No friends yet. Search a @username above, or add people you meet around Benin.</p>
      )}

      {online.length > 0 && <h3 className="msgs-sub fr-sub"><i className="fr-dot is-on" /> Online · {online.length}</h3>}
      <ul className="fr-list">{online.map(row)}</ul>
      {offline.length > 0 && <h3 className="msgs-sub fr-sub">Offline · {offline.length}</h3>}
      <ul className="fr-list">{offline.map(row)}</ul>

      {outgoing.length > 0 && (
        <section aria-label="Sent requests">
          <h3 className="msgs-sub">Waiting on them</h3>
          {outgoing.map((r) => (
            <div className="msgs-req" key={r.id}>
              <span className="msgs-face msgs-face--sm">{r.avatar && <AvatarPortrait config={r.avatar} size={44} />}</span>
              <span className="grow">Request to <b>@{r.username}</b></span>
              <Button size="sm" variant="ghost" loading={busy === `req:${r.id}`} onClick={() => void respond(r.id, false, true)}>Cancel</Button>
            </div>
          ))}
        </section>
      )}

      {me && (
        <div className="fr-privacy">
          <Switch checked={me.share_location} onChange={(v) => void togglePrivacy(v)} disabled={busy === 'privacy'}
            label="Show my location to friends" hint="Friends see the place you are at and can join you. Off = they only see you are online." />
        </div>
      )}
    </div>
  );
}
