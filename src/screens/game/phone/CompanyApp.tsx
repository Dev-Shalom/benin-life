// Business app hub (docs/COMPANIES.md). One phone icon ("Business"), four tabs: "My companies" (start a company, till, branches, staff, pricing,
// marketing, news), "Map plots" (the original plot businesses, BusinessApp), "Discover" (every company and verified real business, plus Rankings)
// and "Real business" (put a real business on the map for real money).
// Server settles each evening lazily (6 PM Benin): one company_status call per open app, no polling, a refresh only after an action.
import { lazy, Suspense, useCallback, useEffect, useMemo, useState } from 'react';
import {
  companyBranchAdd, companyBranchUpgrade, companyCashout, companyDiscover, companyFire, companyGenerator, companyHire, companyManager, companyMarketingBuy, companyPublic,
  companyRankings, companyRegister, companySell, companySetPricing, companyStatus, COLORS, EVENT_TEXT, LOGOS,
  type AreaInfo, type CompanyCard, type CompanyStatus, type DiscoverRow, type IndustryInfo, type PublicCompany, type RankRow,
} from '../../../api/company';
import { errorMessage } from '../../../lib/api';
import { naira, nairaShort } from '../../../lib/format';
import { useGame } from '../../../state/game';
import { useRealBiz } from '../../../lib/realBiz';
import type { GameState } from '../../../lib/types';
import { Button, EmptyState, Modal, Sheet, Tabs, toast } from '../../../ui';
import { SellToPlayersButton } from '../SellToPlayers';
import { RealBizFormModal, RealListings } from './RealBizForm';
import './BusinessApp.css';
import './CompanyApp.css';

const BusinessApp = lazy(() => import('./BusinessApp'));
export type Tab = 'mine' | 'plots' | 'discover' | 'real';
const LOG_ICON: Record<string, string> = {
  founded: '🏁', night: '🌙', cashout: '💰', branch: '🏬', format: '⬆️', hire: '🧑‍🍳', fire: '👋', manager: '🧑‍💼', generator: '⚡', pricing: '🏷️', marketing: '📣', till_full: '🚫', capped: '🧢',
  listed: '🏷️', unlisted: '↩️', market_buy: '🏷️', ev_good_review: '⭐', ev_bad_review: '😠', ev_outage: '💡', ev_supplier: '🚚',
};
const TIER = (n: number) => '₦'.repeat(n);
const timeOf = (iso: string) => new Date(iso).toLocaleTimeString('en-GB', { hour: 'numeric', minute: '2-digit', hour12: true, timeZone: 'Africa/Lagos' });

function Stars({ n }: { n: number }) {
  return <span className="bz-stars" aria-label={`${n} of 5 stars`}>{Array.from({ length: 5 }, (_, i) => <span key={i} className={i < n ? 'is-on' : ''} aria-hidden>★</span>)}</span>;
}
function Stat({ label, value, tone }: { label: string; value: string; tone?: 'good' | 'bad' | 'warn' }) {
  return <span className={`bz-stat${tone ? ` is-${tone}` : ''}`}><small>{label}</small><b>{value}</b></span>;
}
const signed = (n: number) => `${n < 0 ? '−' : ''}${nairaShort(Math.abs(n))}`;

