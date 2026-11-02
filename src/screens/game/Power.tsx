// Power cuts (docs/POWER.md): the HUD chip, the Power sheet (also the Power tab of the Houses app), and the pop-ups.
// The server decides everything (power_status); this file only shows it. Pop-ups use the Life-moment card look but are NOT life moments:
// they never count against the moments cap, and they wait while a club spray, another popup, a task or the road owns the screen.
import { useEffect, useMemo, useRef, useState } from 'react';
import {
  powerAck, powerGenRepair, powerGenToggle, powerRefuel, type PowerNotice, type PowerStatus,
} from '../../api/power';
import { GameError, errorMessage } from '../../lib/api';
import { useGame } from '../../state/game';
import { beninTime, hoursLabel, startPower, usePower } from '../../state/power';
import { useUi } from '../../state/ui';
import { Button, Modal, Sheet, toast } from '../../ui';
import { useHeld } from './MomentsHost';
import './Power.css';

const SOURCE_LABEL: Record<string, string> = {
  mains: 'NEPA light', generator: 'Your generator', battery: 'Inverter battery', solar: 'Solar', none: 'No light',
};

/** Walk the player to the nearest filling station on the map (the sheet and cards use it). */
export function goToStation(): void {
  const g = useGame.getState();
  const here = g.state?.location;
  const list = g.locations.filter((l) => l.id.startsWith('fs_'));
  if (!list.length) { toast('Filling stations are on the map. Open the map.', 'info'); return; }
  const best = [...list].sort((a, b) => Math.hypot(a.x - (here?.x ?? 0), a.y - (here?.y ?? 0)) - Math.hypot(b.x - (here?.x ?? 0), b.y - (here?.y ?? 0)))[0];
  const ui = useUi.getState();
  ui.closeAll();
  ui.setMapOpen(true);
  ui.select(best.id);
}

function openBuyBackup(): void {
  const ui = useUi.getState();
  usePower.getState().closeSheet();
  ui.setOverlay('buy');
}

// ---------------------------------------------------------------------------------------------- HUD chip
export function PowerChip() {
  const d = usePower((s) => s.data);
  const open = usePower((s) => s.openSheet);
  if (!d || !d.enabled) return null;
  let icon = '⚡';
  let text = 'NEPA';
  let tone = 'on';
  if (d.mains === 'off') {
    if (d.source === 'generator') { icon = '⛽'; text = `Gen${d.hours_left ? ' ' + hoursLabel(d.hours_left) : ''}`; tone = 'gen'; }
    else if (d.source === 'battery') { icon = '🔋'; text = `${Math.round(d.backup.inverter?.pct ?? 0)}%`; tone = 'batt'; }
    else if (d.source === 'solar') { icon = '☀️'; text = `Solar ${Math.round(d.backup.inverter?.pct ?? 0)}%`; tone = 'batt'; }
    else { icon = '🕯️'; text = 'No light'; tone = 'off'; }
  } else if (d.backup.generator?.on) { icon = '⛽'; text = 'Gen on'; tone = 'warn'; }
  return (
    <button type="button" className={`power-chip power-chip--${tone}`} data-testid="power-chip" onClick={open}
      aria-label={`Power: ${d.mains === 'on' ? 'NEPA is on' : 'NEPA don take light'}. ${text}. Open`}>
      <span aria-hidden>{icon}</span><span>{text}</span>
    </button>
  );
}

// ---------------------------------------------------------------------------------------------- the panel
function Bar({ pct, tone }: { pct: number; tone: 'fuel' | 'batt' }) {
  return <span className={`pw-bar pw-bar--${tone}`} role="meter" aria-valuemin={0} aria-valuemax={100} aria-valuenow={Math.round(pct)}><span style={{ width: `${Math.max(0, Math.min(100, pct))}%` }} /></span>;
}

