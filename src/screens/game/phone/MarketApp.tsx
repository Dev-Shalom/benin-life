// Phone "Benin Market" (R9, docs/MARKET.md): players buy from and sell to each other.
// Browse (kind / price / search / sort), My listings (cancel, answer offers), My offers (withdraw). Selling starts from the
// Bag, Cars, My items and Invest land ("Sell to players"); this app lists what is already on the market.
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  dropMarketInfoCache, leftText, marketBrowse, marketBuy, marketCancel, marketInfo, marketMine, marketOffer, marketOfferCancel,
  marketOfferRespond, marketReport, type MarketInfo, type MarketKind, type MarketListing, type MarketMine, type MarketSort,
} from '../../../api/market';
import { errorMessage } from '../../../lib/api';
import { naira, nairaShort } from '../../../lib/format';
import { useGame } from '../../../state/game';
import { Thumb } from '../../../art/thumbs/Thumb';
import { Button, EmptyState, Modal, Tabs, toast } from '../../../ui';
import '../market.css';

type Tab = 'browse' | 'mine' | 'offers';
const KINDS: { id: MarketKind | ''; label: string }[] = [
  { id: '', label: 'All' }, { id: 'item', label: 'Items' }, { id: 'furniture', label: 'Furniture' }, { id: 'car', label: 'Cars' }, { id: 'land', label: 'Land' },
];
const SORTS: { id: MarketSort; label: string }[] = [
  { id: 'new', label: 'Newest' }, { id: 'price_asc', label: 'Cheapest' }, { id: 'price_desc', label: 'Dearest' }, { id: 'deal', label: 'Best deal' },
];
const KIND_EMOJI: Record<MarketKind, string> = { item: '🎒', furniture: '🛋️', car: '🚗', land: '🏞️' };

function Pic({ l }: { l: Pick<MarketListing, 'kind' | 'ref' | 'icon'> }) {
  const fallback = <span className="mk-pic__emoji" aria-hidden>{l.icon || KIND_EMOJI[l.kind]}</span>;
  return (
    <span className="mk-pic">
      {l.kind === 'car' ? <Thumb spec={{ type: 'car', id: l.ref }} fallback={fallback} className="mk-pic__thumb" /> : fallback}
    </span>
  );
}

function DealBadge({ pct }: { pct: number | null }) {
  if (pct == null) return null;
  const tone = pct <= 85 ? 'good' : pct >= 120 ? 'dear' : 'fair';
  return <span className={`mk-deal mk-deal--${tone}`} title="Price compared with what it is worth">{pct}% of value</span>;
}

function Card({ l, onOpen }: { l: MarketListing; onOpen: (l: MarketListing) => void }) {
  return (
    <button type="button" className="mk-card" onClick={() => onOpen(l)} data-testid="market-card">
      <Pic l={l} />
      <span className="mk-card__main">
        <span className="mk-card__title">{l.title}</span>
        <span className="mk-card__cond">{l.cond}</span>
        <span className="mk-card__meta">
          <span>@{l.seller}</span>
          {l.private && <span className="mk-tag mk-tag--private">Private</span>}
          {l.open_to_offers && <span className="mk-tag">Offers</span>}
          <span className="mk-card__time">{leftText(l.expires_at)} left</span>
        </span>
      </span>
      <span className="mk-card__price">
        <b>{nairaShort(l.price)}</b>
        <DealBadge pct={l.pct} />
      </span>
    </button>
  );
}

