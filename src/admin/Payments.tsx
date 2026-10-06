// PAY: Paystack purchases (newest first) with revenue today (WAT) / 7 days / all time, filter by status,
// search by username or reference. Read-only: money is credited only by the verify / webhook Edge Functions.
import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { naira } from '../lib/format';
import { Icon } from '../ui';
import { adminApi, type PaymentRow } from './api';
import { Badge, Btn, LoadError, PageHead, Skeleton } from './parts';
import { timeShort, useLoad } from './util';

const kobo = (k: number) => '₦' + Math.round(k / 100).toLocaleString('en-NG');
const STATUSES = ['all', 'success', 'pending', 'failed'] as const;
const TONE: Record<PaymentRow['status'], 'green' | 'amber' | 'red'> = { success: 'green', pending: 'amber', failed: 'red' };

export default function Payments() {
  const [status, setStatus] = useState<(typeof STATUSES)[number]>('all');
  const [q, setQ] = useState('');
  const [search, setSearch] = useState('');
  useEffect(() => {
    const t = window.setTimeout(() => setSearch(q.trim()), 300);
    return () => window.clearTimeout(t);
  }, [q]);
  const { data, error, loading, reload } = useLoad(() => adminApi.payments(status === 'all' ? null : status, search || null), [status, search]);
  const t = data?.totals;

  return (
    <div className="adm-page">
      <PageHead title="Payments" sub="Paystack top-ups. Naira is credited only after the server verifies the payment with Paystack."
        actions={<Btn icon="refresh" onClick={reload} disabled={loading}>Refresh</Btn>} />
      {data && !data.enabled && (
        <div className="adm-card adm-pay-off">
          <Icon name="lock" size={16} /> Top-ups are <b>off</b> for players. Turn on <Link to="/admin/settings">Settings → payments.enabled</Link> once the Paystack keys are set (docs/PAYMENTS.md).
        </div>
      )}
      {t && (
        <div className="adm-stats">
          <div className="adm-stat adm-stat--green"><span className="adm-kicker">Revenue today</span><b className="adm-stat__value">{kobo(t.today_kobo)}</b><span className="adm-stat__sub">{t.today_count} paid · since midnight WAT</span></div>
          <div className="adm-stat"><span className="adm-kicker">Last 7 days</span><b className="adm-stat__value">{kobo(t.d7_kobo)}</b><span className="adm-stat__sub">{t.d7_count} paid</span></div>
          <div className="adm-stat"><span className="adm-kicker">All time</span><b className="adm-stat__value">{kobo(t.all_kobo)}</b><span className="adm-stat__sub">{t.all_count} paid · {t.payers} payers</span></div>
          <div className="adm-stat adm-stat--amber"><span className="adm-kicker">Pending / failed</span><b className="adm-stat__value">{t.pending} / {t.failed}</b><span className="adm-stat__sub">{naira(t.naira_sold)} game naira sold</span></div>
        </div>
      )}
      <div className="adm-toolbar">
        <div className="adm-chips">
          {STATUSES.map((s) => (
            <button key={s} type="button" className={`adm-chip${status === s ? ' is-on' : ''}`} onClick={() => setStatus(s)}>{s[0].toUpperCase() + s.slice(1)}</button>
          ))}
        </div>
        <label className="adm-search">
          <span aria-hidden>🔎</span>
          <input type="search" placeholder="Search name or reference…" value={q} onChange={(e) => setQ(e.target.value)} />
        </label>
      </div>
      {error && <LoadError error={error} onRetry={reload} />}
      {!data && loading && <Skeleton rows={5} />}
      {data && (
        <div className="adm-card adm-pay-list">
          {data.rows.length === 0 && <p className="adm-empty">No payments yet.</p>}
          {data.rows.map((r) => (
            <div key={r.id} className="adm-pay-row">
              <div className="adm-pay-row__main">
                <b>{r.username ? `@${r.username}` : 'Deleted account'}</b>
                <span className="adm-sub">{r.pack_label ?? r.pack_id ?? '–'} · {naira(r.game_naira)} · {timeShort(r.paid_at ?? r.created_at)}</span>
                <span className="adm-sub adm-mono">{r.reference}{r.note ? ` · ${r.note}` : ''}</span>
              </div>
              <div className="adm-pay-row__side">
                <b>{kobo(r.amount_kobo)}</b>
                <Badge tone={TONE[r.status]}>{r.status}</Badge>
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
