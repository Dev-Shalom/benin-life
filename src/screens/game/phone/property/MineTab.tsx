// Houses -> My properties: the homes you own (bought or built, every unit of a block of flats), and the landlord's dashboard: tenant,
// rent, income, listing state, notice. Live here / List for rent / Give notice / Sell.
import { useState } from 'react';
import {
  propertyCancelNotice, propertyGiveNotice, propertyList, propertyLiveIn, propertySell, propertyUnlist, type PropCard, type PropOverview,
} from '../../../../api/property';
import { errorMessage } from '../../../../lib/api';
import { useNow } from '../../../../lib/clock';
import { naira, nairaShort, parseNaira } from '../../../../lib/format';
import { useProperty } from '../../../../state/property';
import { useUi } from '../../../../state/ui';
import { Button, EmptyState, toast } from '../../../../ui';
import { dateShort, daysLeft, QuoteRow, PSheet } from './util';

type Dlg = { kind: 'list' | 'sell' | 'notice'; p: PropCard } | null;

export default function MineTab({ data, onBuy }: { data: PropOverview; onBuy: () => void }) {
  const now = useNow(30_000);
  const afterAction = useProperty((s) => s.afterAction);
  const [open, setOpen] = useState<string | null>(null);
  const [dlg, setDlg] = useState<Dlg>(null);
  const [busy, setBusy] = useState<string | null>(null);

  const run = async (key: string, fn: () => Promise<{ message: string }>, then?: () => void) => {
    setBusy(key);
    try {
      const r = await fn();
      toast(r.message, 'good');
      await afterAction();
      then?.();
    } catch (e) {
      toast(errorMessage(e), 'bad');
    } finally {
      setBusy(null);
    }
  };

  const list = data.properties;
  const totalValue = list.reduce((t, p) => t + p.value, 0);
  const tenants = list.filter((p) => p.occupant?.role === 'tenant');
  const weekly = tenants.reduce((t, p) => t + (p.occupant?.rent ?? 0), 0);
  const earned = list.reduce((t, p) => t + p.earned, 0);

  if (list.length === 0) {
    return (
      <div className="pp-tab" data-testid="prop-mine">
        <EmptyState icon="home" title="You don't own a home yet"
          body="Buy a ready home, or build one on plots you own. Then live in it, or let it out and collect rent."
          action={<Button variant="green" onClick={onBuy}>See homes for sale</Button>} />
      </div>
    );
  }

  return (
    <div className="pp-tab" data-testid="prop-mine">
      <div className="pp-stats">
        <div className="pp-stat"><small>Homes</small><b>{list.length}</b></div>
        <div className="pp-stat"><small>Worth</small><b title={naira(totalValue)}>{nairaShort(totalValue)}</b></div>
        <div className="pp-stat is-good"><small>Rent a week</small><b title={naira(weekly)}>{nairaShort(weekly)}</b></div>
      </div>
      {earned > 0 && <p className="pp-hint">You have earned {naira(earned)} in rent so far (before the {data.settings.rent_cut_pct}% agent cut). Rent lands in your bank when your tenant pays on the rent day.</p>}
      <div className="pp-list">
        {list.map((p) => {
          const occ = p.occupant;
          const tenant = occ?.role === 'tenant' ? occ : null;
          const isOpen = open === p.id;
          const state = p.lives_here ? 'You live here' : tenant ? `@${tenant.username} rents it` : p.listed ? 'For rent' : 'Empty';
          return (
            <div key={p.id} className={`pp-prop${isOpen ? ' is-open' : ''}`}>
              <button type="button" className="pp-card pp-card--flat" onClick={() => setOpen(isOpen ? null : p.id)} aria-expanded={isOpen}>
                <span className="pp-card__icon" aria-hidden>{p.emoji}</span>
                <span className="pp-card__main">
                  <b>{p.name}</b>
                  <small>{p.source === 'built' ? 'Built by you' : 'Bought'} · {p.bedrooms} bedroom{p.bedrooms === 1 ? '' : 's'} · {p.m2} m²</small>
                  <span className="pp-tags">
                    <span className={`pp-tag${p.lives_here ? ' is-home' : tenant ? ' is-let' : p.listed ? ' is-listed' : ''}`}>{state}</span>
                    {tenant?.ends_at && <span className="pp-tag is-warn">Notice · {daysLeft(tenant.ends_at, now)}</span>}
                    {tenant && tenant.owed > 0 && <span className="pp-tag is-bad">Owes {nairaShort(tenant.owed)}</span>}
                    {p.pending_income > 0 && <span className="pp-tag is-good">Rent waiting</span>}
                  </span>
                </span>
                <span className="pp-card__price" title={naira(p.value)}>{nairaShort(p.value)}<small>worth</small></span>
              </button>
              {isOpen && (
                <div className="pp-prop__body">
                  <div className="pp-q pp-q--tight">
                    <QuoteRow label="Market rent a week" value={naira(p.market_rent)} />
                    {p.listed && p.listed_rent != null && !tenant && <QuoteRow label="Your asking rent" value={`${naira(p.listed_rent)}${p.caution > 0 ? ` + ${naira(p.caution)} caution` : ''}`} />}
                    {tenant && <QuoteRow label={`Rent from @${tenant.username}`} value={`${naira(tenant.rent)} a week`} />}
                    <QuoteRow label="Selling today pays" value={naira(p.sale.net)} hint={`${data.settings.resale_pct}% of the value, less the agent`} />
                    {p.upgrades > 0 && <QuoteRow label="Upgrades kept in it" value={String(p.upgrades)} />}
                    {p.earned > 0 && <QuoteRow label="Rent earned here" value={naira(p.earned)} />}
                  </div>
                  {tenant && (
                    <div className="pp-tenant" data-testid="prop-tenant">
                      <b>@{tenant.username}</b>
                      <small>
                        Since {dateShort(tenant.since)} · caution held {naira(tenant.caution)}
                        {tenant.owed > 0 ? ` · owes ${naira(tenant.owed)}` : ' · rent up to date'}
                      </small>
                      {tenant.ends_at ? (
                        <small className="pp-tenant__warn">Notice given: out by {dateShort(tenant.ends_at)} ({daysLeft(tenant.ends_at, now)}).</small>
                      ) : (
                        <small>A tenant who owes {data.settings.evict_owed_weeks} weeks of rent is moved out. Otherwise you give {data.settings.notice_days} days notice.</small>
                      )}
                    </div>
                  )}
                  <div className="pp-actions">
                    {!occ && (
                      <Button size="sm" variant="green" loading={busy === `in${p.id}`} onClick={() => void run(`in${p.id}`, () => propertyLiveIn(p.id), () => useUi.getState().setOverlay(null))}>Live here</Button>
                    )}
                    {!occ && !p.listed && data.rent_out_enabled && <Button size="sm" variant="gold" onClick={() => setDlg({ kind: 'list', p })}>List for rent</Button>}
                    {!occ && p.listed && <Button size="sm" variant="ghost" onClick={() => setDlg({ kind: 'list', p })}>Change rent</Button>}
                    {!occ && p.listed && <Button size="sm" variant="ghost" loading={busy === `un${p.id}`} onClick={() => void run(`un${p.id}`, () => propertyUnlist(p.id))}>Take off market</Button>}
                    {tenant && !tenant.ends_at && <Button size="sm" variant="ghost" onClick={() => setDlg({ kind: 'notice', p })}>Give notice</Button>}
                    {tenant?.ends_at && tenant.ended_by === 'landlord' && (
                      <Button size="sm" variant="ghost" loading={busy === `cn${p.id}`} onClick={() => void run(`cn${p.id}`, () => propertyCancelNotice(p.id))}>Withdraw notice</Button>
                    )}
                    {!occ && <Button size="sm" variant="danger" onClick={() => setDlg({ kind: 'sell', p })}>Sell</Button>}
                  </div>
                  {p.lives_here && <p className="pp-hint">You live here. To let it out or sell it, move into another home first (Rent tab).</p>}
                </div>
              )}
            </div>
          );
        })}
      </div>
      <ListSheet dlg={dlg?.kind === 'list' ? dlg.p : null} data={data} onClose={() => setDlg(null)} onDone={() => { setDlg(null); void afterAction(); }} />
      <SellSheet p={dlg?.kind === 'sell' ? dlg.p : null} data={data} onClose={() => setDlg(null)} />
      <PSheet open={dlg?.kind === 'notice'} onClose={() => setDlg(null)} title="Give notice?" subtitle={dlg?.p.name}
        footer={<div className="garage-sheet__foot">
          <Button block variant="danger" loading={busy === 'notice'} onClick={() => dlg && void run('notice', () => propertyGiveNotice(dlg.p.id), () => setDlg(null))}>Give {data.settings.notice_days} days notice</Button>
          <Button block variant="ghost" onClick={() => setDlg(null)}>Not now</Button>
        </div>}>
        <p className="pp-hint">
          @{dlg?.p.occupant?.username} will be told and must leave in {data.settings.notice_days} days. Their caution goes back to them.
          You can't throw a tenant out at once. When they are gone the home is taken off the market.
        </p>
      </PSheet>
    </div>
  );
}

