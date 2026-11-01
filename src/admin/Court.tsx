// Admin -> Court (docs/COURT.md): cases (override a ruling, dismiss), judges (appoint / remove), lawyers (ban), and every court.* setting.
// Every action is audited server side. Cards that wrap, so it works at phone width.
import { useMemo, useState } from 'react';
import {
  adminCourtAppointJudge, adminCourtBanLawyer, adminCourtDismiss, adminCourtOverride, adminCourtOverview, adminCourtRemoveJudge, KIND_LABEL,
  type AdminCourtCase,
} from '../api/court';
import { errorMessage } from '../lib/api';
import { naira } from '../lib/format';
import { toast } from '../ui';
import { adminApi, type ConfigRow } from './api';
import { Badge, Btn, ConfirmButton, LoadError, NumberControl, PageHead, Skeleton, Toggle } from './parts';
import { useLoad } from './util';
import './Offices.css';

const when = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleString('en-GB', { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' }) : '—');

function Setting({ row, onSaved }: { row: ConfigRow; onSaved: () => void }) {
  const [v, setV] = useState<unknown>(row.value);
  const dirty = JSON.stringify(v) !== JSON.stringify(row.value);
  const save = async () => { try { await adminApi.configSet(row.key, v); toast('Saved.', 'good'); onSaved(); } catch (e) { toast(errorMessage(e), 'bad'); } };
  return (
    <div className="adm-card ao-lever" data-testid={`court-set-${row.key}`}>
      <div className="ao-lever__top"><b>{row.label}</b><span className="adm-sub">{row.key}</span></div>
      <span className="adm-sub">{row.description}</span>
      <div className="ao-actions">
        {row.kind === 'bool' ? <Toggle checked={Boolean(v)} onChange={setV} label={row.label} />
          : row.kind === 'text' ? <input className="adm-input" value={String(v ?? '')} onChange={(e) => setV(e.target.value)} aria-label={row.label} />
            : <NumberControl kind={row.kind} value={typeof v === 'number' ? v : ''} min={row.min} max={row.max} onChange={(n) => setV(n === '' ? 0 : n)} />}
        {dirty && <Btn small tone="primary" onClick={() => void save()}>Save</Btn>}
      </div>
    </div>
  );
}

function CaseRow({ c, reason, run }: { c: AdminCourtCase; reason: string; run: (fn: () => Promise<{ message: string }>) => Promise<void> }) {
  return (
    <article className="adm-card ao-lever" data-testid={`court-admin-case-${c.id}`}>
      <div className="ao-lever__top"><b>{c.case_no} · {c.title}</b>
        <span>{c.status === 'ruled' ? <Badge tone={c.verdict === 'guilty' ? 'red' : 'green'}>{c.verdict === 'guilty' ? 'Guilty' : 'Not guilty'}{c.verdict_by === 'auto' ? ' (auto)' : c.verdict_by === 'admin' ? ' (admin)' : ''}</Badge>
          : c.status === 'dismissed' ? <Badge>Dismissed</Badge> : c.live ? <Badge tone="red">LIVE</Badge> : <Badge tone="amber">Scheduled</Badge>}</span></div>
      <span className="adm-sub">{KIND_LABEL[c.kind]} · {naira(c.claim)} · @{c.plaintiff.username} vs @{c.defendant.username} · judge {c.judge ? `@${c.judge.username}` : 'none'} · hearing {when(c.hearing_at)}</span>
      {c.status === 'ruled' && <span className="adm-sub">Paid {naira(c.restitution_paid)} · debt {naira(c.restitution_debt)} · fine {naira(c.fine)}{c.jail_seconds ? ` · jail ${c.jail_seconds}s` : ''}{c.overridden ? ' · overruled' : ''}</span>}
      {c.status !== 'dismissed' && (
        <div className="ao-actions">
          {c.verdict !== 'guilty' && <ConfirmButton small tone="primary" disabled={!reason.trim()} onConfirm={() => run(() => adminCourtOverride(c.id, 'guilty', reason))}>Rule guilty</ConfirmButton>}
          {c.verdict !== 'not_guilty' && <ConfirmButton small tone="primary" disabled={!reason.trim()} onConfirm={() => run(() => adminCourtOverride(c.id, 'not_guilty', reason))}>Rule not guilty</ConfirmButton>}
          {c.status === 'scheduled' && <ConfirmButton small disabled={!reason.trim()} onConfirm={() => run(() => adminCourtDismiss(c.id, reason))}>Dismiss + refund</ConfirmButton>}
        </div>
      )}
    </article>
  );
}

export default function Court() {
  const [filter, setFilter] = useState<string>('');
  const { data, error, loading, reload } = useLoad(() => adminCourtOverview(filter || null), [filter]);
  const cfg = useLoad(() => adminApi.configList(), []);
  const [reason, setReason] = useState('');
  const [judgeName, setJudgeName] = useState('');
  const rows = useMemo(() => (cfg.data ?? []).filter((r) => r.category === 'court'), [cfg.data]);
  const run = async (fn: () => Promise<{ message: string }>) => {
    try { const r = await fn(); toast(r.message, 'good'); await reload(); } catch (e) { toast(errorMessage(e), 'bad'); }
  };
  return (
    <div className="adm-page" data-testid="admin-court">
      <PageHead title="Court" sub="High Court, Benin: cases, judges, lawyers and settings. Every action here is audited." />
      {error && <LoadError error={error} onRetry={() => void reload()} />}
      {loading && !data && <Skeleton rows={4} />}
      {data && (
        <>
          <div className="adm-card"><div className="ao-actions">
            <Badge tone="amber">{data.stats.open} open</Badge><Badge tone="green">{data.stats.ruled} ruled</Badge><Badge>{data.stats.dismissed} dismissed</Badge>
            <Badge tone="blue">{data.stats.auto} automatic</Badge><Badge tone="violet">{data.stats.overridden} overruled</Badge><Badge>{data.stats.lawyers} lawyers</Badge>
            <Badge tone="red">debt {naira(data.stats.debt_owed)}</Badge><Badge>fees lost {naira(data.stats.fees_burned)}</Badge>
          </div></div>

          <h3>Judges</h3>
          <div className="adm-card">
            <div className="ao-actions">
              <input className="adm-input" placeholder="Appoint by username" value={judgeName} onChange={(e) => setJudgeName(e.target.value)} aria-label="Judge username" />
              <Btn tone="primary" disabled={!judgeName.trim()} onClick={() => void run(() => adminCourtAppointJudge(judgeName.trim(), reason))}>Appoint judge</Btn>
            </div>
            <span className="adm-sub">Takes the first free seat. Salary, term and badge ("Hon. Justice") are set in Admin, Offices.</span>
          </div>
          {data.judges.map((j) => (
            <article key={j.office_id} className="adm-card ao-lever">
              <div className="ao-lever__top"><b>{j.name}</b><span className="adm-sub">{naira(j.salary_per_day)} a day</span></div>
              <span className="adm-sub">{j.holder ? `@${j.holder.username} · term ends ${when(j.holder.term_end)} · seen ${when(j.holder.last_seen)} · ${j.holder.open_cases} open` : 'Vacant'}</span>
              {j.holder && <div className="ao-actions"><ConfirmButton small disabled={!reason.trim()} onConfirm={() => run(() => adminCourtRemoveJudge(j.holder!.id, reason))}>Remove judge</ConfirmButton></div>}
            </article>
          ))}

          <h3>Cases</h3>
          <div className="adm-card">
            <input className="adm-input" placeholder="Reason for the next action (needed for override, dismiss, remove, ban)" value={reason} onChange={(e) => setReason(e.target.value)} aria-label="Reason" />
            <div className="ao-actions">
              {['', 'scheduled', 'ruled', 'dismissed'].map((f) => <Btn key={f || 'all'} small tone={filter === f ? 'primary' : 'ghost'} onClick={() => setFilter(f)}>{f || 'All'}</Btn>)}
            </div>
          </div>
          {data.cases.map((c) => <CaseRow key={c.id} c={c} reason={reason} run={run} />)}
          {!data.cases.length && <p className="adm-sub">No cases.</p>}

          <h3>Lawyers</h3>
          {data.lawyers.map((l) => (
            <article key={l.user_id} className="adm-card ao-lever">
              <div className="ao-lever__top"><b>@{l.username} · {l.rank}</b><span>{l.banned ? <Badge tone="red">banned</Badge> : l.retired ? <Badge>retired</Badge> : l.available ? <Badge tone="green">available</Badge> : <Badge>paused</Badge>}</span></div>
              <span className="adm-sub">{l.wins} won · {l.losses} lost · fee {naira(l.fee)}{l.ban_reason ? ` · ${l.ban_reason}` : ''}</span>
              <div className="ao-actions">
                {l.banned ? <Btn small onClick={() => void run(() => adminCourtBanLawyer(l.user_id, false))}>Reinstate</Btn>
                  : <ConfirmButton small disabled={!reason.trim()} onConfirm={() => run(() => adminCourtBanLawyer(l.user_id, true, reason))}>Ban lawyer</ConfirmButton>}
              </div>
            </article>
          ))}
        </>
      )}
      <h3>Settings</h3>
      {rows.map((r) => <Setting key={r.key + JSON.stringify(r.value)} row={r} onSaved={() => void cfg.reload()} />)}
    </div>
  );
}
