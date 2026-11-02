// Filling stations (docs/POWER.md part 2) and the black market yard (part 3).
// FuelStrip: the pump attendant's line, today's petrol and diesel price and the queue, on the place card of a station. The fuel itself is
// bought from the normal shop list of the place (shop_buy), so a player-owned Filling station works the same way.
// YardStrip + YardSheet: the hidden yard. A dark panel: every deal shows its price and its risks, cash only, night only.
import { useCallback, useEffect, useState } from 'react';
import { bmBuy, bmStatus, fuelStationInfo, type BmDeal, type BmOffer, type BmStatus, type FuelStationInfo } from '../../api/power';
import { errorMessage } from '../../lib/api';
import { naira } from '../../lib/format';
import { useGame } from '../../state/game';
import { Button, Sheet, toast } from '../../ui';
import './Power.css';

export function FuelStrip({ locId, compact = false }: { locId: string; compact?: boolean }) {
  const rec = useGame((s) => s.locationsById[locId]);
  const isStation = locId.startsWith('fs_') || rec?.biz_type === 'filling_station';
  const [info, setInfo] = useState<FuelStationInfo | null>(null);
  useEffect(() => {
    if (!isStation) { setInfo(null); return; }
    let alive = true;
    fuelStationInfo(locId).then((r) => alive && setInfo(r)).catch(() => alive && setInfo(null));
    return () => { alive = false; };
  }, [locId, isStation]);
  if (!isStation || !info?.station) return null;
  const diff = info.petrol && info.yesterday ? info.petrol - info.yesterday : 0;
  const mood = info.state === 'dry' ? 'dry' : info.state === 'scarce' ? 'scarce' : 'normal';
  return (
    <section className={`fs-strip fs-strip--${mood}`} data-testid="fuel-strip">
      <div className="fs-strip__att">
        <span className="fs-strip__face" aria-hidden>🧑🏾‍🔧</span>
        <p className="fs-strip__line">&ldquo;{info.line}&rdquo;<small>Pump attendant{info.owner ? ` · owned by @${info.owner}` : ''}</small></p>
      </div>
      {info.dry ? (
        <p className="fs-strip__dry">No fuel today. Try another station, or ask around after dark.</p>
      ) : !compact && (
        <div className="fs-strip__prices">
          <span><small>Petrol a litre</small><b>{naira(info.petrol ?? 0)}</b>{diff !== 0 && <i className={diff > 0 ? 'is-up' : 'is-down'}>{diff > 0 ? '▲' : '▼'} {naira(Math.abs(diff))}</i>}</span>
          <span><small>Diesel a litre</small><b>{naira(info.diesel ?? 0)}</b></span>
        </div>
      )}
      {info.scarce && <p className="fs-strip__warn">Fuel scarcity: prices are up and the queue is long{info.queue_seconds ? ` (about ${info.queue_seconds} s)` : ''}.</p>}
    </section>
  );
}

const RISK_LABEL = { low: 'Low risk', medium: 'Some risk', high: 'Risky' } as const;

