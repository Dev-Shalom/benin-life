// Own your home admin view (docs/PROPERTY.md): player listings, tenancies, builds in progress, recent property events, and
// force-ending a bad tenancy (audited, the tenant is moved out and gets the caution back). Prices, designs and areas: Content.
// Fees, bands and notice days: Settings -> Own your home.
import { useState } from 'react';
import { adminPropertyEndTenancy, adminPropertyOverview } from '../api/property';
import { errorMessage } from '../lib/api';
import { naira, nairaShort } from '../lib/format';
import { toast } from '../ui';
import { Badge, Btn, ConfirmButton, LoadError, PageHead, Skeleton } from './parts';
import { timeShort, useLoad } from './util';

export default function Property() {
  const { data, error, loading, reload } = useLoad(() => adminPropertyOverview(150), []);
  const [reason, setReason] = useState('');
  if (error && !data) return <LoadError error={error} onRetry={() => void reload()} />;
  if (!data) return <Skeleton rows={6} />;
  const s = data.stats;
  const end = async (id: string) => {
    try {
      toast((await adminPropertyEndTenancy(id, reason)).message, 'good');
    } catch (e) { toast(errorMessage(e), 'bad'); }
    void reload();
  };
  return (
    <div className="adm-page" data-testid="admin-property">
      <PageHead title="Property" sub="Homes players own, let and build"
        actions={<Btn small icon="refresh" onClick={() => void reload()} disabled={loading}>Refresh</Btn>} />

      <section className="adm-card">
        <p className="adm-sub">
          {s.properties} homes ({s.bought} bought, {s.built} built) worth {nairaShort(s.value)} · {s.owner_living} lived in by the owner ·{' '}
          <b>{s.tenancies} tenancies</b> paying {naira(s.rent_per_week)} a week · {s.listed_vacant} for rent · {s.builds} builds going ·
          {' '}{naira(s.rent_paid_7d)} rent paid in the last 7 days
        </p>
      </section>

      <section className="adm-card">
        <h3>Tenancies</h3>
        <label className="adm-field">
          <span className="adm-field__label">Reason (saved in the Audit log when you end one)</span>
          <input className="adm-input" value={reason} maxLength={200} placeholder="e.g. landlord abuse, rent dispute, scam" onChange={(e) => setReason(e.target.value)} />
        </label>
        {data.tenancies.length === 0 ? <p className="adm-sub">No tenants right now.</p> : (
          <div className="adm-scroll">
            <table className="adm-table">
              <thead><tr><th>Home</th><th>Landlord</th><th>Tenant</th><th>Rent</th><th>Owed</th><th>Notice</th><th /></tr></thead>
              <tbody>
                {data.tenancies.map((t) => (
                  <tr key={t.property}>
                    <td><b>{t.name}</b><br /><span className="adm-sub">since {timeShort(t.since)}</span></td>
                    <td>@{t.owner}</td><td>@{t.tenant}</td>
                    <td title={naira(t.rent)}>{nairaShort(t.rent)}<br /><span className="adm-sub">caution {nairaShort(t.caution)}</span></td>
                    <td>{t.owed > 0 ? <Badge tone="red">{nairaShort(t.owed)}</Badge> : '-'}</td>
                    <td>{t.ends_at ? <Badge tone="amber">{timeShort(t.ends_at)}</Badge> : '-'}</td>
                    <td><ConfirmButton small confirmText="End + move out?" onConfirm={() => end(t.property)}>Force end</ConfirmButton></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>

      <section className="adm-card">
        <h3>Listings for rent</h3>
        {data.listings.length === 0 ? <p className="adm-sub">Nothing is listed.</p> : (
          <div className="adm-scroll">
            <table className="adm-table">
              <thead><tr><th>Home</th><th>Landlord</th><th>Rent</th><th>Market</th><th>Caution</th><th>Listed</th></tr></thead>
              <tbody>
                {data.listings.map((l) => (
                  <tr key={l.id}>
                    <td><b>{l.name}</b></td><td>@{l.owner}</td><td>{nairaShort(l.rent)}</td><td>{nairaShort(l.market_rent)}</td>
                    <td>{l.caution > 0 ? nairaShort(l.caution) : '-'}</td><td>{timeShort(l.listed_at)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>

      <section className="adm-card">
        <h3>Builds in progress</h3>
        {data.builds.length === 0 ? <p className="adm-sub">No builders on site.</p> : (
          <table className="adm-table">
            <thead><tr><th>Build</th><th>Owner</th><th>Cost</th><th>Ready</th></tr></thead>
            <tbody>
              {data.builds.map((b) => <tr key={b.id}><td><b>{b.name}</b> · {b.area}</td><td>@{b.owner}</td><td>{nairaShort(b.cost)}</td><td>{timeShort(b.ready_at)}</td></tr>)}
            </tbody>
          </table>
        )}
      </section>

      <section className="adm-card">
        <h3>Recent events</h3>
        <ul className="adm-list">
          {data.events.map((e, i) => (
            <li key={i}><span className="adm-sub">{timeShort(e.at)}</span> <b>{e.kind.replace(/_/g, ' ')}</b>{e.user ? ` · @${e.user}` : ''}</li>
          ))}
        </ul>
      </section>
    </div>
  );
}
