// Admin -> Gist (docs/GIST.md): reported gists, comments, groups and group messages (hide / delete / ban the author), bans, groups
// (rename the starter groups, change a cap, hide), and photo clean-up. Switches and limits are in Settings -> Benin Gist.
import { useState } from 'react';
import { Link } from 'react-router-dom';
import { toast } from '../ui';
import { errorMessage } from '../lib/api';
import { supabase } from '../lib/supabase';
import { gistPhotoUrl } from '../api/gist';
import { adminApi, type GistGroupRow, type GistKind, type GistReportRow } from './api';
import { Badge, Btn, ConfirmButton, LoadError, PageHead, Skeleton } from './parts';
import { timeShort, useLoad } from './util';

type Tab = 'reports' | 'groups' | 'bans' | 'photos';

const KIND_LABEL: Record<GistKind, string> = { post: 'Gist', comment: 'Comment', group: 'Group', message: 'Group message' };

function Stat({ label, value, sub, tone }: { label: string; value: number | string; sub?: string; tone?: 'amber' | 'green' }) {
  return (
    <div className={`adm-stat${tone ? ` adm-stat--${tone}` : ''}`}>
      <small>{label}</small>
      <span className="adm-stat__value">{value}</span>
      {sub && <span className="adm-stat__sub">{sub}</span>}
    </div>
  );
}

function Reports() {
  const [all, setAll] = useState(false);
  const { data, setData, error, loading, reload } = useLoad(() => adminApi.gistReports(all ? 'all' : 'open'), [all]);
  const [busy, setBusy] = useState<string | null>(null);
  const key = (r: GistReportRow) => `${r.kind}:${r.target_id}`;
  const act = async (r: GistReportRow, fn: () => Promise<{ message: string }>, remove = true) => {
    setBusy(key(r));
    try {
      const res = await fn();
      toast(res.message, 'good');
      if (remove && !all && data) setData(data.filter((x) => key(x) !== key(r)));
      else void reload();
    } catch (e) { toast(errorMessage(e), 'bad'); } finally { setBusy(null); }
  };
  return (
    <>
      <div className="adm-toolbar">
        <div className="adm-chips">
          <button type="button" className={`adm-chip${!all ? ' is-on' : ''}`} onClick={() => setAll(false)}>Waiting</button>
          <button type="button" className={`adm-chip${all ? ' is-on' : ''}`} onClick={() => setAll(true)}>All</button>
        </div>
        <Btn icon="refresh" onClick={() => void reload()} disabled={loading}>Refresh</Btn>
      </div>
      {error && <LoadError error={error} onRetry={() => void reload()} />}
      {!data && loading && <Skeleton rows={4} />}
      {data && data.length === 0 && <div className="adm-card"><p className="adm-empty">Nothing to review. 🎉</p></div>}
      <div className="adm-stack">
        {(data ?? []).map((r) => {
          const c = r.content;
          const b = busy === key(r);
          return (
            <article key={key(r)} className={`adm-card adm-report${c?.hidden || r.status === 'done' ? ' is-off' : ''}`}>
              <div className="adm-report__head">
                <Badge tone="blue">{KIND_LABEL[r.kind]}</Badge>
                <b>{c?.author ? `@${c.author}` : '(official / unknown)'}</b>
                <span className="adm-sub">{c?.group ? `in ${c.group} · ` : ''}{timeShort(c?.at)}</span>
                <Badge tone={r.reports >= 3 ? 'red' : 'amber'}>{r.reports} {r.reports === 1 ? 'report' : 'reports'}</Badge>
                {c?.hidden && <Badge>Hidden</Badge>}
                {r.status === 'done' && <Badge tone="green">Handled</Badge>}
              </div>
              <p className="adm-report__body">{c?.text || '(no text)'}</p>
              {c?.photo_path && <img src={gistPhotoUrl(c.photo_path)} alt="Reported gist" style={{ maxWidth: 220, borderRadius: 12, display: 'block', marginBottom: 8 }} />}
              <p className="adm-sub">
                {r.reasons?.length ? `Reasons: ${r.reasons.join(', ')} · ` : ''}Reported by {r.reporters.filter(Boolean).join(', ')}
              </p>
              <div className="adm-btnrow">
                {c?.hidden
                  ? <Btn small disabled={b} onClick={() => void act(r, () => adminApi.gistHide(r.kind, r.target_id, false), false)}>Unhide</Btn>
                  : <Btn small tone="danger" disabled={b} onClick={() => void act(r, () => adminApi.gistHide(r.kind, r.target_id, true))}>Hide</Btn>}
                <ConfirmButton small disabled={b} onConfirm={() => void act(r, () => adminApi.gistDelete(r.kind, r.target_id))}>Delete</ConfirmButton>
                {c?.author_id && r.kind !== 'group' && (
                  <ConfirmButton small disabled={b} confirmText="Ban 24 h and hide all their gists?" onConfirm={() => void act(r, () => adminApi.gistBan(c.author_id!, true, 24, `report: ${r.kind}`, true), false)}>
                    Ban author 24 h
                  </ConfirmButton>
                )}
                {r.status === 'open' && <Btn small tone="quiet" disabled={b} onClick={() => void act(r, () => adminApi.gistDismiss(r.kind, r.target_id))}>Dismiss</Btn>}
              </div>
            </article>
          );
        })}
      </div>
    </>
  );
}

