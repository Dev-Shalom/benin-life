// Houses -> Buy: every area has a price for each home type. Tap one for the whole bill (price + agent + legal) before paying.
import { useEffect, useMemo, useRef, useState } from 'react';
import { propertyBuy, propertyQuoteBuy, type PropBuyQuote, type PropOffer, type PropOverview, type PropType } from '../../../../api/property';
import { errorMessage } from '../../../../lib/api';
import { naira, nairaShort } from '../../../../lib/format';
import { useProperty } from '../../../../state/property';
import { Button, EmptyState, toast } from '../../../../ui';
import { KIND_LABEL, QuoteRow, PSheet } from './util';

export default function BuyTab({ data, onBought }: { data: PropOverview; onBought: () => void }) {
  const [area, setArea] = useState<string>('all');
  const [kind, setKind] = useState<string>('all');
  const [pick, setPick] = useState<PropOffer | null>(null);
  const types = useMemo(() => new Map(data.types.map((t) => [t.id, t])), [data.types]);
  const areas = useMemo(() => new Map(data.areas.map((a) => [a.id, a])), [data.areas]);
  const kinds = useMemo(() => Array.from(new Set(data.types.map((t) => t.kind))), [data.types]);

  const rows = useMemo(() => data.offers
    .filter((o) => (area === 'all' || o.area === area) && (kind === 'all' || types.get(o.type_id)?.kind === kind))
    .sort((a, b) => a.price - b.price), [data.offers, area, kind, types]);

  const cheapest = (id: string) => {
    const xs = data.offers.filter((o) => o.area === id);
    return xs.length ? Math.min(...xs.map((o) => o.price)) : null;
  };

  return (
    <div className="pp-tab" data-testid="prop-buy">
      <p className="pp-lead">
        Buy a home and it is yours. <b>No weekly rent</b>, but you still pay the house bill and ground rent. Sell it back any time
        for {data.settings.resale_pct}% of its value, or let it out to other players.
      </p>
      {!data.buy_enabled && <p className="pp-note">Buying homes is paused right now.</p>}
      <div className="pp-chips" role="tablist" aria-label="Area">
        <button type="button" className={`pp-chip${area === 'all' ? ' is-on' : ''}`} onClick={() => setArea('all')}>All areas</button>
        {data.areas.map((a) => {
          const c = cheapest(a.id);
          return c == null ? null : (
            <button key={a.id} type="button" className={`pp-chip${area === a.id ? ' is-on' : ''}`} onClick={() => setArea(a.id)}>
              {a.name}<small>from {nairaShort(c)}</small>
            </button>
          );
        })}
      </div>
      <div className="pp-chips pp-chips--sm" role="tablist" aria-label="Type">
        <button type="button" className={`pp-chip${kind === 'all' ? ' is-on' : ''}`} onClick={() => setKind('all')}>Any type</button>
        {kinds.map((k) => (
          <button key={k} type="button" className={`pp-chip${kind === k ? ' is-on' : ''}`} onClick={() => setKind(k)}>{KIND_LABEL[k] ?? k}</button>
        ))}
      </div>
      {area !== 'all' && <p className="pp-area-blurb">{areas.get(area)?.blurb}</p>}
      {rows.length === 0 ? (
        <EmptyState icon="home" title="Nothing for sale here" body="Try another area or type of home." />
      ) : (
        <div className="pp-list">
          {rows.map((o) => {
            const t = types.get(o.type_id);
            return (
              <button key={o.id} type="button" className="pp-card" onClick={() => setPick(o)} disabled={!data.buy_enabled}>
                <span className="pp-card__icon" aria-hidden>{t?.emoji ?? '🏠'}</span>
                <span className="pp-card__main">
                  <b>{t?.name}</b>
                  <small>{areas.get(o.area)?.name} · {t?.bedrooms} bedroom{t?.bedrooms === 1 ? '' : 's'} · {t?.m2} m²</small>
                  <small className="pp-card__rent">Could rent for about {nairaShort(o.rent_market)} a week</small>
                </span>
                <span className="pp-card__price" title={naira(o.price)}>{nairaShort(o.price)}<small>+ {nairaShort(o.agent + o.legal)} fees</small></span>
              </button>
            );
          })}
        </div>
      )}
      <BuySheet offer={pick} type={pick ? types.get(pick.type_id) : undefined} areaName={pick ? areas.get(pick.area)?.name ?? '' : ''}
        data={data} onClose={() => setPick(null)} onBought={() => { setPick(null); onBought(); }} />
    </div>
  );
}

