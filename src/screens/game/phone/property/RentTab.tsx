// Houses -> Rent: homes from the city landlord (the move-house list), and "For rent by players": homes other players let out, with
// filters by area, price and type, and a clear quote (caution + first week + agent) before you pay.
import { useEffect, useMemo, useRef, useState } from 'react';
import type { HouseOption, HouseOptions } from '../../../../api/houses';
import {
  propertyListings, propertyRent, propertyRentQuote, type PropListing, type PropOverview, type PropRentQuote,
} from '../../../../api/property';
import { errorMessage } from '../../../../lib/api';
import { naira, nairaShort } from '../../../../lib/format';
import { useMove } from '../../../../state/move';
import { useProperty } from '../../../../state/property';
import { useUi } from '../../../../state/ui';
import { Button, EmptyState, Segmented, toast } from '../../../../ui';
import { KIND_LABEL, QuoteRow, PSheet } from './util';

const PRICE_CHIPS: { id: string; label: string; max: number | null }[] = [
  { id: 'any', label: 'Any rent', max: null }, { id: '10k', label: 'to ₦10K', max: 10_000 }, { id: '50k', label: 'to ₦50K', max: 50_000 },
  { id: '250k', label: 'to ₦250K', max: 250_000 }, { id: '1m', label: 'to ₦1M', max: 1_000_000 },
];

export default function RentTab({ data, opts, owed, visiting, onMoved }: {
  data: PropOverview; opts: HouseOptions | null; owed: number; visiting: boolean; onMoved: () => void;
}) {
  const [mode, setMode] = useState<'city' | 'players'>('players');
  const openMove = useMove((s) => s.open);
  return (
    <div className="pp-tab" data-testid="prop-rent">
      <Segmented<'city' | 'players'> label="Who is the landlord" value={mode} onChange={setMode}
        options={[{ id: 'players', label: 'By players' }, { id: 'city', label: 'City landlord' }]} />
      {mode === 'city' && (
        <section className="move-list pp-city" aria-label="Move house">
          <p className="pp-lead">
            Rent a home from the city landlord. The fee is {opts?.move_in_weeks ?? 4} weeks of the new rent (agent, caution and legal).
            Your furniture comes along, and the home you leave stays in Past homes for {opts?.return_days ?? 30} days.
          </p>
          {!opts && <div className="panel-skel"><span /><span /></div>}
          {opts?.homes.map((h: HouseOption) => {
            const mine = h.status === 'current';
            const past = h.status === 'past';
            const disabled = mine || !opts.enabled || visiting || owed > 0;
            return (
              <button key={h.id} type="button" className="garage-opt" disabled={disabled}
                onClick={() => { openMove(h, opts.garage?.name ?? null, opts.move_in_weeks); useUi.getState().setOverlay(null); }}>
                <span className="garage-opt__emoji" aria-hidden>{h.emoji || '🏠'}</span>
                <span className="grow">
                  <span className="garage-opt__title">{h.name}{h.district ? ` · ${h.district}` : ''}</span>
                  <span className="garage-opt__sub">{h.area} m² · {naira(h.weekly_rent)} a week</span>
                  <span className="garage-opt__meta">
                    {mine ? 'Your home' : owed > 0 ? 'Pay your rent first' : visiting ? 'Go home first' : !opts.enabled ? 'Moving is paused'
                      : past ? `Past home: move back${h.past_upgrades > 0 ? `, your ${h.past_upgrades} upgrade${h.past_upgrades === 1 ? '' : 's'} are waiting` : ''}` : h.tag}
                  </span>
                </span>
                {!mine && (
                  <span className="garage-opt__price" title={naira(h.move_in)}>{nairaShort(h.move_in)}<small>{past ? 'to move back' : 'to move in'}</small></span>
                )}
              </button>
            );
          })}
        </section>
      )}
      {mode === 'players' && <PlayerListings data={data} owed={owed} visiting={visiting} onMoved={onMoved} />}
    </div>
  );
}

