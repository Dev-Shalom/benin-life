// R11 Gangs admin (docs/CREWS.md): every gang with boss, members, bank, level and open reports. Opening the member view is audited
// (action crew_view). Rename (name and tag, same word and real-name checks as players) and disband (the bank is shared out) are audited.
// Jobs and levels: Content -> Gang jobs / Gang levels. Switches, fees, cooldowns, prizes and blocked names: Settings -> Gangs.
import { useState } from 'react';
import { adminCrewDisband, adminCrewDismissReports, adminCrewGet, adminCrewRename, adminCrewsList, type AdminCrewDetail } from '../api/crews';
import { errorMessage } from '../lib/api';
import { naira } from '../lib/format';
import { CrewTag, toast } from '../ui';
import { Badge, Btn, ConfirmButton, LoadError, PageHead, Skeleton } from './parts';
import { timeShort, useLoad } from './util';

export default function Crews() {
  const [q, setQ] = useState('');
  const { data, error, loading, reload } = useLoad(() => adminCrewsList(q, 200), [q]);
  const [open, setOpen] = useState<AdminCrewDetail | null>(null);
  const [reason, setReason] = useState('');
  const [name, setName] = useState('');
  const [tag, setTag] = useState('');
  if (error && !data) return <LoadError error={error} onRetry={() => void reload()} />;
  if (!data) return <Skeleton rows={6} />;
  const s = data.stats;
  const view = async (id: number) => {
    try { const d = await adminCrewGet(id); setOpen(d); setName(d.crew.name); setTag(String(d.crew.tag)); } catch (e) { toast(errorMessage(e), 'bad'); }
  };
  const run = async (fn: () => Promise<{ message: string }>, close = false) => {
    try { toast((await fn()).message, 'good'); if (close) setOpen(null); else if (open) void view(open.crew.id); } catch (e) { toast(errorMessage(e), 'bad'); }
    void reload();
  };
  return (
    <div className="adm-page" data-testid="admin-crews">
      <PageHead title="Gangs" sub="Player gangs: disband, rename and review reports"
        actions={<Btn small icon="refresh" onClick={() => void reload()} disabled={loading}>Refresh</Btn>} />
      <section className="adm-card">
        <p className="adm-sub">{s.crews} gangs · {s.members} members · {naira(s.bank)} in gang banks · {s.open_reports} open reports · {s.jobs_7d} jobs in the last 7 days</p>
        <label className="adm-field">
          <span className="adm-field__label">Search by name or tag</span>
          <input className="adm-input" value={q} onChange={(e) => setQ(e.target.value)} placeholder="e.g. ring" />
        </label>
      </section>
      <section className="adm-card">
        <h3>All gangs</h3>
        {data.rows.length === 0 ? <p className="adm-sub">No gangs yet.</p> : (
          <div className="adm-scroll">
            <table className="adm-table">
              <thead><tr><th>Gang</th><th>Boss</th><th>Level</th><th>Members</th><th>Bank</th><th>Jobs</th><th>Loot</th><th>Reports</th><th>Since</th><th /></tr></thead>
              <tbody>
                {data.rows.map((r) => (
                  <tr key={r.id}>
                    <td><b><CrewTag tag={r.tag} color={r.color} emblem={r.emblem} />{r.name}</b>{r.recruiting && <> <Badge tone="blue">open</Badge></>}</td>
                    <td>@{r.boss ?? '?'}</td>
                    <td>{r.level}</td>
                    <td>{r.members}</td>
                    <td>{naira(r.bank)}</td>
                    <td>{r.jobs_done} done · {r.jobs_caught} busted</td>
                    <td>{naira(r.loot_total)}</td>
                    <td>{r.reports > 0 ? <Badge tone={r.flagged ? 'red' : 'amber'}>{r.reports}</Badge> : '–'}</td>
                    <td>{timeShort(r.created_at)}</td>
                    <td><Btn small onClick={() => void view(r.id)}>Members</Btn></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>
      {open && (
        <section className="adm-card" data-testid="admin-crew-detail">
          <h3>{String(open.crew.name)} [{String(open.crew.tag)}] · level {open.crew.level} · bank {naira(open.crew.bank)}</h3>
          <p className="adm-sub">Opening this view was logged in the audit trail.</p>
          <div className="adm-scroll">
            <table className="adm-table">
              <thead><tr><th>Member</th><th>Rank</th><th>Joined</th><th>Deposited</th><th>Jobs</th><th>Earned</th><th>Last seen</th></tr></thead>
              <tbody>{open.members.map((m) => <tr key={m.id}><td>@{m.username}</td><td>{m.rank}</td><td>{timeShort(m.joined_at)}</td><td>{naira(m.deposited)}</td><td>{m.jobs}</td><td>{naira(m.earned)}</td><td>{timeShort(m.last_seen)}</td></tr>)}</tbody>
            </table>
          </div>
          {open.reports.length > 0 && (
            <>
              <h4>Reports</h4>
              <ul>{open.reports.map((r) => <li key={r.id}>{r.status === 'open' ? '🔴' : '✅'} @{r.by ?? '?'}: {r.reason} <span className="adm-sub">{timeShort(r.created_at)}</span></li>)}</ul>
              <Btn small onClick={() => void run(() => adminCrewDismissReports(open.crew.id))}>Mark reports reviewed</Btn>
            </>
          )}
          <h4>Recent jobs</h4>
          <ul>{open.runs.map((r) => <li key={r.id}>{r.job ?? '?'} · {r.status} · {r.members} members{r.pot > 0 ? ` · ${naira(r.pot)}` : ''} <span className="adm-sub">{timeShort(r.created_at)}</span></li>)}</ul>
          <label className="adm-field">
            <span className="adm-field__label">Reason (sent to the members, kept in the audit trail)</span>
            <input className="adm-input" value={reason} maxLength={200} onChange={(e) => setReason(e.target.value)} placeholder="e.g. name abuse" />
          </label>
          <div className="adm-row">
            <input className="adm-input" value={name} maxLength={20} onChange={(e) => setName(e.target.value)} aria-label="New name" />
            <input className="adm-input" value={tag} maxLength={4} onChange={(e) => setTag(e.target.value.toUpperCase())} aria-label="New tag" style={{ maxWidth: 90 }} />
            <Btn small onClick={() => void run(() => adminCrewRename(open.crew.id, name, tag === String(open.crew.tag) ? null : tag, reason))}>Rename</Btn>
            <ConfirmButton tone="danger" small confirmText="Tap again: disband" onConfirm={() => run(() => adminCrewDisband(open.crew.id, reason), true)}>Disband</ConfirmButton>
          </div>
          <Btn small onClick={() => setOpen(null)}>Close</Btn>
        </section>
      )}
    </div>
  );
}
