// Benin Gist -> Feed (docs/GIST.md). For you / Following, #tag filter, post composer (text + optional compressed photo), like, tip,
// the post page with comments (one level of replies) and player profiles. Paged by RPC with cursors, pull to refresh, no Realtime.
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import type { ReactNode } from 'react';
import {
  discardGistPhoto, gistComment, gistComments, gistDeleteComment, gistDeletePost, gistFeed, gistFollow, gistLike, gistPhotoUrl, gistPost,
  gistPostGet, gistProfile, gistTipPost, gistTrending, gistUserPosts, uploadGistPhoto,
  type FeedCursor, type FeedView, type GistComment, type GistPost, type GistProfile, type GistSummary,
} from '../../../../api/gist';
import { socialSearchPlayers } from '../../../../api/social';
import { errorMessage } from '../../../../lib/api';
import { useConfig } from '../../../../lib/config';
import { naira, nairaShort, timeAgo } from '../../../../lib/format';
import { compressImage } from '../../../../lib/image';
import type { GameState } from '../../../../lib/types';
import { useGame } from '../../../../state/game';
import { AmountBox } from '../../../../panels/bank/BankUI';
import { Button, Icon, Spinner, toast } from '../../../../ui';
import { SocialPlayerButton } from '../../SocialPlayerButton';
import { MiniSheet, SendMoneySheet } from '../DmConversation';
import { FeeLine, useFeeQuote } from '../FeeLine';
import { count, Face, GistText, PageHead, ReportSheet } from './gistKit';

export interface FeedNav {
  openPost: (id: number) => void;
  openProfile: (userId: string) => void;
  openProfileByName: (username: string) => void;
  openTag: (tag: string) => void;
}

// ---------------------------------------------------------------------------------------------------------------
// One post
// ---------------------------------------------------------------------------------------------------------------
function PostCard({ post, nav, onLike, onTip, onMenu, detail }: {
  post: GistPost; nav: FeedNav; onLike: (p: GistPost) => void; onTip: (p: GistPost) => void; onMenu: (p: GistPost) => void; detail?: boolean;
}) {
  const [zoom, setZoom] = useState(false);
  return (
    <article className={`gist-post${detail ? ' is-detail' : ''}`}>
      <header className="gist-post__head">
        <Face user={post.user} size={46} onClick={() => nav.openProfile(post.user.id)} />
        <div className="gist-post__who">
          <button type="button" className="gist-post__name" onClick={() => nav.openProfile(post.user.id)}>@{post.user.username}</button>
          <time dateTime={post.created_at}>{timeAgo(post.created_at)}</time>
        </div>
        <button type="button" className="gist-iconbtn" aria-label="More" onClick={() => onMenu(post)}><Icon name="more" size={20} stroke={3} /></button>
      </header>
      {post.body && (
        <p className="gist-post__body" onClick={detail ? undefined : () => nav.openPost(post.id)}>
          <GistText text={post.body} onTag={nav.openTag} onMention={nav.openProfileByName} />
        </p>
      )}
      {post.photo_path && (
        <button type="button" className={`gist-post__photo${zoom ? ' is-zoom' : ''}`} aria-label={zoom ? 'Shrink photo' : 'Enlarge photo'} onClick={() => setZoom((z) => !z)}>
          <img src={gistPhotoUrl(post.photo_path)} alt="Photo in the gist" loading="lazy" decoding="async" />
        </button>
      )}
      <footer className="gist-post__actions">
        <button type="button" className={`gist-act gist-act--like${post.liked ? ' is-on' : ''}`} aria-pressed={post.liked} onClick={() => onLike(post)}
          aria-label={`${post.liked ? 'Unlike' : 'Like'}, ${post.likes} likes`}>
          <svg width="20" height="20" viewBox="0 0 24 24" fill={post.liked ? 'currentColor' : 'none'} stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
            <path d="M12 20s-7-4.4-7-10a4 4 0 0 1 7-2.6A4 4 0 0 1 19 10c0 5.6-7 10-7 10Z" />
          </svg>
          <span>{count(post.likes)}</span>
        </button>
        <button type="button" className="gist-act" onClick={() => nav.openPost(post.id)} aria-label={`Comments, ${post.comments}`}>
          <Icon name="chat" size={20} /><span>{count(post.comments)}</span>
        </button>
        {!post.mine && (
          <button type="button" className="gist-act gist-act--tip" onClick={() => onTip(post)} aria-label="Tip the poster">
            <span className="gist-act__coin" aria-hidden>🪙</span><span>Tip</span>
          </button>
        )}
        {post.tip_total > 0 && <span className="gist-post__tips" title={`${post.tips} tips`}>🪙 {nairaShort(post.tip_total)}</span>}
      </footer>
    </article>
  );
}

