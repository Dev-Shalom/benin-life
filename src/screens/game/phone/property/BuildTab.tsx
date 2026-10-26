// Houses -> Build: pick where (an area where you own plots from Invest -> Land), pick a design, read the quote, start. The builders
// work in real-time stages; the plots are locked while they work and under the finished house.
import { useEffect, useMemo, useRef, useState } from 'react';
import {
  propertyBuildCancel, propertyBuildStart, propertyQuoteBuild, type PropBuild, type PropBuildQuote, type PropDesign, type PropOverview,
} from '../../../../api/property';
import { errorMessage } from '../../../../lib/api';
import { useNow } from '../../../../lib/clock';
import { naira, nairaShort } from '../../../../lib/format';
import { useProperty } from '../../../../state/property';
import { useUi } from '../../../../state/ui';
import { Button, toast } from '../../../../ui';
import { longDuration, QuoteRow, PSheet } from './util';

function Builders({ b, now, data, onCancel }: { b: PropBuild; now: number; data: PropOverview; onCancel: () => void }) {
  const start = Date.parse(b.started_at);
  const end = Date.parse(b.ready_at);
  const pct = Number.isNaN(start) || Number.isNaN(end) || end <= start ? b.progress : Math.max(0, Math.min(100, ((now - start) / (end - start)) * 100));
  const left = Number.isNaN(end) ? b.seconds_left : Math.max(0, (end - now) / 1000);
  const reload = useProperty((s) => s.load);
  const fired = useRef(false);
  useEffect(() => {
    if (left <= 0 && !fired.current) { fired.current = true; const t = window.setTimeout(() => void reload(), 1500); return () => window.clearTimeout(t); }
    return undefined;
  }, [left, reload]);
  return (
    <div className="pp-build" data-testid="prop-building">
      <div className="pp-build__head">
        <span className="pp-build__scaffold" aria-hidden>🏗️</span>
        <div className="grow">
          <b>{b.emoji} {b.name}</b>
          <small>{b.area_name} · {b.units > 1 ? `${b.units} units · ` : ''}{b.plots} plot{b.plots === 1 ? '' : 's'}</small>
        </div>
        <span className="pp-build__pct">{Math.round(pct)}%</span>
      </div>
      <div className="pp-bar" role="progressbar" aria-valuemin={0} aria-valuemax={100} aria-valuenow={Math.round(pct)} aria-label={`${b.name} progress`}>
        <span style={{ width: `${pct}%` }} />
      </div>
      <ol className="pp-stages">
        {b.stages.map((s) => {
          const e = Date.parse(s.ends_at);
          const st = Date.parse(s.starts_at);
          const state = now >= e ? 'done' : now >= st ? 'now' : 'next';
          return <li key={s.name} className={`is-${state}`}><i aria-hidden>{state === 'done' ? '✓' : ''}</i>{s.name}</li>;
        })}
      </ol>
      <div className="pp-build__foot">
        <span>{left > 0 ? `${b.stage} · about ${longDuration(left)} left` : 'Finishing up…'}</span>
        <button type="button" className="pp-link" onClick={onCancel}>Cancel build</button>
      </div>
      <small className="pp-hint">Cancelling gives back {data.settings.cancel_refund_pct}% of the works ({nairaShort(b.refund)}).</small>
    </div>
  );
}