// ------------------------------------------------------------------------------------------------ buy / offer / report
function ListingSheet({ l, info, onClose, onDone }: { l: MarketListing; info: MarketInfo | null; onClose: () => void; onDone: () => void }) {
  const profile = useGame((s) => s.state?.profile);
  const [mode, setMode] = useState<'view' | 'offer' | 'report'>('view');
  const [amount, setAmount] = useState(String(Math.round(l.price * 0.9)));
  const [reason, setReason] = useState('');
  const [busy, setBusy] = useState(false);
  const money = (profile?.cash ?? 0) + Math.max(0, profile?.bank ?? 0);
  const minOffer = Math.ceil((l.price * (info?.min_offer_pct ?? 50)) / 100);
  const n = Number(amount) || 0;
  const offerOk = n >= minOffer && n < l.price && n <= money;

  const run = async (fn: () => Promise<{ message: string }>, close = true) => {
    setBusy(true);
    try {
      const r = await fn();
      toast(r.message, 'good');
      dropMarketInfoCache();
      await useGame.getState().refresh();
      onDone();
      if (close) onClose();
    } catch (e) {
      toast(errorMessage(e), 'bad');
    } finally {
      setBusy(false);
    }
  };

  return (
    <Modal open onClose={() => !busy && onClose()} title={l.title}
      art={<span className="mk-sheet__art"><Pic l={l} /></span>}
      actions={mode === 'view' ? (
        <>
          <Button variant="ghost" disabled={busy} onClick={onClose}>Close</Button>
          {l.open_to_offers && !l.my_offer && <Button variant="ghost" disabled={busy} onClick={() => setMode('offer')}>Make an offer</Button>}
          <Button variant="gold" loading={busy} disabled={money < l.price} onClick={() => void run(() => marketBuy(l.id, l.price))} data-testid="market-confirm-buy">
            {money < l.price ? 'Not enough money' : `Buy for ${naira(l.price)}`}
          </Button>
        </>
      ) : mode === 'offer' ? (
        <>
          <Button variant="ghost" disabled={busy} onClick={() => setMode('view')}>Back</Button>
          <Button variant="gold" loading={busy} disabled={!offerOk} onClick={() => void run(() => marketOffer(l.id, n))} data-testid="market-send-offer">Send offer {n > 0 ? naira(n) : ''}</Button>
        </>
      ) : (
        <>
          <Button variant="ghost" disabled={busy} onClick={() => setMode('view')}>Back</Button>
          <Button variant="danger" loading={busy} onClick={() => void run(() => marketReport(l.id, reason))}>Send report</Button>
        </>
      )}>
      <div className="mk-sheet">
        <div className="sell-dialog__row"><span>Seller</span><b>@{l.seller}</b></div>
        <div className="sell-dialog__row"><span>Condition</span><span>{l.cond}</span></div>
        <div className="sell-dialog__row"><span>Asking price</span><b>{naira(l.price)}</b></div>
        <div className="sell-dialog__row"><span>Worth about</span><span>{naira(l.value)} <DealBadge pct={l.pct} /></span></div>
        <div className="sell-dialog__row"><span>Ends in</span><span>{leftText(l.expires_at)}</span></div>
        {l.private && <p className="mk-sheet__note">Private deal: only you can see this listing.</p>}
        {l.my_offer && <p className="mk-sheet__note">Your offer of {naira(l.my_offer.amount)} is waiting for @{l.seller}.</p>}
        {mode === 'view' && (
          <>
            <p className="sell-dialog__note">
              You pay from your bank first, then cash. It lands in your {l.kind === 'item' ? 'Bag' : l.kind === 'car' ? 'garage' : l.kind === 'furniture' ? 'My items (place it at home)' : 'land holdings'}.
              You have {naira(money)}.
            </p>
            <button type="button" className="mk-link" onClick={() => setMode('report')}>Report this listing</button>
          </>
        )}
        {mode === 'offer' && (
          <>
            <label className="mk-sell__price">
              <span>Your offer</span>
              <input className="input" inputMode="numeric" enterKeyHint="done" autoComplete="off" value={amount} aria-label="Your offer in naira"
                onChange={(e) => setAmount(e.target.value.replace(/[^0-9]/g, '').replace(/^0+(?=\d)/, '').slice(0, 13))} />
            </label>
            <p className={`mk-sell__range${n && !offerOk ? ' is-bad' : ''}`}>
              {n >= l.price ? 'An offer must be below the price. To pay the full price, just buy.' : n && n < minOffer ? `Lowest offer is ${naira(minOffer)}.` : n > money ? 'You do not have that much yet.' : `Between ${naira(minOffer)} and ${naira(l.price - 1)}. The seller can accept or decline.`}
            </p>
          </>
        )}
        {mode === 'report' && (
          <label className="mk-sell__price">
            <span>What is wrong? (optional)</span>
            <input className="input" enterKeyHint="send" autoComplete="off" maxLength={200} value={reason} aria-label="Reason for the report" onChange={(e) => setReason(e.target.value)} />
          </label>
        )}
      </div>
    </Modal>
  );
}