export function PowerPanel() {
  const d = usePower((s) => s.data);
  const apply = usePower((s) => s.apply);
  const [busy, setBusy] = useState<string | null>(null);
  useEffect(() => { void usePower.getState().load().catch(() => undefined); }, []);
  if (!d) return <div className="panel-skel"><span /><span /></div>;
  if (!d.enabled) return <p className="pw-note">Power cuts are switched off right now. The light stays on.</p>;
  const g = d.backup.generator ?? null;
  const inv = d.backup.inverter ?? null;
  const area = d.area;
  const bag = (d.bag ?? []).filter((b) => !g || b.fuel === g.fuel);
  const run = async (key: string, fn: () => Promise<PowerStatus & { message?: string }>) => {
    setBusy(key);
    try {
      const r = await fn();
      apply(r);
      if (r.message) toast(r.message, key === 'repair' ? 'good' : 'info');
      void useGame.getState().refresh();
    } catch (e) { toast(errorMessage(e), 'bad'); } finally { setBusy(null); }
  };
  const until = d.until ? beninTime(d.until) : '';
  const left = d.until ? Math.max(0, (Date.parse(d.until) - Date.now()) / 3600000) : null;
  return (
    <div className="pw" data-testid="power-panel">
      <section className={`pw-hero pw-hero--${d.mains}`}>
        <span className="pw-hero__icon" aria-hidden>{d.mains === 'on' ? '💡' : '🕯️'}</span>
        <div className="grow">
          <b>{d.mains === 'on' ? 'NEPA is on' : d.city ? 'NEPA don take light for all of Benin' : 'NEPA don take light'}</b>
          <small>
            {d.mains === 'off'
              ? `${until ? `Back about ${until}` : 'Back soon'}${left != null ? ` (${hoursLabel(left)})` : ''}`
              : until ? `Next cut about ${until}` : 'No cut coming soon'}
          </small>
        </div>
      </section>
      <div className="pw-rows">
        <div className="pw-row"><span>Your area</span><b>{area?.name ?? '-'}</b></div>
        <div className="pw-row"><span>Outage chance</span><b>about {Math.round(area?.outage_pct ?? 0)}% of the time</b></div>
        <div className="pw-row"><span>Light comes from</span><b className={d.lit ? 'is-good' : 'is-bad'}>{SOURCE_LABEL[d.source] ?? d.source}{d.hours_left && d.source !== 'mains' ? ` · ${hoursLabel(d.hours_left)} left` : ''}</b></div>
        {d.visiting && <p className="pw-note">You are visiting. The light is the host&apos;s light.</p>}
      </div>

      {g && !d.visiting && (
        <section className="pw-card" data-testid="power-generator">
          <div className="pw-card__top"><span aria-hidden>⛽</span><b>{g.name}</b><span className={`pw-pill${g.running ? ' is-on' : ''}`}>{g.running ? 'Running' : 'Off'}</span></div>
          <div className="pw-fuel">
            <Bar pct={(g.fuel_l / g.tank_l) * 100} tone="fuel" />
            <small>{g.fuel_l.toFixed(1)} of {g.tank_l} litres of {g.fuel}{g.hours_left ? ` · about ${hoursLabel(g.hours_left)} when running` : ''}</small>
          </div>
          {g.faulty && <p className="pw-warn">It is coughing: bad fuel or a faulty machine. It burns more fuel until a mechanic fixes it.</p>}
          {g.noisy && g.running && <p className="pw-note">Noisy: sleeping next to it adds stress.</p>}
          <div className="pw-actions">
            <Button variant={g.on ? 'ghost' : 'green'} block loading={busy === 'toggle'} disabled={!g.on && g.empty}
              onClick={() => void run('toggle', () => powerGenToggle(!g.on))}>{g.on ? 'Turn off' : g.empty ? 'No fuel' : 'Turn on'}</Button>
            {bag.map((b) => (
              <Button key={b.item} variant="gold" loading={busy === b.item} disabled={g.fuel_l >= g.tank_l - 0.01}
                onClick={() => void run(b.item, () => powerRefuel(b.item, 1))}>
                Pour {b.litres} L {b.grey ? 'grey fuel' : b.name.toLowerCase().includes('can') ? 'jerrycan' : 'fuel'} (you have {b.qty})
              </Button>
            ))}
            {g.fuel_l < g.tank_l - 0.5 && bag.length === 0 && <Button variant="ghost" onClick={() => { usePower.getState().closeSheet(); goToStation(); }}>Buy {g.fuel} at a filling station</Button>}
            {g.faulty && <Button variant="gold" loading={busy === 'repair'} onClick={() => void run('repair', () => powerGenRepair())}>Call a mechanic</Button>}
          </div>
        </section>
      )}

      {inv && !d.visiting && (
        <section className="pw-card" data-testid="power-inverter">
          <div className="pw-card__top"><span aria-hidden>🔋</span><b>Inverter and batteries</b><span className="pw-pill">{Math.round(inv.pct)}%</span></div>
          <div className="pw-fuel">
            <Bar pct={inv.pct} tone="batt" />
            <small>{inv.kwh.toFixed(1)} of {inv.cap_kwh.toFixed(1)} kWh{inv.hours_left && d.mains === 'off' ? ` · about ${hoursLabel(inv.hours_left)} left` : ''}{inv.solar_kw > 0 ? ` · solar ${inv.solar_kw} kW` : ''}</small>
          </div>
          <p className="pw-note">It takes over by itself when NEPA goes. It fills slowly on the mains{inv.solar_kw > 0 ? ' and free from the sun by day' : ''}. More batteries give more hours.</p>
          {inv.health < 100 && <p className="pw-warn">The battery is weak ({Math.round(inv.health)}%). A mechanic can service it.</p>}
          {inv.health < 100 && !g?.faulty && <Button variant="gold" loading={busy === 'repair'} onClick={() => void run('repair', () => powerGenRepair())}>Call a mechanic</Button>}
        </section>
      )}

      {!g && !inv && !d.visiting && (
        <section className="pw-card">
          <div className="pw-card__top"><span aria-hidden>🔌</span><b>No backup yet</b></div>
          <p className="pw-note">You no get generator or inverter. When NEPA goes, your room goes dark and sleep gives less rest.</p>
          <Button variant="green" block onClick={openBuyBackup}>Buy a backup</Button>
        </section>
      )}
    </div>
  );
}

