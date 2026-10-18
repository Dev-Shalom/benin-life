// R9 Benin Market admin view (docs/MARKET.md): live listings (remove + return the item, audited), recent trades with
// suspicious flags, reported listings first. Fee, price band and per-kind switches are in Content -> Market settings;
// limits and thresholds in Settings -> Benin Market.
import { useState } from 'react';
import { adminMarketOverview, adminMarketRemove, leftText } from '../api/market';
import { errorMessage } from '../lib/api';
import { naira, nairaShort } from '../lib/format';
import { toast } from '../ui';
import { Badge, Btn, ConfirmButton, LoadError, PageHead, Skeleton } from './parts';
import { timeShort, useLoad } from './util';

const FLAG_TEXT: Record<string, { label: string; tip: string; tone: 'red' | 'amber' | 'violet' | 'blue' }> = {
  far_low: { label: 'Far too cheap', tip: 'Sold for far less than it is worth: money may be moving to an alt', tone: 'red' },
  far_high: { label: 'Far too dear', tip: 'Sold for far more than it is worth: money may be moving to an alt', tone: 'red' },
  flip: { label: 'Back-and-forth', tip: 'The same two players traded the other way round recently', tone: 'amber' },
  repeat_pair: { label: 'Repeat pair', tip: 'The same two players keep trading with each other', tone: 'amber' },
  new_account: { label: 'New account', tip: 'One side is still inside the new-account wait (an admin trusted sender?)', tone: 'violet' },
};
const KIND = { item: 'Item', furniture: 'Furniture', car: 'Car', land: 'Land' } as const;

export default function Market() {
  const { data, error, loading, reload } = useLoad(() => adminMarketOverview(150), []);
  const [reason, setReason] = useState('');
  const [onlyFlagged, setOnlyFlagged] = useState(false);
  if (error && !data) return <LoadError error={error} onRetry={() => void reload()} />;
  if (!data) return <Skeleton rows={6} />;
  const s = data.stats;
  const trades = data.trades.filter((t) => !onlyFlagged || t.flags.length > 0);
  const remove = async (id: number) => {
    try {
      toast((await adminMarketRemove(id, reason)).message, 'good');
    } catch (e) { toast(errorMessage(e), 'bad'); }
    void reload();
  };
  return (
    <div className="adm-page" data-testid="admin-market">
      <PageHead title="Market" sub="Player-to-player trading: live listings and recent trades"
        actions={<Btn small icon="refresh" onClick={() => void reload()} disabled={loading}>Refresh</Btn>} />

      <section className="adm-card">
        <p className="adm-sub">
          {s.active} live · {s.sold_7d} sold this week for {naira(s.volume_7d)} · {naira(s.fees_7d)} taken as fees ·{' '}
          <b>{s.flagged_7d} flagged</b> · {s.reported} reported
        </p>
      </section>

      <section className="adm-card">
        <h3>Live listings</h3>
        <label className="adm-field">
          <span className="adm-field__label">Reason (sent to the seller when you remove one)</span>
          <input className="adm-input" value={reason} maxLength={200} placeholder="e.g. spam, scam, wrong price" onChange={(e) => setReason(e.target.value)} />
        </label>
        {data.live.length === 0 ? <p className="adm-sub">Nothing is listed.</p> : (
          <div className="adm-scroll">
            <table className="adm-table">
              <thead><tr><th>Thing</th><th>Seller</th><th>Price</th><th>vs value</th><th>Reports</th><th>Ends</th><th /></tr></thead>
              <tbody>
                {data.live.map((l) => (
                  <tr key={l.id}>
                    <td><b>{l.icon} {l.title}</b><br /><span className="adm-sub">{KIND[l.kind]} · {l.cond}{l.private_to ? ` · private to @${l.private_to}` : ''}{l.open_to_offers ? ' · offers' : ''}</span></td>
                    <td>@{l.seller}</td>
                    <td title={naira(l.price)}>{nairaShort(l.price)}</td>
                    <td>{l.pct == null ? '-' : `${l.pct}%`}</td>
                    <td>{l.reports > 0 ? <Badge tone="amber">{l.reports}</Badge> : '-'}{l.reasons.length > 0 && <><br /><span className="adm-sub">{l.reasons.join(' / ')}</span></>}</td>
                    <td>{leftText(l.expires_at)}</td>
                    <td><ConfirmButton small confirmText="Remove + return?" onConfirm={() => remove(l.id)}>Remove</ConfirmButton></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>

      <section className="adm-card">
        <h3>Recent trades</h3>
        <div className="adm-chips adm-toolbar">
          <button type="button" className={`adm-chip${!onlyFlagged ? ' is-on' : ''}`} onClick={() => setOnlyFlagged(false)}>All</button>
          <button type="button" className={`adm-chip${onlyFlagged ? ' is-on' : ''}`} onClick={() => setOnlyFlagged(true)}>Flagged only</button>
        </div>
        <p className="adm-sub">Flags: far too cheap or dear (Settings, then Benin Market, sets the %), back-and-forth or repeat pair between the same two players, a new account on either side. IP and device are not tracked in this game, so there is no same-IP flag.</p>
        {trades.length === 0 ? <p className="adm-sub">No trades{onlyFlagged ? ' with flags' : ''} yet.</p> : (
          <div className="adm-scroll">
            <table className="adm-table">
              <thead><tr><th>When</th><th>Thing</th><th>Seller</th><th>Buyer</th><th>Price</th><th>vs value</th><th>Flags</th></tr></thead>
              <tbody>
                {trades.map((t) => (
                  <tr key={t.id}>
                    <td>{timeShort(t.created_at)}</td>
                    <td>{t.title}<br /><span className="adm-sub">{KIND[t.kind]}{t.via === 'offer' ? ' · by offer' : ''}</span></td>
                    <td>@{t.seller}</td>
                    <td>@{t.buyer}</td>
                    <td title={`${naira(t.price)} (fee ${naira(t.fee)})`}>{nairaShort(t.price)}</td>
                    <td>{t.pct == null ? '-' : `${t.pct}%`}</td>
                    <td>{t.flags.length === 0 ? '-' : t.flags.map((f) => <span key={f} title={FLAG_TEXT[f]?.tip}><Badge tone={FLAG_TEXT[f]?.tone ?? 'grey'}>{FLAG_TEXT[f]?.label ?? f}</Badge> </span>)}</td>
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