// ------------------------------------------------------------------------------------------------ browse
function Browse({ info, onChanged }: { info: MarketInfo | null; onChanged: () => void }) {
  const [kind, setKind] = useState<MarketKind | ''>('');
  const [search, setSearch] = useState('');
  const [sort, setSort] = useState<MarketSort>('new');
  const [max, setMax] = useState('');
  const [rows, setRows] = useState<MarketListing[] | null>(null);
  const [total, setTotal] = useState(0);
  const [err, setErr] = useState('');
  const [open, setOpen] = useState<MarketListing | null>(null);
  const seq = useRef(0);

  const load = useCallback(async () => {
    const my = ++seq.current;
    try {
      const r = await marketBrowse({ kind, search, sort, max: max ? Number(max) : null });
      if (my !== seq.current) return;
      setRows(r.rows); setTotal(r.total); setErr('');
    } catch (e) {
      if (my === seq.current) setErr(errorMessage(e));
    }
  }, [kind, search, sort, max]);

  useEffect(() => {
    const t = window.setTimeout(() => void load(), search ? 280 : 0);
    return () => window.clearTimeout(t);
  }, [load, search]);

  return (
    <div className="mk-browse">
      <Tabs tabs={KINDS.map((k) => ({ id: k.id || 'all', label: k.label }))} value={kind || 'all'} onChange={(id) => setKind(id === 'all' ? '' : (id as MarketKind))} className="mk-kinds" />
      <div className="mk-filters">
        <input className="input mk-search" type="search" enterKeyHint="search" autoComplete="off" placeholder="Search things or sellers" value={search} aria-label="Search the market"
          onChange={(e) => setSearch(e.target.value.slice(0, 40))} />
        <div className="mk-filters__row">
          <label className="mk-select">
            <span className="sr-only">Sort</span>
            <select className="input" value={sort} aria-label="Sort by" onChange={(e) => setSort(e.target.value as MarketSort)}>
              {SORTS.map((s) => <option key={s.id} value={s.id}>{s.label}</option>)}
            </select>
          </label>
          <input className="input mk-max" inputMode="numeric" enterKeyHint="done" autoComplete="off" placeholder="Max price ₦" value={max} aria-label="Highest price in naira"
            onChange={(e) => setMax(e.target.value.replace(/[^0-9]/g, '').slice(0, 13))} />
        </div>
      </div>
      {err && <p className="mk-err" role="alert">{err} <button type="button" className="mk-link" onClick={() => void load()}>Try again</button></p>}
      {!rows && !err && <div className="panel-skel"><span /><span /><span /></div>}
      {rows && rows.length === 0 && (
        <EmptyState icon="bag" title="Nothing here yet" body="Nobody is selling that right now. Sell your own from your Bag, Cars, My items or Invest, with Sell to players." />
      )}
      {rows && rows.length > 0 && (
        <>
          <p className="mk-count">{total} for sale</p>
          <div className="mk-list">{rows.map((l) => <Card key={l.id} l={l} onOpen={setOpen} />)}</div>
        </>
      )}
      {open && <ListingSheet l={open} info={info} onClose={() => setOpen(null)} onDone={() => { void load(); onChanged(); }} />}
    </div>
  );
}

// ------------------------------------------------------------------------------------------------ mine
function Mine({ data, reload }: { data: MarketMine | null; reload: () => void }) {
  const [busy, setBusy] = useState<string | null>(null);
  const run = async (key: string, fn: () => Promise<{ message: string }>) => {
    setBusy(key);
    try {
      const r = await fn();
      toast(r.message, 'good');
      dropMarketInfoCache();
      await useGame.getState().refresh();
      reload();
    } catch (e) {
      toast(errorMessage(e), 'bad');
      reload();
    } finally { setBusy(null); }
  };
  if (!data) return <div className="panel-skel"><span /><span /><span /></div>;
  const active = data.listings.filter((l) => l.status === 'active');
  const closed = data.listings.filter((l) => l.status !== 'active');
  return (
    <div className="mk-mine">
      {data.offers_in.length > 0 && (
        <section className="mk-section">
          <h4>Offers on your things</h4>
          {data.offers_in.map((o) => (
            <div key={o.id} className="mk-offer" data-testid="market-offer-in">
              <span className="mk-offer__text"><b>@{o.buyer}</b> offers <b>{naira(o.amount)}</b> for {o.title}<small>You are asking {naira(o.price)}. Ends in {leftText(o.expires_at)}.</small></span>
              <span className="mk-offer__btns">
                <Button size="sm" variant="ghost" loading={busy === `d${o.id}`} onClick={() => void run(`d${o.id}`, () => marketOfferRespond(o.id, false))}>Decline</Button>
                <Button size="sm" variant="green" loading={busy === `a${o.id}`} onClick={() => void run(`a${o.id}`, () => marketOfferRespond(o.id, true))} data-testid="market-accept">Accept</Button>
              </span>
            </div>
          ))}
        </section>
      )}
      <section className="mk-section">
        <h4>On the market ({active.length})</h4>
        {active.length === 0 && <p className="muted">You have nothing listed. Open your Bag, Cars, My items or Invest and tap Sell to players.</p>}
        {active.map((l) => (
          <div key={l.id} className="mk-card mk-card--mine">
            <Pic l={l} />
            <span className="mk-card__main">
              <span className="mk-card__title">{l.title}</span>
              <span className="mk-card__cond">{l.cond}</span>
              <span className="mk-card__meta">
                {l.private && <span className="mk-tag mk-tag--private">Private to @{l.private_to}</span>}
                {l.open_to_offers && <span className="mk-tag">Offers{l.offers ? ` (${l.offers})` : ''}</span>}
                {l.reports > 0 && <span className="mk-tag mk-tag--warn">{l.reports} report{l.reports > 1 ? 's' : ''}</span>}
                <span className="mk-card__time">{leftText(l.expires_at)} left</span>
              </span>
            </span>
            <span className="mk-card__price">
              <b>{nairaShort(l.price)}</b>
              <Button size="sm" variant="ghost" loading={busy === `c${l.id}`} onClick={() => void run(`c${l.id}`, () => marketCancel(l.id))}>Take down</Button>
            </span>
          </div>
        ))}
      </section>
      {closed.length > 0 && (
        <section className="mk-section">
          <h4>Recently ended</h4>
          {closed.map((l) => (
            <div key={l.id} className="mk-row">
              <Pic l={l} />
              <span className="grow"><b>{l.title}</b><small>{l.status === 'sold' ? `Sold for ${naira(l.sold_price)} (fee ${naira(l.fee)})` : l.status === 'expired' ? 'Expired, it came back to you' : l.status === 'removed' ? 'Removed by an admin, returned to you' : 'Taken down'}</small></span>
            </div>
          ))}
        </section>
      )}
      {data.history.length > 0 && (
        <section className="mk-section">
          <h4>Your trades</h4>
          {data.history.map((t) => (
            <div key={t.id} className="mk-row mk-row--plain">
              <span className="grow"><b>{t.title}</b><small>{t.side === 'sold' ? 'Sold to' : 'Bought from'} @{t.other}</small></span>
              <b className={t.side === 'sold' ? 'is-up' : ''}>{t.side === 'sold' ? '+' : '−'}{naira(t.price)}</b>
            </div>
          ))}
        </section>
      )}
    </div>
  );
}

