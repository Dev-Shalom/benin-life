// E4 admin Economy dashboard (docs/ECONOMY_SINKS.md): money in the game, created vs destroyed per day by category (from the ledger),
// top holders, tax, the inflation indicator and quick links to the tunable settings. Read-only; the numbers are edited in
// Settings -> Economy and Content -> Policies.
import { useState } from 'react';
import { Link } from 'react-router-dom';
import { naira, nairaShort } from '../lib/format';
import { adminApi } from './api';
import { Badge, Btn, LoadError, PageHead, Skeleton } from './parts';
import { useLoad } from './util';

function Stat({ label, value, sub, title, tone }: { label: string; value: string; sub?: string; title?: string; tone?: 'green' | 'red' | 'amber' }) {
  return (
    <div className={`adm-stat${tone ? ` adm-stat--${tone}` : ''}`}>
      <span className="adm-kicker">{label}</span>
      <b className="adm-stat__value" title={title}>{value}</b>
      {sub && <span className="adm-stat__sub">{sub}</span>}
    </div>
  );
}

const dayLabel = (iso: string) => new Date(`${iso}T12:00:00Z`).toLocaleDateString('en-GB', { day: 'numeric', month: 'short', timeZone: 'UTC' });

/** Created (green) and destroyed (red) a day: a plain grouped bar chart, labelled, no hover needed. */
function DayChart({ series }: { series: { day: string; created: number; destroyed: number }[] }) {
  const max = Math.max(1, ...series.map((d) => Math.max(d.created, d.destroyed)));
  const W = 640; const H = 170; const padL = 6; const padB = 22; const gap = 6;
  const bw = (W - padL) / series.length;
  return (
    <svg viewBox={`0 0 ${W} ${H}`} className="eco-chart" role="img" aria-label="Money created and destroyed per day">
      {[0.25, 0.5, 0.75, 1].map((f) => <line key={f} x1={padL} x2={W} y1={(H - padB) * (1 - f)} y2={(H - padB) * (1 - f)} className="eco-chart__grid" />)}
      {series.map((d, i) => {
        const x = padL + i * bw;
        const hc = ((H - padB - 4) * d.created) / max; const hd = ((H - padB - 4) * d.destroyed) / max;
        const w = (bw - gap) / 2;
        return (
          <g key={d.day}>
            <title>{`${dayLabel(d.day)}: made ${naira(d.created)}, destroyed ${naira(d.destroyed)}`}</title>
            <rect x={x + gap / 2} y={H - padB - hc} width={w} height={hc} className="eco-chart__made" rx="2" />
            <rect x={x + gap / 2 + w} y={H - padB - hd} width={w} height={hd} className="eco-chart__gone" rx="2" />
            {(i % 2 === 0 || series.length < 8) && <text x={x + bw / 2} y={H - 6} textAnchor="middle" className="eco-chart__lbl">{dayLabel(d.day)}</text>}
          </g>
        );
      })}
    </svg>
  );
}

const STATE: Record<string, { label: string; tone: 'green' | 'red' | 'amber' | 'grey' }> = {
  ok: { label: 'Stable', tone: 'green' }, hot: { label: 'Growing fast', tone: 'red' }, cooling: { label: 'Shrinking', tone: 'amber' }, unknown: { label: 'Not enough data', tone: 'grey' },
};
const pct = (n: number | null) => (n == null ? '–' : `${n > 0 ? '+' : ''}${n}%`);

