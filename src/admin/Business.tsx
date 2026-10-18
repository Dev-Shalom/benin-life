// R10 Business admin view (docs/BUSINESS.md): every owned business, who owns it, takings, level; remove one (audited, takings
// paid out). Types and plots are edited in Content -> Business types / Business plots; caps and event chances in Settings -> Business.
// Gifting a business to one player: Players -> that player -> Businesses.
import { useState } from 'react';
import { adminBusinessOverview, adminBusinessRemove } from '../api/business';
import { errorMessage } from '../lib/api';
import { naira } from '../lib/format';
import { toast } from '../ui';
import { Badge, Btn, ConfirmButton, LoadError, PageHead, Skeleton } from './parts';
import { timeShort, useLoad } from './util';

export default function Business() {
  const { data, error, loading, reload } = useLoad(() => adminBusinessOverview(300), []);
  const [reason, setReason] = useState('');
  if (error && !data) return <LoadError error={error} onRetry={() => void reload()} />;
  if (!data) return <Skeleton rows={6} />;
  const s = data.stats;
  const remove = async (id: number) => {
    try { toast((await adminBusinessRemove(id, reason)).message, 'good'); } catch (e) { toast(errorMessage(e), 'bad'); }
    void reload();
  };
  return (
    <div className="adm-page" data-testid="admin-business">
      <PageHead title="Business" sub="Player-owned businesses"
        actions={<Btn small icon="refresh" onClick={() => void reload()} disabled={loading}>Refresh</Btn>} />
      <section className="adm-card">
        <p className="adm-sub">
          {s.owned} owned · {s.free} of {s.plots} plots free · {s.listed} on the Market · {naira(s.income_7d)} earned by owners in the last 7 days
        </p>
      </section>
      <section className="adm-card">
        <h3>Owned businesses</h3>
        <label className="adm-field">
          <span className="adm-field__label">Reason (sent to the owner when you remove one; their takings are paid out)</span>
          <input className="adm-input" value={reason} maxLength={200} placeholder="e.g. rule break" onChange={(e) => setReason(e.target.value)} />
        </label>
        {data.rows.length === 0 ? <p className="adm-sub">Nobody owns a business yet.</p> : (
          <div className="adm-scroll">
            <table className="adm-table">
              <thead><tr><th>Business</th><th>Owner</th><th>Plot</th><th>Level</th><th>Takings</th><th>Staff</th><th>Earned</th><th>Since</th><th /></tr></thead>
              <tbody>
                {data.rows.map((r) => (
                  <tr key={r.id}>
                    <td><b>{r.icon} {r.name}</b><br /><span className="adm-sub">{r.type}{r.listed ? ' · on the Market' : ''}</span></td>
                    <td>@{r.owner} {r.source !== 'buy' && <Badge tone={r.source === 'admin' ? 'blue' : 'violet'}>{r.source}</Badge>}</td>
                    <td>{r.plot}</td>
                    <td>{r.level}</td>
                    <td>{naira(r.takings)}</td>
                    <td>{r.staff}</td>
                    <td>{naira(r.lifetime_income + r.lifetime_visit)}</td>
                    <td>{timeShort(r.bought_at)}</td>
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