function ListSheet({ dlg: p, data, onClose, onDone }: { dlg: PropCard | null; data: PropOverview; onClose: () => void; onDone: () => void }) {
  const [rent, setRent] = useState('');
  const [caution, setCaution] = useState('');
  const [busy, setBusy] = useState(false);
  const [lastId, setLastId] = useState<string | null>(null);
  if (p && p.id !== lastId) {
    setLastId(p.id);
    setRent(String(p.listed_rent ?? p.market_rent));
    setCaution(String(p.caution || 0));
  }
  const rentN = parseNaira(rent) ?? 0;
  const cautionN = parseNaira(caution, { allowZero: true }) ?? 0;
  const inBand = p ? rentN >= p.rent_min && rentN <= p.rent_max : false;
  const cautionMax = rentN * data.settings.caution_max_weeks;
  const cutPct = data.settings.rent_cut_pct;
  const save = async () => {
    if (!p) return;
    setBusy(true);
    try {
      const r = await propertyList(p.id, rentN, cautionN);
      toast(r.message, 'good');
      onDone();
    } catch (e) {
      toast(errorMessage(e), 'bad');
    } finally {
      setBusy(false);
    }
  };
  return (
    <PSheet open={Boolean(p)} onClose={busy ? () => {} : onClose} title="List for rent" subtitle={p?.name}
      footer={<div className="garage-sheet__foot">
        <Button block variant="green" loading={busy} disabled={!inBand || cautionN > cautionMax} onClick={() => void save()}>{rentN > 0 ? `List at ${naira(rentN)} a week` : 'List'}</Button>
        <Button block variant="ghost" disabled={busy} onClick={onClose}>Not now</Button>
      </div>}>
      {p && (
        <div className="pp-sheet">
          <label className="pp-field">
            <span>Rent a week</span>
            <input inputMode="numeric" value={rent} onChange={(e) => setRent(e.target.value)} aria-label="Weekly rent" />
          </label>
          <div className="pp-band">
            <div className="pp-band__bar"><span style={{ left: `${Math.max(0, Math.min(100, ((p.market_rent - p.rent_min) / Math.max(1, p.rent_max - p.rent_min)) * 100))}%` }} /></div>
            <div className="pp-band__labels"><small>{naira(p.rent_min)}</small><small>market {naira(p.market_rent)}</small><small>{naira(p.rent_max)}</small></div>
          </div>
          {!inBand && rentN > 0 && <p className="pp-note pp-note--bad">Rent for this home must be between {naira(p.rent_min)} and {naira(p.rent_max)}.</p>}
          <label className="pp-field">
            <span>Caution (optional, paid back when they leave)</span>
            <input inputMode="numeric" value={caution} onChange={(e) => setCaution(e.target.value)} aria-label="Caution fee" />
          </label>
          {cautionN > cautionMax && <p className="pp-note pp-note--bad">At most {data.settings.caution_max_weeks} weeks of rent: {naira(cautionMax)}.</p>}
          <ul className="pp-bullets">
            <li>You get about <b>{naira(Math.round(rentN * (100 - cutPct) / 100))}</b> a week after the {cutPct}% agent cut.</li>
            <li>The tenant also pays the agent and the first week up front. You can't change the rent while someone lives there.</li>
            <li>To get the home back you give {data.settings.notice_days} days notice. The tenant can leave any time.</li>
          </ul>
        </div>
      )}
    </PSheet>
  );
}