export default function Economy() {
  const [days, setDays] = useState(14);
  const { data: d, error, loading, reload } = useLoad(() => adminApi.economyOverview(days), [days]);
  if (error && !d) return <LoadError error={error} onRetry={() => void reload()} />;
  if (!d) return <Skeleton rows={7} />;
  const st = STATE[d.inflation.state] ?? STATE.unknown;
  const t = d.tax;
  const off = Object.entries(d.switches).filter(([, on]) => !on).map(([k]) => k.replace('_', ' '));
  return (
    <div className="adm-page" data-testid="admin-economy">
      <PageHead title="Economy" sub={`Money made and destroyed, from the ledger. ${d.days} days from ${dayLabel(d.from)} (Benin time). Admin accounts are left out.`}
        actions={<><Btn onClick={() => setDays(days === 14 ? 30 : 14)}>{days === 14 ? 'Show 30 days' : 'Show 14 days'}</Btn><Btn icon="refresh" onClick={() => void reload()} disabled={loading}>{loading ? 'Loading…' : 'Refresh'}</Btn></>} />
      {off.length > 0 && <p className="adm-sub"><Badge tone="amber">switched off</Badge> {off.join(', ')}: see Settings → Economy.</p>}

      <div className="adm-stats">
        <Stat label="Total money in the game" value={nairaShort(d.supply.total)} title={naira(d.supply.total)} sub={`${d.supply.players.toLocaleString()} players`} tone="green" />
        <Stat label={`Made (${d.days} d)`} value={nairaShort(d.window.created)} title={naira(d.window.created)} sub="into players' pockets" />
        <Stat label={`Destroyed (${d.days} d)`} value={nairaShort(d.window.destroyed)} title={naira(d.window.destroyed)}
          sub={d.window.destroyed_pct_of_created != null ? `${d.window.destroyed_pct_of_created}% of what was made` : 'nothing made yet'} tone="red" />
        <Stat label="Money supply growth" value={pct(d.inflation.growth_pct)} sub={`last 7 days ${pct(d.inflation.growth_7d_pct)} · ${st.label}`} tone={d.inflation.state === 'hot' ? 'red' : d.inflation.state === 'ok' ? 'green' : 'amber'} />
        <Stat label="Tax collected" value={nairaShort(t.collected_total)} title={naira(t.collected_total)} sub={`${nairaShort(t.collected_window)} in ${d.days} d · ${nairaShort(t.owed_total)} still owed`} />
      </div>

      <section className="adm-card">
        <h2 className="adm-h2">Where the money sits</h2>
        <div className="eco-parts">
          {([['Cash', d.supply.cash], ['Bank', d.supply.bank], ['Yahoo balance', d.supply.yahoo], ['Gang banks', d.supply.gangs], ['Business takings', d.supply.business]] as const).map(([k, v]) => (
            <div key={k} className="eco-part"><span>{k}</span><b title={naira(v)}>{nairaShort(v)}</b><i style={{ width: `${d.supply.total ? (v / d.supply.total) * 100 : 0}%` }} /></div>
          ))}
        </div>
      </section>

      <section className="adm-card">
        <h2 className="adm-h2">Made vs destroyed a day</h2>
        <p className="adm-sub"><span className="adm-key adm-key--in" /> made <span className="adm-key adm-key--out" /> destroyed. Moves between players (transfers, tips, Market, bank deposits) are not counted.</p>
        <DayChart series={d.series} />
        <div className="adm-scroll">
          <table className="adm-table">
            <thead><tr><th>Day</th><th>Made</th><th>Destroyed</th><th>Net</th></tr></thead>
            <tbody>
              {[...d.series].reverse().map((x) => (
                <tr key={x.day}><td>{dayLabel(x.day)}</td><td title={naira(x.created)}>{nairaShort(x.created)}</td><td title={naira(x.destroyed)}>{nairaShort(x.destroyed)}</td>
                  <td className={x.net < 0 ? 'is-neg' : 'is-pos'}>{x.net < 0 ? '−' : '+'}{nairaShort(Math.abs(x.net))}</td></tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>

      <div className="adm-grid2">
        <section className="adm-card">
          <h2 className="adm-h2">Faucets and sinks by category</h2>
          <div className="adm-scroll">
            <table className="adm-table">
              <thead><tr><th>Category</th><th>Made</th><th>Destroyed</th></tr></thead>
              <tbody>
                {d.categories.map((c) => (
                  <tr key={c.category}><td>{c.category}</td><td title={naira(c.created)}>{c.created ? nairaShort(c.created) : '–'}</td><td title={naira(c.destroyed)}>{c.destroyed ? nairaShort(c.destroyed) : '–'}</td></tr>
                ))}
              </tbody>
            </table>
          </div>
        </section>
        <section className="adm-card">
          <h2 className="adm-h2">The sinks, one by one ({d.days} d)</h2>
          <ul className="eco-sinks">
            <li><span>Income tax</span><b>{nairaShort(t.collected_window)}</b></li>
            <li><span>Transfer fees + stamp duty</span><b>{nairaShort(t.transfer_charges_window)}</b></li>
            <li><span>Bills paid (house, car, business, land)</span><b>{nairaShort(t.bills_paid_window)}</b></li>
            <li><span>VAT</span><b>{nairaShort(t.vat_window)}</b></li>
            <li><span>Luxury levy</span><b>{nairaShort(t.luxury_window)}</b></li>
            <li><span>Donations, parties, Chief titles</span><b>{nairaShort(t.prestige_window)}</b></li>
          </ul>
          <p className="adm-sub">Open bills now {nairaShort(t.bills_open_total)} ({nairaShort(t.bills_overdue_total)} overdue). Tax owed {nairaShort(t.owed_total)}.</p>
        </section>
      </div>

      <section className="adm-card">
        <h2 className="adm-h2">Top 20 holders</h2>
        <p className="adm-sub">Cash + bank + Yahoo balance + business takings.</p>
        <div className="adm-scroll">
          <table className="adm-table">
            <thead><tr><th>#</th><th>Player</th><th>Cash</th><th>Bank</th><th>Yahoo</th><th>Business</th><th>Total</th></tr></thead>
            <tbody>
              {d.holders.map((h) => (
                <tr key={h.id}><td>{h.rank}</td><td>@{h.username}</td><td>{nairaShort(h.cash)}</td><td>{nairaShort(h.bank)}</td><td>{h.yahoo ? nairaShort(h.yahoo) : '–'}</td>
                  <td>{h.business ? nairaShort(h.business) : '–'}</td><td title={naira(h.total)}><b>{nairaShort(h.total)}</b></td></tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>

      <section className="adm-card">
        <h2 className="adm-h2">Biggest movers by ledger reason</h2>
        <div className="adm-scroll">
          <table className="adm-table">
            <thead><tr><th>Reason</th><th>Category</th><th>Made</th><th>Destroyed</th></tr></thead>
            <tbody>
              {d.reasons.slice(0, 20).map((r) => (
                <tr key={r.reason}><td><code>{r.reason}</code></td><td>{r.category}</td><td>{r.created ? nairaShort(r.created) : '–'}</td><td>{r.destroyed ? nairaShort(r.destroyed) : '–'}</td></tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>

      <section className="adm-card">
        <h2 className="adm-h2">Tune it</h2>
        <ul className="eco-links">
          <li><Link to="/admin/settings?cat=economy">Settings → Economy</Link> <small>transfer fee tiers, tax bands, bills, VAT, party and Chief prices, and every master switch</small></li>
          <li><Link to="/admin/settings?cat=bank">Settings → Bank</Link> <small>daily transfer limit, wait for new accounts</small></li>
          <li><Link to="/admin/settings?cat=leaderboard">Settings → Leaderboards</Link> <small>earn_reasons: what counts as income for the weekly tax</small></li>
          <li><Link to="/admin/content">Content → Policies</Link> <small>the Governor&apos;s Tax holiday (value = percent cut of every rate)</small></li>
          <li><Link to="/admin/elections">Elections</Link> <small>who is Governor now</small></li>
        </ul>
      </section>
    </div>
  );
}
