// R10 Business app (docs/BUSINESS.md). "My businesses": takings, level, staff, stock, events log, Collect / Restock / Upgrade / Hire /
// Insure / Work a shift / Sell. "Buy a business": the types with their requirements, and the free plots by area, first come first served.
// The server settles income lazily (no cron), so every open of this app shows fresh takings.
import { useCallback, useEffect, useMemo, useState } from 'react';
import {
  businessBuy, businessCatalog, businessCollect, businessFire, businessHire, businessInsure, businessMine, businessRestock, businessSell, businessUpgrade,
  businessWork, inText, type BusinessCard, type BusinessCatalog, type BusinessMine, type BusinessSlot, type BusinessTypeInfo,
} from '../../../api/business';
import { errorMessage } from '../../../lib/api';
import { naira, nairaShort } from '../../../lib/format';
import type { GameState } from '../../../lib/types';
import { useGame } from '../../../state/game';
import { Button, EmptyState, Modal, Tabs, toast } from '../../../ui';
import { SellToPlayersButton } from '../SellToPlayers';
import './BusinessApp.css';
import { canPoll } from '../../../lib/activity';

type Tab = 'mine' | 'buy';
const LOG_ICON: Record<string, string> = {
  buy: '🏷️', collect: '💰', restock: '📦', upgrade: '⬆️', hire: '🧑‍🍳', fire: '👋', shift: '🛠️', insure: '🛡️', grant: '🎁', listed: '🏷️', unlisted: '↩️', market_buy: '🏷️',
  ev_robbery: '🔫', ev_outage: '💡', ev_levy: '🧾', ev_theft: '🫳', ev_goodday: '🎉',
};

function Stars({ level, max }: { level: number; max: number }) {
  return <span className="bz-stars" aria-label={`Level ${level} of ${max}`}>{Array.from({ length: max }, (_, i) => <span key={i} className={i < level ? 'is-on' : ''} aria-hidden>★</span>)}</span>;
}

function Stat({ label, value, tone }: { label: string; value: string; tone?: 'good' | 'bad' | 'warn' }) {
  return <span className={`bz-stat${tone ? ` is-${tone}` : ''}`}><small>{label}</small><b>{value}</b></span>;
}

