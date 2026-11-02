// Admin -> Power (docs/POWER.md): the Blackout control (start a city-wide blackout for N hours, end it), the Fuel scarcity control, every area's
// outage state, and all the power / fuel / black market settings. Every start and end is audited server side.
import { useState } from 'react';
import {
  adminPowerEventEnd, adminPowerEventStart, adminPowerOverview, type AdminPowerEvent,
} from '../api/power';
import { errorMessage } from '../lib/api';
import { naira } from '../lib/format';
import { toast } from '../ui';
import { adminApi, type ConfigRow } from './api';
import { Badge, Btn, ConfirmButton, LoadError, NumberControl, PageHead, Skeleton, Toggle } from './parts';
import { useLoad } from './util';
import './Offices.css';

const when = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleString('en-GB', { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' }) : '-');

function Setting({ row, onSaved }: { row: ConfigRow; onSaved: () => void }) {
  const [v, setV] = useState<unknown>(row.value);
  const dirty = JSON.stringify(v) !== JSON.stringify(row.value);
  const save = async () => { try { await adminApi.configSet(row.key, v); toast('Saved.', 'good'); onSaved(); } catch (e) { toast(errorMessage(e), 'bad'); } };
  return (
    <div className="adm-card ao-lever" data-testid={`power-set-${row.key}`}>
      <div className="ao-lever__top"><b>{row.label}</b><span className="adm-sub">{row.key}</span></div>
      <span className="adm-sub">{row.description}</span>
      <div className="ao-actions">
        {row.kind === 'bool' ? <Toggle checked={Boolean(v)} onChange={setV} label={row.label} />
          : row.kind === 'text' ? <input className="adm-input" value={String(v ?? '')} onChange={(e) => setV(e.target.value)} aria-label={row.label} />
            : <NumberControl kind={row.kind} value={typeof v === 'number' ? v : ''} min={row.min} max={row.max} onChange={(n) => setV(n === '' ? 0 : n)} />}
        {dirty && <Btn small tone="primary" onClick={() => void save()}>Save</Btn>}
      </div>
    </div>
  );
}

function EventControl({ kind, title, blurb, active, defaultHours, maxHours, reload }: {
  kind: 'blackout' | 'scarcity'; title: string; blurb: string; active: AdminPowerEvent | null; defaultHours: number; maxHours: number; reload: () => void;
}) {
  const [hours, setHours] = useState(defaultHours);
  const [note, setNote] = useState('');
  const run = async (fn: () => Promise<{ message: string }>) => {
    try { toast((await fn()).message, 'good'); reload(); } catch (e) { toast(errorMessage(e), 'bad'); }
  };
  return (
    <article className="adm-card ao-lever" data-testid={`power-${kind}`}>
      <div className="ao-lever__top"><b>{title}</b>{active ? <Badge tone="red">ON until {when(active.ends_at)}</Badge> : <Badge>Off</Badge>}</div>
      <span className="adm-sub">{blurb}</span>
      <div className="ao-actions">
        <label className="adm-sub">Hours <NumberControl kind="number" value={hours} min={0.1} max={maxHours} onChange={(n) => setHours(n === '' ? defaultHours : n)} /></label>
        <input className="adm-input" placeholder="Note (optional, kept in the audit)" value={note} onChange={(e) => setNote(e.target.value)} aria-label="Note" />
      </div>
      <div className="ao-actions">
        <ConfirmButton tone="primary" confirmText="Tap again to start" onConfirm={() => run(() => adminPowerEventStart(kind, hours, note))}>{active ? 'Restart for these hours' : 'Start now'}</ConfirmButton>
        {active && <ConfirmButton onConfirm={() => run(() => adminPowerEventEnd(kind))}>End now</ConfirmButton>}
      </div>
    </article>
  );
}

export default function Power() {
  const { data, error, loading, reload } = useLoad(() => adminPowerOverview(), []);
  const cfg = useLoad(() => adminApi.configList(), []);
  const rows = (cfg.data ?? []).filter((r) => ['power', 'fuel', 'blackmarket'].includes(r.category));
  const val = (k: string, d: number) => { const r = (cfg.data ?? []).find((x) => x.key === k); return typeof r?.value === 'number' ? r.value : d; };
  return (
    <div className="adm-page" data-testid="admin-power">
      <PageHead title="Power" sub="NEPA outages by area, the blackout button, fuel scarcity and the black market. Start and end are audited." />
      {error && <LoadError error={error} onRetry={() => void reload()} />}
      {loading && !data && <Skeleton rows={4} />}
      {data && (
        <>
          <div className="adm-card"><div className="ao-actions">
            <Badge tone="amber">{data.generators_on} generators running</Badge><Badge tone="blue">{data.with_backup} players with a backup</Badge>
            <Badge>petrol today {data.petrol_today ? naira(data.petrol_today) : '-'}</Badge><Badge>diesel today {data.diesel_today ? naira(data.diesel_today) : '-'}</Badge>
            {data.random_blackout_now && <Badge tone="red">random blackout now</Badge>}{data.random_scarcity_now && <Badge tone="red">random scarcity now</Badge>}
          </div></div>
          <EventControl kind="blackout" title="Blackout (all of Benin)" active={data.blackout} defaultHours={2} maxHours={val('power.blackout_max_hours', 12)} reload={() => void reload()}
            blurb="Every area loses light at once, for N real hours. Players get the 'NEPA don take light for all of Benin' card. End it any time." />
          <EventControl kind="scarcity" title="Fuel scarcity" active={data.scarcity} defaultHours={val('fuel.scarcity_default_hours', 8)} maxHours={72} reload={() => void reload()}
            blurb="Station prices go up (setting), some stations run dry, queues get long, and the black market becomes the only easy fuel." />
          <h3>Areas right now</h3>
          {data.areas.map((a) => (
            <article key={a.id} className="adm-card ao-lever">
              <div className="ao-lever__top"><b>{a.name}</b><span>{a.mains === 'on' ? <Badge tone="green">light on</Badge> : <Badge tone="red">light off</Badge>}</span></div>
              <span className="adm-sub">Outage chance {a.outage_pct}% · flips {when(a.until)}. Change the % in the settings below (or the NEPA MD can nudge it a little).</span>
            </article>
          ))}
          <h3>Recent blackouts and scarcities</h3>
          {data.recent.map((e) => <article key={e.id} className="adm-card ao-lever"><div className="ao-lever__top"><b>{e.kind}</b><span className="adm-sub">{when(e.started_at)} to {when(e.ends_at)}</span></div>{e.note && <span className="adm-sub">{e.note}</span>}</article>)}
          {!data.recent.length && <p className="adm-sub">None yet.</p>}
        </>
      )}
      <h3>Settings</h3>
      <p className="adm-sub">Also under Settings: Power cuts, Fuel and Black market. Gear (tank, burn, battery sizes), areas and the black market shelf are in Content.</p>
      {cfg.loading && !cfg.data && <Skeleton rows={3} />}
      {rows.map((r) => <Setting key={r.key} row={r} onSaved={() => void cfg.reload()} />)}
    </div>
  );
}