// ---------------------------------------------------------------------------------------------------------------
// Sheets: composer, tip, post menu
// ---------------------------------------------------------------------------------------------------------------
function Composer({ me, summary, preset, onClose, onPosted }: {
  me: GameState['profile']; summary: GistSummary; preset?: string; onClose: () => void; onPosted: (p: GistPost) => void;
}) {
  const [text, setText] = useState(preset ?? '');
  const [photo, setPhoto] = useState<{ blob: Blob; url: string } | null>(null);
  const [busy, setBusy] = useState(false);
  const fileRef = useRef<HTMLInputElement>(null);
  useEffect(() => () => { if (photo) URL.revokeObjectURL(photo.url); }, [photo]);
  const left = summary.post_max_len - text.length;
  const ready = (text.trim().length > 0 || photo) && left >= 0 && !busy;

  const pick = async (file: File | undefined) => {
    if (!file) return;
    try {
      const blob = await compressImage(file, summary.photo_max_kb * 1024);
      setPhoto((old) => { if (old) URL.revokeObjectURL(old.url); return { blob, url: URL.createObjectURL(blob) }; });
    } catch (e) { toast(errorMessage(e), 'bad'); }
  };
  const addTag = (place: string) => {
    const tag = `#${place.replace(/[^A-Za-z0-9]/g, '')}`;
    if (text.toLowerCase().includes(tag.toLowerCase())) return;
    setText((t) => `${t}${t && !/\s$/.test(t) ? ' ' : ''}${tag} `);
  };
  const post = async () => {
    setBusy(true);
    let path: string | null = null;
    try {
      if (photo) path = await uploadGistPhoto(me.id, photo.blob);
      const p = await gistPost(text, path);
      onPosted(p);
      onClose();
    } catch (e) {
      if (path) void discardGistPhoto(path).catch(() => undefined);
      toast(errorMessage(e), 'bad');
      setBusy(false);
    }
  };
  return (
    <MiniSheet title="New gist" onClose={onClose}>
      <div className="dm-sheet__body gist-compose">
        <div className="gist-compose__row">
          <Face user={{ username: me.username, avatar: me.avatar }} size={44} />
          <textarea value={text} maxLength={summary.post_max_len + 40} autoFocus rows={4} placeholder="Wetin dey happen for Benin?" aria-label="Your gist"
            onChange={(e) => setText(e.target.value)} />
        </div>
        {photo && (
          <div className="gist-compose__photo">
            <img src={photo.url} alt="Your photo" />
            <button type="button" aria-label="Remove photo" onClick={() => setPhoto(null)}><Icon name="close" size={16} stroke={2.6} /></button>
          </div>
        )}
        <div className="gist-chips" role="group" aria-label="Add a place tag">
          {summary.places.slice(0, 8).map((pl) => <button key={pl} type="button" className="gist-chip" onClick={() => addTag(pl)}>#{pl.replace(/[^A-Za-z0-9]/g, '')}</button>)}
        </div>
        <div className="gist-compose__foot">
          {summary.photos_enabled && (
            <>
              <input ref={fileRef} type="file" accept="image/*" hidden onChange={(e) => { void pick(e.target.files?.[0]); e.target.value = ''; }} />
              <button type="button" className="gist-iconbtn gist-iconbtn--fill" aria-label="Add a photo" onClick={() => fileRef.current?.click()}><Icon name="camera" size={20} /></button>
            </>
          )}
          <span className={`gist-count${left < 0 ? ' is-over' : left < 30 ? ' is-low' : ''}`}>{left}</span>
          <Button variant="green" className="grow" loading={busy} disabled={!ready} onClick={() => void post()}>Post gist</Button>
        </div>
      </div>
    </MiniSheet>
  );
}

const TIP_CHIPS = [500, 1000, 5000];

function TipSheet({ state, post, onClose, onTipped }: { state: GameState; post: GistPost; onClose: () => void; onTipped: (r: { tips: number; tip_total: number }) => void }) {
  const refresh = useGame((s) => s.refresh);
  const { cfg } = useConfig();
  const min = cfg<number>('tips.min_amount', 100);
  const [amount, setAmount] = useState('');
  const [busy, setBusy] = useState(false);
  const n = Number(amount) || 0;
  const quote = useFeeQuote(n, min, 'tip');
  const bank = state.profile.bank;
  const total = quote?.total ?? n;
  const blocked = n < min ? `At least ${naira(min)}` : total > bank + state.profile.cash ? 'Not enough money' : null;
  const send = async () => {
    setBusy(true);
    try {
      const r = await gistTipPost(post.id, n, null);
      toast(`🪙 ${r.message}`, 'good');
      void refresh();
      onTipped(r);
      onClose();
    } catch (e) { toast(errorMessage(e), 'bad'); setBusy(false); }
  };
  return (
    <MiniSheet title={`Tip @${post.user.username}`} onClose={onClose}>
      <div className="dm-sheet__body stack">
        <p className="dm-sheet__lead">Say thanks for a good gist. It comes from your bank (cash if the bank is short). Bank balance <b>{naira(bank)}</b>.</p>
        <AmountBox value={amount} onChange={setAmount} max={Math.max(0, Math.min(bank, cfg<number>('tips.max_amount', 1_000_000)))} min={min} />
        <div className="gist-chips">
          {TIP_CHIPS.map((c) => <button key={c} type="button" className={`gist-chip${n === c ? ' is-on' : ''}`} onClick={() => setAmount(String(c))}>{nairaShort(c)}</button>)}
        </div>
        <FeeLine quote={quote} />
        <Button variant="green" block loading={busy} disabled={Boolean(blocked) || busy} onClick={() => void send()}>{blocked ?? `Tip ${naira(n)}`}</Button>
      </div>
    </MiniSheet>
  );
}

function PostMenu({ post, onClose, onDelete, onReport, onProfile }: {
  post: GistPost; onClose: () => void; onDelete: () => void; onReport: () => void; onProfile: () => void;
}) {
  return (
    <MiniSheet title={`@${post.user.username}'s gist`} onClose={onClose}>
      <div className="dm-sheet__body gist-menu">
        <button type="button" className="msg-menu__item" onClick={onProfile}><Icon name="user" size={18} /> View profile</button>
        <button type="button" className="msg-menu__item" onClick={() => { void navigator.clipboard?.writeText(post.body).then(() => toast('Copied.', 'good')).catch(() => undefined); onClose(); }}><Icon name="copy" size={18} /> Copy text</button>
        {post.mine
          ? <button type="button" className="msg-menu__item is-danger" onClick={onDelete}><Icon name="trash" size={18} /> Delete gist</button>
          : <button type="button" className="msg-menu__item is-danger" onClick={onReport}><Icon name="warning" size={18} /> Report</button>}
      </div>
    </MiniSheet>
  );
}

/** Shared like / tip / menu behaviour for a list of posts. */
function usePostActions(state: GameState, setPosts: (fn: (old: GistPost[]) => GistPost[]) => void, nav: FeedNav) {
  const [tip, setTip] = useState<GistPost | null>(null);
  const [menu, setMenu] = useState<GistPost | null>(null);
  const [report, setReport] = useState<GistPost | null>(null);
  const patch = useCallback((id: number, p: Partial<GistPost>) => setPosts((old) => old.map((x) => (x.id === id ? { ...x, ...p } : x))), [setPosts]);
  const like = useCallback(async (p: GistPost) => {
    const want = !p.liked;
    patch(p.id, { liked: want, likes: Math.max(0, p.likes + (want ? 1 : -1)) });
    try {
      const r = await gistLike(p.id, want);
      patch(p.id, { liked: r.liked, likes: r.likes });
    } catch (e) {
      patch(p.id, { liked: p.liked, likes: p.likes });
      toast(errorMessage(e), 'bad');
    }
  }, [patch]);
  const del = async (p: GistPost) => {
    setMenu(null);
    try {
      const r = await gistDeletePost(p.id);
      if (r.photo_path) void discardGistPhoto(r.photo_path).catch(() => undefined);
      setPosts((old) => old.filter((x) => x.id !== p.id));
      toast(r.message, 'info');
    } catch (e) { toast(errorMessage(e), 'bad'); }
  };
  const sheets: ReactNode = (
    <>
      {tip && <TipSheet state={state} post={tip} onClose={() => setTip(null)} onTipped={(r) => patch(tip.id, { tips: r.tips, tip_total: r.tip_total })} />}
      {menu && <PostMenu post={menu} onClose={() => setMenu(null)} onDelete={() => void del(menu)} onReport={() => { setReport(menu); setMenu(null); }}
        onProfile={() => { nav.openProfile(menu.user.id); setMenu(null); }} />}
      {report && <ReportSheet kind="post" id={report.id} onClose={() => setReport(null)} onDone={(hidden) => { if (hidden) setPosts((old) => old.filter((x) => x.id !== report.id)); }} />}
    </>
  );
  return { like, setTip, setMenu, sheets };
}

// ---------------------------------------------------------------------------------------------------------------
// Feed tab
// ---------------------------------------------------------------------------------------------------------------
export function FeedTab({ state, summary, nav, tag, setTag, refreshKey }: {
  state: GameState; summary: GistSummary | null; nav: FeedNav; tag: string | null; setTag: (t: string | null) => void; refreshKey: number;
}) {
  const me = state.profile;
  const [view, setView] = useState<FeedView>('foryou');
  const [posts, setPosts] = useState<GistPost[] | null>(null);
  const [next, setNext] = useState<FeedCursor | null>(null);
  const [loadingMore, setLoadingMore] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [refreshing, setRefreshing] = useState(false);
  const [trending, setTrending] = useState<{ tag: string; n: number }[]>([]);
  const [composing, setComposing] = useState(false);
  const [pull, setPull] = useState(0);
  const rootRef = useRef<HTMLDivElement>(null);
  const sentinel = useRef<HTMLDivElement>(null);
  const reqId = useRef(0);
  const actions = usePostActions(state, (fn) => setPosts((old) => (old ? fn(old) : old)), nav);

  const load = useCallback(async (quiet = false) => {
    const id = ++reqId.current;
    if (!quiet) setPosts(null);
    setError(null);
    try {
      const page = await gistFeed(view, null, tag);
      if (id !== reqId.current) return;
      setPosts(page.posts);
      setNext(page.next);
    } catch (e) {
      if (id !== reqId.current) return;
      setError(errorMessage(e));
      setPosts((old) => old ?? []);
    }
  }, [view, tag]);

  useEffect(() => { void load(); }, [load, refreshKey]);
  useEffect(() => {
    let alive = true;
    gistTrending().then((t) => alive && setTrending(t)).catch(() => undefined);
    return () => { alive = false; };
  }, []);

  const more = useCallback(async () => {
    if (!next || loadingMore) return;
    setLoadingMore(true);
    const id = reqId.current;
    try {
      const page = await gistFeed(view, next, tag);
      if (id !== reqId.current) return;
      setPosts((old) => { const have = new Set((old ?? []).map((p) => p.id)); return [...(old ?? []), ...page.posts.filter((p) => !have.has(p.id))]; });
      setNext(page.next);
    } catch (e) { toast(errorMessage(e), 'bad'); }
    finally { setLoadingMore(false); }
  }, [next, loadingMore, view, tag]);

  // infinite scroll: load the next page when the sentinel comes into view
  useEffect(() => {
    const el = sentinel.current;
    const scroller = el?.closest('.phone-app__body');
    if (!el || !scroller || typeof IntersectionObserver === 'undefined') return;
    const io = new IntersectionObserver((entries) => { if (entries[0]?.isIntersecting) void more(); }, { root: scroller, rootMargin: '240px' });
    io.observe(el);
    return () => io.disconnect();
  }, [more, posts?.length]);

  const refresh = useCallback(async () => {
    setRefreshing(true);
    await load(true);
    setRefreshing(false);
  }, [load]);

  // pull to refresh (touch): only from the very top of the scroller
  useEffect(() => {
    const scroller = rootRef.current?.closest('.phone-app__body') as HTMLElement | null;
    if (!scroller) return;
    let y0 = -1;
    let dist = 0;
    const start = (e: TouchEvent) => { y0 = scroller.scrollTop <= 0 ? e.touches[0].clientY : -1; dist = 0; };
    const move = (e: TouchEvent) => {
      if (y0 < 0) return;
      dist = Math.max(0, e.touches[0].clientY - y0);
      setPull(dist > 6 ? Math.min(dist * 0.5, 72) : 0);
    };
    const end = () => {
      if (y0 >= 0 && dist > 120) void refresh();
      y0 = -1; dist = 0; setPull(0);
    };
    scroller.addEventListener('touchstart', start, { passive: true });
    scroller.addEventListener('touchmove', move, { passive: true });
    scroller.addEventListener('touchend', end);
    scroller.addEventListener('touchcancel', end);
    return () => { scroller.removeEventListener('touchstart', start); scroller.removeEventListener('touchmove', move); scroller.removeEventListener('touchend', end); scroller.removeEventListener('touchcancel', end); };
  }, [refresh]);

  const chips = useMemo(() => {
    const seen = new Set<string>();
    const out: { tag: string; label: string; n?: number }[] = [];
    for (const t of trending) { seen.add(t.tag); out.push({ tag: t.tag, label: `#${t.tag}`, n: t.n }); }
    for (const pl of summary?.places ?? []) {
      const key = pl.replace(/[^A-Za-z0-9]/g, '').toLowerCase();
      if (key && !seen.has(key)) { seen.add(key); out.push({ tag: key, label: `#${pl.replace(/[^A-Za-z0-9]/g, '')}` }); }
    }
    return out.slice(0, 14);
  }, [trending, summary?.places]);

  const canPost = summary?.can_post ?? true;
  return (
    <div className="gist-feed" ref={rootRef}>
      <div className="gist-ptr" style={{ height: refreshing ? 40 : pull }} aria-hidden={!refreshing && pull === 0}>
        {(refreshing || pull > 0) && <span className={refreshing ? 'is-spin' : ''} style={{ transform: `rotate(${pull * 4}deg)` }}><Icon name="refresh" size={20} /></span>}
      </div>

      <div className="gist-views">
        <div className="gist-seg" role="tablist" aria-label="Feed">
          <button type="button" role="tab" aria-selected={view === 'foryou'} className={view === 'foryou' ? 'is-on' : ''} onClick={() => setView('foryou')}>For you</button>
          <button type="button" role="tab" aria-selected={view === 'following'} className={view === 'following' ? 'is-on' : ''} onClick={() => setView('following')}>Following</button>
        </div>
        <button type="button" className="gist-iconbtn gist-iconbtn--fill" aria-label="Refresh the feed" onClick={() => void refresh()} disabled={refreshing}><Icon name="refresh" size={18} /></button>
      </div>

      <div className="gist-chips gist-chips--scroll" role="group" aria-label="Trending tags and places">
        {chips.map((c) => (
          <button key={c.tag} type="button" className={`gist-chip${tag === c.tag ? ' is-on' : ''}`} onClick={() => setTag(tag === c.tag ? null : c.tag)}>
            {c.label}{c.n ? <small>{c.n}</small> : null}
          </button>
        ))}
      </div>
      {tag && <p className="gist-filter">Showing <b>#{tag}</b> <button type="button" onClick={() => setTag(null)}>Clear</button></p>}

      {canPost ? (
        <button type="button" className="gist-newpost" onClick={() => setComposing(true)}>
          <Face user={{ username: me.username, avatar: me.avatar }} size={40} />
          <span>What&apos;s the gist, {me.username}?</span>
          <span className="gist-newpost__go" aria-hidden><Icon name="plus" size={18} stroke={2.8} /></span>
        </button>
      ) : (
        <p className="gist-note"><Icon name="info" size={16} /> {summary?.why ?? 'You can read, but not post right now.'}</p>
      )}

      {error && <div className="social-error" role="alert">{error}<Button size="sm" variant="ghost" onClick={() => void load()}>Retry</Button></div>}
      {posts === null ? <div className="social-loading"><Spinner size={20} /></div>
        : posts.length === 0 && !error ? (
          <div className="gist-empty">
            <span aria-hidden>🗣️</span>
            <b>{view === 'following' ? 'Nothing from your people yet' : tag ? `No gist for #${tag} yet` : 'No gist yet'}</b>
            <p>{view === 'following' ? 'Follow players, or add friends, and their gists show here.' : 'Be the first. Tell Benin City wetin dey happen.'}</p>
          </div>
        ) : (
          <div className="gist-list">
            {posts.map((p) => <PostCard key={p.id} post={p} nav={nav} onLike={(x) => void actions.like(x)} onTip={actions.setTip} onMenu={actions.setMenu} />)}
            {next && <div ref={sentinel} className="gist-more"><Button size="sm" variant="ghost" loading={loadingMore} onClick={() => void more()}>Load more</Button></div>}
            {!next && posts.length > 5 && <p className="gist-end">You are all caught up.</p>}
          </div>
        )}
      {actions.sheets}
      {composing && summary && <Composer me={me} summary={summary} preset={tag ? `#${tag} ` : undefined} onClose={() => setComposing(false)}
        onPosted={(p) => { setPosts((old) => [p, ...(old ?? [])]); toast('Your gist is live.', 'good'); }} />}
    </div>
  );
}

// ---------------------------------------------------------------------------------------------------------------
// A post with its comments
// ---------------------------------------------------------------------------------------------------------------
function CommentRow({ c, post, isReply, onReply, onDelete, onReport, nav }: {
  c: GistComment; post: GistPost; isReply?: boolean; onReply: (c: GistComment) => void; onDelete: (c: GistComment) => void; onReport: (c: GistComment) => void; nav: FeedNav;
}) {
  const canDelete = c.mine || post.mine;
  return (
    <div className={`gist-comment${isReply ? ' is-reply' : ''}`}>
      <Face user={c.user} size={isReply ? 28 : 34} onClick={() => nav.openProfile(c.user.id)} />
      <div className="gist-comment__main">
        <div className="gist-comment__bubble">
          <button type="button" className="gist-comment__name" onClick={() => nav.openProfile(c.user.id)}>@{c.user.username}</button>
          <p>
            {c.reply_to_name && <><button type="button" className="gist-mention" onClick={() => nav.openProfileByName(c.reply_to_name!)}>@{c.reply_to_name}</button>{' '}</>}
            <GistText text={c.body} onTag={nav.openTag} onMention={nav.openProfileByName} />
          </p>
        </div>
        <div className="gist-comment__meta">
          <time dateTime={c.created_at}>{timeAgo(c.created_at)}</time>
          <button type="button" onClick={() => onReply(c)}>Reply</button>
          {canDelete ? <button type="button" onClick={() => onDelete(c)}>Delete</button> : <button type="button" onClick={() => onReport(c)}>Report</button>}
        </div>
      </div>
    </div>
  );
}

export function PostPage({ state, id, nav, onBack }: { state: GameState; id: number; nav: FeedNav; onBack: () => void }) {
  const [post, setPost] = useState<GistPost | null>(null);
  const [gone, setGone] = useState<string | null>(null);
  const [comments, setComments] = useState<GistComment[]>([]);
  const [hasMore, setHasMore] = useState(false);
  const [loading, setLoading] = useState(true);
  const [draft, setDraft] = useState('');
  const [replyTo, setReplyTo] = useState<GistComment | null>(null);
  const [sending, setSending] = useState(false);
  const [reportC, setReportC] = useState<GistComment | null>(null);
  const inputRef = useRef<HTMLInputElement>(null);
  const setPosts = useCallback((fn: (old: GistPost[]) => GistPost[]) => {
    setPost((old) => { if (!old) return old; const out = fn([old]); if (out.length === 0) { onBack(); return old; } return out[0]; });
  }, [onBack]);
  const actions = usePostActions(state, setPosts, nav);

  useEffect(() => {
    let alive = true;
    setLoading(true);
    Promise.all([gistPostGet(id), gistComments(id)]).then(([p, c]) => {
      if (!alive) return;
      setPost(p); setComments(c.comments); setHasMore(c.has_more);
    }).catch((e) => alive && setGone(errorMessage(e))).finally(() => alive && setLoading(false));
    return () => { alive = false; };
  }, [id]);

  const loadMore = async () => {
    const last = comments[comments.length - 1];
    try {
      const c = await gistComments(id, last?.id ?? 0);
      setComments((old) => [...old, ...c.comments.filter((x) => !old.some((o) => o.id === x.id))]);
      setHasMore(c.has_more);
    } catch (e) { toast(errorMessage(e), 'bad'); }
  };

  const send = async () => {
    const body = draft.trim();
    if (!body || sending) return;
    setSending(true);
    try {
      const r = await gistComment(id, body, replyTo?.id ?? null);
      const c = { ...r.comment, replies: [] };
      setComments((old) => {
        if (!c.parent_id) return [...old, c];
        return old.map((x) => (x.id === c.parent_id ? { ...x, replies: [...(x.replies ?? []), c] } : x));
      });
      setPost((p) => (p ? { ...p, comments: r.comments } : p));
      setDraft(''); setReplyTo(null);
    } catch (e) { toast(errorMessage(e), 'bad'); }
    finally { setSending(false); }
  };

  const remove = async (c: GistComment) => {
    try {
      const r = await gistDeleteComment(c.id);
      setComments((old) => c.parent_id ? old.map((x) => (x.id === c.parent_id ? { ...x, replies: (x.replies ?? []).filter((y) => y.id !== c.id) } : x)) : old.filter((x) => x.id !== c.id));
      setPost((p) => (p ? { ...p, comments: r.comments } : p));
    } catch (e) { toast(errorMessage(e), 'bad'); }
  };

  const startReply = (c: GistComment) => { setReplyTo(c); inputRef.current?.focus({ preventScroll: true }); };

  return (
    <div className="phone-app__body social-app msgs gist-page gist-page--post">
      <PageHead title="Gist" onBack={onBack} />
      {loading && <div className="social-loading"><Spinner size={20} /></div>}
      {gone && <p className="msgs-empty">{gone}</p>}
      {post && (
        <>
          <PostCard post={post} nav={nav} detail onLike={(x) => void actions.like(x)} onTip={actions.setTip} onMenu={actions.setMenu} />
          <h3 className="msgs-sub">{post.comments === 0 ? 'No comments yet' : `${post.comments} ${post.comments === 1 ? 'comment' : 'comments'}`}</h3>
          <div className="gist-comments">
            {comments.map((c) => (
              <div key={c.id} className="gist-thread">
                <CommentRow c={c} post={post} nav={nav} onReply={startReply} onDelete={(x) => void remove(x)} onReport={setReportC} />
                {(c.replies ?? []).map((r) => <CommentRow key={r.id} c={r} post={post} isReply nav={nav} onReply={startReply} onDelete={(x) => void remove(x)} onReport={setReportC} />)}
              </div>
            ))}
            {hasMore && <Button size="sm" variant="ghost" onClick={() => void loadMore()}>More comments</Button>}
          </div>
          <form className="gist-reply kb-composer" onSubmit={(e) => { e.preventDefault(); void send(); }}>
            {replyTo && (
              <div className="gist-reply__to">Replying to <b>@{replyTo.user.username}</b>
                <button type="button" aria-label="Cancel reply" onClick={() => setReplyTo(null)}><Icon name="close" size={14} stroke={2.6} /></button>
              </div>
            )}
            <div className="gist-reply__row">
              <input ref={inputRef} value={draft} maxLength={400} placeholder={replyTo ? `Reply to @${replyTo.user.username}…` : 'Add a comment…'} aria-label="Comment"
                enterKeyHint="send" onChange={(e) => setDraft(e.target.value)} />
              <Button type="submit" variant="green" size="sm" loading={sending} disabled={!draft.trim()}>Send</Button>
            </div>
          </form>
        </>
      )}
      {actions.sheets}
      {reportC && <ReportSheet kind="comment" id={reportC.id} onClose={() => setReportC(null)}
        onDone={(hidden) => { if (hidden) setComments((old) => old.filter((x) => x.id !== reportC.id).map((x) => ({ ...x, replies: (x.replies ?? []).filter((y) => y.id !== reportC.id) }))); }} />}
    </div>
  );
}

// ---------------------------------------------------------------------------------------------------------------
// A player's profile: their gists, Follow, Add friend, Message, Send money
// ---------------------------------------------------------------------------------------------------------------
export function ProfilePage({ state, userId, username, nav, onBack, onMessage, onChanged }: {
  state: GameState; userId: string | null; username?: string; nav: FeedNav; onBack: () => void; onMessage: (userId: string) => void; onChanged: () => void;
}) {
  const [profile, setProfile] = useState<GistProfile | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const [posts, setPosts] = useState<GistPost[] | null>(null);
  const [next, setNext] = useState<number | null>(null);
  const [money, setMoney] = useState(false);
  const [busy, setBusy] = useState(false);
  const actions = usePostActions(state, (fn) => setPosts((old) => (old ? fn(old) : old)), nav);

  useEffect(() => {
    let alive = true;
    (async () => {
      try {
        let id = userId;
        if (!id && username) {
          const found = await socialSearchPlayers(username);
          id = found.find((p) => p.username.toLowerCase() === username.toLowerCase())?.id ?? null;
          if (!id) throw new Error(`There is no player called @${username}.`);
        }
        if (!id) throw new Error('That player is not available.');
        const [pr, list] = await Promise.all([gistProfile(id), gistUserPosts(id)]);
        if (!alive) return;
        setProfile(pr); setPosts(list.posts); setNext(list.next?.id ?? null);
      } catch (e) { if (alive) setErr(errorMessage(e)); }
    })();
    return () => { alive = false; };
  }, [userId, username]);

  const follow = async () => {
    if (!profile) return;
    setBusy(true);
    try {
      const r = await gistFollow(profile.id, !profile.i_follow);
      setProfile({ ...profile, i_follow: r.following, followers: Math.max(0, profile.followers + (r.following ? 1 : -1)) });
    } catch (e) { toast(errorMessage(e), 'bad'); }
    finally { setBusy(false); }
  };
  const more = async () => {
    if (!profile || next == null) return;
    try {
      const list = await gistUserPosts(profile.id, next);
      setPosts((old) => [...(old ?? []), ...list.posts]);
      setNext(list.next?.id ?? null);
    } catch (e) { toast(errorMessage(e), 'bad'); }
  };

  return (
    <div className="phone-app__body social-app msgs gist-page">
      <PageHead title="Profile" onBack={onBack} />
      {err && <p className="msgs-empty">{err}</p>}
      {!profile && !err && <div className="social-loading"><Spinner size={20} /></div>}
      {profile && (
        <>
          <section className="gist-profile">
            <Face user={profile} size={88} />
            <h3>@{profile.username}</h3>
            <small>In Benin City since {new Date(profile.joined).toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' })}</small>
            <dl className="gist-stats">
              <div><dt>Gists</dt><dd>{profile.posts}</dd></div>
              <div><dt>Followers</dt><dd>{profile.followers}</dd></div>
              <div><dt>Following</dt><dd>{profile.following}</dd></div>
            </dl>
            {!profile.me && (
              <div className="gist-profile__actions">
                <Button variant={profile.i_follow ? 'ghost' : 'green'} loading={busy} onClick={() => void follow()}>{profile.i_follow ? 'Following' : 'Follow'}</Button>
                {profile.friend_status === 'friend'
                  ? <Button variant="ghost" icon="chat" onClick={() => onMessage(profile.id)}>Message</Button>
                  : <SocialPlayerButton userId={profile.id} onChanged={() => { onChanged(); void gistProfile(profile.id).then(setProfile).catch(() => undefined); }} />}
                <Button variant="ghost" icon="cash" onClick={() => setMoney(true)}>Send money</Button>
              </div>
            )}
          </section>
          <h3 className="msgs-sub">Gists</h3>
          {posts === null ? <div className="social-loading"><Spinner size={18} /></div>
            : posts.length === 0 ? <p className="msgs-empty">{profile.me ? 'You have not posted yet.' : `@${profile.username} has not posted yet.`}</p>
              : <div className="gist-list">
                {posts.map((p) => <PostCard key={p.id} post={p} nav={nav} onLike={(x) => void actions.like(x)} onTip={actions.setTip} onMenu={actions.setMenu} />)}
                {next != null && <div className="gist-more"><Button size="sm" variant="ghost" onClick={() => void more()}>Load more</Button></div>}
              </div>}
        </>
      )}
      {actions.sheets}
      {money && profile && <SendMoneySheet state={state} friend={profile} onClose={() => setMoney(false)} onSent={() => { setMoney(false); }} />}
    </div>
  );
}