function PlayerListings({ data, owed, visiting, onMoved }: { data: PropOverview; owed: number; visiting: boolean; onMoved: () => void }) {
  const [area, setArea] = useState<string>('all');
  const [price, setPrice] = useState<string>('any');
  const [kind, setKind] = useState<string>('all');
  const [rows, setRows] = useState<PropListing[] | null>(null);
  const [pick, setPick] = useState<PropListing | null>(null);
  const kinds = useMemo(() => Array.from(new Set(data.types.map((t) => t.kind))), [data.types]);
  const max = PRICE_CHIPS.find((p) => p.id === price)?.max ?? null;
  useEffect(() => {
    let alive = true;
    setRows(null);
    propertyListings(area === 'all' ? null : area, max, kind === 'all' ? null : kind)
      .then((r) => alive && setRows(r.listings)).catch((e) => { if (alive) { setRows([]); toast(errorMessage(e), 'bad'); } });
    return () => { alive = false; };
  }, [area, max, kind, data.owned_count, data.residence?.property.id]);

  return (
    <div className="pp-players" data-testid="prop-listings">
      <p className="pp-lead">Homes other players let out. Rent goes to the landlord every rent day, and you can leave any time. A landlord gives {data.settings.notice_days} days notice to take it back.</p>
      {!data.rent_out_enabled && <p className="pp-note">Renting from players is paused right now.</p>}
      <div className="pp-chips" role="tablist" aria-label="Area">
        <button type="button" className={`pp-chip${area === 'all' ? ' is-on' : ''}`} onClick={() => setArea('all')}>All areas</button>
        {data.areas.map((a) => <button key={a.id} type="button" className={`pp-chip${area === a.id ? ' is-on' : ''}`} onClick={() => setArea(a.id)}>{a.name}</button>)}
      </div>
      <div className="pp-chips pp-chips--sm" role="tablist" aria-label="Price">
        {PRICE_CHIPS.map((p) => <button key={p.id} type="button" className={`pp-chip${price === p.id ? ' is-on' : ''}`} onClick={() => setPrice(p.id)}>{p.label}</button>)}
      </div>
      <div className="pp-chips pp-chips--sm" role="tablist" aria-label="Type">
        <button type="button" className={`pp-chip${kind === 'all' ? ' is-on' : ''}`} onClick={() => setKind('all')}>Any type</button>
        {kinds.map((k) => <button key={k} type="button" className={`pp-chip${kind === k ? ' is-on' : ''}`} onClick={() => setKind(k)}>{KIND_LABEL[k] ?? k}</button>)}
      </div>
      {rows == null ? <div className="panel-skel"><span /><span /></div> : rows.length === 0 ? (
        <EmptyState icon="home" title="No homes for rent here yet" body="Landlords list homes from Houses, My properties. Check back soon, or try another area." />
      ) : (
        <div className="pp-list">
          {rows.map((l) => {
            const diff = l.market_rent > 0 ? Math.round((1 - l.rent / l.market_rent) * 100) : 0;
            return (
              <button key={l.id} type="button" className="pp-card" onClick={() => setPick(l)} disabled={owed > 0 || visiting}>
                <span className="pp-card__icon" aria-hidden>{l.emoji}</span>
                <span className="pp-card__main">
                  <b>{l.type_name}{l.unit_no ? ` (unit ${l.unit_no})` : ''}</b>
                  <small>{l.area_name} · {l.bedrooms} bedroom{l.bedrooms === 1 ? '' : 's'} · {l.m2} m² · @{l.landlord}</small>
                  <span className="pp-tags">
                    {diff >= 5 && <span className="pp-tag is-good">{diff}% under market</span>}
                    {diff <= -5 && <span className="pp-tag is-warn">{-diff}% over market</span>}
                    {l.upgrades > 0 && <span className="pp-tag">{l.upgrades} upgrade{l.upgrades === 1 ? '' : 's'}</span>}
                    {l.garage && <span className="pp-tag">Garage</span>}
                    {l.caution > 0 && <span className="pp-tag">Caution {nairaShort(l.caution)}</span>}
                  </span>
                </span>
                <span className="pp-card__price" title={naira(l.rent)}>{nairaShort(l.rent)}<small>a week</small></span>
              </button>
            );
          })}
        </div>
      )}
      {(owed > 0 || visiting) && <p className="pp-note">{owed > 0 ? 'Pay the rent you owe before you move.' : 'Go home before you move.'}</p>}
      <RentSheet listing={pick} data={data} onClose={() => setPick(null)} onRented={() => { setPick(null); onMoved(); }} />
    </div>
  );
}

