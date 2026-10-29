// Industry offices admin (docs/OFFICES.md): appoint anybody by username, applicants (accept / reject / remove), holders (remove, freeze), every office's
// salary and limits, every lever's band, step and cooldown, and the audit of changes. Built from cards that wrap, so it works at phone width.
// Every action is audited server side and alerts the player.
import { useState } from 'react';
import {
  adminIndAppoint, adminIndApplication, adminIndFreeze, adminIndOverview, adminIndRemoveHolder, fmtLever, type AdminIndOffice, type IndLever,
} from '../api/offices';
import { errorMessage } from '../lib/api';
import { naira } from '../lib/format';
import { toast } from '../ui';
import { adminApi } from './api';
import { Badge, Btn, ConfirmButton, LoadError, PageHead, Skeleton } from './parts';
import { useLoad } from './util';
import './Offices.css';

const when = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleString('en-GB', { weekday: 'short', day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' }) : '—');
type Draft = Record<string, string>;

function LeverRow({ l, office, run }: { l: IndLever; office: AdminIndOffice; run: (fn: () => Promise<{ message: string }>) => Promise<void> }) {
  const [d, setD] = useState<Draft>({ band_min: String(l.band_min), band_max: String(l.band_max), step: String(l.step), cooldown_hours: String(l.cooldown_hours) });
  const dirty = d.band_min !== String(l.band_min) || d.band_max !== String(l.band_max) || d.step !== String(l.step) || d.cooldown_hours !== String(l.cooldown_hours);
  const set = (k: string, v: string) => setD({ ...d, [k]: v });
  return (
    <div className={`ao-lever${l.changed ? ' is-changed' : ''}`} data-testid={`ao-lever-${l.id}`}>
      <div className="ao-lever__top">
        <b>{l.label}</b>
        <span className="ao-lever__val">{fmtLever(l.unit, l.current)}{l.changed && <small> (normal {fmtLever(l.unit, l.baseline)}, set by @{l.changed_by})</small>}</span>
      </div>
      <div className="ao-fields">
        {(['band_min', 'band_max', 'step', 'cooldown_hours'] as const).map((k) => (
          <label key={k} className="ao-field"><span>{k === 'band_min' ? 'Band min' : k === 'band_max' ? 'Band max' : k === 'step' ? 'Step' : 'Cooldown (h)'}</span>
            <input className="adm-input" inputMode="decimal" value={d[k]} onChange={(e) => set(k, e.target.value)} aria-label={`${l.label} ${k}`} /></label>
        ))}
      </div>
      <div className="ao-actions">
        {dirty && <Btn small tone="primary" onClick={() => void run(async () => {
          const r = await adminApi.rowUpsert('ind_levers', { id: l.id, band_min: Number(d.band_min), band_max: Number(d.band_max), step: Number(d.step), cooldown_hours: Number(d.cooldown_hours) });
          return { message: r.message ?? 'Saved.' };
        })}>Save limits</Btn>}
        <Btn small onClick={() => void run(() => adminIndFreeze(office.id, l.id, !l.frozen))}>{l.frozen ? 'Unfreeze' : 'Freeze'}</Btn>
        {l.frozen && <Badge tone="blue">frozen</Badge>}
        {l.active === false && <Badge tone="grey">off</Badge>}
      </div>
    </div>
  );
}

function OfficeCard({ o, reason, run }: { o: AdminIndOffice; reason: string; run: (fn: () => Promise<{ message: string }>) => Promise<void> }) {
  const [open, setOpen] = useState(false);
  const [d, setD] = useState<Draft>({ salary_per_day: String(o.salary_per_day), term_days: String(o.term_days), max_changes_per_day: String(o.max_changes_per_day), max_total_drift_pct: String(o.max_total_drift_pct) });
  const dirty = d.salary_per_day !== String(o.salary_per_day) || d.term_days !== String(o.term_days) || d.max_changes_per_day !== String(o.max_changes_per_day) || d.max_total_drift_pct !== String(o.max_total_drift_pct);
  const h = o.holder;
  const set = (k: string, v: string) => setD({ ...d, [k]: v });
  return (
    <article className="adm-card ao-office" data-testid={`ao-office-${o.id}`}>
      <div className="ao-head">
        <span className="ao-icon" aria-hidden>{o.icon}</span>
        <div className="ao-head__who">
          <b>{o.name}</b>
          <span className="adm-sub">{h ? <>@{h.username} · term ends {when(h.term_end)} · seen {when(h.last_seen)}</> : 'Vacant'} · {naira(o.salary_per_day)} a day</span>
          <div className="ao-badges">
            {!o.active && <Badge tone="grey">closed</Badge>}
            {o.frozen && <Badge tone="blue">all levers frozen</Badge>}
            {h && <Badge tone={h.low_approval ? 'red' : 'green'}>{h.approval.pct == null ? 'no ratings' : `${h.approval.pct}% approve (${h.approval.votes})`}</Badge>}
            {h?.low_approval && <Badge tone="red">low approval</Badge>}
            {h && <Badge tone="grey">{h.changes_today}/{o.max_changes_per_day} changes today</Badge>}
          </div>
        </div>
      </div>
      <div className="ao-actions">
        {h && <ConfirmButton tone="danger" small confirmText="Tap again: remove holder" onConfirm={() => { if (!reason.trim()) { toast('Write a reason first.', 'bad'); return; } return run(() => adminIndRemoveHolder(h.id, reason.trim())); }}>Remove holder</ConfirmButton>}
        <Btn small onClick={() => void run(() => adminIndFreeze(o.id, null, !o.frozen))}>{o.frozen ? 'Unfreeze all levers' : 'Freeze all levers'}</Btn>
        <Btn small onClick={() => setOpen(!open)}>{open ? 'Hide limits' : `Limits and levers (${o.levers.length})`}</Btn>
      </div>
      {open && (
        <div className="ao-body">
          <div className="ao-fields">
            {([['salary_per_day', 'Salary a day'], ['term_days', 'Term (days)'], ['max_changes_per_day', 'Changes a day'], ['max_total_drift_pct', 'Total drift %']] as const).map(([k, label]) => (
              <label key={k} className="ao-field"><span>{label}</span><input className="adm-input" inputMode="decimal" value={d[k]} onChange={(e) => set(k, e.target.value)} aria-label={`${o.name} ${label}`} /></label>
            ))}
          </div>
          <div className="ao-actions">
            {dirty && <Btn small tone="primary" onClick={() => void run(async () => {
              const r = await adminApi.rowUpsert('ind_offices', { id: o.id, salary_per_day: Number(d.salary_per_day), term_days: Number(d.term_days), max_changes_per_day: Number(d.max_changes_per_day), max_total_drift_pct: Number(d.max_total_drift_pct) });
              return { message: r.message ?? 'Saved.' };
            })}>Save office</Btn>}
            <Btn small onClick={() => void run(async () => { const r = await adminApi.rowUpsert('ind_offices', { id: o.id, active: !o.active }); return { message: r.message ?? 'Saved.' }; })}>{o.active ? 'Close office' : 'Open office'}</Btn>
          </div>
          {o.levers.map((l) => <LeverRow key={l.id} l={l} office={o} run={run} />)}
        </div>
      )}
    </article>
  );
}

export default function Offices() {
  const { data, error, loading, reload } = useLoad(() => adminIndOverview(), []);
  const [office, setOffice] = useState('bank_governor');
  const [who, setWho] = useState('');
  const [reason, setReason] = useState('');
  if (error && !data) return <LoadError error={error} onRetry={() => void reload()} />;
  if (!data) return <Skeleton rows={6} />;
  const run = async (fn: () => Promise<{ message: string }>) => {
    try { toast((await fn()).message, 'good'); setReason(''); } catch (e) { toast(errorMessage(e), 'bad'); }
    void reload();
  };
  return (
    <div className="adm-page" data-testid="admin-offices">
      <PageHead title="Offices" sub="Industry offices: appoint, remove, freeze, and tune what each office can change"
        actions={<Btn small icon="refresh" onClick={() => void reload()} disabled={loading}>Refresh</Btn>} />
      {!data.enabled && <section className="adm-card"><p className="adm-sub">Industry offices are switched off in Settings, Industry offices.</p></section>}

      <section className="adm-card ao-appoint">
        <h3>Appoint anybody</h3>
        <p className="adm-sub">Pick an office and type a username. No application needed. One office per player; the seat must be empty.</p>
        <div className="ao-fields ao-fields--appoint">
          <label className="ao-field"><span>Office</span>
            <select className="adm-input" value={office} onChange={(e) => setOffice(e.target.value)} aria-label="Office">
              {data.offices.map((o) => <option key={o.id} value={o.id}>{o.name}{o.holder ? ' (filled)' : ''}{o.active ? '' : ' (closed)'}</option>)}
            </select></label>
          <label className="ao-field"><span>Username</span><input className="adm-input" value={who} onChange={(e) => setWho(e.target.value)} placeholder="username" aria-label="Username" autoCapitalize="off" /></label>
        </div>
        <ConfirmButton tone="primary" small confirmText="Tap again: appoint" disabled={!who.trim()} onConfirm={() => run(() => adminIndAppoint(office, who.trim(), reason.trim()))}>Appoint</ConfirmButton>
      </section>

      <section className="adm-card">
        <h3>Reason or note</h3>
        <p className="adm-sub">Used by Remove holder (required) and by Reject / Remove applicant (optional). It is kept in the audit log and shown to the player.</p>
        <input className="adm-input" value={reason} maxLength={200} onChange={(e) => setReason(e.target.value)} placeholder="Reason or note" aria-label="Reason or note" />
      </section>

      <section className="adm-card" data-testid="ao-applicants">
        <h3>Applicants ({data.applicants.length})</h3>
        {data.applicants.length === 0 ? <p className="adm-sub">Nobody is waiting.</p> : data.applicants.map((a) => (
          <div key={a.id} className="ao-applicant">
            <div className="ao-applicant__who">
              <b>@{a.username}</b> <span className="adm-sub">wants {a.office}</span>
              <p className="ao-pitch">“{a.pitch}”</p>
              <span className="adm-sub">Account {a.account_days} days · career level {a.level ?? 0} · seen {when(a.last_seen)}{a.holds_office ? ' · already holds an office' : ''}</span>
            </div>
            <div className="ao-actions">
              <ConfirmButton tone="primary" small confirmText="Tap again: accept" onConfirm={() => run(() => adminIndApplication(a.id, 'accept', reason.trim()))}>Accept</ConfirmButton>
              <ConfirmButton tone="ghost" small confirmText="Tap again: reject" onConfirm={() => run(() => adminIndApplication(a.id, 'reject', reason.trim()))}>Reject</ConfirmButton>
              <ConfirmButton tone="danger" small confirmText="Tap again: remove" onConfirm={() => run(() => adminIndApplication(a.id, 'remove', reason.trim()))}>Remove</ConfirmButton>
            </div>
          </div>
        ))}
      </section>

      <h3 className="ao-h">Offices and levers</h3>
      {data.offices.map((o) => <OfficeCard key={o.id} o={o} reason={reason} run={run} />)}

      <section className="adm-card" data-testid="ao-audit">
        <h3>Audit of changes</h3>
        {data.audit.length === 0 ? <p className="adm-sub">No lever has been changed yet.</p> : (
          <ul className="ao-list">
            {data.audit.map((c) => (
              <li key={c.id}><b>{c.lever}</b> {fmtLever(c.unit, c.old)} → <b>{fmtLever(c.unit, c.new)}</b>
                <span className="adm-sub"> {c.kind === 'restore' ? 'restored to normal' : `by @${c.by ?? '?'}`} · {c.office} · {when(c.at)}{c.announced ? ' · announced' : ''}</span></li>
            ))}
          </ul>
        )}
      </section>

      <section className="adm-card">
        <h3>Past holders</h3>
        {data.history.length === 0 ? <p className="adm-sub">None yet.</p> : (
          <ul className="ao-list">
            {data.history.map((x) => <li key={x.id}><b>@{x.username ?? '?'}</b> · {x.office} <Badge tone={x.status === 'removed' ? 'red' : 'grey'}>{x.status}</Badge>
              <span className="adm-sub"> {when(x.term_start)} to {when(x.ended_at)} · paid {naira(x.salary_paid)}{x.ended_reason ? ` · ${x.ended_reason}` : ''}</span></li>)}
          </ul>
        )}
      </section>
    </div>
  );
}
