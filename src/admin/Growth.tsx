// Admin -> Growth (docs/GROWTH.md): are players coming back, and which door did they come through?
// One cached document from admin_growth_overview(); simple bar charts drawn with plain divs (no chart library).
import { useState } from 'react';
import { adminApi, type GrowthDay, type GrowthOverview } from './api';
import { Btn, LoadError, PageHead, Skeleton } from './parts';
import { useLoad } from './util';
import './Growth.css';

const SOURCE_LABEL: Record<string, string> = {
  tiktok: 'TikTok', whatsapp: 'WhatsApp', friend: 'A friend', campus: 'Campus', instagram: 'Instagram', x: 'X',
  google: 'Google', other: 'Other', unknown: 'Not said', facebook: 'Facebook', youtube: 'YouTube', telegram: 'Telegram',
};
const sourceLabel = (s: string) => SOURCE_LABEL[s] ?? s.replace(/_/g, ' ');

const pct = (num: number, den: number) => (den > 0 ? Math.round((num / den) * 100) : null);
const pctText = (v: number | null) => (v === null ? '—' : `${v}%`);
const shortDay = (d: string) => new Date(`${d}T12:00:00`).toLocaleDateString('en-NG', { day: 'numeric', month: 'short' });

function Stat({ label, value, sub, tone }: { label: string; value: number | string; sub?: string; tone?: 'green' | 'amber' }) {
  return (
    <div className={`adm-stat${tone ? ` adm-stat--${tone}` : ''}`}>
      <small>{label}</small>
      <span className="adm-stat__value">{value}</span>
      {sub && <span className="adm-stat__sub">{sub}</span>}
    </div>
  );
}

/** A 30-day bar chart: bars in a flex row, the busiest day on top, first / middle / last day under it. */
function Bars({ days, label, tone }: { days: GrowthDay[]; label: string; tone: 'blue' | 'green' }) {
  const max = Math.max(1, ...days.map((d) => d.n));
  const total = days.reduce((a, d) => a + d.n, 0);
  const last = days.length - 1;
  return (
    <div className="gr-chart" role="img" aria-label={`${label}: ${total} in 30 days, busiest day ${max}`}>
      <div className="gr-chart__top"><span>{max}</span><span>busiest day</span></div>
      <div className="gr-chart__bars">
        {days.map((d, i) => (
          <span key={d.day} className={`gr-bar gr-bar--${tone}${i === last ? ' is-today' : ''}`} title={`${shortDay(d.day)}: ${d.n}`}
            style={{ height: `${Math.max(d.n > 0 ? 4 : 1, (d.n / max) * 100)}%` }} />
        ))}
      </div>
      <div className="gr-chart__axis"><span>{days[0] ? shortDay(days[0].day) : ''}</span><span>{days[15] ? shortDay(days[15].day) : ''}</span><span>Today</span></div>
    </div>
  );
}

function Rate({ label, value, sub }: { label: string; value: number | null; sub: string }) {
  return (
    <div className="gr-rate">
      <small>{label}</small>
      <b>{pctText(value)}</b>
      <span>{sub}</span>
    </div>
  );
}