function RentSheet({ listing, data, onClose, onRented }: { listing: PropListing | null; data: PropOverview; onClose: () => void; onRented: () => void }) {
  const [q, setQ] = useState<PropRentQuote | null>(null);
  const [busy, setBusy] = useState(false);
  const afterAction = useProperty((s) => s.afterAction);
  const closeRef = useRef(onClose);
  closeRef.current = onClose;
  useEffect(() => {
    setQ(null);
    if (!listing) return undefined;
    let alive = true;
    propertyRentQuote(listing.id).then((x) => alive && setQ(x)).catch((e) => { if (alive) { toast(errorMessage(e), 'bad'); closeRef.current(); } });
    return () => { alive = false; };
  }, [listing]);
  const go = async () => {
    if (!listing) return;
    setBusy(true);
    try {
      const r = await propertyRent(listing.id);
      toast(r.message, 'good');
      useUi.getState().setOverlay(null);
      await afterAction();
      onRented();
    } catch (e) {
      toast(errorMessage(e), 'bad');
    } finally {
      setBusy(false);
    }
  };
  const l = listing;
  return (
    <PSheet open={Boolean(l)} onClose={busy ? () => {} : onClose} title={l ? `Rent: ${l.type_name}` : 'Rent a home'} subtitle={l ? `${l.area_name} · landlord @${l.landlord}` : undefined}
      footer={l && (
        <div className="garage-sheet__foot">
          <Button block variant="green" loading={busy} disabled={!q?.can_rent} onClick={() => void go()}>{q ? `Pay ${naira(q.total)} and move in` : 'Getting your quote…'}</Button>
          <Button block variant="ghost" disabled={busy} onClick={onClose}>Not now</Button>
        </div>
      )}>
      {l && (
        <div className="pp-sheet">
          <div className="pp-q" aria-label="Move-in quote">
            <QuoteRow label="Rent a week" value={naira(l.rent)} hint={`market ${naira(l.market_rent)}`} />
            <QuoteRow label="Caution" hint="paid back when you leave without debts" value={naira(l.caution)} />
            <QuoteRow label={`Rent in advance (${data.settings.advance_weeks} week)`} value={naira(l.advance)} />
            <QuoteRow label="Agent and legal fee" value={naira(l.agent)} />
            <QuoteRow label="You pay now" strong value={naira(l.total)} />
          </div>
          {q && !q.can_rent && q.reason && <p className="pp-note pp-note--bad">{q.reason}</p>}
          {q && <p className="pp-hint">You have {naira(q.have)} (bank first, then cash).</p>}
          <ul className="pp-bullets">
            <li>Then {naira(l.rent)} goes to your landlord every rent day, from your bank first, then cash.</li>
            <li>If you owe {data.settings.evict_owed_weeks} weeks of rent you are moved out and the landlord keeps the caution.</li>
            <li>The landlord cannot enter without your invite, and can't evict you at once: {data.settings.notice_days} days notice. You can leave any time.</li>
            <li>Your furniture comes along. Upgrades in this home belong to the landlord.</li>
          </ul>
        </div>
      )}
    </PSheet>
  );
}
