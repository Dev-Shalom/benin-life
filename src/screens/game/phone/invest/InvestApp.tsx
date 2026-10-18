// I1 Invest & Save (docs/INVEST.md): the Save and Invest tabs of the phone Bank app. Everything is server-authoritative;
// the numbers shown in the buy sheets mirror the server formulas, and the result toast is what the server really did.
import { useEffect, useMemo, useState, type ReactNode } from 'react';
import {
  investBuy, investCollect, investMarketBuy, investMarketSell, investSeries, investWithdraw, landBuy, landLevy, landSell, realLeft,
  type InvestMarket, type InvestOverview, type InvestPosition, type InvestProduct, type LandResult, type Risk,
} from '../../../../api/invest';
import { naira, nairaShort } from '../../../../lib/format';
import { Button, Sheet, toast } from '../../../../ui';
import { SellToPlayersButton } from '../../SellToPlayers';
import { LineChart, Spark, trend, type Pt } from './Spark';
import { useInvest } from './useInvest';

type SheetKey = { t: 'product' | 'market' | 'holding'; id: string | number } | null;
type Run = ReturnType<typeof useInvest>['run'];

const RISK: Record<Risk, string> = { safe: 'Low risk', medium: 'Medium risk', high: 'High risk' };
const SAVE_KINDS = ['savings', 'safelock'];
const SAFE_KINDS = ['mmf', 'fd', 'tbill', 'bond'];

const signed = (n: number) => `${n >= 0 ? '+' : '−'}${naira(Math.abs(n))}`;
const pctText = (p: number) => `${p >= 0 ? '▲' : '▼'} ${Math.abs(p).toFixed(1)}%`;
const qtyText = (q: number) => (Number.isInteger(q) ? String(q) : String(Number(q.toFixed(8))));
const interest = (amt: number, rate: number, days: number) => Math.floor((amt * rate) / 100 * (days / 365));

function Risky({ risk }: { risk: Risk }) {
  return <span className={`inv-badge inv-badge--${risk}`}>{RISK[risk]}</span>;
}

function Delta({ n, pct }: { n?: number; pct?: number }) {
  const v = n ?? pct ?? 0;
  return <span className={`inv-delta ${v >= 0 ? 'is-up' : 'is-down'}`}>{n != null ? signed(n) : pctText(pct ?? 0)}</span>;
}

function Section({ title, sub, children }: { title: string; sub?: string; children: ReactNode }) {
  return (
    <section className="inv-sec">
      <h3 className="inv-sec__title">{title}</h3>
      {sub && <p className="inv-sec__sub">{sub}</p>}
      <div className="inv-sec__body">{children}</div>
    </section>
  );
}

/** Growth line for a holding that is not a market price: cost at the start, value now. */
function growthPts(p: InvestPosition, nowMs: number): Pt[] {
  const t1 = nowMs / 1000;
  let t0 = new Date(p.opened_at).getTime() / 1000;
  if (t1 - t0 < 3600) t0 = t1 - 3600;
  const n = 14;
  return Array.from({ length: n + 1 }, (_, i) => {
    const f = i / n;
    return [t0 + (t1 - t0) * f, p.cost + (p.value - p.cost) * f] as Pt;
  });
}

function useSeries(marketId: string | null, hours = 168) {
  const [pts, setPts] = useState<Pt[] | null>(null);
  useEffect(() => {
    if (!marketId) return;
    let alive = true;
    investSeries(marketId, 140, hours).then((r) => alive && setPts(r.points)).catch(() => alive && setPts([]));
    return () => { alive = false; };
  }, [marketId, hours]);
  return pts;
}

function NeedBank({ need, bank, goWhere }: { need: number; bank: number; goWhere: () => void }) {
  if (need <= bank) return null;
  return (
    <p className="inv-warn">
      Your bank has {naira(bank)}. This needs {naira(need)}. Investments are paid from your <b>bank</b>, not your pocket:
      {' '}<button type="button" className="ride-retry" onClick={goWhere}>deposit cash first</button> at Bronze Bank or a PoS stand.
    </p>
  );
}

function Rows({ rows }: { rows: [string, ReactNode, boolean?][] }) {
  return (
    <div className="bankx__fee inv-rows">
      {rows.map(([k, v, strong], i) => <div key={i} className={strong ? 'is-total' : ''}><span>{k}</span><b>{v}</b></div>)}
    </div>
  );
}

