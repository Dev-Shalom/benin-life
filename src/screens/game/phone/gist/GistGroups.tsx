// Benin Gist -> Groups (docs/GIST.md): my groups (with unread counts), Discover (search, most active / new / big), create a group,
// and the old "chat where you are" (place or house chat) kept one tap away.
import { useCallback, useEffect, useRef, useState } from 'react';
import { gistGroupCreate, gistGroupJoin, gistGroupsDiscover, gistGroupsMine, type GistGroup, type GistSummary } from '../../../../api/gist';
import { errorMessage } from '../../../../lib/api';
import { timeAgo } from '../../../../lib/format';
import type { GameState } from '../../../../lib/types';
import { Button, Icon, Spinner, Switch, toast } from '../../../../ui';
import { MiniSheet } from '../DmConversation';
import { count, GroupTile } from './gistKit';

const EMOJI = ['💬', '🎓', '💼', '🪩', '🏷️', '⚽', '🍲', '🎵', '🚗', '🏠', '📚', '🎮', '🙏🏾', '💸', '🌍', '🔥', '😂', '🛍️', '🧑🏾‍🍳', '📣'];

function rowTime(iso: string | null) {
  if (!iso) return '';
  const d = new Date(iso);
  const now = new Date();
  if (d.toDateString() === now.toDateString()) return d.toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit' });
  const y = new Date(now); y.setDate(now.getDate() - 1);
  if (d.toDateString() === y.toDateString()) return 'Yesterday';
  return d.toLocaleDateString('en-GB', { day: 'numeric', month: 'short' });
}

function CreateGroupSheet({ summary, onClose, onCreated }: { summary: GistSummary | null; onClose: () => void; onCreated: (g: GistGroup) => void }) {
  const [name, setName] = useState('');
  const [emoji, setEmoji] = useState('💬');
  const [desc, setDesc] = useState('');
  const [isPublic, setPublic] = useState(true);
  const [busy, setBusy] = useState(false);
  const create = async () => {
    setBusy(true);
    try { onCreated(await gistGroupCreate(name, emoji, desc, isPublic)); onClose(); }
    catch (e) { toast(errorMessage(e), 'bad'); setBusy(false); }
  };
  return (
    <MiniSheet title="New group" onClose={onClose}>
      <div className="dm-sheet__body stack gist-create">
        <div className="gist-create__top">
          <GroupTile id={name.length} emoji={emoji} size={64} />
          <input className="input" value={name} maxLength={32} placeholder="Group name" aria-label="Group name" autoFocus onChange={(e) => setName(e.target.value)} />
        </div>
        <div className="gist-emojis" role="group" aria-label="Group icon">
          {EMOJI.map((e) => <button key={e} type="button" className={e === emoji ? 'is-on' : ''} aria-label={e} aria-pressed={e === emoji} onClick={() => setEmoji(e)}>{e}</button>)}
        </div>
        <textarea className="input" rows={2} maxLength={200} value={desc} placeholder="What is this group about? (optional)" aria-label="Description" onChange={(e) => setDesc(e.target.value)} />
        <Switch checked={isPublic} onChange={setPublic} label={isPublic ? 'Public group' : 'Private group'}
          hint={isPublic ? 'Anyone can find it in Discover and join.' : 'Invite only. You or an admin add your friends.'} />
        <p className="gist-fine">Up to {summary?.group_cap ?? 200} members. You can add admins, mute people and pin a message.</p>
        <Button variant="green" block loading={busy} disabled={name.trim().length < 3 || busy} onClick={() => void create()}>Create group</Button>
      </div>
    </MiniSheet>
  );
}