export function PowerSheet() {
  const open = usePower((s) => s.sheet);
  const close = usePower((s) => s.closeSheet);
  return <Sheet open={open} onClose={close} title="Power" subtitle="NEPA, your generator and your inverter" size="tall"><PowerPanel /></Sheet>;
}

// ---------------------------------------------------------------------------------------------- pop-ups
const TOASTS: Record<string, true> = { outage_gen_on: true, outage_inverter: true, battery_empty: true, bm_unlocked: true };

function ackOf(n: PowerNotice): Promise<unknown> {
  const kind = n.kind.startsWith('outage') ? 'outage' : n.kind.startsWith('back') ? 'back' : n.kind === 'fuel_empty' ? 'fuel' : n.kind === 'battery_empty' ? 'batt' : 'bm';
  return powerAck(kind, n.key).catch(() => undefined);
}

function PowerCard({ n, d, onDone }: { n: PowerNotice; d: PowerStatus; onDone: () => void }) {
  const [busy, setBusy] = useState(false);
  const g = d.backup.generator ?? null;
  const city = Boolean(d.city);
  const done = () => { void ackOf(n); onDone(); };
  const act = async (fn: () => Promise<unknown>, ok?: string) => {
    setBusy(true);
    try { await fn(); if (ok) toast(ok, 'good'); void usePower.getState().load().catch(() => undefined); void useGame.getState().refresh(); done(); }
    catch (e) { toast(errorMessage(e), 'bad'); if (e instanceof GameError && e.hint === 'no_fuel') { done(); goToStation(); } } finally { setBusy(false); }
  };
  const k = n.kind;
  let icon = '🕯️'; let title = city ? 'NEPA don take light for all of Benin' : 'NEPA don take light'; let kicker = d.area?.name ?? 'Benin';
  let body = ''; let actions: React.ReactNode = null; let tone: 'default' | 'bad' | 'good' = 'default';
  if (k === 'outage_none' || k === 'outage_inverter_empty') {
    body = k === 'outage_none' ? 'You no get generator or inverter. The room is dark and sleep will give you less rest.' : 'Your inverter battery is flat, so the room is dark.';
    actions = (<>
      <button type="button" className="mm-choice is-main" onClick={() => { done(); openBuyBackup(); }}><span className="mm-choice__label">Buy a backup</span></button>
      <button type="button" className="mm-choice" onClick={done}><span className="mm-choice__label">OK</span></button></>);
  } else if (k === 'outage_gen') {
    body = `Turn on your generator? Fuel: ${g?.fuel_l.toFixed(1)} of ${g?.tank_l} litres${g?.hours_left ? ` (about ${hoursLabel(g.hours_left)})` : ''}.`;
    actions = (<>
      <button type="button" className="mm-choice is-main" disabled={busy} onClick={() => void act(() => powerGenToggle(true), 'Generator on.')}><span className="mm-choice__label">{busy ? '...' : 'Turn on'}</span></button>
      <button type="button" className="mm-choice" onClick={done}><span className="mm-choice__label">Not now</span></button></>);
  } else if (k === 'outage_nofuel') {
    body = 'Your generator no get fuel. Buy petrol or diesel at a filling station, then pour it in from the Power sheet.';
    actions = (<>
      <button type="button" className="mm-choice is-main" onClick={() => { done(); goToStation(); }}><span className="mm-choice__label">Find a filling station</span></button>
      <button type="button" className="mm-choice" onClick={done}><span className="mm-choice__label">OK</span></button></>);
  } else if (k === 'fuel_empty') {
    icon = '⛽'; title = 'Your fuel don finish'; kicker = g?.name ?? 'Generator'; body = 'The generator stopped. Buy fuel and pour it in to get light again.'; tone = 'bad';
    actions = (<>
      <button type="button" className="mm-choice is-main" onClick={() => { done(); goToStation(); }}><span className="mm-choice__label">Buy fuel</span></button>
      <button type="button" className="mm-choice" onClick={done}><span className="mm-choice__label">OK</span></button></>);
  } else if (k === 'back' || k === 'back_gen_on') {
    icon = '💡'; title = 'Light don come back'; tone = 'good'; kicker = d.area?.name ?? 'Benin';
    body = k === 'back_gen_on' ? 'NEPA don bring light. Your generator is still running and burning fuel. Switch it off.' : 'NEPA don bring light. Make we thank God.';
    actions = k === 'back_gen_on' ? (<>
      <button type="button" className="mm-choice is-main" disabled={busy} onClick={() => void act(() => powerGenToggle(false), 'Generator off.')}><span className="mm-choice__label">{busy ? '...' : 'Switch it off'}</span></button>
      <button type="button" className="mm-choice" onClick={done}><span className="mm-choice__label">Later</span></button></>)
      : <button type="button" className="mm-choice is-main" onClick={done}><span className="mm-choice__label">OK</span></button>;
  }
  return (
    <Modal open dismissable={false} onClose={() => undefined} tone={tone}
      art={<div className="bcast-art mm-art" aria-hidden>{icon}</div>}
      title={<span className="bcast-title"><small className="bcast-kicker">{kicker}</small>{title}</span>}
      actions={<div className="mm-actions" data-power-card data-testid="power-card" data-kind={k}><div className="mm-choices">{actions}</div></div>}>
      <p className="bcast-body mm-body" data-power-card>{body}</p>
    </Modal>
  );
}

