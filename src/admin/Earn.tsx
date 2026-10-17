// E2 admin view: referrals, weekly top-earner winners and tips (docs/HUSTLES.md). Read-only; the numbers are edited in
// Settings (referral.*, leaderboard.weekly_*, tips.*) and Content -> Hustles.
import { naira, nairaShort } from '../lib/format';
import { adminApi } from './api';
import { Badge, LoadError, PageHead, Skeleton } from './parts';
import { timeShort, useLoad } from './util';

const TONE: Record<string, 'green' | 'amber' | 'red' | 'grey'> = { rewarded: 'green', pending: 'amber', rejected: 'red' };

export default function Earn() {
  const { data, error, loading, reload } = useLoad(() => adminApi.earnOverview(150), []);
  if (error && !data) return <LoadError error={error} onRetry={() => void reload()} />;
  if (!data) return <Skeleton rows={6} />;
  const r = data.referrals;
  return (
    <div className="adm-page" data-testid="admin-earn">
      <PageHead title="Earn" sub="Referrals, weekly top earners and tips" actions={<button type="button" className="adm-btn adm-btn--ghost adm-btn--sm" onClick={() => void reload()} disabled={loading}>Refresh</button>} />

      <section className="adm-card">
        <h3>Referrals</h3>
        <p className="adm-sub">{r.total} total · {r.pending} pending · {r.rewarded} paid · {r.rejected} rejected · {naira(r.paid)} given out</p>
        {r.rows.length === 0 ? <p className="adm-sub">Nobody has used a referral link yet.</p> : (
          <div className="adm-scroll">
            <table className="adm-table">
              <thead><tr><th>When</th><th>Inviter</th><th>New player</th><th>Status</th><th>Played</th><th>Bonus</th></tr></thead>
              <tbody>
                {r.rows.map((x) => (
                  <tr key={x.id}>
                    <td>{timeShort(x.created_at)}</td>
                    <td>@{x.inviter}</td>
                    <td>@{x.new_player}</td>
                    <td><Badge tone={TONE[x.status] ?? 'grey'}>{x.status}</Badge>{x.reason ? ` ${x.reason}` : ''}</td>
                    <td>{x.play_minutes} min</td>
                    <td>{x.status === 'rewarded' ? `${nairaShort(x.bonus_referrer)} + ${nairaShort(x.bonus_referred)}` : '–'}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>

      <section className="adm-card">
        <h3>Weekly top earners</h3>
        {data.weeks.length === 0 ? <p className="adm-sub">No week has closed yet.</p> : data.weeks.map((w) => (
          <div key={w.week_start} className="adm-row">
            <b>Week of {w.week_start}</b>{' '}
            <span className="adm-sub">{w.skipped ? 'before the feature (no prizes)' : `${w.players} earners · ${nairaShort(Number(w.earned))} earned`}</span>
            {w.winners.length > 0 && (
              <ol className="adm-sub">
                {w.winners.map((x) => <li key={x.rank}>#{x.rank} @{x.username}: earned {naira(x.total)}, prize {naira(x.prize)}</li>)}
              </ol>
            )}
          </div>
        ))}
      </section>

      <section className="adm-card">
        <h3>Tips</h3>
        <p className="adm-sub">{data.tips.total} tips · {naira(Number(data.tips.amount))} in total</p>
        {data.tips.rows.length > 0 && (
          <div className="adm-scroll">
            <table className="adm-table">
              <thead><tr><th>When</th><th>From</th><th>To</th><th>Amount</th><th>Note</th></tr></thead>
              <tbody>
                {data.tips.rows.map((x) => (
                  <tr key={x.id}><td>{timeShort(x.created_at)}</td><td>@{x.from}</td><td>@{x.to}</td><td>{naira(x.amount)}</td><td>{x.note ?? ''}</td></tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>
    </div>
  );
}
