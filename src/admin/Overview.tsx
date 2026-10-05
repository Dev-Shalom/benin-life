// Overview: live numbers for the whole game (admin_stats), refreshed every 30 s.
import { useEffect } from 'react';
import { Link } from 'react-router-dom';
import { naira, nairaShort } from '../lib/format';
import { adminApi } from './api';
import { Btn, LoadError, PageHead, Skeleton } from './parts';
import { useLoad } from './util';

function Stat({ label, value, sub, tone }: { label: string; value: string; sub?: string; tone?: 'green' | 'red' | 'amber' }) {
  return (
    <div className={`adm-stat${tone ? ` adm-stat--${tone}` : ''}`}>
      <span className="adm-kicker">{label}</span>
      <b className="adm-stat__value">{value}</b>
      {sub && <span className="adm-stat__sub">{sub}</span>}
    </div>
  );
}

function Bars({ rows }: { rows: { label: string; value: number; display?: string }[] }) {
  const max = Math.max(1, ...rows.map((r) => r.value));
  return (
    <div className="adm-bars">
      {rows.map((r) => (
        <div key={r.label} className="adm-bars__row">
          <span className="adm-bars__label">{r.label}</span>
          <span className="adm-bars__track"><span className="adm-bars__fill" style={{ width: `${(r.value / max) * 100}%` }} /></span>
          <span className="adm-bars__val">{r.display ?? r.value}</span>
        </div>
      ))}
    </div>
  );
}

export default function Overview() {
  const { data: s, error, loading, reload } = useLoad(() => adminApi.stats());
  useEffect(() => {
    const t = window.setInterval(() => { if (document.visibilityState === 'visible') void reload(); }, 30000);
    return () => window.clearInterval(t);
  }, [reload]);

  const moneyMax = s ? Math.max(1, ...s.money_today.map((m) => Math.max(m.created, m.destroyed))) : 1;
  const originTotal = s ? Math.max(1, s.origins.reduce((a, o) => a + o.count, 0)) : 1;

  return (
    <div className="adm-page">
      <PageHead title="Overview" sub="Today is counted from midnight in Benin (WAT)."
        actions={<Btn icon="refresh" onClick={reload} disabled={loading}>{loading ? 'Loading…' : 'Refresh'}</Btn>} />
      {error && <LoadError error={error} onRetry={reload} />}
      {!s && loading && <Skeleton rows={6} />}
      {s && (
        <>
          <div className="adm-stats">
            <Stat label="Online now" value={String(s.online)} sub={`seen in the last ${s.online_minutes} min`} tone="green" />
            <Stat label="Players" value={s.players.toLocaleString()} sub={`${s.new_today} new today`} />
            <Stat label="Money in the game" value={nairaShort(s.cash_total + s.bank_total)} sub={`${nairaShort(s.cash_total)} cash · ${nairaShort(s.bank_total)} bank`} />
            <Stat label="Made today" value={nairaShort(s.created_today)} sub={`${nairaShort(s.destroyed_today)} spent or lost`} />
            <Stat label="Chat today" value={s.chat_today.toLocaleString()} sub="messages" />
            <Link to="/admin/chat" className="adm-statlink">
              <Stat label="Reports" value={String(s.reports_pending)} sub="waiting in Chat" tone={s.reports_pending > 0 ? 'amber' : undefined} />
            </Link>
          </div>

          <div className="adm-grid2">
            <section className="adm-card">
              <h2 className="adm-h2">Money today by reason</h2>
              <p className="adm-sub"><span className="adm-key adm-key--in" /> into players’ pockets <span className="adm-key adm-key--out" /> out of them</p>
              {s.money_today.length === 0 ? <p className="adm-empty">No money moved yet today.</p> : (
                <div className="adm-flow">
                  {s.money_today.map((m) => (
                    <div key={m.reason} className="adm-flow__row">
                      <span className="adm-flow__label">{m.label}<small>{m.count}×</small></span>
                      <span className="adm-flow__bars">
                        <span className="adm-flow__out"><span style={{ width: `${(m.destroyed / moneyMax) * 100}%` }} /></span>
                        <span className="adm-flow__in"><span style={{ width: `${(m.created / moneyMax) * 100}%` }} /></span>
                      </span>
                      <span className="adm-flow__val">
                        {m.created > 0 && <span className="is-pos">+{nairaShort(m.created)}</span>}
                        {m.destroyed > 0 && <span className="is-neg">−{nairaShort(m.destroyed)}</span>}
                      </span>
                    </div>
                  ))}
                </div>
              )}
            </section>

            <div className="adm-stack">
              <section className="adm-card">
                <h2 className="adm-h2">Origins</h2>
                <div className="adm-split-bar" role="img" aria-label="Origins split">
                  {s.origins.map((o) => (
                    <span key={o.origin} className={`adm-split-bar__seg is-${o.origin}`} style={{ flexGrow: o.count }} />
                  ))}
                </div>
                <ul className="adm-legend">
                  {s.origins.map((o) => (
                    <li key={o.origin}><span className={`adm-legend__dot is-${o.origin}`} />{o.name} <b>{o.count}</b> <small>{Math.round((o.count / originTotal) * 100)}%</small></li>
                  ))}
                </ul>
              </section>
              <section className="adm-card">
                <h2 className="adm-h2">Jobs</h2>
                <Bars rows={s.jobs.map((j) => ({ label: `${j.emoji} ${j.name}`.trim(), value: j.count }))} />
              </section>
            </div>
          </div>

          <section className="adm-card">
            <h2 className="adm-h2">Richest 10</h2>
            <ol className="adm-rich">
              {s.richest.map((r, i) => (
                <li key={r.id}>
                  <span className="adm-rich__n">{i + 1}</span>
                  <span className="adm-rich__name">{r.username}</span>
                  <span className="adm-rich__split">{nairaShort(r.cash)} cash · {nairaShort(r.bank)} bank</span>
                  <b className="adm-money">{naira(r.total)}</b>
                </li>
              ))}
            </ol>
          </section>
        </>
      )}
    </div>
  );
}