function Amount({ value, onChange, min, max, bank, label = 'Amount', units }: {
  value: string; onChange: (v: string) => void; min: number; max: number; bank: number; label?: string; units?: boolean;
}) {
  const chips: [string, number][] = units
    ? [['1', 1], ['5', 5], ['10', 10]]
    : [['Min', min], ['₦100K', 100000], ['₦1M', 1000000], ['All bank', Math.min(bank, max)]];
  return (
    <div className="bankx__amount">
      <label className="bankx__amount-field">
        <span className="bankx__amount-label">{label}</span>
        <span className="bankx__amount-input">
          {!units && <span aria-hidden>₦</span>}
          <input className="input" inputMode="numeric" pattern="[0-9]*" placeholder="0" value={value} aria-label={label}
            onChange={(e) => onChange(e.target.value.replace(/[^0-9]/g, '').replace(/^0+(?=\d)/, '').slice(0, 16))} />
        </span>
      </label>
      <div className="bankx__chips">
        {chips.filter(([, v]) => v >= min && v <= max).map(([l, v]) => (
          <button key={l} type="button" className={`bankx__chip${Number(value) === v ? ' is-on' : ''}`} onClick={() => onChange(String(v))}>{l}</button>
        ))}
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------------------------- cards

function PortfolioCard({ d, goWhere, filter }: { d: InvestOverview; goWhere: () => void; filter?: string[] }) {
  const ps = filter ? d.positions.filter((p) => filter.includes(p.kind)) : d.positions;
  const invested = filter ? ps.reduce((a, p) => a + p.cost, 0) : d.summary.invested;
  const value = filter ? ps.reduce((a, p) => a + p.value, 0) : d.summary.value;
  const today = filter ? ps.reduce((a, p) => a + p.day_change, 0) : d.summary.today;
  const profit = filter ? value - invested : d.summary.profit;
  const pct = invested > 0 ? (profit / invested) * 100 : 0;
  return (
    <div className="inv-port">
      <span className="inv-port__label">{filter ? 'Total saved' : 'Portfolio value'}</span>
      <span className="inv-port__amt">{naira(value)}</span>
      <div className="inv-port__grid">
        <div><span>Invested</span><b>{nairaShort(invested)}</b></div>
        <div><span>Total profit</span><b className={profit >= 0 ? 'is-up' : 'is-down'}>{profit >= 0 ? '+' : '−'}{nairaShort(Math.abs(profit))}{invested > 0 ? ` (${pct.toFixed(1)}%)` : ''}</b></div>
        <div><span>Today</span><b className={today >= 0 ? 'is-up' : 'is-down'}>{today >= 0 ? '+' : '−'}{nairaShort(Math.abs(today))}</b></div>
      </div>
      <p className="inv-port__note">
        Money moves from your <b>bank</b> ({naira(d.bank)}). Only have cash?{' '}
        <button type="button" onClick={goWhere}>Deposit it first</button>. One game year = {d.year_days} real days.
      </p>
    </div>
  );
}

function HoldingCard({ p, d, onOpen }: { p: InvestPosition; d: InvestOverview; onOpen: () => void }) {
  const market = p.chart === 'market' && ['stock', 'crypto', 'land'].includes(p.kind) ? d.markets.find((m) => m.id === p.market_id) : null;
  const pts: Pt[] = market ? market.spark.map(([t, v]) => [t, v * p.qty] as Pt) : growthPts(p, new Date(d.now).getTime());
  const pct = p.cost > 0 ? (p.profit / p.cost) * 100 : 0;
  return (
    <button type="button" className="inv-hold" onClick={onOpen}>
      <span className="inv-hold__icon" aria-hidden>{p.icon}</span>
      <span className="grow inv-hold__main">
        <span className="inv-hold__name">{p.name}{p.kind === 'stock' || p.kind === 'crypto' ? ` ×${qtyText(p.qty)}` : p.kind === 'land' ? ` · ${p.qty} plot${p.qty > 1 ? 's' : ''}` : ''}</span>
        <span className="inv-hold__sub">
          {naira(p.value)} · <span className={p.profit >= 0 ? 'is-up' : 'is-down'}>{signed(p.profit)} ({pct.toFixed(1)}%)</span>
        </span>
        <span className="inv-hold__tags">
          {p.ready && <span className="inv-tag inv-tag--go">{p.kind === 'farm' ? 'Ready to harvest' : 'Matured'}</span>}
          {p.collectable > 0 && !p.ready && <span className="inv-tag inv-tag--go">Collect {nairaShort(p.collectable)}</span>}
          {p.locked && <span className="inv-tag">Locked</span>}
          {p.vacant_until && new Date(p.vacant_until) > new Date(d.now) && <span className="inv-tag inv-tag--bad">Empty</span>}
        </span>
      </span>
      <Spark pts={pts} label={`${p.name} value`} />
    </button>
  );
}

function ProductCard({ p, d, onOpen, held }: { p: InvestProduct; d: InvestOverview; onOpen: () => void; held: boolean }) {
  const realDays = (days: number) => realLeft(days * d.day_seconds);
  const unit = ['farm', 'transport', 'pos', 'flat'].includes(p.kind);
  const head = unit
    ? p.kind === 'farm' ? `+${p.gain_min_pct}–${p.gain_max_pct}% / cycle` : `${naira(p.income_day)} / day`
    : `${p.rate_pct}% / yr`;
  const sub = unit
    ? `${naira(p.unit_price)} per unit${p.kind === 'farm' ? ` · ${p.cycle_days} d (≈ ${realDays(p.cycle_days)})` : ''}`
    : p.term_days ? `${p.term_days} days (≈ ${realDays(p.term_days)}) · ${p.forfeits_interest ? 'early exit loses interest' : `early sell ${p.exit_fee_pct}% fee`}`
      : p.kind === 'bond' ? 'Sell any time at market price' : 'Withdraw any time';
  return (
    <button type="button" className="inv-card" onClick={onOpen}>
      <span className="inv-card__icon" aria-hidden>{p.icon}</span>
      <span className="grow">
        <span className="inv-card__name">{p.name}{held && <i className="inv-card__held">you hold</i>}</span>
        <span className="inv-card__sub">{sub}</span>
      </span>
      <span className="inv-card__right"><b>{head}</b><Risky risk={p.risk} /></span>
    </button>
  );
}

function MarketCard({ m, onOpen, held }: { m: InvestMarket; onOpen: () => void; held: boolean }) {
  const t = trend(m.spark);
  return (
    <button type="button" className="inv-card" onClick={onOpen}>
      <span className="inv-card__icon" aria-hidden>{m.icon}</span>
      <span className="grow">
        <span className="inv-card__name">{m.name}{held && <i className="inv-card__held">you hold</i>}</span>
        <span className="inv-card__sub">
          {m.kind === 'land' ? `Plot ${naira(m.price)}` : `${naira(m.price)}${m.kind === 'stock' ? ' / share' : ''}`}{' '}
          <span className={m.change_24h >= 0 ? 'is-up' : 'is-down'}>{pctText(m.change_24h)} today</span>
        </span>
        {m.kind === 'land' && <span className="inv-card__sub">Settlement {m.community_pct}% · agent {m.fee_pct}%</span>}
      </span>
      <span className="inv-card__right">
        <Spark pts={m.spark} label={`${m.name} price, last 7 days, ${t.up ? 'up' : 'down'} ${Math.abs(t.pct).toFixed(1)}%`} />
        <Risky risk={m.risk} />
      </span>
    </button>
  );
}

// ---------------------------------------------------------------------------------------------- sheets

function ProductSheet({ p, d, run, close, goWhere }: { p: InvestProduct; d: InvestOverview; run: Run; close: () => void; goWhere: () => void }) {
  const unit = ['farm', 'transport', 'pos', 'flat'].includes(p.kind);
  const [val, setVal] = useState(unit ? '1' : '');
  const n = Number(val) || 0;
  const cost = unit ? p.unit_price * n : n;
  const realDays = (days: number) => realLeft(days * d.day_seconds);
  const bondM = p.kind === 'bond' ? d.markets.find((m) => m.id === p.market_id) : null;
  const ok = n >= p.min_amount && n <= p.max_amount && cost <= d.bank;
  const action = p.kind === 'savings' || p.kind === 'safelock' ? 'Save' : 'Invest';
  const rows: [string, ReactNode, boolean?][] = [];
  if (!unit) {
    rows.push(['You put in', naira(n)]);
    if (p.term_days) {
      const i = interest(n, p.rate_pct, p.term_days);
      rows.push([`Locked ${p.term_days} days (≈ ${realDays(p.term_days)})`, `${p.rate_pct}% / yr`]);
      rows.push(['Interest if you wait', `+${naira(i)}`]);
      rows.push(['You get at the end', naira(n + i), true]);
    } else {
      rows.push(['Rate', `${p.rate_pct}% a game year`]);
      rows.push(['Interest per real day (about)', `+${naira(Math.floor((n * p.rate_pct) / 100 / d.year_days))}`]);
    }
    if (bondM) rows.push(['Market price now', `${naira(bondM.price)} per ₦100 face (${pctText(bondM.change_24h)} today)`]);
  } else {
    rows.push([`${n} unit${n > 1 ? 's' : ''} × ${naira(p.unit_price)}`, naira(cost), true]);
    if (p.kind === 'farm') {
      rows.push(['One cycle', `${p.cycle_days} d (≈ ${realDays(p.cycle_days)})`]);
      rows.push(['Harvest if all goes well', `${naira(Math.floor(cost * (1 + p.gain_min_pct / 100)))} – ${naira(Math.floor(cost * (1 + p.gain_max_pct / 100)))}`]);
    } else {
      rows.push(['Income', `${naira(p.income_day * n)} per day (≈ ${naira(Math.round(p.income_day * n * 86400 / d.day_seconds / 24))} per real hour)`]);
    }
    rows.push(['Sell back later', p.kind === 'flat' ? `market price − ${p.exit_fee_pct}% agent fee` : `${p.resale_pct}% of cost${p.depr_pct_year ? `, minus ${p.depr_pct_year}% a year` : ''}`]);
  }
  const events = Object.values(p.events ?? {});
  return (
    <Sheet className="inv-sheet-host" open onClose={close} title={`${p.icon} ${p.name}`} subtitle={p.blurb} size="tall">
      <div className="stack inv-sheet">
        <div><Risky risk={p.risk} /></div>
        <Amount value={val} onChange={setVal} min={p.min_amount} max={p.max_amount} bank={d.bank} units={unit}
          label={unit ? `Units (${p.min_amount}–${p.max_amount})` : `Amount (min ${naira(p.min_amount)})`} />
        {n > 0 && <Rows rows={rows} />}
        {p.forfeits_interest && <p className="inv-fine">Break it before the end and you lose <b>all</b> the interest. You get your money back.</p>}
        {p.kind === 'tbill' && <p className="inv-fine">Sell early: {p.exit_fee_pct}% fee, you keep the interest earned so far. No fee at maturity.</p>}
        {events.length > 0 && (
          <div className="inv-risks">
            <b>What can go wrong</b>
            <ul>{events.map((e, i) => (
              <li key={i}>{e.label}: {e.chance_pct}% chance {p.kind === 'farm' ? 'each cycle' : 'each day'}
                {e.loss_of === 'cycle' ? `, lose ${e.loss_pct}% of the harvest` : e.loss_of === 'unit' ? `, repair or loss of ${e.loss_pct}% of the price`
                  : e.loss_of === 'vacancy' ? `, no rent for ${e.span_days} days` : `, lose ${e.loss_pct}% of that day's income`}</li>
            ))}</ul>
          </div>
        )}
        <NeedBank need={cost} bank={d.bank} goWhere={() => { close(); goWhere(); }} />
        <Button variant="green" block disabled={!ok} onClick={async () => { const r = await run(() => investBuy(p.id, n)); if (r) close(); }}>
          {n < p.min_amount ? `Minimum ${unit ? `${p.min_amount} unit` : naira(p.min_amount)}` : n > p.max_amount ? `Maximum ${unit ? p.max_amount : naira(p.max_amount)}` : `${action} ${naira(cost)}`}
        </Button>
      </div>
    </Sheet>
  );
}

function MarketSheet({ m, d, run, close, goWhere, startSell }: { m: InvestMarket; d: InvestOverview; run: Run; close: () => void; goWhere: () => void; startSell: boolean }) {
  const pos = d.positions.find((x) => x.ref_id === m.id);
  const [mode, setMode] = useState<'buy' | 'sell'>(startSell && pos ? 'sell' : 'buy');
  const [val, setVal] = useState(m.kind === 'land' ? '1' : '');
  const [hours, setHours] = useState(168);
  const [deal, setDeal] = useState<LandResult | null>(null);
  const pts = useSeries(m.id, hours);
  const land = m.kind === 'land', crypto = m.kind === 'crypto';
  const price = m.price;
  const n = Number(val) || 0;
  // buy: stocks/land n units; crypto n naira
  const qty = crypto && mode === 'buy' ? Math.floor((n / price) * 1e8) / 1e8 : n;
  const gross = mode === 'buy' ? (crypto ? n : Math.ceil(qty * price)) : Math.floor(qty * price);
  const fee = Math.ceil((gross * m.fee_pct) / 100);
  const settle = land && mode === 'buy' ? Math.ceil((gross * m.community_pct) / 100) : 0;
  const total = mode === 'buy' ? gross + fee + settle : gross - fee;
  const held = pos?.qty ?? 0;
  const costBasis = pos && qty > 0 ? Math.floor((pos.cost * Math.min(qty, held)) / held) : 0;
  const t = pts ? trend(pts) : { up: true, pct: 0 };
  const buyOk = mode === 'buy' && qty >= m.min_qty && qty <= m.max_qty && total <= d.bank && (crypto ? n >= 100 : true);
  const sellOk = mode === 'sell' && qty > 0 && qty <= held;

  const doLandBuy = async () => {
    const r = await run(() => landBuy(m.id, n), true);
    if (!r) return;
    if (r.status === 'levy') setDeal(r);
    else { toast(r.message, 'good'); close(); }
  };
  const doLevy = async (pay: boolean) => {
    if (!deal?.deal_id) return;
    const r = await run(() => landLevy(deal.deal_id!, pay));
    if (r) { setDeal(null); if (pay) close(); }
  };

  return (
    <Sheet className="inv-sheet-host" open onClose={close} title={`${m.icon} ${m.name}`} subtitle={m.blurb} size="tall">
      <div className="stack inv-sheet">
        <div className="inv-sheet__price">
          <b>{naira(price)}</b><span>{land ? 'per plot' : crypto ? `per ${m.ticker}` : 'per share'}</span>
          <span className={m.change_24h >= 0 ? 'is-up' : 'is-down'}>{pctText(m.change_24h)} today</span>
          <Risky risk={m.risk} />
        </div>
        <div className="inv-range">
          {([[24, '1 day'], [168, '7 days'], [720, '30 days']] as const).map(([h, l]) => (
            <button key={h} type="button" className={hours === h ? 'is-on' : ''} onClick={() => setHours(h)}>{l}</button>
          ))}
          {pts && pts.length > 1 && <span className={`inv-range__delta ${t.up ? 'is-up' : 'is-down'}`}>{pctText(t.pct)}</span>}
        </div>
        {pts && <LineChart pts={pts} label={`${m.name} price history`} format={(v) => naira(Math.round(v * 100) / 100)} />}
        {pos && (
          <div className="inv-mine">
            You hold <b>{land ? `${pos.qty} plot${pos.qty > 1 ? 's' : ''}` : `${qtyText(pos.qty)} ${m.ticker}`}</b> worth <b>{naira(pos.value)}</b>{' '}
            (<span className={pos.profit >= 0 ? 'is-up' : 'is-down'}>{signed(pos.profit)}</span> after fees you paid)
          </div>
        )}
        {deal ? (
          <div className="inv-levy">
            <b>The community came back</b>
            <p>{deal.message}</p>
            <Rows rows={[
              [`${deal.plots} plot${(deal.plots ?? 1) > 1 ? 's' : ''} + agent + settlement`, naira(deal.total ?? 0)],
              [`Development levy (${deal.levy_pct}%)`, naira(deal.levy ?? 0)],
              ['Total to close the deal', naira(deal.total_with_levy ?? 0), true],
            ]} />
            <NeedBank need={deal.total_with_levy ?? 0} bank={d.bank} goWhere={() => { close(); goWhere(); }} />
            <div className="row bank-confirm__btns">
              <Button variant="ghost" className="grow" onClick={() => void doLevy(false)}>Walk away</Button>
              <Button variant="green" className="grow" disabled={(deal.total_with_levy ?? 0) > d.bank} onClick={() => void doLevy(true)}>Pay levy</Button>
            </div>
            <p className="inv-fine">Walking away costs nothing, just a short wait before the next deal.</p>
          </div>
        ) : (
          <>
            {pos && (
              <div className="inv-seg" role="tablist">
                <button type="button" role="tab" aria-selected={mode === 'buy'} className={mode === 'buy' ? 'is-on' : ''} onClick={() => { setMode('buy'); setVal(land ? '1' : ''); }}>Buy</button>
                <button type="button" role="tab" aria-selected={mode === 'sell'} className={mode === 'sell' ? 'is-on' : ''} onClick={() => { setMode('sell'); setVal(land ? '1' : ''); }}>Sell</button>
              </div>
            )}
            {crypto && mode === 'buy' ? (
              <Amount value={val} onChange={setVal} min={100} max={m.max_qty * price} bank={d.bank} label="Naira to spend (fee on top)" />
            ) : (
              <>
                <label className="bankx__amount-field">
                  <span className="bankx__amount-label">{land ? 'Plots' : crypto ? `${m.ticker} to sell` : 'Shares'}</span>
                  <span className="bankx__amount-input">
                    <input className="input" inputMode={crypto ? 'decimal' : 'numeric'} value={val} placeholder="0" aria-label="Quantity"
                      onChange={(e) => setVal(crypto ? e.target.value.replace(/[^0-9.]/g, '').slice(0, 14) : e.target.value.replace(/[^0-9]/g, '').replace(/^0+(?=\d)/, '').slice(0, 9))} />
                  </span>
                </label>
                <div className="bankx__chips">
                  {(mode === 'sell' ? [['Half', held / 2], ['All', held]] as [string, number][] : land ? [['1', 1], ['5', 5], ['10', 10]] as [string, number][] : [['1', 1], ['10', 10], ['100', 100]] as [string, number][])
                    .map(([l, v]) => {
                      const q = mode === 'sell' ? (crypto ? Math.floor(v * 1e8) / 1e8 : Math.max(1, Math.floor(v))) : v;
                      return <button key={l} type="button" className={`bankx__chip${Number(val) === q ? ' is-on' : ''}`} onClick={() => setVal(qtyText(q))}>{l}</button>;
                    })}
                </div>
              </>
            )}
            {qty > 0 && (
              mode === 'buy' ? (
                <Rows rows={land ? [
                  [`${qty} plot${qty > 1 ? 's' : ''} × ${naira(price)}`, naira(gross)],
                  [`Agent fee (${m.fee_pct}%)`, naira(fee)],
                  [`Community settlement (${m.community_pct}%)`, naira(settle)],
                  [`Possible development levy`, `${m.levy_chance_pct}% chance of ${m.levy_min_pct}–${m.levy_max_pct}% extra`],
                  ['Total (before any levy)', naira(total), true],
                ] : [
                  [`${qtyText(qty)} ${m.ticker} × ${naira(price)}`, naira(gross)],
                  [`Broker fee (${m.fee_pct}%)`, naira(fee)],
                  ['Total from your bank', naira(total), true],
                ]} />
              ) : (
                <Rows rows={[
                  [`${qtyText(qty)} ${land ? 'plot(s)' : m.ticker} × ${naira(price)}`, naira(gross)],
                  [`${land ? 'Agent' : 'Broker'} fee (${m.fee_pct}%)`, `−${naira(fee)}`],
                  ['You get in your bank', naira(total), true],
                  ['Profit on this sale', <span key="p" className={total - costBasis >= 0 ? 'is-up' : 'is-down'}>{signed(total - costBasis)}</span>],
                ]} />
              )
            )}
            {m.dividend_yield_pct > 0 && <p className="inv-fine">Pays occasional dividends (about {m.dividend_yield_pct}% of the price each time) straight to your bank.</p>}
            {land && mode === 'buy' && <p className="inv-fine">The community / elders (omonile) must be settled before you sign. Rougher areas ask for more, and sometimes come back for a levy.</p>}
            {mode === 'buy' && <NeedBank need={total} bank={d.bank} goWhere={() => { close(); goWhere(); }} />}
            {mode === 'buy' ? (
              <Button variant="green" block disabled={!buyOk}
                onClick={() => (land ? void doLandBuy() : void run(() => investMarketBuy(m.id, qty)).then((r) => r && setVal('')))}>
                {qty <= 0 ? 'Enter an amount' : qty < m.min_qty ? `Minimum ${m.min_qty}` : `Buy for ${naira(total)}`}
              </Button>
            ) : (
              <Button variant="danger" block disabled={!sellOk}
                onClick={() => void run(() => (land ? landSell(m.id, qty) : investMarketSell(m.id, qty >= held ? null : qty))).then((r) => { if (r) { setVal(''); if (qty >= held) close(); } })}>
                {qty <= 0 ? 'Enter how many' : qty > held ? 'You do not have that many' : `Sell for ${naira(total)}`}
              </Button>
            )}
            {land && mode === 'sell' && held > 0 && (
              <SellToPlayersButton kind="land" refId={m.id} maxQty={held} name={`${m.name} plots`} icon={m.icon} block label="Sell to players instead"
                onListed={() => { void run(async () => ({ message: '' }), true); close(); }} />
            )}
          </>
        )}
      </div>
    </Sheet>
  );
}

function HoldingSheet({ p, d, run, close, openMarket }: { p: InvestPosition; d: InvestOverview; run: Run; close: () => void; openMarket: () => void }) {
  const [val, setVal] = useState('');
  const pooled = p.kind === 'savings' || p.kind === 'mmf';
  const mk = p.chart === 'market' && ['stock', 'crypto', 'land'].includes(p.kind);
  const series = useSeries(mk ? p.market_id : null, 168);
  const nowMs = new Date(d.now).getTime();
  const pts: Pt[] | null = mk ? (series ? series.map(([t, v]) => [t, v * p.qty] as Pt) : null) : growthPts(p, nowMs);
  const n = Number(val) || 0;
  const pct = p.cost > 0 ? (p.profit / p.cost) * 100 : 0;
  const farm = p.kind === 'farm';
  const left = p.matures_at ? (new Date(p.matures_at).getTime() - nowMs) / 1000 : 0;
  const realLeftSec = (left * 86400) / 86400; // matures_at is real time already
  const done = async (fn: () => Promise<{ message: string } | null>) => { const r = await fn(); if (r) close(); };
  return (
    <Sheet className="inv-sheet-host" open onClose={close} title={`${p.icon} ${p.name}`} subtitle={p.note} size="tall">
      <div className="stack inv-sheet">
        <div className="inv-sheet__price">
          <b>{naira(p.value)}</b><span>worth now</span><Delta n={p.profit} /><span className="inv-fine">({pct.toFixed(1)}%)</span>
        </div>
        {pts && <LineChart pts={pts} label={`${p.name} value over time`} />}
        <Rows rows={[
          ['You put in', naira(p.cost)],
          ['Worth now', naira(p.value)],
          ['Profit / loss', <span key="a" className={p.profit >= 0 ? 'is-up' : 'is-down'}>{signed(p.profit)}</span>],
          ...(p.locked && p.matures_at ? [['Unlocks in', `${realLeft(left)} real time`] as [string, ReactNode]] : []),
          ...(farm && !p.ready && p.matures_at ? [['Harvest in', `${realLeft(realLeftSec)} real time`] as [string, ReactNode]] : []),
          ...(farm && p.gain_pct != null ? [['This cycle pays', `+${p.gain_pct}% if no disaster`] as [string, ReactNode]] : []),
          ...(p.day_change ? [['Today', <Delta key="d" n={p.day_change} />] as [string, ReactNode]] : []),
        ]} />
        {mk && <Button variant="green" block onClick={openMarket}>Buy more or sell</Button>}
        {pooled && (
          <>
            <label className="bankx__amount-field">
              <span className="bankx__amount-label">Withdraw to your bank</span>
              <span className="bankx__amount-input"><span aria-hidden>₦</span>
                <input className="input" inputMode="numeric" value={val} placeholder="0" aria-label="Withdraw amount"
                  onChange={(e) => setVal(e.target.value.replace(/[^0-9]/g, '').slice(0, 16))} /></span>
            </label>
            <div className="bankx__chips">
              <button type="button" className="bankx__chip" onClick={() => setVal(String(Math.floor(p.value / 2)))}>Half</button>
              <button type="button" className="bankx__chip" onClick={() => setVal(String(p.value))}>All</button>
            </div>
            <Button variant="green" block disabled={n < 1 || n > p.value} onClick={() => void done(() => run(() => investWithdraw(p.id, n >= p.value ? null : n)))}>
              Withdraw {n > 0 ? naira(Math.min(n, p.value)) : ''}
            </Button>
          </>
        )}
        {p.kind === 'bond' && (
          <>
            <Rows rows={[['Sell value (market price + coupon)', naira(p.exit_value)], ['Fee', naira(p.exit_fee)]]} />
            <Button variant="green" block onClick={() => void done(() => run(() => investWithdraw(p.id, null)))}>Sell all for {naira(p.exit_value)}</Button>
          </>
        )}
        {['safelock', 'fd', 'tbill'].includes(p.kind) && (
          p.matured ? (
            <Button variant="green" block onClick={() => void done(() => run(() => investWithdraw(p.id)))}>Collect {naira(p.exit_value)}</Button>
          ) : (
            <>
              <p className="inv-warn">
                {p.forfeit > 0 ? <>Breaking early gives you <b>{naira(p.exit_value)}</b> back and you lose <b>{naira(p.forfeit)}</b> interest.</>
                  : <>Selling early gives you <b>{naira(p.exit_value)}</b> (fee {naira(p.exit_fee)}).</>}
              </p>
              <Button variant="danger" block onClick={() => void done(() => run(() => investWithdraw(p.id)))}>
                {p.kind === 'tbill' ? 'Sell early' : 'Break early'} · get {naira(p.exit_value)}
              </Button>
            </>
          )
        )}
        {farm && (p.ready ? (
          <>
            <p className="inv-fine">Harvest time! Risks (bird flu, flood, theft) are rolled when you collect. Expected {naira(p.collectable)} if nothing goes wrong.</p>
            <Button variant="green" block onClick={() => void done(() => run(() => investCollect(p.id)))}>Harvest</Button>
            <Button variant="ghost" block onClick={() => void done(() => run(() => investCollect(p.id, true)))}>Harvest and start the next cycle</Button>
          </>
        ) : (
          <>
            <p className="inv-warn">Selling the unit now returns <b>{naira(p.exit_value)}</b> and loses this cycle.</p>
            <Button variant="danger" block onClick={() => void done(() => run(() => investWithdraw(p.id)))}>Sell unit back · {naira(p.exit_value)}</Button>
          </>
        ))}
        {['transport', 'pos', 'flat'].includes(p.kind) && (
          <>
            <Button variant="green" block disabled={p.collectable < 1} onClick={() => void run(() => investCollect(p.id))}>
              {p.collectable > 0 ? `Collect income ${naira(p.collectable)}` : 'No income to collect yet'}
            </Button>
            <Button variant="danger" block onClick={() => void done(() => run(() => investWithdraw(p.id)))}>
              Sell for {naira(p.exit_value)}{p.exit_fee > 0 ? ` (fee ${naira(p.exit_fee)})` : ''}
            </Button>
          </>
        )}
      </div>
    </Sheet>
  );
}

// ---------------------------------------------------------------------------------------------- tabs

function useSheets(d: InvestOverview | null, run: Run, goWhere: () => void) {
  const [sheet, setSheet] = useState<SheetKey>(null);
  const [sell, setSell] = useState(false);
  const close = () => setSheet(null);
  const node = useMemo(() => {
    if (!d || !sheet) return null;
    if (sheet.t === 'product') {
      const p = d.products.find((x) => x.id === sheet.id);
      return p ? <ProductSheet p={p} d={d} run={run} close={close} goWhere={goWhere} /> : null;
    }
    if (sheet.t === 'market') {
      const m = d.markets.find((x) => x.id === sheet.id);
      return m ? <MarketSheet m={m} d={d} run={run} close={close} goWhere={goWhere} startSell={sell} /> : null;
    }
    const p = d.positions.find((x) => x.id === sheet.id);
    if (!p) return null;
    return <HoldingSheet p={p} d={d} run={run} close={close}
      openMarket={() => { setSell(true); setSheet({ t: 'market', id: p.ref_id }); }} />;
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [d, sheet, sell, run, goWhere]);
  return { open: (s: SheetKey, asSell = false) => { setSell(asSell); setSheet(s); }, node };
}

function Loading({ err, onRetry }: { err: string | null; onRetry: () => void }) {
  if (err) return <p className="phone-app__lead">{err} <button type="button" className="ride-retry" onClick={onRetry}>Try again</button></p>;
  return <div className="panel-skel"><span /><span /><span /></div>;
}

export function SaveTab({ active, goWhere }: { active: boolean; goWhere: () => void }) {
  const { data: d, err, reload, run } = useInvest(active);
  const sheets = useSheets(d, run, goWhere);
  if (!d) return <Loading err={err} onRetry={() => void reload()} />;
  const mine = d.positions.filter((p) => SAVE_KINDS.includes(p.kind));
  const prods = d.products.filter((p) => SAVE_KINDS.includes(p.kind));
  return (
    <div className="stack inv">
      <PortfolioCard d={d} goWhere={goWhere} filter={SAVE_KINDS} />
      {!d.enabled && <p className="inv-warn">Saving is paused for now. You can still withdraw.</p>}
      {mine.length > 0 && (
        <Section title="Your savings">
          {mine.map((p) => <HoldingCard key={p.id} p={p} d={d} onOpen={() => sheets.open({ t: 'holding', id: p.id })} />)}
        </Section>
      )}
      <Section title="Save" sub="Safe. Your money earns interest by real time. SafeLock pays more, but locked: break it early and you lose all the interest.">
        {prods.map((p) => (
          <ProductCard key={p.id} p={p} d={d} held={mine.some((x) => x.ref_id === p.id)} onOpen={() => sheets.open({ t: 'product', id: p.id })} />
        ))}
      </Section>
      {sheets.node}
    </div>
  );
}

export function InvestTab({ active, goWhere }: { active: boolean; goWhere: () => void }) {
  const { data: d, err, reload, run } = useInvest(active);
  const sheets = useSheets(d, run, goWhere);
  if (!d) return <Loading err={err} onRetry={() => void reload()} />;
  const mine = d.positions.filter((p) => !SAVE_KINDS.includes(p.kind));
  const held = (id: string) => d.positions.some((p) => p.ref_id === id);
  const prods = (kinds: string[]) => d.products.filter((p) => kinds.includes(p.kind));
  const mkts = (kind: string) => d.markets.filter((m) => m.kind === kind);
  const pcard = (p: InvestProduct) => <ProductCard key={p.id} p={p} d={d} held={held(p.id)} onOpen={() => sheets.open({ t: 'product', id: p.id })} />;
  const mcard = (m: InvestMarket) => <MarketCard key={m.id} m={m} held={held(m.id)} onOpen={() => sheets.open({ t: 'market', id: m.id })} />;
  return (
    <div className="stack inv">
      <PortfolioCard d={d} goWhere={goWhere} />
      {!d.enabled && <p className="inv-warn">Investing is paused for now. You can still sell and withdraw.</p>}
      {mine.length > 0 && (
        <Section title="Your investments">
          {mine.map((p) => <HoldingCard key={p.id} p={p} d={d} onOpen={() => sheets.open({ t: 'holding', id: p.id })} />)}
        </Section>
      )}
      <Section title="Safe" sub="Steady returns. Money market, fixed deposits, T-bills and the FGN bond.">
        {prods(SAFE_KINDS).map(pcard)}
      </Section>
      <Section title="Medium risk" sub="Can pay well, can lose value. Prices move every hour, farms and vehicles have bad days.">
        <h4 className="inv-sub">NGX stocks</h4>
        {mkts('stock').map(mcard)}
        <h4 className="inv-sub">Farms</h4>
        {prods(['farm']).map(pcard)}
        <h4 className="inv-sub">Transport</h4>
        {prods(['transport']).map(pcard)}
        <h4 className="inv-sub">POS business</h4>
        {prods(['pos']).map(pcard)}
      </Section>
      <Section title="High risk" sub="Big upside, real swings. Land costs settlement and agent fees; crypto can halve.">
        <h4 className="inv-sub">Land by area</h4>
        {mkts('land').map(mcard)}
        <h4 className="inv-sub">Rental flats</h4>
        {prods(['flat']).map(pcard)}
        <h4 className="inv-sub">Crypto</h4>
        {mkts('crypto').map(mcard)}
      </Section>
      {d.log.length > 0 && (
        <Section title="Recent activity">
          <ul className="bank-hist">
            {d.log.slice(0, 8).map((l) => (
              <li key={l.id} className="bank-hist__row">
                <span className="grow"><span className="bank-hist__label">{l.label}</span></span>
                <b className={`bank-hist__amt${l.amount > 0 ? ' is-in' : ''}`}>{l.amount === 0 ? '' : `${l.amount > 0 ? '+' : '−'}${naira(Math.abs(l.amount))}`}</b>
              </li>
            ))}
          </ul>
        </Section>
      )}
      {sheets.node}
    </div>
  );
}
