// Companies admin view (docs/COMPANIES.md): every company, owner, till, sales, stars; remove one (audited, the till is paid out).
// Industries, areas, formats and marketing are edited in Content; every number in Settings -> Company.
import { useState } from 'react';
import { rpc, errorMessage } from '../lib/api';
import { naira } from '../lib/format';
import { toast } from '../ui';
import { Badge, Btn, ConfirmButton, LoadError, PageHead, Skeleton } from './parts';
import { timeShort, useLoad } from './util';

interface Row {
  id: number; name: string; logo: string; industry: string; owner: string; owner_id: string; hq: string; locations: number; stars: number; staff: number; manager: boolean;
  till: number; listed: boolean; source: string; sales_7d: number; lifetime_sales: number; lifetime_net: number; created_at: string;
}
interface Overview {
  stats: { companies: number; listed: number; till_total: number; sales_7d: number; income_7d: number; real_live: number; real_review: number };
  industries: { id: string; name: string; icon: string; companies: number }[];
  rows: Row[];
}

export default function Companies() {
  const { data, error, loading, reload } = useLoad(() => rpc<Overview>('admin_company_overview', { p_limit: 300 }), []);
  const [reason, setReason] = useState('');
  if (error && !data) return <LoadError error={error} onRetry={() => void reload()} />;
  if (!data) return <Skeleton rows={6} />;
  const s = data.stats;
  const remove = async (id: number) => {
    try { toast((await rpc<{ message: string }>('admin_company_remove', { p_company: id, p_reason: reason })).message, 'good'); } catch (e) { toast(errorMessage(e), 'bad'); }
    void reload();
  };
  return (
    <div className="adm-page" data-testid="admin-companies">
      <PageHead title="Companies" sub="Online companies players run (no map plot)" actions={<Btn small icon="refresh" onClick={() => void reload()} disabled={loading}>Refresh</Btn>} />
      <section className="adm-card">
        <p className="adm-sub">
          {s.companies} companies · {s.listed} on the Market · {naira(s.till_total)} waiting in tills · {naira(s.sales_7d)} sales in 7 evenings · {naira(s.income_7d)} cashed out in 7 days ·
          real businesses: {s.real_live} live, {s.real_review} waiting for review
        </p>
        <p className="adm-sub">{data.industries.map((i) => `${i.icon} ${i.name} ${i.companies}`).join(' · ')}</p>
      </section>
      <section className="adm-card">
        <h3>All companies</h3>
        <label className="adm-field">
          <span className="adm-field__label">Reason (sent to the owner when you remove one; their till is paid out)</span>
          <input className="adm-input" value={reason} maxLength={200} placeholder="e.g. rude name" onChange={(e) => setReason(e.target.value)} />
        </label>
        {data.rows.length === 0 ? <p className="adm-sub">Nobody has registered a company yet.</p> : (
          <div className="adm-scroll">
            <table className="adm-table">
              <thead><tr><th>Company</th><th>Owner</th><th>HQ</th><th>Stars</th><th>Staff</th><th>Till</th><th>Sales 7d</th><th>Profit</th><th>Since</th><th /></tr></thead>
              <tbody>
                {data.rows.map((r) => (
                  <tr key={r.id}>
                    <td><b>{r.logo} {r.name}</b><br /><span className="adm-sub">{r.industry} · {r.locations} location{r.locations > 1 ? 's' : ''}{r.listed ? ' · on the Market' : ''}</span></td>
                    <td>@{r.owner} {r.source !== 'new' && <Badge tone="violet">{r.source}</Badge>}</td>
                    <td>{r.hq}</td><td>{r.stars}★</td><td>{r.staff}{r.manager ? ' + mgr' : ''}</td>
                    <td>{naira(r.till)}</td><td>{naira(r.sales_7d)}</td><td>{naira(r.lifetime_net)}</td><td>{timeShort(r.created_at)}</td>
                    <td><ConfirmButton tone="danger" small confirmText="Tap again: remove" onConfirm={() => remove(r.id)}>Remove</ConfirmButton></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>
    </div>
  );
}