function BuySheet({ offer, type, areaName, data, onClose, onBought }: {
  offer: PropOffer | null; type?: PropType; areaName: string; data: PropOverview; onClose: () => void; onBought: () => void;
}) {
  const [quote, setQuote] = useState<PropBuyQuote | null>(null);
  const [busy, setBusy] = useState(false);
  const afterAction = useProperty((s) => s.afterAction);
  const closeRef = useRef(onClose);
  closeRef.current = onClose;
  useEffect(() => {
    setQuote(null);
    if (!offer) return undefined;
    let alive = true;
    propertyQuoteBuy(offer.id).then((q) => alive && setQuote(q)).catch((e) => { if (alive) { toast(errorMessage(e), 'bad'); closeRef.current(); } });
    return () => { alive = false; };
  }, [offer]);

  const buy = async () => {
    if (!offer) return;
    setBusy(true);
    try {
      const r = await propertyBuy(offer.id);
      toast(r.message, 'good');
      await afterAction();
      onBought();
    } catch (e) {
      toast(errorMessage(e), 'bad');
    } finally {
      setBusy(false);
    }
  };

  const s = data.settings;
  const resale = offer ? Math.floor(offer.price * s.resale_pct / 100) : 0;
  const resaleNet = resale - Math.round(resale * s.sell_agent_pct / 100);
  return (
    <PSheet open={Boolean(offer)} onClose={busy ? () => {} : onClose} title={type ? `${type.emoji} ${type.name}` : 'Buy a home'} subtitle={areaName}
      footer={offer && (
        <div className="garage-sheet__foot">
          <Button block variant="green" loading={busy} disabled={!quote?.can_buy} onClick={() => void buy()}>
            {quote ? `Buy for ${naira(quote.total)}` : 'Getting your quote…'}
          </Button>
          <Button block variant="ghost" disabled={busy} onClick={onClose}>Not now</Button>
        </div>
      )}>
      {offer && (
        <div className="pp-sheet">
          {type && <p className="pp-lead">{type.blurb} {type.bedrooms} bedroom{type.bedrooms === 1 ? '' : 's'}, about {type.m2} m².</p>}
          <div className="pp-q" aria-label="Your quote">
            <QuoteRow label="Price" value={naira(offer.price)} />
            <QuoteRow label="Agent fee" hint={`${s.agent_fee_pct}% of the price`} value={naira(offer.agent)} />
            <QuoteRow label="Legal and documentation" hint={`${s.legal_fee_pct}% (deed, survey, registration)`} value={naira(offer.legal)} />
            <QuoteRow label="You pay" strong value={naira(offer.total)} />
          </div>
          {quote && !quote.can_buy && quote.reason && <p className="pp-note pp-note--bad">{quote.reason}</p>}
          {quote && <p className="pp-hint">You have {naira(quote.have)} (bank first, then cash).</p>}
          <ul className="pp-bullets">
            <li><b>No rent.</b> Move in free, or let it out for about {naira(offer.rent_market)} a week.</li>
            <li>You still pay the weekly house bill and ground rent (a small share of its value).</li>
            <li>Sell it back for about <b>{naira(resaleNet)}</b> after the agent ({s.resale_pct}% of the value). The fees above are not refunded.</li>
          </ul>
        </div>
      )}
    </PSheet>
  );
}