export default function BuildTab({ data, onStarted }: { data: PropOverview; onStarted: () => void }) {
  const now = useNow(15_000);
  const afterAction = useProperty((s) => s.afterAction);
  const first = data.areas.find((a) => a.can_build && a.land.plots > 0)?.id ?? data.areas.find((a) => a.can_build)?.id ?? 'ekenwan';
  const [area, setArea] = useState<string>(first);
  const [designId, setDesignId] = useState<string>(data.designs[0]?.id ?? '');
  const [quote, setQuote] = useState<PropBuildQuote | null>(null);
  const [busy, setBusy] = useState(false);
  const [cancel, setCancel] = useState<PropBuild | null>(null);
  const [confirm, setConfirm] = useState(false);

  const a = data.areas.find((x) => x.id === area);
  const design: PropDesign | undefined = data.designs.find((d) => d.id === designId);
  useEffect(() => {
    setQuote(null);
    if (!design || !a?.can_build) return undefined;
    let alive = true;
    propertyQuoteBuild(design.id, a.id).then((q) => alive && setQuote(q)).catch(() => undefined);
    return () => { alive = false; };
  }, [design, a?.id, a?.can_build, data.money.bank, data.money.cash, a?.land.free]);

  const types = useMemo(() => new Map(data.types.map((t) => [t.id, t])), [data.types]);
  const start = async () => {
    if (!design || !a) return;
    setBusy(true);
    try {
      const r = await propertyBuildStart(design.id, a.id);
      toast(r.message, 'good');
      setConfirm(false);
      await afterAction();
      onStarted();
    } catch (e) {
      toast(errorMessage(e), 'bad');
    } finally {
      setBusy(false);
    }
  };
  const doCancel = async () => {
    if (!cancel) return;
    setBusy(true);
    try {
      const r = await propertyBuildCancel(cancel.id);
      toast(r.message, 'info');
      setCancel(null);
      await afterAction();
    } catch (e) {
      toast(errorMessage(e), 'bad');
    } finally {
      setBusy(false);
    }
  };

  const stageTimes = design ? design.stages.map((s) => ({ ...s, secs: design.hours * 3600 * s.pct / Math.max(1, design.stages.reduce((t, x) => t + x.pct, 0)) })) : [];
  const need = design?.plots ?? 1;

  return (
    <div className="pp-tab" data-testid="prop-build">
      <p className="pp-lead">
        Build on land you own. Building is <b>very expensive</b>: the plots, the works and a plan approval fee. The builders work for real
        hours, and a finished house is worth only a little more than it cost.
      </p>
      {data.builds.map((b) => <Builders key={b.id} b={b} now={now} data={data} onCancel={() => setCancel(b)} />)}
      {!data.build_enabled && <p className="pp-note">Building is paused right now.</p>}

      <h4 className="pp-h">1. Where? <small>Your plots from Invest, Land</small></h4>
      <div className="pp-chips" role="tablist" aria-label="Area">
        {data.areas.filter((x) => x.can_build).map((x) => (
          <button key={x.id} type="button" className={`pp-chip${area === x.id ? ' is-on' : ''}`} onClick={() => setArea(x.id)}>
            {x.name}<small>{x.land.plots > 0 ? `${x.land.free} free plot${x.land.free === 1 ? '' : 's'}` : 'no plots'}</small>
          </button>
        ))}
      </div>
      {a && (
        <div className="pp-plots">
          <span>You hold <b>{a.land.plots}</b> plot{a.land.plots === 1 ? '' : 's'} in {a.name}{a.land.locked > 0 ? `, ${a.land.locked} under a house or build` : ''}.</span>
          {a.land.plot_price != null && <small>A plot costs about {nairaShort(a.land.plot_price)} today.</small>}
          <button type="button" className="pp-link" onClick={() => useUi.getState().openPhone('bank')}>Buy plots in Bank, Invest, Land</button>
        </div>
      )}

      <h4 className="pp-h">2. What? <small>Cost in {a?.name}</small></h4>
      <div className="pp-list">
        {data.designs.map((d) => (
          <button key={d.id} type="button" className={`pp-card pp-card--pick${designId === d.id ? ' is-picked' : ''}`} onClick={() => setDesignId(d.id)}>
            <span className="pp-card__icon" aria-hidden>{d.emoji}</span>
            <span className="pp-card__main">
              <b>{d.name}</b>
              <small>{d.description}</small>
              <small className="pp-card__rent">
                {d.plots} plot{d.plots === 1 ? '' : 's'}{d.units > 1 ? ` · ${d.units} homes (${types.get(d.type_id)?.name ?? ''})` : ` · ${types.get(d.type_id)?.bedrooms ?? ''} bedrooms`} · about {longDuration(d.hours * 3600)}
              </small>
            </span>
            <span className="pp-card__price" title={naira(d.costs[area] ?? 0)}>{nairaShort(d.costs[area] ?? 0)}<small>works</small></span>
          </button>
        ))}
      </div>

      {design && a && (
        <div className="pp-q" aria-label="Build quote">
          <QuoteRow label="Builders (works)" value={quote ? naira(quote.cost) : '…'} />
          <QuoteRow label="Plan approval" hint={`${data.settings.permit_pct}% of the works, not refunded`} value={quote ? naira(quote.permit) : '…'} />
          <QuoteRow label="You pay now" strong value={quote ? naira(quote.total) : '…'} />
          <QuoteRow label="Plots needed" value={`${need} (you have ${a.land.free} free)`} />
          <QuoteRow label="Time" value={`about ${longDuration(design.hours * 3600)}`} />
        </div>
      )}
      {design && (
        <ol className="pp-stages pp-stages--plan" aria-label="Stages">
          {stageTimes.map((s) => <li key={s.name}><i aria-hidden /> {s.name} <small>{longDuration(s.secs)}</small></li>)}
        </ol>
      )}
      {quote && !quote.can_build && quote.reason && <p className="pp-note pp-note--bad">{quote.reason}</p>}
      <Button block variant="green" disabled={!quote?.can_build || !data.build_enabled} onClick={() => setConfirm(true)}>
        {quote ? `Start building · ${nairaShort(quote.total)}` : 'Start building'}
      </Button>
      <p className="pp-hint">The plots stay locked while the builders work and under the finished house. You can't sell them. When the house is done it is yours to live in, let or sell{design && design.units > 1 ? ` (${design.units} separate homes)` : ''}.</p>

      <PSheet open={confirm} onClose={busy ? () => {} : () => setConfirm(false)} title={design ? `Build a ${design.name.toLowerCase()}?` : 'Build'} subtitle={a?.name}
        footer={<div className="garage-sheet__foot">
          <Button block variant="green" loading={busy} onClick={() => void start()}>{quote ? `Pay ${naira(quote.total)} and start` : 'Start'}</Button>
          <Button block variant="ghost" disabled={busy} onClick={() => setConfirm(false)}>Not now</Button>
        </div>}>
        {quote && design && (
          <div className="pp-sheet">
            <div className="pp-q">
              <QuoteRow label="Builders" value={naira(quote.cost)} />
              <QuoteRow label="Plan approval" value={naira(quote.permit)} />
              <QuoteRow label="Total" strong value={naira(quote.total)} />
            </div>
            <p className="pp-hint">About {longDuration(design.hours * 3600)} of real time, in {design.stages.length} stages. Paid from your bank first, then cash. Cancel while it builds and you get {data.settings.cancel_refund_pct}% of the works back.</p>
          </div>
        )}
      </PSheet>
      <PSheet open={Boolean(cancel)} onClose={busy ? () => {} : () => setCancel(null)} title="Cancel this build?" subtitle={cancel ? `${cancel.name} · ${cancel.area_name}` : ''}
        footer={<div className="garage-sheet__foot">
          <Button block variant="danger" loading={busy} onClick={() => void doCancel()}>Yes, cancel · get {cancel ? nairaShort(cancel.refund) : ''} back</Button>
          <Button block variant="ghost" disabled={busy} onClick={() => setCancel(null)}>Keep building</Button>
        </div>}>
        <p className="pp-hint">You get {data.settings.cancel_refund_pct}% of the works back. The plan approval fee is gone. Your plots are free again.</p>
      </PSheet>
    </div>
  );
}