// ------------------------------------------------------------------------------------------------ start a company
function StartCompany({ st, onClose, onDone }: { st: CompanyStatus; onClose: () => void; onDone: () => void }) {
  const [name, setName] = useState('');
  const [industry, setIndustry] = useState<IndustryInfo | null>(null);
  const [area, setArea] = useState<AreaInfo | null>(st.areas.find((a) => a.id === 'ugbowo') ?? st.areas[0] ?? null);
  const [logo, setLogo] = useState('🍲');
  const [color, setColor] = useState(COLORS[0]);
  const [busy, setBusy] = useState(false);
  const profile = useGame((s) => s.state?.profile);
  const money = (profile?.cash ?? 0) + Math.max(0, profile?.bank ?? 0);
  const setup = industry && area ? Math.round((industry.price * area.setup_mult) / 10) * 10 : 0;
  const total = st.reg_fee + setup;
  const go = async () => {
    if (!industry || !area) return;
    setBusy(true);
    try {
      const r = await companyRegister(name.trim(), industry.id, logo, color, area.id);
      toast(r.message, 'good');
      await useGame.getState().refresh();
      onDone();
    } catch (e) { toast(errorMessage(e), 'bad'); } finally { setBusy(false); }
  };
  const tiers = [1, 2, 3, 4].map((t) => ({ t, rows: st.areas.filter((a) => a.tier === t) })).filter((x) => x.rows.length);
  return (
    <Modal open onClose={() => !busy && onClose()} title="🏢 Start a company"
      actions={<>
        <Button variant="ghost" disabled={busy} onClick={onClose}>Back</Button>
        <Button variant="gold" loading={busy} disabled={!industry || !area || name.trim().length < 3 || money < total} onClick={() => void go()} data-testid="company-register">
          {!industry ? 'Pick an industry' : money < total ? 'Not enough money' : `Register · ${naira(total)}`}
        </Button>
      </>}>
      <div className="co-form" data-testid="company-start">
        <label className="bz-field"><span>Company name (unique)</span>
          <input value={name} maxLength={28} onChange={(e) => setName(e.target.value)} placeholder="e.g. Mama Nosa Foods" enterKeyHint="done" data-testid="company-name" /></label>
        <div className="bz-field"><span>Industry</span>
          <div className="co-picks" data-tour="business-industries">
            {st.industries.map((i) => (
              <button key={i.id} type="button" className={`co-pick${industry?.id === i.id ? ' is-on' : ''}${i.met ? '' : ' is-locked'}`} onClick={() => i.met && setIndustry(i)} data-testid={`industry-${i.id}`}>
                <span className="co-pick__icon" aria-hidden>{i.icon}</span>
                <b>{i.name}</b>
                <small>From {nairaShort(i.price)}</small>
                <small>{i.met ? `~${nairaShort(i.base_revenue)} sales a night` : i.gate ?? 'Locked'}</small>
              </button>
            ))}
          </div>
          {industry && <p className="bz-hint">{industry.blurb}{industry.req_skill_level > 1 || industry.req_cert_text ? ` Needs: ${[industry.req_skill_level > 1 ? `Business skill ${industry.req_skill_level}` : null, industry.req_cert_text].filter(Boolean).join(' and ')}.` : ''}</p>}
        </div>
        <div className="bz-field"><span>Head office area</span>
          <div className="co-areas" data-testid="company-areas">
            {tiers.map(({ t, rows }) => (
              <div key={t} className="co-tier"><h5>{TIER(t)} {['Outskirts', 'Mid city', 'Upscale', 'Premium'][t - 1]}</h5>
                <div className="co-chips">{rows.map((a) => (
                  <button key={a.id} type="button" className={`co-area${area?.id === a.id ? ' is-on' : ''}`} onClick={() => setArea(a)} data-testid={`area-${a.id}`}>
                    <b>{a.name}</b><small>setup ×{a.setup_mult} · sales ×{a.rev_mult}</small></button>
                ))}</div></div>
            ))}
          </div>
        </div>
        <div className="co-two">
          <div className="bz-field"><span>Logo</span><div className="co-emoji">{LOGOS.map((l) => <button key={l} type="button" className={logo === l ? 'is-on' : ''} onClick={() => setLogo(l)} aria-label={`Logo ${l}`}>{l}</button>)}</div></div>
          <div className="bz-field"><span>Colour</span><div className="co-swatches">{COLORS.map((c) => <button key={c} type="button" className={color === c ? 'is-on' : ''} style={{ background: c }} onClick={() => setColor(c)} aria-label={`Colour ${c}`} />)}</div></div>
        </div>
        <div className="co-preview" style={{ borderColor: color }}><span className="co-logo" style={{ background: color }} aria-hidden>{logo}</span><b>{name.trim() || 'Your company'}</b><small>{industry?.name ?? 'Industry'} · {area?.name ?? 'Area'}</small></div>
        <div className="bz-rows">
          <div><span>Registration fee</span><b>{naira(st.reg_fee)}</b></div>
          <div><span>Setup ({industry?.name ?? 'industry'} in {area?.name ?? 'area'})</span><b>{industry ? naira(setup) : '–'}</b></div>
          <div><span>Total</span><b>{industry ? naira(total) : '–'}</b></div>
        </div>
        <p className="bz-hint">No map plot needed: anybody can open a company. Your first evening settles at {st.settle_hour}:00 Benin time.</p>
      </div>
    </Modal>
  );
}