function GroupEditor({ g, onDone }: { g: GistGroupRow; onDone: () => void }) {
  const [name, setName] = useState(g.name);
  const [emoji, setEmoji] = useState(g.emoji);
  const [desc, setDesc] = useState(g.description);
  const [cap, setCap] = useState(g.member_cap ? String(g.member_cap) : '');
  const [busy, setBusy] = useState(false);
  const save = async (patch?: { hidden?: boolean; isPublic?: boolean }) => {
    setBusy(true);
    try {
      const r = await adminApi.gistGroupSet(g.id, { name, emoji, description: desc, cap: cap === '' ? 0 : Number(cap), ...patch });
      toast(r.message, 'good');
      onDone();
    } catch (e) { toast(errorMessage(e), 'bad'); } finally { setBusy(false); }
  };
  return (
    <article className={`adm-card${g.hidden ? ' is-off' : ''}`}>
      <div className="adm-report__head">
        <span style={{ fontSize: 22 }} aria-hidden>{g.emoji}</span>
        <b>{g.name}</b>
        {g.system && <Badge tone="blue">Official</Badge>}
        <Badge tone={g.is_public ? 'green' : 'grey'}>{g.is_public ? 'Public' : 'Private'}</Badge>
        {g.hidden && <Badge tone="red">Hidden</Badge>}
        <span className="adm-sub">{g.members} members · {g.owner ? `owner @${g.owner}` : 'no owner'}{g.last_msg_at ? ` · last message ${timeShort(g.last_msg_at)}` : ''}</span>
      </div>
      <div className="adm-fields" style={{ display: 'grid', gap: 8, marginTop: 10 }}>
        <label className="adm-field"><span className="adm-field__label">Name</span><input className="adm-input" value={name} maxLength={40} onChange={(e) => setName(e.target.value)} /></label>
        <label className="adm-field"><span className="adm-field__label">Icon (emoji)</span><input className="adm-input" value={emoji} maxLength={8} onChange={(e) => setEmoji(e.target.value)} /></label>
        <label className="adm-field"><span className="adm-field__label">Description</span><textarea className="adm-input" rows={2} maxLength={300} value={desc} onChange={(e) => setDesc(e.target.value)} /></label>
        <label className="adm-field"><span className="adm-field__label">Member cap (empty = the default in Settings)</span><input className="adm-input" inputMode="numeric" value={cap} onChange={(e) => setCap(e.target.value.replace(/\D/g, ''))} /></label>
      </div>
      <div className="adm-btnrow">
        <Btn small tone="primary" disabled={busy} onClick={() => void save()}>Save</Btn>
        <Btn small disabled={busy} onClick={() => void save({ hidden: !g.hidden })}>{g.hidden ? 'Unhide' : 'Hide group'}</Btn>
        {!g.system && <ConfirmButton small disabled={busy} onConfirm={() => { setBusy(true); adminApi.gistDelete('group', g.id).then((r) => { toast(r.message, 'good'); onDone(); }).catch((e) => toast(errorMessage(e), 'bad')).finally(() => setBusy(false)); }}>Delete group</ConfirmButton>}
      </div>
    </article>
  );
}

function Groups() {
  const [q, setQ] = useState('');
  const { data, error, loading, reload } = useLoad(() => adminApi.gistGroups(q.trim() || null), []);
  return (
    <>
      <div className="adm-toolbar">
        <input className="adm-input" style={{ maxWidth: 260 }} placeholder="Search groups" value={q} onChange={(e) => setQ(e.target.value)} onKeyDown={(e) => { if (e.key === 'Enter') void reload(); }} />
        <Btn icon="refresh" onClick={() => void reload()} disabled={loading}>Search</Btn>
      </div>
      <p className="adm-sub">The five official starter groups are first. Rename them here. A cap set on a group beats the default in Settings -&gt; Benin Gist.</p>
      {error && <LoadError error={error} onRetry={() => void reload()} />}
      {!data && loading && <Skeleton rows={4} />}
      <div className="adm-stack">{(data ?? []).map((g) => <GroupEditor key={`${g.id}:${g.name}:${g.hidden}`} g={g} onDone={() => void reload()} />)}</div>
    </>
  );
}