function OfferRow({ o, cash, onBuy, busy }: { o: BmOffer; cash: number; onBuy: (o: BmOffer, qty: number) => void; busy: boolean }) {
  const [qty, setQty] = useState(o.kind === 'grey_fuel' ? 5 : 1);
  const total = o.price * qty;
  return (
    <article className="yd-offer" data-testid={`yard-offer-${o.id}`}>
      <div className="yd-offer__top"><span className="yd-offer__emoji" aria-hidden>{o.emoji}</span>
        <div className="grow"><b>{o.name}</b><small>{o.blurb}</small></div>
        <span className="yd-price">{naira(o.price)}</span></div>
      <div className="yd-risks">
        <span className={`yd-risk yd-risk--${o.risk_level}`}>{RISK_LABEL[o.risk_level]}</span>
        <span>Scam {o.risk.scam_pct}%</span><span>Raid {o.risk.raid_pct}%</span><span>Robbery {o.risk.robbery_pct}%</span>
        {o.risk.faulty_pct > 0 && <span>Faulty {o.risk.faulty_pct}%</span>}
        {o.risk.stolen_pct > 0 && <span>Hot {o.risk.stolen_pct}%</span>}
        <span>Shop price {naira(o.risk.shop_price)}</span>
      </div>
      <div className="yd-offer__buy">
        {o.kind === 'grey_fuel' && (
          <span className="yd-qty">
            <button type="button" aria-label="Fewer litres" onClick={() => setQty((q) => Math.max(1, q - 1))}>-</button>
            <b>{qty} L</b>
            <button type="button" aria-label="More litres" onClick={() => setQty((q) => Math.min(20, q + 1))}>+</button>
          </span>
        )}
        <Button variant="gold" block loading={busy} disabled={cash < total} onClick={() => onBuy(o, qty)}>{cash < total ? `Need ${naira(total)} cash` : `Buy for ${naira(total)}`}</Button>
      </div>
    </article>
  );
}

export function YardSheet({ open, onClose }: { open: boolean; onClose: () => void }) {
  const [st, setSt] = useState<BmStatus | null>(null);
  const [deal, setDeal] = useState<BmDeal | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const load = useCallback(() => { bmStatus().then(setSt).catch(() => undefined); }, []);
  useEffect(() => { if (open) { setDeal(null); load(); } }, [open, load]);
  const buy = async (o: BmOffer, qty: number) => {
    setBusy(o.id);
    try {
      const r = await bmBuy(o.id, qty);
      setDeal(r);
      toast(r.message, r.outcome === 'ok' ? 'good' : r.outcome === 'faulty' ? 'info' : 'bad');
      await useGame.getState().refresh();
      load();
    } catch (e) { toast(errorMessage(e), 'bad'); } finally { setBusy(null); }
  };
  return (
    <Sheet open={open} onClose={onClose} title="The Yard" subtitle="No sign. No receipt. Cash only." size="tall" className="yd-sheet">
      {!st ? <div className="panel-skel"><span /><span /></div> : !st.unlocked ? <p className="yd-line">Nobody told you about any yard.</p> : (
        <div className="yd">
          <p className="yd-line">&ldquo;{st.line}&rdquo;</p>
          {st.hot && st.open && <p className="yd-hot">Police dey around tonight: raids are likelier.</p>}
          {!st.open && <p className="yd-shut">Open from {st.open_hour}:00 to {st.close_hour}:00 at night.</p>}
          {st.open && !st.here && <p className="yd-shut">You are not at the yard. Go to The Yard on the map to buy.</p>}
          {deal && <p className={`yd-deal yd-deal--${deal.outcome}`} data-testid="yard-deal">{deal.message}{deal.cred ? ` (street cred ${deal.cred > 0 ? '+' : ''}${deal.cred})` : ''}</p>}
          {(st.offers ?? []).map((o) => <OfferRow key={o.id} o={o} cash={st.cash ?? 0} busy={busy === o.id} onBuy={(x, q) => void buy(x, q)} />)}
          <p className="yd-foot">Cash on you: {naira(st.cash ?? 0)}. Grey fuel can be adulterated. Tokunbo gear can be faulty or stolen. Police raid sometimes.</p>
        </div>
      )}
    </Sheet>
  );
}

export function YardStrip({ locId }: { locId: string }) {
  const [open, setOpen] = useState(false);
  if (locId !== 'bm_yard') return null;
  return (
    <>
      <button type="button" className="yd-strip" data-testid="yard-open" onClick={() => setOpen(true)}>
        <span aria-hidden>🕶️</span><span className="grow"><b>Open the yard</b><small>Cheap fuel and tokunbo gear. Risky.</small></span>
      </button>
      <YardSheet open={open} onClose={() => setOpen(false)} />
    </>
  );
}
