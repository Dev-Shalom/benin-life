// S1-D: player feedback (suggestions, bugs, reviews). Newest first, filter by type/status, average rating,
// set a status and reply (the player sees the reply in their Feedback app and gets an in-game alert).
import { useState } from 'react';
import { rpc, errorMessage } from '../lib/api';
import { toast } from '../ui';
import { Badge, Btn, LoadError, PageHead, Skeleton } from './parts';
import { timeShort, useLoad } from './util';

type Kind = 'suggestion' | 'bug' | 'review';
type Status = 'new' | 'planned' | 'done' | 'ignored';
interface Row {
  id: number; user_id: string | null; username: string; kind: Kind; rating: number | null; body: string; status: Status;
  reply: string | null; replied_at: string | null; app_version: string | null; device: string | null; viewport: string | null;
  location_id: string | null; location_name: string | null; created_at: string;
}
interface Data {
  rows: Row[];
  stats: { total: number; new: number; reviews: number; avg_rating: number | null; by_kind: Record<string, number>; by_status: Record<string, number> };
}

const KINDS: { id: Kind | 'all'; label: string }[] = [
  { id: 'all', label: 'All' }, { id: 'suggestion', label: '💡 Suggestions' }, { id: 'bug', label: '🐞 Bugs' }, { id: 'review', label: '⭐ Reviews' },
];
const STATUSES: { id: Status | 'all'; label: string }[] = [
  { id: 'all', label: 'Any status' }, { id: 'new', label: 'New' }, { id: 'planned', label: 'Planned' }, { id: 'done', label: 'Done' }, { id: 'ignored', label: 'Ignored' },
];
const STATUS_TONE: Record<Status, 'blue' | 'violet' | 'green' | 'grey'> = { new: 'blue', planned: 'violet', done: 'green', ignored: 'grey' };

export default function Feedback() {
  const [kind, setKind] = useState<Kind | 'all'>('all');
  const [status, setStatus] = useState<Status | 'all'>('all');
  const { data, error, loading, reload } = useLoad(() => rpc<Data>('admin_feedback_list', { p_kind: kind, p_status: status, p_limit: 200 }), [kind, status]);
  const [open, setOpen] = useState<number | null>(null);
  const s = data?.stats;
  return (
    <div className="adm-page">
      <PageHead title="Feedback" sub="Suggestions, bug reports and reviews from players. Reply and they see it in their Feedback app."
        actions={<Btn small icon="refresh" onClick={reload} disabled={loading}>Refresh</Btn>} />
      {s && (
        <div className="adm-fb-stats">
          <div className="adm-card"><span className="adm-kicker">Average rating</span><b>{s.avg_rating != null ? `${Number(s.avg_rating).toFixed(1)} ★` : '—'}</b><small>{s.reviews} reviews</small></div>
          <div className="adm-card"><span className="adm-kicker">New</span><b>{s.new}</b><small>waiting for you</small></div>
          <div className="adm-card"><span className="adm-kicker">Total</span><b>{s.total}</b><small>{s.by_kind.suggestion ?? 0} ideas · {s.by_kind.bug ?? 0} bugs</small></div>
        </div>
      )}
      <div className="adm-chips adm-fb-filters">
        {KINDS.map((k) => <button key={k.id} type="button" className={`adm-chip${kind === k.id ? ' is-on' : ''}`} onClick={() => setKind(k.id)}>{k.label}</button>)}
      </div>
      <div className="adm-chips adm-fb-filters">
        {STATUSES.map((k) => <button key={k.id} type="button" className={`adm-chip${status === k.id ? ' is-on' : ''}`} onClick={() => setStatus(k.id)}>{k.label}</button>)}
      </div>
      {error && <LoadError error={error} onRetry={reload} />}
      {!data && loading && <Skeleton rows={4} />}
      {data && data.rows.length === 0 && <p className="adm-empty">No feedback here yet.</p>}
      <div className="adm-fb-list">
        {data?.rows.map((r) => <Item key={r.id} r={r} open={open === r.id} onToggle={() => setOpen(open === r.id ? null : r.id)} onSaved={reload} />)}
      </div>
    </div>
  );
}

function Item({ r, open, onToggle, onSaved }: { r: Row; open: boolean; onToggle: () => void; onSaved: () => void }) {
  const [reply, setReply] = useState(r.reply ?? '');
  const [busy, setBusy] = useState(false);
  const save = async (status: Status | null, withReply: boolean) => {
    setBusy(true);
    try {
      const res = await rpc<{ message: string }>('admin_feedback_update', { p_id: r.id, p_status: status, p_reply: withReply ? reply.trim() : null });
      toast(res.message, 'good');
      onSaved();
    } catch (e) { toast(errorMessage(e), 'bad'); } finally { setBusy(false); }
  };
  const k = KINDS.find((x) => x.id === r.kind);
  return (
    <article className={`adm-card adm-fb${open ? ' is-open' : ''}`}>
      <button type="button" className="adm-fb__head" onClick={onToggle} aria-expanded={open}>
        <span className="adm-fb__who"><b>@{r.username}</b> <small>{k?.label} · {timeShort(r.created_at)}</small></span>
        <span className="adm-fb__badges">
          {r.rating ? <span className="adm-fb__stars" aria-label={`${r.rating} stars`}>{'★'.repeat(r.rating)}<span>{'★'.repeat(5 - r.rating)}</span></span> : null}
          <Badge tone={STATUS_TONE[r.status]}>{r.status}</Badge>
          {r.reply && <Badge tone="amber">Replied</Badge>}
        </span>
        <span className="adm-fb__body">{r.body}</span>
      </button>
      {open && (
        <div className="adm-fb__detail">
          <p className="adm-sub">{[r.location_name ?? r.location_id, r.viewport, r.app_version && `build ${r.app_version}`].filter(Boolean).join(' · ')}</p>
          {r.device && <p className="adm-sub adm-cerr__ua">{r.device}</p>}
          <div className="adm-chips">
            {(['new', 'planned', 'done', 'ignored'] as Status[]).map((st) => (
              <button key={st} type="button" disabled={busy} className={`adm-chip${r.status === st ? ' is-on' : ''}`} onClick={() => void save(st, false)}>
                {st[0].toUpperCase() + st.slice(1)}
              </button>
            ))}
          </div>
          <label className="adm-field"><span className="adm-field__label">Reply to @{r.username} (they get an alert)</span>
            <textarea className="adm-input adm-fb__reply" rows={3} maxLength={1000} value={reply} onChange={(e) => setReply(e.target.value)} placeholder="Thank you! We don add am to the plan." />
          </label>
          <div className="adm-btnrow">
            <Btn tone="primary" disabled={busy || !reply.trim() || reply.trim() === (r.reply ?? '')} onClick={() => void save(null, true)}>Send reply</Btn>
            {r.replied_at && <small className="adm-sub">Last reply {timeShort(r.replied_at)}</small>}
          </div>
        </div>
      )}
    </article>
  );
}