// ------------------------------------------------------------------------------------------------ one of my businesses
function MyCard({ b, info, atHere, busy, run, onGo, onSold }: {
  b: BusinessCard; info: BusinessMine; atHere: boolean; busy: string | null;
  run: (key: string, fn: () => Promise<{ message: string }>) => void; onGo: (loc: string) => void; onSold: () => void;
}) {
  const [open, setOpen] = useState(false);
  const [sell, setSell] = useState(false);
  const fillPct = useMemo(() => {
    const capH = info.cap_hours;
    const left = Math.max(0, (Date.parse(b.cap_at) - Date.now()) / 3600000);
    return Math.max(0, Math.min(100, Math.round(((capH - left) / capH) * 100)));
  }, [b.cap_at, info.cap_hours]);
  const k = (a: string) => `${a}${b.id}`;
  const canWork = info.enabled && !b.setting_up && !b.listed;
  return (
    <article className={`bz-card${b.listed ? ' is-listed' : ''}`} data-testid="business-card">
      <header className="bz-card__head">
        <span className="bz-card__icon" aria-hidden>{b.icon}</span>
        <span className="bz-card__title">
          <b>{b.name}</b>
          <small>{b.type_name} · {b.plot_label}</small>
        </span>
        <Stars level={b.level} max={b.max_level} />
      </header>

      {b.setting_up && <p className="bz-note">🏗️ The builders dey work. Ready in {inText(b.ready_at)}.</p>}
      {b.listed && <p className="bz-note">🏷️ On the Market. It is locked until it sells or you take it down (Market app).</p>}

      <div className="bz-take">
        <span className="bz-take__num"><small>Takings waiting</small><b data-testid="business-takings">{naira(b.takings)}</b></span>
        <Button variant="gold" size="sm" disabled={b.takings < 1 || b.listed} loading={busy === k('c')} onClick={() => run(k('c'), () => businessCollect(b.id))} data-testid="business-collect">
          Collect takings
        </Button>
      </div>
      {!b.listed && (
        <div className="bz-fill" title="Takings stop growing when the till is full">
          <span className="bz-fill__bar"><span style={{ width: `${fillPct}%` }} className={b.full ? 'is-full' : ''} /></span>
          <small>{b.full ? 'Till full. Collect now: nothing more is added.' : `Till full in ${inText(b.cap_at)}`}</small>
        </div>
      )}

      <div className="bz-stats">
        <Stat label="Net a day" value={`${b.net_day >= 0 ? '' : '−'}${nairaShort(Math.abs(b.net_day))}`} tone={b.net_day < 0 ? 'bad' : undefined} />
        <Stat label="Staff" value={`${b.staff}/${b.staff_slots}`} />
        {b.needs_stock && <Stat label="Stock" value={`${b.stock_pct}%`} tone={b.stock_pct < 60 ? 'bad' : b.stock_pct < 100 ? 'warn' : 'good'} />}
        <Stat label="Level" value={`${b.level}/${b.max_level}`} />
        {b.boost && <Stat label="Boost" value={`+${b.boost_pct}%`} tone="good" />}
        <Stat label="Insured" value={b.insured ? 'Yes' : 'No'} tone={b.insured ? 'good' : undefined} />
      </div>

      <div className="bz-actions">
        {b.needs_stock && (
          <Button size="sm" variant="ghost" disabled={!info.enabled || b.listed} loading={busy === k('r')} onClick={() => run(k('r'), () => businessRestock(b.id))} data-testid="business-restock">
            Restock · {nairaShort(b.restock_cost)}
          </Button>
        )}
        <Button size="sm" variant="ghost" disabled={!info.enabled || b.listed || b.staff >= b.staff_slots} loading={busy === k('h')} onClick={() => run(k('h'), () => businessHire(b.id))} data-testid="business-hire">
          Hire · {nairaShort(b.hire_fee)}
        </Button>
        {b.staff > 0 && <Button size="sm" variant="ghost" disabled={b.listed} loading={busy === k('f')} onClick={() => run(k('f'), () => businessFire(b.id))}>Let one go</Button>}
        {b.next && (
          <Button size="sm" variant="green" disabled={!info.enabled || b.listed} loading={busy === k('u')} onClick={() => run(k('u'), () => businessUpgrade(b.id))} data-testid="business-upgrade">
            Upgrade · {nairaShort(b.next.cost)}
          </Button>
        )}
        <Button size="sm" variant="ghost" disabled={!info.enabled || b.listed} loading={busy === k('i')} onClick={() => run(k('i'), () => businessInsure(b.id))}>
          {b.insured ? 'Extend insurance' : 'Insure'} · {nairaShort(b.insure_cost)}
        </Button>
        {atHere
          ? <Button size="sm" variant="gold" disabled={!canWork || b.shifts_used >= b.shifts_cap} loading={busy === k('w')} onClick={() => run(k('w'), () => businessWork(b.id))} data-testid="business-work">Work a shift</Button>
          : <Button size="sm" variant="ghost" disabled={b.listed} onClick={() => onGo(b.location)}>Go there to work a shift</Button>}
      </div>
      {b.next && <p className="bz-hint">Level {b.next.level}: income ×{b.next.mult}. A shift at your own place gives +{b.boost_pct}% income and Business XP ({b.shifts_used}/{b.shifts_cap} today).</p>}

      {b.staff_list.length > 0 && (
        <p className="bz-hint">Staff: {b.staff_list.map((s) => s.name).join(', ')} · {naira(b.staff_wage)} a day each, +{b.staff_income_pct}% income each.</p>
      )}

      <button type="button" className="bz-more" onClick={() => setOpen((o) => !o)} aria-expanded={open}>{open ? 'Hide details' : 'Events and details'}</button>
      {open && (
        <div className="bz-details">
          <div className="bz-rows">
            <div><span>Gross a day (now)</span><b>{naira(b.gross_day)}</b></div>
            <div><span>Running costs a day</span><b>{naira(b.cost_day)}</b></div>
            <div><span>Invested</span><b>{naira(b.invested)}</b></div>
            <div><span>Earned so far</span><b>{naira(b.lifetime_income + b.lifetime_visit)}</b></div>
            <div><span>From customers</span><b>{naira(b.lifetime_visit)}</b></div>
            {b.needs_stock && <div><span>Stock until</span><b>{inText(b.stock_until) === 'now' ? 'Out of stock' : `in ${inText(b.stock_until)}`}</b></div>}
          </div>
          <h5>Events log</h5>
          {(b.log ?? []).length === 0 && <p className="muted">Nothing yet.</p>}
          <ul className="bz-log">
            {(b.log ?? []).map((l) => (
              <li key={l.id} className={l.kind.startsWith('ev_') ? (l.amount < 0 ? 'is-bad' : 'is-good') : ''}>
                <span aria-hidden>{LOG_ICON[l.kind] ?? '•'}</span>
                <span className="bz-log__t">{l.title}<small>{new Date(l.at).toLocaleString([], { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' })}</small></span>
                {l.amount !== 0 && <b className={l.amount > 0 ? 'is-up' : 'is-down'}>{l.amount > 0 ? '+' : '−'}{nairaShort(Math.abs(l.amount))}</b>}
              </li>
            ))}
          </ul>
          <div className="bz-actions">
            <SellToPlayersButton kind="business" refId={String(b.id)} name={b.name} icon={b.icon} label="Sell to players" onListed={onSold} />
            <Button size="sm" variant="danger" disabled={b.listed} onClick={() => setSell(true)} data-testid="business-sell">Sell to the system · {nairaShort(b.sell_back)}</Button>
          </div>
        </div>
      )}
      {sell && (
        <Modal open onClose={() => busy !== k('s') && setSell(false)} title={`Sell ${b.name}?`}
          actions={<>
            <Button variant="ghost" onClick={() => setSell(false)}>Keep it</Button>
            <Button variant="danger" loading={busy === k('s')} onClick={() => { run(k('s'), () => businessSell(b.id)); setSell(false); }}>Sell for {naira(b.sell_back)}</Button>
          </>}>
          <p>The system pays {info.sell_back_pct}% of what you invested ({naira(b.invested)}). Takings waiting ({naira(b.takings)}) are paid out as well. To get more, sell it to another player on the Market.</p>
        </Modal>
      )}
    </article>
  );
}

// ------------------------------------------------------------------------------------------------ buy
function BuySheet({ t, slot, onClose, onBought }: { t: BusinessTypeInfo; slot: BusinessSlot; onClose: () => void; onBought: (loc: string) => void }) {
  const [name, setName] = useState(t.name);
  const [busy, setBusy] = useState(false);
  const profile = useGame((s) => s.state?.profile);
  const money = (profile?.cash ?? 0) + Math.max(0, profile?.bank ?? 0);
  const go = async () => {
    setBusy(true);
    try {
      const r = await businessBuy(t.id, slot.plot, name.trim());
      toast(r.message, 'good');
      await useGame.getState().refresh();
      void useGame.getState().loadLocations();
      onBought(r.location);
    } catch (e) {
      toast(errorMessage(e), 'bad');
    } finally { setBusy(false); }
  };
  return (
    <Modal open onClose={() => !busy && onClose()} title={`${t.icon} ${t.name}`}
      actions={<>
        <Button variant="ghost" disabled={busy} onClick={onClose}>Back</Button>
        <Button variant="gold" loading={busy} disabled={money < slot.price || name.trim().length < 3} onClick={() => void go()} data-testid="business-confirm-buy">
          {money < slot.price ? 'Not enough money' : `Buy for ${naira(slot.price)}`}
        </Button>
      </>}>
      <div className="bz-sheet">
        <div className="bz-rows">
          <div><span>Plot</span><b>{slot.label}</b></div>
          <div><span>Price</span><b>{naira(slot.price)}</b></div>
          <div><span>Setup time</span><b>{t.setup_minutes} min</b></div>
          <div><span>Income a day</span><b>{nairaShort(t.income_min)} to {nairaShort(t.income_max)}</b></div>
          <div><span>Running costs</span><b>{nairaShort(t.rent_day + t.power_day)} a day + staff</b></div>
        </div>
        <label className="bz-field">
          <span>Name your business</span>
          <input value={name} maxLength={28} onChange={(e) => setName(e.target.value)} enterKeyHint="done" placeholder="e.g. Mama Nosa's Buka" data-testid="business-name" />
        </label>
        <p className="bz-hint">Everybody sees the name on the map with your @name. Visitors who spend there pay you a share.</p>
      </div>
    </Modal>
  );
}

function TypeCard({ t, onPick }: { t: BusinessTypeInfo; onPick: (t: BusinessTypeInfo, s: BusinessSlot) => void }) {
  const [open, setOpen] = useState(false);
  const free = t.slots.filter((s) => !s.taken);
  const areas = useMemo(() => {
    const m = new Map<string, BusinessSlot[]>();
    for (const s of t.slots) m.set(s.area_label, [...(m.get(s.area_label) ?? []), s]);
    return [...m.entries()];
  }, [t.slots]);
  return (
    <article className={`bz-type${t.met ? '' : ' is-locked'}`} data-testid={`business-type-${t.id}`}>
      <button type="button" className="bz-type__head" onClick={() => setOpen((o) => !o)} aria-expanded={open}>
        <span className="bz-card__icon" aria-hidden>{t.icon}</span>
        <span className="bz-card__title">
          <b>{t.name}</b>
          <small>From {nairaShort(t.price)} · {nairaShort(t.income_min)} to {nairaShort(t.income_max)} a day</small>
        </span>
        <span className="bz-type__free">{free.length} free</span>
      </button>
      <div className="bz-chips">
        <span className={`bz-chip ${t.met ? 'is-ok' : 'is-need'}`}>{t.met ? '✓ You qualify' : t.gate ?? 'Requirement not met'}</span>
        <span className="bz-chip">Setup {t.setup_minutes} min</span>
        <span className="bz-chip">{t.staff_slots} staff slots</span>
        <span className="bz-chip">{t.max_level} levels</span>
        {t.needs_stock && <span className="bz-chip">Needs restocking</span>}
      </div>
      {open && (
        <div className="bz-type__body">
          <p className="bz-hint">{t.blurb}</p>
          {(t.req_skill_level > 1 || t.req_cert_text) && (
            <p className="bz-hint">Needs: {[t.req_skill_level > 1 ? `Business skill level ${t.req_skill_level}` : null, t.req_cert_text].filter(Boolean).join(' and ')}.</p>
          )}
          {areas.length === 0 && <p className="muted">No plots for this business right now.</p>}
          {areas.map(([area, slots]) => (
            <div key={area} className="bz-area">
              <h5>{area}</h5>
              <div className="bz-slots">
                {slots.map((s) => s.taken ? (
                  <span key={s.plot} className="bz-slot is-taken"><b>{s.label}</b><small>Taken by @{s.taken_by}{s.taken_name ? ` · ${s.taken_name}` : ''}</small></span>
                ) : (
                  <button key={s.plot} type="button" className="bz-slot" disabled={!t.met} onClick={() => onPick(t, s)} data-testid={`business-slot-${s.plot}`}>
                    <b>{s.label}</b><small>{naira(s.price)}</small>
                  </button>
                ))}
              </div>
            </div>
          ))}
        </div>
      )}
    </article>
  );
}

export default function BusinessApp({ state, onGo }: { state: GameState; onGo: (id: string) => void }) {
  const [tab, setTab] = useState<Tab>('mine');
  const [mine, setMine] = useState<BusinessMine | null>(null);
  const [cat, setCat] = useState<BusinessCatalog | null>(null);
  const [err, setErr] = useState('');
  const [busy, setBusy] = useState<string | null>(null);
  const [pick, setPick] = useState<{ t: BusinessTypeInfo; s: BusinessSlot } | null>(null);
  const loadMine = useCallback(() => { businessMine().then((m) => { setMine(m); setErr(''); }).catch((e) => setErr(errorMessage(e))); }, []);
  const loadCat = useCallback(() => { businessCatalog().then(setCat).catch((e) => setErr(errorMessage(e))); }, []);
  useEffect(() => { loadMine(); loadCat(); }, [loadMine, loadCat]);
  useEffect(() => {
    const id = window.setInterval(() => { if (canPoll()) loadMine(); }, 60_000);
    return () => window.clearInterval(id);
  }, [loadMine]);
  // first visit with nothing owned: start on the buy list
  const [started, setStarted] = useState(false);
  useEffect(() => {
    if (!started && mine) { setStarted(true); if (mine.businesses.length === 0) setTab('buy'); }
  }, [mine, started]);

  const run = useCallback((key: string, fn: () => Promise<{ message: string }>) => {
    setBusy(key);
    fn().then(async (r) => {
      toast(r.message, 'good');
      await useGame.getState().refresh();
      void useGame.getState().loadLocations();
    }).catch((e) => toast(errorMessage(e), 'bad')).finally(() => { setBusy(null); loadMine(); loadCat(); });
  }, [loadMine, loadCat]);

  const total = (mine?.businesses ?? []).reduce((s, b) => s + b.takings, 0);
  const tabs = useMemo(() => [
    { id: 'mine', label: 'My businesses', badge: mine?.businesses.length || null },
    { id: 'buy', label: 'Buy a business' },
  ], [mine]);
  const here = state.location.id;
  const there = !state.travel;

  return (
    <div className="phone-app__body bz-app" data-testid="business-app">
      {mine && !mine.enabled && <p className="bz-err" role="status">Business ownership is closed for now. You can still collect and sell.</p>}
      <Tabs tabs={tabs} value={tab} onChange={(id) => setTab(id as Tab)} className="bz-tabs" tourPrefix="business" />
      {err && !mine && <p className="bz-err" role="alert">{err}</p>}

      {tab === 'mine' && (
        <div className="bz-list">
          {!mine && <div className="panel-skel"><span /><span /><span /></div>}
          {mine && mine.businesses.length === 0 && (
            <EmptyState icon="bag" title="No business yet" body="Buy a shop, a buka, a bar or even a filling station, and it earns while you hustle."
              action={<Button variant="gold" onClick={() => setTab('buy')}>See businesses for sale</Button>} />
          )}
          {mine && mine.businesses.length > 1 && total > 0 && (
            <Button variant="gold" block loading={busy === 'all'} onClick={() => run('all', () => businessCollect(null))}>Collect all · {naira(total)}</Button>
          )}
          {mine?.businesses.map((b) => (
            <MyCard key={b.id} b={b} info={mine} atHere={there && here === b.location} busy={busy} run={run} onGo={onGo} onSold={() => { loadMine(); loadCat(); }} />
          ))}
          {mine && mine.businesses.length > 0 && (
            <p className="bz-foot">{mine.businesses.length}/{mine.max_owned} businesses. Takings stop growing {mine.cap_hours} hours after your last collect. Customers who spend at your place pay you {mine.visit_cut_pct}% of the price.</p>
          )}
        </div>
      )}

      {tab === 'buy' && (
        <div className="bz-list">
          {!cat && <div className="panel-skel"><span /><span /><span /></div>}
          {cat && (
            <p className="bz-count">{cat.owned}/{cat.max_owned} owned · Business skill level {cat.skill_level}</p>
          )}
          {cat?.types.map((t) => <TypeCard key={t.id} t={t} onPick={(ty, s) => setPick({ t: ty, s })} />)}
        </div>
      )}
      {pick && <BuySheet t={pick.t} slot={pick.s} onClose={() => setPick(null)} onBought={(loc) => { setPick(null); loadMine(); loadCat(); setTab('mine'); void loc; }} />}
    </div>
  );
}