function GroupRow({ g, onOpen }: { g: GistGroup; onOpen: (id: number) => void }) {
  return (
    <button type="button" className={`msgs-row gist-grouprow${g.unread > 0 ? ' is-unread' : ''}`} onClick={() => onOpen(g.id)}>
      <GroupTile id={g.id} emoji={g.emoji} />
      <span className="msgs-row__main">
        <b>{g.name}{!g.is_public && <span className="gist-lock" title="Private" aria-label="Private"><Icon name="lock" size={13} /></span>}</b>
        <span>{g.last_msg_text ? `${g.last_msg_user ? `${g.last_msg_user}: ` : ''}${g.last_msg_text}` : g.description || 'No messages yet. Say hello.'}</span>
      </span>
      <span className="msgs-row__side">
        <time>{rowTime(g.last_msg_at)}</time>
        {g.unread > 0 ? <span className="msgs-badge">{g.unread > 99 ? '99+' : g.unread}</span> : g.role === 'owner' || g.role === 'admin' ? <span className="gist-role">{g.role}</span> : null}
      </span>
    </button>
  );
}

export function GroupsTab({ state, summary, onOpenGroup, onOpenPlaceChat, homeNow, refreshKey }: {
  state: GameState; summary: GistSummary | null; onOpenGroup: (id: number) => void; onOpenPlaceChat: () => void; homeNow: boolean; refreshKey: number;
}) {
  const [mode, setMode] = useState<'mine' | 'discover'>('mine');
  const [mine, setMine] = useState<GistGroup[] | null>(null);
  const [found, setFound] = useState<GistGroup[] | null>(null);
  const [query, setQuery] = useState('');
  const [sort, setSort] = useState<'active' | 'new' | 'big'>('active');
  const [error, setError] = useState<string | null>(null);
  const [creating, setCreating] = useState(false);
  const [busy, setBusy] = useState<number | null>(null);
  const [moreBusy, setMoreBusy] = useState(false);
  const [done, setDone] = useState(false);
  const req = useRef(0);

  const loadMine = useCallback(async () => {
    try { setMine(await gistGroupsMine()); setError(null); } catch (e) { setError(errorMessage(e)); setMine((old) => old ?? []); }
  }, []);
  useEffect(() => { void loadMine(); }, [loadMine, refreshKey]);

  useEffect(() => {
    if (mode !== 'discover') return;
    const id = ++req.current;
    setFound(null); setDone(false);
    const t = window.setTimeout(() => {
      gistGroupsDiscover(query.trim(), sort, 0).then((r) => { if (id === req.current) { setFound(r); setDone(r.length < 30); } })
        .catch((e) => { if (id === req.current) { setError(errorMessage(e)); setFound([]); } });
    }, query ? 260 : 0);
    return () => window.clearTimeout(t);
  }, [mode, query, sort, refreshKey]);

  const loadMore = async () => {
    if (!found || moreBusy || done) return;
    setMoreBusy(true);
    try {
      const r = await gistGroupsDiscover(query.trim(), sort, found.length);
      setFound((old) => [...(old ?? []), ...r.filter((x) => !(old ?? []).some((o) => o.id === x.id))]);
      setDone(r.length < 30);
    } catch (e) { toast(errorMessage(e), 'bad'); }
    finally { setMoreBusy(false); }
  };

  const join = async (g: GistGroup) => {
    setBusy(g.id);
    try {
      await gistGroupJoin(g.id);
      toast(`You joined ${g.name}.`, 'good');
      void loadMine();
      onOpenGroup(g.id);
    } catch (e) { toast(errorMessage(e), 'bad'); }
    finally { setBusy(null); }
  };

  return (
    <div className="gist-groups">
      {!state.travel && (
        <button type="button" className="msgs-row gist-placechat" onClick={onOpenPlaceChat}>
          <span className="msgs-face msgs-face--group" aria-hidden>{homeNow ? '🏠' : '📍'}</span>
          <span className="msgs-row__main">
            <b>{homeNow ? 'House chat' : `Chat at ${state.location.name}`}</b>
            <span>{homeNow ? 'Everyone inside the house right now' : 'Everyone at this place right now'}</span>
          </span>
          <Icon name="chevronRight" size={18} />
        </button>
      )}

      <div className="gist-views">
        <div className="gist-seg" role="tablist" aria-label="Groups">
          <button type="button" role="tab" aria-selected={mode === 'mine'} className={mode === 'mine' ? 'is-on' : ''} onClick={() => setMode('mine')}>My groups</button>
          <button type="button" role="tab" aria-selected={mode === 'discover'} className={mode === 'discover' ? 'is-on' : ''} onClick={() => setMode('discover')}>Discover</button>
        </div>
        <button type="button" className="gist-iconbtn gist-iconbtn--solid" aria-label="Create a group" onClick={() => setCreating(true)} disabled={summary ? !summary.can_post : false}><Icon name="plus" size={20} stroke={2.8} /></button>
      </div>
      {summary && !summary.can_post && <p className="gist-note"><Icon name="info" size={16} /> {summary.why}</p>}
      {error && <div className="social-error" role="alert">{error}<Button size="sm" variant="ghost" onClick={() => { setError(null); void loadMine(); }}>Retry</Button></div>}

      {mode === 'mine' ? (
        mine === null ? <div className="social-loading"><Spinner size={18} /></div>
          : mine.length === 0 ? (
            <div className="gist-empty">
              <span aria-hidden>👥</span>
              <b>No groups yet</b>
              <p>Join a public group in Discover, or start your own and add your friends.</p>
              <Button variant="green" onClick={() => setMode('discover')}>Find a group</Button>
            </div>
          ) : <div className="msgs-list">{mine.map((g) => <GroupRow key={g.id} g={g} onOpen={onOpenGroup} />)}</div>
      ) : (
        <>
          <label className="msgs-input gist-search">
            <Icon name="chat" size={18} />
            <input value={query} placeholder="Search groups" aria-label="Search groups" onChange={(e) => setQuery(e.target.value)} />
          </label>
          <div className="gist-chips" role="group" aria-label="Sort groups">
            {([['active', 'Active'], ['new', 'New'], ['big', 'Biggest']] as const).map(([k, label]) => (
              <button key={k} type="button" className={`gist-chip${sort === k ? ' is-on' : ''}`} aria-pressed={sort === k} onClick={() => setSort(k)}>{label}</button>
            ))}
          </div>
          {found === null ? <div className="social-loading"><Spinner size={18} /></div>
            : found.length === 0 ? <p className="msgs-empty">{query ? 'No group matches that.' : 'No public groups yet. Start one!'}</p>
              : (
                <div className="gist-discover">
                  {found.map((g) => (
                    <div key={g.id} className="gist-gcard">
                      <button type="button" className="gist-gcard__main" onClick={() => onOpenGroup(g.id)}>
                        <GroupTile id={g.id} emoji={g.emoji} />
                        <span>
                          <b><span className="gist-name">{g.name}</span>{g.system && <span className="gist-official" title="Official group"><Icon name="check" size={11} stroke={3.4} /></span>}</b>
                          <small>{count(g.members)} / {count(g.cap)} members{g.last_msg_at ? ` · active ${timeAgo(g.last_msg_at)}` : ''}</small>
                          {g.description && <em>{g.description}</em>}
                        </span>
                      </button>
                      {g.joined ? <span className="gist-joined">Joined</span>
                        : g.members >= g.cap ? <span className="gist-full">Full</span>
                          : <Button size="sm" variant="green" loading={busy === g.id} onClick={() => void join(g)}>Join</Button>}
                    </div>
                  ))}
                  {!done && <div className="gist-more"><Button size="sm" variant="ghost" loading={moreBusy} onClick={() => void loadMore()}>Show more</Button></div>}
                </div>
              )}
        </>
      )}
      {creating && <CreateGroupSheet summary={summary} onClose={() => setCreating(false)} onCreated={(g) => { void loadMine(); setMode('mine'); onOpenGroup(g.id); }} />}
    </div>
  );
}
