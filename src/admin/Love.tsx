// Family & love admin (docs/LOVE.md): live counts, the report inbox and "end this link-up". Settings: Settings -> Family & love.
// Flirt lines and dates: Content. Handling a report and ending a link-up are audited (love_report_*, love_end).
import { adminKidsOverview, adminKidsRemove } from '../api/kids';
import { adminLoveEnd, adminLoveOverview, adminLoveReportSet } from '../api/love';
import { errorMessage } from '../lib/api';
import { toast } from '../ui';
import { Badge, Btn, ConfirmButton, LoadError, PageHead, Skeleton } from './parts';
import { timeShort, useLoad } from './util';

function Stat({ label, value, tone }: { label: string; value: number | string; tone?: 'green' | 'amber' }) {
  return (
    <div className={`adm-stat${tone ? ` adm-stat--${tone}` : ''}`}>
      <span className="adm-kicker">{label}</span>
      <b className="adm-stat__value">{value}</b>
    </div>
  );
}

export default function Love() {
  const { data, error, loading, reload } = useLoad(() => adminLoveOverview());
  const kidsLoad = useLoad(() => adminKidsOverview());
  const kids = kidsLoad.data;
  if (error && !data) return <LoadError error={error} onRetry={() => void reload()} />;
  if (!data) return <Skeleton rows={5} />;
  const run = async (fn: () => Promise<{ message: string }>) => {
    try { toast((await fn()).message, 'good'); } catch (e) { toast(errorMessage(e), 'bad'); }
    void reload();
    void kidsLoad.reload();
  };
  return (
    <div className="adm-page" data-testid="admin-love">
      <PageHead title="Family & love" sub={data.enabled ? 'Link-ups, couples and reports' : 'Switched off in Settings → Family & love'}
        actions={<Btn small icon="refresh" onClick={() => void reload()} disabled={loading}>Refresh</Btn>} />
      <section className="adm-stats">
        <Stat label="Open to link-ups" value={data.open_players} />
        <Stat label="Talking" value={data.talking} />
        <Stat label="Couples" value={data.couples} tone="green" />
        <Stat label="Ended (7 days)" value={data.ended_7d} />
        <Stat label="Asks waiting" value={data.pending_asks} />
        <Stat label="Open reports" value={data.open_reports} tone={data.open_reports > 0 ? 'amber' : undefined} />
      </section>
      {kids && (
        <section className="adm-card" data-testid="admin-kids">
          <h3>Kids {!kids.enabled && <Badge tone="amber">switched off</Badge>}</h3>
          <section className="adm-stats">
            <Stat label="Expecting" value={kids.expecting} />
            <Stat label="At home" value={kids.home} tone="green" />
            <Stat label="With relatives" value={kids.with_relatives} />
            <Stat label="Alerted (24 h)" value={kids.needs_attention} />
            <Stat label="Unwell" value={kids.sick} tone={kids.sick > 0 ? 'amber' : undefined} />
            <Stat label="Grown up" value={kids.grown} />
            <Stat label="Gone" value={kids.gone} />
            <Stat label="Passed away" value={kids.passed} />
            <Stat label="Due for the sweep" value={kids.due_now} tone={kids.due_now > 50 ? 'amber' : undefined} />
          </section>
          <p className="adm-sub">"Due for the sweep" stays near 0 when the player-push Cron job runs every minute (docs/LOVE.md). Removing a child tells both parents and is audited (kids_remove).</p>
          {kids.passed_list.length > 0 && (
            <div data-testid="admin-kids-passed">
              <p className="adm-sub">Passing away is {kids.passing_enabled ? 'ON' : 'OFF'} (Settings, Kids). Children who passed:</p>
              <ul className="adm-sub">{kids.passed_list.map((p) => <li key={p.id}>{p.name ?? 'No name'} · {p.days_lived} days · {p.warnings} warnings · @{p.a ?? 'gone'} / @{p.b ?? 'gone'}</li>)}</ul>
            </div>
          )}
          {kids.children.length === 0 ? <p className="adm-sub">No active children yet.</p> : (
            <div className="adm-scroll">
              <table className="adm-table">
                <thead><tr><th>Child</th><th>Parents</th><th>Status</th><th /></tr></thead>
                <tbody>
                  {kids.children.map((c) => (
                    <tr key={c.id}>
                      <td><b>{c.name ?? 'No name yet'}</b> <span className="adm-sub">#{c.id}</span></td>
                      <td>@{c.a ?? 'gone'} · @{c.b ?? 'gone'}</td>
                      <td><Badge tone={c.sick ? 'amber' : 'grey'}>{c.status}{c.sick ? ' · unwell' : ''}</Badge></td>
                      <td className="adm-actions"><ConfirmButton small confirmText="Tap again: remove" onConfirm={() => run(() => adminKidsRemove(c.id, 'admin'))}>Remove</ConfirmButton></td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </section>
      )}
      <section className="adm-card">
        <h3>Reports</h3>
        {data.reports.length === 0 ? <p className="adm-sub">No reports. Good.</p> : (
          <div className="adm-scroll">
            <table className="adm-table">
              <thead><tr><th>When</th><th>Reported</th><th>By</th><th>What happened</th><th>Status</th><th /></tr></thead>
              <tbody>
                {data.reports.map((r) => (
                  <tr key={r.id}>
                    <td>{timeShort(r.created_at)}</td>
                    <td><b>@{r.reported.username}</b>{r.rel_status && r.rel_status !== 'ended' && <> <Badge tone="blue">{r.rel_status}</Badge></>}</td>
                    <td>@{r.reporter.username}</td>
                    <td className="adm-wrap">{r.reason || <span className="adm-sub">no text</span>}</td>
                    <td><Badge tone={r.status === 'open' ? 'amber' : 'grey'}>{r.status}</Badge></td>
                    <td className="adm-actions">
                      {r.status === 'open' && <Btn small onClick={() => void run(() => adminLoveReportSet(r.id, 'reviewed'))}>Reviewed</Btn>}
                      {r.status === 'open' && <Btn small tone="quiet" onClick={() => void run(() => adminLoveReportSet(r.id, 'dismissed'))}>Dismiss</Btn>}
                      {r.rel_id != null && r.rel_status && r.rel_status !== 'ended' && (
                        <ConfirmButton small confirmText="Tap again: end it" onConfirm={() => run(() => adminLoveEnd(r.rel_id!, `report ${r.id}`))}>End link-up</ConfirmButton>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
        <p className="adm-sub">To mute or ban a player, use Players. Ending a link-up tells both players and is audited.</p>
      </section>
    </div>
  );
}