function Offers({ data, reload }: { data: MarketMine | null; reload: () => void }) {
  const [busy, setBusy] = useState<number | null>(null);
  if (!data) return <div className="panel-skel"><span /><span /></div>;
  if (data.offers_out.length === 0) return <EmptyState icon="bag" title="No offers yet" body="Open a listing that says Offers, and tap Make an offer to try a lower price." />;
  const cancel = async (id: number) => {
    setBusy(id);
    try { toast((await marketOfferCancel(id)).message, 'good'); } catch (e) { toast(errorMessage(e), 'bad'); } finally { setBusy(null); reload(); }
  };
  return (
    <div className="mk-mine">
      <section className="mk-section">
        {data.offers_out.map((o) => (
          <div key={o.id} className="mk-offer" data-testid="market-offer-out">
            <span className="mk-offer__text"><b>{naira(o.amount)}</b> for {o.title}<small>@{o.seller} asks {naira(o.price)}. {o.status === 'pending' ? `Waiting, ends in ${leftText(o.expires_at)}.` : o.status === 'accepted' ? 'Accepted. It is yours.' : o.status === 'declined' ? 'Declined.' : o.status === 'expired' ? 'Expired.' : 'Closed.'}</small></span>
            {o.status === 'pending' && <Button size="sm" variant="ghost" loading={busy === o.id} onClick={() => void cancel(o.id)}>Withdraw</Button>}
          </div>
        ))}
      </section>
    </div>
  );
}

export default function MarketApp() {
  const [tab, setTab] = useState<Tab>('browse');
  const [info, setInfo] = useState<MarketInfo | null>(null);
  const [mine, setMine] = useState<MarketMine | null>(null);
  const [err, setErr] = useState('');
  const loadMine = useCallback(() => { marketMine().then(setMine).catch((e) => setErr(errorMessage(e))); }, []);
  const loadInfo = useCallback(() => { marketInfo().then(setInfo).catch((e) => setErr(errorMessage(e))); }, []);
  useEffect(() => { loadInfo(); loadMine(); }, [loadInfo, loadMine]);
  const pending = (mine?.offers_in.length ?? 0);
  const tabs = useMemo(() => [
    { id: 'browse', label: 'Browse' },
    { id: 'mine', label: 'My listings', badge: pending || null },
    { id: 'offers', label: 'My offers', badge: mine?.offers_out.filter((o) => o.status === 'pending').length || null },
  ], [pending, mine]);
  return (
    <div className="phone-app__body mk-app">
      {info && !info.enabled && <p className="mk-err" role="status">Benin Market is closed for now. You can still take your listings down.</p>}
      <Tabs tabs={tabs} value={tab} onChange={(id) => { setTab(id as Tab); loadMine(); }} className="mk-tabs" />
      {err && !mine && <p className="mk-err" role="alert">{err}</p>}
      {tab === 'browse' && <Browse info={info} onChanged={() => { loadMine(); loadInfo(); }} />}
      {tab === 'mine' && <Mine data={mine} reload={() => { loadMine(); loadInfo(); }} />}
      {tab === 'offers' && <Offers data={mine} reload={loadMine} />}
      {info && (
        <p className="mk-foot">
          Sell from your Bag, Cars, My items or Invest. {info.active}/{info.max_active} listed · {info.daily_used}/{info.daily_cap} today.
        </p>
      )}
    </div>
  );
}