function Bans() {
  const { data, error, loading, reload } = useLoad(() => adminApi.gistBans(), []);
  const [busy, setBusy] = useState<string | null>(null);
  const lift = async (id: string) => {
    setBusy(id);
    try { toast((await adminApi.gistBan(id, false)).message, 'good'); await reload(); } catch (e) { toast(errorMessage(e), 'bad'); } finally { setBusy(null); }
  };
  return (
    <>
      <p className="adm-sub">Players banned from Benin Gist can still read. To ban someone, use Ban author on a report, or open them in <Link to="/admin/players">Players</Link>. A chat mute (Players) also stops them posting.</p>
      {error && <LoadError error={error} onRetry={() => void reload()} />}
      {!data && loading && <Skeleton rows={3} />}
      {data && data.length === 0 && <div className="adm-card"><p className="adm-empty">Nobody is banned.</p></div>}
      <div className="adm-stack">
        {(data ?? []).map((b) => (
          <article key={b.user_id} className="adm-card">
            <div className="adm-report__head">
              <b>@{b.username ?? 'unknown'}</b>
              <Badge tone="red">{b.until_at ? `until ${timeShort(b.until_at)}` : 'for good'}</Badge>
              <span className="adm-sub">{b.reason ?? ''}</span>
            </div>
            <div className="adm-btnrow"><Btn small disabled={busy === b.user_id} onClick={() => void lift(b.user_id)}>Lift ban</Btn></div>
          </article>
        ))}
      </div>
    </>
  );
}

function Photos() {
  const { data, error, loading, reload } = useLoad(() => adminApi.gistOrphanPhotos(), []);
  const [busy, setBusy] = useState(false);
  const clean = async () => {
    if (!data?.length) return;
    setBusy(true);
    try {
      const { error: err } = await supabase.storage.from('gist-photos').remove(data.map((x) => x.name));
      if (err) throw new Error(err.message);
      toast(`Removed ${data.length} unused photo${data.length === 1 ? '' : 's'}.`, 'good');
      await reload();
    } catch (e) { toast(errorMessage(e), 'bad'); } finally { setBusy(false); }
  };
  const bytes = (data ?? []).reduce((n, x) => n + (x.bytes ?? 0), 0);
  return (
    <>
      <p className="adm-sub">Photo files that no gist uses any more (deleted or expired gists, failed posts), older than an hour. Removing them frees Storage space.</p>
      {error && <LoadError error={error} onRetry={() => void reload()} />}
      {!data && loading && <Skeleton rows={2} />}
      {data && (
        <div className="adm-card">
          <p>{data.length === 0 ? 'No unused photos.' : `${data.length} unused photo${data.length === 1 ? '' : 's'} · ${(bytes / 1024).toFixed(0)} KB`}</p>
          <div className="adm-btnrow">
            <ConfirmButton disabled={busy || data.length === 0} onConfirm={() => void clean()}>Delete them</ConfirmButton>
            <Btn icon="refresh" onClick={() => void reload()} disabled={loading}>Refresh</Btn>
          </div>
        </div>
      )}
    </>
  );
}

export default function Gist() {
  const [tab, setTab] = useState<Tab>('reports');
  const { data: o, reload } = useLoad(() => adminApi.gistOverview(), []);
  const tabs: { id: Tab; label: string; n?: number }[] = [
    { id: 'reports', label: 'Reports', n: o?.open_reports }, { id: 'groups', label: 'Groups' }, { id: 'bans', label: 'Bans', n: o?.bans }, { id: 'photos', label: 'Photo clean-up' },
  ];
  return (
    <div className="adm-page" data-testid="admin-gist">
      <PageHead title="Benin Gist" sub="Reports, groups and bans. On/off switch, limits and rate limits: Settings -> Benin Gist."
        actions={<Btn icon="refresh" onClick={() => void reload()}>Refresh</Btn>} />
      <div className="adm-stats adm-stats--compact" style={{ marginBottom: 14 }}>
        <Stat label="Open reports" value={o?.open_reports ?? '–'} tone={o && o.open_reports > 0 ? 'amber' : undefined} />
        <Stat label="Gists 24 h" value={o?.posts_24h ?? '–'} sub={o ? `${o.posts} kept` : undefined} />
        <Stat label="Comments 24 h" value={o?.comments_24h ?? '–'} />
        <Stat label="Groups" value={o?.groups ?? '–'} sub={o ? `${o.public_groups} public` : undefined} />
        <Stat label="Messages 24 h" value={o?.messages_24h ?? '–'} />
        <Stat label="Photos" value={o?.photos ?? '–'} sub={o ? `${o.hidden_posts} gists hidden` : undefined} />
      </div>
      <div className="adm-chips adm-chips--scroll" role="tablist">
        {tabs.map((t) => (
          <button key={t.id} type="button" role="tab" aria-selected={tab === t.id} className={`adm-chip${tab === t.id ? ' is-on' : ''}`} onClick={() => setTab(t.id)}>
            {t.label}{t.n ? <span className="adm-chip__n">{t.n}</span> : null}
          </button>
        ))}
      </div>
      {tab === 'reports' && <Reports />}
      {tab === 'groups' && <Groups />}
      {tab === 'bans' && <Bans />}
      {tab === 'photos' && <Photos />}
    </div>
  );
}