// ------------------------------------------------------------------------------------------------ one company
function CompanyView({ c, st, busy, run, onSold }: {
  c: CompanyCard; st: CompanyStatus; busy: string | null; run: (key: string, fn: () => Promise<{ message: string }>) => void; onSold: () => void;
}) {
  const [open, setOpen] = useState(false);
  const [sell, setSell] = useState(false);
  const [branchPick, setBranchPick] = useState(false);
  const k = (a: string) => `${a}${c.id}`;
  const off = c.listed || !st.enabled;
  const used = new Set(c.branches.map((b) => b.area));
  const share = async () => {
    try {
      if (navigator.share) await navigator.share({ title: c.name, url: c.share });
      else { await navigator.clipboard.writeText(c.share); toast('Link copied: ' + c.share, 'good'); }
    } catch { /* cancelled */ }
  };
  const fill = Math.round((c.till_nights / c.cap_nights) * 100);
  return (
    <article className={`bz-card co-card${c.listed ? ' is-listed' : ''}`} style={{ '--co': c.color } as React.CSSProperties} data-testid="company-card">
      <header className="bz-card__head">
        <span className="co-logo" style={{ background: c.color }} aria-hidden>{c.logo}</span>
        <span className="bz-card__title"><b>{c.name}</b><small>{c.industry_name} · HQ {c.hq_area}{c.branches.length > 1 ? ` + ${c.branches.length - 1} branch${c.branches.length > 2 ? 'es' : ''}` : ''}</small></span>
        <Stars n={c.stars} />
      </header>
      {c.listed && <p className="bz-note">🏷️ On the Market. It is locked until it sells or you take it down (Market app).</p>}

      <div className="bz-take" data-tour="company-till">
        <span className="bz-take__num"><small>Till</small><b data-testid="company-till">{naira(c.till)}</b></span>
        <Button variant="gold" size="sm" disabled={c.till < 1 || c.listed} loading={busy === k('c')} onClick={() => run(k('c'), () => companyCashout(c.id))} data-testid="company-cashout">Cash out</Button>
      </div>
      {!c.listed && (
        <div className="bz-fill" title="The till stops growing when it holds the most uncollected evenings">
          <span className="bz-fill__bar"><span style={{ width: `${fill}%` }} className={c.full ? 'is-full' : ''} /></span>
          <small>{c.full ? 'Till full. Cash out: more evenings are lost.' : `${c.till_nights}/${c.cap_nights} evenings in the till`} · next evening {timeOf(c.next_settle_at)}</small>
        </div>
      )}

      <div className="co-evening">
        <h5>{c.last ? `Last evening (${new Date(c.last.night).toLocaleDateString([], { day: 'numeric', month: 'short' })})` : 'No evening yet'}</h5>
        {c.last ? (
          <div className="bz-stats">
            <Stat label="Customers" value={String(c.last.customers)} />
            <Stat label="Sales" value={nairaShort(c.last.sales)} />
            <Stat label="Before bills" value={signed(c.last.before_bills)} />
            <Stat label="After bills" value={signed(c.last.net)} tone={c.last.net < 0 ? 'bad' : 'good'} />
            <Stat label="Stars" value={`${c.last.stars}`} />
            <Stat label="Events" value={c.last.events.length ? c.last.events.map((e) => EVENT_TEXT[e] ?? e).join(', ') : 'None'} tone={c.last.events.includes('outage') || c.last.events.includes('bad_review') ? 'warn' : undefined} />
          </div>
        ) : <p className="bz-hint">Your first evening settles at {timeOf(c.next_settle_at)}. Hire staff before then.</p>}
        <div className="co-tonight"><small>Tonight (estimate)</small>
          <span>{c.tonight.customers} customers · {nairaShort(c.tonight.sales)} sales · {signed(c.tonight.before_bills)} before bills · <b>{signed(c.tonight.after_bills)}</b> after bills</span></div>
      </div>

      <div className="co-sect" data-tour="company-branches"><h5>Locations</h5>
        {c.branches.map((b) => (
          <div key={b.id} className="co-branch" data-testid="company-branch">
            <span aria-hidden>{b.emoji}</span>
            <span className="grow"><b>{b.area_name}{b.is_hq ? ' · HQ' : ''}</b><small>{b.format_name} · {TIER(b.tier)} · {b.staff_slots} staff slots · upkeep {nairaShort(b.upkeep_week)}/wk</small></span>
            {b.next_format && <Button size="sm" variant="green" disabled={off} loading={busy === k('f' + b.id)} onClick={() => run(k('f' + b.id), () => companyBranchUpgrade(c.id, b.id))}>{b.next_name} · {nairaShort(b.next_cost ?? 0)}</Button>}
          </div>
        ))}
        {c.branches.length - 1 < c.max_branches && <Button size="sm" variant="ghost" disabled={off} onClick={() => setBranchPick((p) => !p)}>+ Branch · from {nairaShort(c.branch_cost)}</Button>}
        {branchPick && <div className="co-chips">{st.areas.filter((a) => !used.has(a.id)).map((a) => (
          <button key={a.id} type="button" className="co-area" disabled={off} onClick={() => { setBranchPick(false); run(k('b'), () => companyBranchAdd(c.id, a.id)); }}>
            <b>{a.name}</b><small>{TIER(a.tier)} · {nairaShort(Math.round(c.branch_cost * a.setup_mult))}</small></button>
        ))}</div>}
      </div>

      <div className="co-sect" data-tour="company-staff"><h5>Staff and pricing</h5>
        <div className="bz-actions">
          <Button size="sm" variant="ghost" disabled={off || c.staff >= c.staff_slots} loading={busy === k('h')} onClick={() => run(k('h'), () => companyHire(c.id))} data-testid="company-hire">Hire · {nairaShort(c.hire_fee)}</Button>
          {c.staff > 0 && <Button size="sm" variant="ghost" disabled={c.listed} loading={busy === k('x')} onClick={() => run(k('x'), () => companyFire(c.id))}>Let one go</Button>}
          {c.manager
            ? <Button size="sm" variant="ghost" disabled={c.listed} loading={busy === k('m')} onClick={() => run(k('m'), () => companyManager(c.id, false))}>Let Manager go</Button>
            : <Button size="sm" variant="ghost" disabled={off} loading={busy === k('m')} onClick={() => run(k('m'), () => companyManager(c.id, true))}>Manager · {nairaShort(c.manager_fee)}</Button>}
          {!c.generator && <Button size="sm" variant="ghost" disabled={off} loading={busy === k('g')} onClick={() => run(k('g'), () => companyGenerator(c.id))}>Generator · {nairaShort(c.generator_cost)}</Button>}
        </div>
        <p className="bz-hint">Staff {c.staff}/{c.staff_slots} at {naira(c.wage)} a week each{c.manager ? ` · Manager ${naira(c.manager_wage)} a week: +${c.manager_bonus_pct}% customers, till holds ${c.manager_extra_nights} more evenings` : ''}{c.generator ? ` · Generator: outages cost ${100 - c.generator_cut_pct}%` : ''}. Weekly bills {naira(c.week_bills)}, taken from the till 1/7 each evening.</p>
        <div className="co-seg" role="group" aria-label="Pricing">
          {(['cheap', 'fair', 'premium'] as const).map((p) => (
            <button key={p} type="button" className={c.pricing === p ? 'is-on' : ''} disabled={c.listed} onClick={() => c.pricing !== p && run(k('p'), () => companySetPricing(c.id, p))} data-testid={`pricing-${p}`}>
              {p[0].toUpperCase() + p.slice(1)}<small>{p === 'fair' ? 'normal' : `×${st.pricing[p][0]} people, ×${st.pricing[p][1]} price`}</small></button>
          ))}
        </div>
      </div>

      <div className="co-sect" data-tour="company-marketing"><h5>Marketing {c.boost_nights > 0 ? `· +${c.boost_pct}% for ${c.boost_nights} evening${c.boost_nights > 1 ? 's' : ''}` : ''}</h5>
        <div className="co-mk">{c.marketing.map((m) => (
          <Button key={m.id} size="sm" variant="ghost" block disabled={off} loading={busy === k('k' + m.id)} onClick={() => run(k('k' + m.id), () => companyMarketingBuy(c.id, m.id))}>
            {m.emoji} {m.name} +{m.boost_pct}% · {m.nights}n · {nairaShort(m.cost)}</Button>
        ))}</div>
      </div>

      <div className="bz-actions">
        <Button size="sm" variant="ghost" onClick={() => void share()}>Share · /c/{c.id}</Button>
        <button type="button" className="bz-more" onClick={() => setOpen((o) => !o)} aria-expanded={open}>{open ? 'Hide news and value' : 'News and value'}</button>
      </div>
      {open && (
        <div className="bz-details" data-testid="company-news">
          <div className="bz-rows">
            <div><span>Company value (about 30 days of profit)</span><b>{naira(c.value)}</b></div>
            <div><span>Sales so far</span><b>{naira(c.lifetime_sales)}</b></div>
            <div><span>Profit so far</span><b>{naira(c.lifetime_net)}</b></div>
            <div><span>Cashed out</span><b>{naira(c.lifetime_cashed)}</b></div>
          </div>
          <h5>News</h5>
          {(c.log ?? []).length === 0 && <p className="muted">Nothing yet.</p>}
          <ul className="bz-log">{(c.log ?? []).map((l) => (
            <li key={l.id} className={l.kind.startsWith('ev_') ? (l.kind === 'ev_good_review' ? 'is-good' : 'is-bad') : ''}>
              <span aria-hidden>{LOG_ICON[l.kind] ?? '•'}</span>
              <span className="bz-log__t">{l.title}<small>{new Date(l.at).toLocaleString([], { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' })}</small></span>
              {l.amount !== 0 && <b className={l.amount > 0 ? 'is-up' : 'is-down'}>{l.amount > 0 ? '+' : '−'}{nairaShort(Math.abs(l.amount))}</b>}
            </li>))}</ul>
          <div className="bz-actions">
            <SellToPlayersButton kind="company" refId={String(c.id)} name={c.name} icon={c.logo} label="Sell to players" onListed={onSold} />
            <Button size="sm" variant="danger" disabled={c.listed} onClick={() => setSell(true)}>Sell to the system · {nairaShort(c.sell_value)}</Button>
          </div>
        </div>
      )}
      {sell && (
        <Modal open onClose={() => setSell(false)} title={`Sell ${c.name}?`}
          actions={<><Button variant="ghost" onClick={() => setSell(false)}>Keep it</Button>
            <Button variant="danger" onClick={() => { setSell(false); run(k('s'), () => companySell(c.id).then((r) => { onSold(); return r; })); }}>Sell for {naira(c.sell_value)}</Button></>}>
          <p>The system pays {st.sell_pct}% of the company value ({naira(c.value)}). Your till ({naira(c.till)}) is paid out as well. Sell to another player on the Market to get more.</p>
        </Modal>
      )}
    </article>
  );
}

// ------------------------------------------------------------------------------------------------ public card
export function CompanyPublicSheet({ id, onClose }: { id: number; onClose: () => void }) {
  const [c, setC] = useState<PublicCompany | null | undefined>(undefined);
  useEffect(() => { companyPublic(id).then(setC).catch(() => setC(null)); }, [id]);
  return (
    <Sheet open onClose={onClose} title={c?.name ?? 'Company'} className="co-sheet">
      {c === undefined && <div className="panel-skel"><span /><span /></div>}
      {c === null && <p className="bz-hint">That company is not here any more.</p>}
      {c && <PublicCard c={c} />}
    </Sheet>
  );
}
export function PublicCard({ c }: { c: PublicCompany }) {
  return (
    <div className="co-public" data-testid="company-public" style={{ '--co': c.color } as React.CSSProperties}>
      <span className="co-logo co-logo--big" style={{ background: c.color }} aria-hidden>{c.logo}</span>
      <h3>{c.name}</h3>
      <Stars n={c.stars} />
      <p className="co-meta">{c.icon} {c.industry_name} · {c.locations} location{c.locations > 1 ? 's' : ''} · {c.areas.join(', ')}</p>
      <p className="co-desc">{c.blurb}</p>
      <div className="bz-rows"><div><span>Owner</span><b>@{c.owner}</b></div><div><span>Sales, last 7 evenings</span><b>{c.sales_band ?? naira(c.sales_7d ?? 0)}</b></div>
        {c.rank && <div><span>Rank this week</span><b>#{c.rank}</b></div>}</div>
      <p className="bz-hint">Share link: {c.share}</p>
    </div>
  );
}

// ------------------------------------------------------------------------------------------------ discover + rankings
function Discover({ st, initialView = 'browse' }: { st: CompanyStatus; initialView?: 'browse' | 'ranks' }) {
  const [mode, setMode] = useState<'browse' | 'ranks'>(initialView);
  const [q, setQ] = useState('');
  const [ind, setInd] = useState('');
  const [area, setArea] = useState('');
  const [kind, setKind] = useState('all');
  const [rows, setRows] = useState<DiscoverRow[] | null>(null);
  const [total, setTotal] = useState(0);
  const [view, setView] = useState<number | null>(null);
  const open = useRealBiz((s) => s.open);
  useEffect(() => {
    const t = window.setTimeout(() => { companyDiscover(q, ind, area, kind).then((r) => { setRows(r.rows); setTotal(r.total); }).catch(() => setRows([])); }, 250);
    return () => window.clearTimeout(t);
  }, [q, ind, area, kind]);
  const switcher = (
    <div className="co-switch" role="tablist" aria-label="Discover view">
      <button type="button" role="tab" aria-selected={mode === 'browse'} className={mode === 'browse' ? 'is-on' : ''} onClick={() => setMode('browse')}>Browse</button>
      <button type="button" role="tab" aria-selected={mode === 'ranks'} className={mode === 'ranks' ? 'is-on' : ''} onClick={() => setMode('ranks')} data-testid="company-rankings-tab">👑 Rankings</button>
    </div>
  );
  if (mode === 'ranks') return <div className="bz-list">{switcher}<Rankings /></div>;
  return (
    <div className="bz-list" data-testid="company-discover">
      {switcher}
      <input className="co-search" type="search" value={q} onChange={(e) => setQ(e.target.value)} placeholder="Search companies and businesses" enterKeyHint="search" />
      <div className="co-two">
        <select value={ind} onChange={(e) => setInd(e.target.value)} aria-label="Industry"><option value="">All industries</option>{st.industries.map((i) => <option key={i.id} value={i.id}>{i.icon} {i.name}</option>)}<option value="other">🏷️ Other</option></select>
        <select value={area} onChange={(e) => setArea(e.target.value)} aria-label="Area"><option value="">All areas</option>{st.areas.map((a) => <option key={a.id} value={a.id}>{a.name}</option>)}</select>
      </div>
      <div className="bz-chips">{[['all', 'All'], ['company', 'In-game companies'], ['real', 'Real businesses']].map(([id, label]) => (
        <button key={id} type="button" className={`bz-chip${kind === id ? ' is-ok' : ''}`} onClick={() => setKind(id)}>{label}</button>))}</div>
      {!rows && <div className="panel-skel"><span /><span /><span /></div>}
      {rows && rows.length === 0 && <EmptyState icon="bag" title="Nothing found" body="Try another search, industry or area." />}
      {rows && <p className="bz-count">{total} result{total === 1 ? '' : 's'}</p>}
      {rows?.map((r) => (
        <button key={`${r.kind}${r.id}`} type="button" className={`co-row${r.verified ? ' is-real' : ''}`} onClick={() => (r.kind === 'real' ? open(r.id) : setView(Number(r.id)))} data-testid={`discover-${r.kind}`}>
          <span className="co-logo" style={{ background: r.color }} aria-hidden>{r.logo}</span>
          <span className="grow"><b>{r.name}</b><small>{r.icon} {r.industry_name} · {r.area_name}</small>
            {r.verified ? <small className="co-verified">✔ Verified real business</small> : <small>{r.locations} location{r.locations > 1 ? 's' : ''} · @{r.owner}</small>}</span>
          {r.stars != null && <Stars n={r.stars} />}
        </button>
      ))}
      {view != null && <CompanyPublicSheet id={view} onClose={() => setView(null)} />}
    </div>
  );
}

function Rankings() {
  const [rows, setRows] = useState<RankRow[] | null>(null);
  const [view, setView] = useState<number | null>(null);
  useEffect(() => { companyRankings().then((r) => setRows(r.rows)).catch(() => setRows([])); }, []);
  return (
    <div className="co-ranks" data-testid="company-ranks">
      <p className="bz-hint">Top companies by sales over the last 7 evenings.</p>
      {!rows && <div className="panel-skel"><span /><span /><span /></div>}
      {rows && rows.length === 0 && <EmptyState icon="star" title="No sales yet" body="Rankings fill up after the first evening at 6 PM." />}
      {rows?.map((r) => (
        <button key={r.id} type="button" className={`co-row${r.mine ? ' is-mine' : ''}`} onClick={() => setView(r.id)}>
          <b className="co-rank">#{r.rank}</b>
          <span className="co-logo" style={{ background: r.color }} aria-hidden>{r.logo}</span>
          <span className="grow"><b>{r.name}</b><small>{r.icon} {r.industry} · @{r.owner}</small></span>
          <span className="co-sales">{r.sales_band ?? nairaShort(r.sales_7d ?? 0)}<Stars n={r.stars} /></span>
        </button>
      ))}
      {view != null && <CompanyPublicSheet id={view} onClose={() => setView(null)} />}
    </div>
  );
}

// ------------------------------------------------------------------------------------------------ the app
export default function CompanyApp({ state, onGo, initialTab = 'mine' }: { state: GameState; onGo: (id: string) => void; initialTab?: Tab }) {
  const [tab, setTab] = useState<Tab>(initialTab);
  const [dview, setDview] = useState<'browse' | 'ranks'>('browse');
  const [st, setSt] = useState<CompanyStatus | null>(null);
  const [err, setErr] = useState('');
  const [busy, setBusy] = useState<string | null>(null);
  const [start, setStart] = useState(false);
  const [real, setReal] = useState(false);
  const load = useCallback(() => { companyStatus().then((s) => { setSt(s); setErr(''); }).catch((e) => setErr(errorMessage(e))); }, []);
  useEffect(() => { load(); }, [load]);
  const run = useCallback((key: string, fn: () => Promise<{ message: string }>) => {
    setBusy(key);
    fn().then(async (r) => { toast(r.message, 'good'); await useGame.getState().refresh(); })
      .catch((e) => toast(errorMessage(e), 'bad')).finally(() => { setBusy(null); load(); });
  }, [load]);
  const total = (st?.companies ?? []).reduce((s, c) => s + (c.listed ? 0 : c.till), 0);
  const tabs = useMemo(() => [
    { id: 'mine', label: 'My companies', badge: st?.companies.length || null },
    { id: 'plots', label: 'Map plots' }, { id: 'discover', label: 'Discover' }, { id: 'real', label: 'Real business' },
  ], [st]);
  return (
    <div className="phone-app__body bz-app co-app" data-testid="business-hub">
      <Tabs tabs={tabs} value={tab} onChange={(id) => setTab(id as Tab)} className="bz-tabs" tourPrefix="business" />
      {err && !st && <p className="bz-err" role="alert">{err}</p>}
      {st && !st.enabled && <p className="bz-err" role="status">Companies are closed for now. You can still cash out and sell.</p>}

      {tab === 'mine' && (
        <div className="bz-list">
          {!st && <div className="panel-skel"><span /><span /><span /></div>}
          {st && st.companies.length === 0 && (
            <section className="co-hero" data-testid="company-empty">
              <span className="co-hero__emoji" aria-hidden>🏢</span>
              <h3>Start a company</h3>
              <p>{nairaShort(st.reg_fee)} to register. Customers every evening.</p>
              <button type="button" className="co-pill co-pill--green" disabled={!st.enabled || st.owned >= st.max_owned} onClick={() => setStart(true)} data-testid="company-start-btn" data-tour="business-start">Register</button>
            </section>
          )}
          {st && st.companies.length === 0 && (
            <button type="button" className="co-pill co-pill--ghost" onClick={() => { setDview('ranks'); setTab('discover'); }} data-testid="company-rankings-btn"><span aria-hidden>👑</span> Rankings</button>
          )}
          {st && st.companies.length > 0 && (
            <Button variant="gold" block disabled={!st.enabled || st.owned >= st.max_owned} onClick={() => setStart(true)} data-testid="company-start-btn" data-tour="business-start">
              + Start another company
            </Button>
          )}
          {st && st.companies.length > 1 && total > 0 && <Button variant="green" block loading={busy === 'all'} onClick={() => run('all', () => companyCashout(null))}>Cash out all · {naira(total)}</Button>}
          {st?.companies.map((c) => <CompanyView key={c.id} c={c} st={st} busy={busy} run={run} onSold={load} />)}
          {st && st.companies.length > 0 && (
            <article className="bz-card co-soon"><span aria-hidden>🛍️</span><span><b>Player shop</b><small>Coming soon: list items from your industry for other players to buy.</small></span></article>
          )}
        </div>
      )}
      {tab === 'discover' && st && <Discover key={dview} st={st} initialView={dview} />}
      {tab === 'real' && <div className="bz-list"><RealListings onNew={() => setReal(true)} /></div>}
      {tab === 'plots' && <Suspense fallback={<div className="panel-skel"><span /><span /></div>}><div className="co-plots"><BusinessApp state={state} onGo={onGo} embedded /></div></Suspense>}
      {start && st && <StartCompany st={st} onClose={() => setStart(false)} onDone={() => { setStart(false); load(); }} />}
      {real && <RealBizFormModal onClose={() => setReal(false)} onDone={() => { setReal(false); load(); }} />}
    </div>
  );
}