/** Mounted once on the game screen. Starts the power poll, shows the notices the server brings: a card, or a quiet toast. */
export function PowerHost() {
  useEffect(() => startPower(), []);
  const d = usePower((s) => s.data);
  const handled = useRef<Set<string>>(new Set());
  const [tick, bump] = useState(0);
  // eslint-disable-next-line react-hooks/exhaustive-deps
  const next = useMemo(() => (d?.notices ?? []).find((n) => !handled.current.has(n.kind + ':' + n.key)) ?? null, [d, tick]);
  const card = next && !TOASTS[next.kind] ? next : null;
  const held = useHeld(!!card, '[data-power-card]');
  const scene = useGame((s) => s.state?.location?.scene);
  const spray = scene === 'club' || scene === 'lounge';
  useEffect(() => {
    if (!next || !d || !TOASTS[next.kind] || held || spray) return;
    handled.current.add(next.kind + ':' + next.key);
    if (next.kind === 'outage_inverter') {
      const h = d.hours_left ?? d.backup.inverter?.hours_left;
      toast(`🔋 Inverter don take over.${h ? ` About ${hoursLabel(h)} left.` : ''}`, 'info');
    } else if (next.kind === 'outage_gen_on') toast('⛽ NEPA don take light. Your generator is running.', 'info');
    else if (next.kind === 'battery_empty') toast('🔋 Battery don finish. The room is dark.', 'bad');
    else if (next.kind === 'bm_unlocked') toast('🤫 Somebody whispered about a yard at Ogida that opens after dark.', 'info');
    void ackOf(next);
    bump((x) => x + 1);
  }, [next, d, held, spray]);
  if (!card || !d || held || spray) return null;
  return <PowerCard key={card.kind + card.key} n={card} d={d} onDone={() => { handled.current.add(card.kind + ':' + card.key); bump((x) => x + 1); }} />;
}