function SellSheet({ p, data, onClose }: { p: PropCard | null; data: PropOverview; onClose: () => void }) {
  const [busy, setBusy] = useState(false);
  const afterAction = useProperty((s) => s.afterAction);
  const sell = async () => {
    if (!p) return;
    setBusy(true);
    try {
      const r = await propertySell(p.id);
      toast(r.message, 'good');
      onClose();
      await afterAction();
    } catch (e) {
      toast(errorMessage(e), 'bad');
    } finally {
      setBusy(false);
    }
  };
  return (
    <PSheet open={Boolean(p)} onClose={busy ? () => {} : onClose} title="Sell this home?" subtitle={p?.name}
      footer={<div className="garage-sheet__foot">
        <Button block variant="danger" loading={busy} onClick={() => void sell()}>{p ? `Sell for ${naira(p.sale.net)}` : 'Sell'}</Button>
        <Button block variant="ghost" disabled={busy} onClick={onClose}>Keep it</Button>
      </div>}>
      {p && (
        <div className="pp-sheet">
          <div className="pp-q">
            <QuoteRow label="Worth today" value={naira(p.value)} />
            <QuoteRow label={`Market pays ${data.settings.resale_pct}%`} value={naira(p.sale.gross)} />
            <QuoteRow label={`Agent fee ${data.settings.sell_agent_pct}%`} value={`-${naira(p.sale.agent)}`} />
            {p.sale.upgrades > 0 && <QuoteRow label="Upgrades paid back" value={naira(p.sale.upgrades)} />}
            <QuoteRow label="Into your bank" strong value={naira(p.sale.net)} />
          </div>
          <p className="pp-hint">You paid about {naira(p.basis)} for it. The market never pays more than that, so selling right after buying always loses the fees.{p.source === 'built' ? ' The plots under it go with the house.' : ''}</p>
        </div>
      )}
    </PSheet>
  );
}