function View({ d }: { d: GrowthOverview }) {
  const t = d.totals;
  const mature1 = d.cohorts.filter((c) => c.d1 !== null);
  const mature7 = d.cohorts.filter((c) => c.d7 !== null);
  const r1 = pct(mature1.reduce((a, c) => a + (c.d1 ?? 0), 0), mature1.reduce((a, c) => a + c.size, 0));
  const r7 = pct(mature7.reduce((a, c) => a + (c.d7 ?? 0), 0), mature7.reduce((a, c) => a + c.size, 0));
  const wk = t.wau_prev > 0 ? Math.round(((t.wau - t.wau_prev) / t.wau_prev) * 100) : null;
  const signups30 = d.signups.reduce((a, x) => a + x.n, 0);
  const appMax = Math.max(1, ...d.apps.map((a) => a.week));
  const cohorts = [...d.cohorts].reverse().slice(0, 21);

  return (
    <>
      <div className="adm-stats gr-stats">
        <Stat label="Active today" value={t.today} sub={`${t.yesterday} yesterday`} tone="green" />
        <Stat label="Online now" value={d.online} sub="seen in the last few minutes" />
        <Stat label="Weekly active" value={t.wau} sub={wk === null ? 'last 7 days' : `${wk >= 0 ? '+' : ''}${wk}% on the week before`} />
        <Stat label="Monthly active" value={t.mau} sub="last 30 days" />
        <Stat label="New in 30 days" value={signups30} sub={`${t.players} players in all`} />
        <Stat label="Come back next day" value={pctText(r1)} sub="day-1 return, 30-day sign-ups" tone={r1 !== null && r1 >= 30 ? 'green' : 'amber'} />
      </div>

      <section className="adm-card gr-card">
        <h2 className="adm-h2">Active players per day</h2>
        <p className="adm-sub">A player counts on a day if the game saw them that day (Benin time).</p>
        <Bars days={d.dau} label="Active players per day" tone="blue" />
      </section>

      <section className="adm-card gr-card">
        <h2 className="adm-h2">New sign-ups per day</h2>
        <Bars days={d.signups} label="New sign-ups per day" tone="green" />
      </section>

      <section className="adm-card gr-card">
        <h2 className="adm-h2">Do they come back?</h2>
        <p className="adm-sub">Share of each sign-up day that was active the next day (day 1) and 7 days later (day 7). A number shows only once that day is over.</p>
        <div className="gr-rates">
          <Rate label="Day 1" value={r1} sub={`${mature1.reduce((a, c) => a + c.size, 0)} players counted`} />
          <Rate label="Day 7" value={r7} sub={`${mature7.reduce((a, c) => a + c.size, 0)} players counted`} />
        </div>
        <div className="gr-table" role="table" aria-label="Return rate by sign-up day">
          <div className="gr-row gr-row--head" role="row"><span>Signed up</span><span>Players</span><span>Day 1</span><span>Day 7</span></div>
          {cohorts.map((c) => (
            <div className="gr-row" role="row" key={c.day}>
              <span>{shortDay(c.day)}</span>
              <span>{c.size}</span>
              <span>{c.d1 === null ? '—' : pctText(pct(c.d1, c.size))}</span>
              <span>{c.d7 === null ? '—' : pctText(pct(c.d7, c.size))}</span>
            </div>
          ))}
          {cohorts.length === 0 && <p className="adm-empty">No sign-ups in the last 30 days yet.</p>}
        </div>
      </section>

      <section className="adm-card gr-card">
        <h2 className="adm-h2">Where players came from</h2>
        <p className="adm-sub">
          Sign-ups of the last {d.sources_days} days. A channel link (?src=tiktok) counts first, then the answer to "How did you hear about Benin Life?",
          then a player invite link counts as "A friend". "Not said" is everyone else.
        </p>
        <div className="gr-table" role="table" aria-label="Sign-up source">
          <div className="gr-row gr-row--head gr-row--src" role="row"><span>Source</span><span>Players</span><span>Day 1</span><span>Day 7</span></div>
          {d.sources.map((s) => (
            <div className="gr-row gr-row--src" role="row" key={s.source}>
              <span className="gr-src">{sourceLabel(s.source)}</span>
              <span>{s.n}</span>
              <span>{pctText(pct(s.r1, s.e1))}<small>{s.e1 ? ` of ${s.e1}` : ''}</small></span>
              <span>{pctText(pct(s.r7, s.e7))}<small>{s.e7 ? ` of ${s.e7}` : ''}</small></span>
            </div>
          ))}
          {d.sources.length === 0 && <p className="adm-empty">No sign-ups in this window.</p>}
        </div>
      </section>

      <section className="adm-card gr-card">
        <h2 className="adm-h2">What players open</h2>
        <p className="adm-sub">Phone apps, players who opened each one (once per player per day). Last 7 days, with today in brackets.</p>
        <div className="adm-bars">
          {d.apps.map((a) => (
            <div className="adm-bars__row" key={a.app}>
              <span className="adm-bars__label">{a.app}</span>
              <span className="adm-bars__track"><span className="adm-bars__fill" style={{ width: `${(a.week / appMax) * 100}%` }} /></span>
              <span className="adm-bars__val">{a.week}<small className="gr-today"> ({a.today})</small></span>
            </div>
          ))}
          {d.apps.length === 0 && <p className="adm-empty">Nothing counted yet. It fills as players open apps.</p>}
        </div>
      </section>
    </>
  );
}

export default function Growth() {
  const [busy, setBusy] = useState(false);
  const { data, setData, error, loading, reload } = useLoad(() => adminApi.growthOverview(false));
  const refresh = async () => {
    setBusy(true);
    try { setData(await adminApi.growthOverview(true)); } catch { void reload(); } finally { setBusy(false); }
  };
  return (
    <>
      <PageHead title="Growth" sub={data ? `Saved ${new Date(data.computed_at).toLocaleTimeString('en-NG', { hour: 'numeric', minute: '2-digit' })}, refreshed every ${Math.round(data.cache_seconds / 60)} min.` : 'Are players coming back?'}
        actions={<Btn icon="refresh" onClick={() => void refresh()} disabled={busy || loading}>Refresh</Btn>} />
      {error && <LoadError error={error} onRetry={() => void reload()} />}
      {!data && loading && <Skeleton rows={6} />}
      {data && <View d={data} />}
    </>
  );
}
