// Phone "Houses" app (V1-4): your home, weekly rent, the next rent day, rent owed + Pay now.
// H1: Move house: every home with its size, rent and move-in fee; picking one opens the confirm sheet.
// Own your home (docs/PROPERTY.md): tabs Home / Rent / Buy / Build / Mine / Past. Home is the old screen (your home, rent, upgrades);
// Rent has the city landlord's homes and the homes other players let out; Buy, Build, My properties (landlord dashboard), Past homes.
import { useEffect, useState } from 'react';
import { houseOptions, type HouseOptions } from '../../../api/houses';
import { payRent } from '../../../api/shops';
import { errorMessage } from '../../../lib/api';
import { dateLabel, gameClockAt, useNow, weekdayOf } from '../../../lib/clock';
import { clockTime, naira, realDuration } from '../../../lib/format';
import { WEEKDAYS } from '../../../lib/pidgin';
import type { GameState } from '../../../lib/types';
import { useCatalog } from '../../../state/catalog';
import { useGame } from '../../../state/game';
import { useProperty } from '../../../state/property';
import { useUi } from '../../../state/ui';
import { Button, Tabs, toast } from '../../../ui';
import HouseUpgrades from './HouseUpgrades';
import BuildTab from './property/BuildTab';
import BuyTab from './property/BuyTab';
import MineTab from './property/MineTab';
import PastTab from './property/PastTab';
import RentTab from './property/RentTab';
import { dateShort, daysLeft } from './property/util';
import './property/property.css';

type Tab = 'home' | 'rent' | 'buy' | 'build' | 'mine' | 'past';
const TAB_IDS: Tab[] = ['home', 'rent', 'buy', 'build', 'mine', 'past'];

export default function HousesApp({ state }: { state: GameState }) {
  const refresh = useGame((s) => s.refresh);
  const byId = useGame((s) => s.locationsById);
  const catalog = useCatalog((s) => s.catalog);
  const loadCatalog = useCatalog((s) => s.loadCatalog);
  const prop = useProperty((s) => s.data);
  const loadProp = useProperty((s) => s.load);
  const phoneApp = useUi((s) => s.phoneApp);
  const nonce = useUi((s) => s.phoneNonce);
  const now = useNow(15_000);
  const [paying, setPaying] = useState(false);
  const [opts, setOpts] = useState<HouseOptions | null>(null);
  const [tab, setTab] = useState<Tab>('home');
  useEffect(() => {
    void loadCatalog();
  }, [loadCatalog]);
  // deep links: houses:buy, houses:build, houses:mine ...
  useEffect(() => {
    const m = /^houses:(home|rent|buy|build|mine|past)$/.exec(phoneApp ?? '');
    if (m) setTab(m[1] as Tab);
  }, [phoneApp, nonce]);
  // the whole property picture (builds, rent income and tenancies settle on this call), again after any move
  useEffect(() => { void loadProp(); }, [loadProp, state.profile.start_home, state.profile.home_location_id]);
  // reload the city list and the past homes after a move (start_home changes) or any property action
  useEffect(() => {
    let alive = true;
    houseOptions().then((o) => alive && setOpts(o)).catch(() => alive && setOpts(null));
    return () => { alive = false; };
  }, [state.profile.start_home, prop]);
  const visiting = Boolean(state.profile.home_visit_host_id);

  const p = state.profile;
  const rent = state.rent;
  const res = prop?.residence ?? null;
  const home = catalog?.homes.find((h) => h.id === p.start_home);
  const loc = byId[p.home_location_id];
  const weekly = rent?.weekly ?? p.weekly_rent;
  const owed = rent?.owed ?? p.rent_owed;
  const dueMs = rent?.due_at ? Date.parse(rent.due_at) : NaN;
  const due = Number.isNaN(dueMs) ? null : gameClockAt(dueMs);
  const enabled = rent?.enabled ?? false;
  const sleepPct = rent?.owed_sleep_pct ?? 60;
  const pastCount = (opts?.homes ?? []).filter((h) => h.status === 'past').length;
  const tenants = (prop?.properties ?? []).filter((x) => x.occupant?.role === 'tenant').length;
  const building = prop?.builds.length ?? 0;

  const pay = async () => {
    setPaying(true);
    try {
      const r = await payRent();
      toast(r.message, r.owed > 0 ? 'info' : 'good');
      await refresh();
    } catch (e) {
      toast(errorMessage(e), 'bad');
    } finally {
      setPaying(false);
    }
  };

  const tabs = [
    { id: 'home', label: 'Home' },
    { id: 'rent', label: 'Rent' },
    { id: 'buy', label: 'Buy' },
    { id: 'build', label: 'Build', badge: building || null },
    { id: 'mine', label: 'My properties', badge: (prop?.owned_count ?? 0) || null },
    { id: 'past', label: 'Past homes', badge: pastCount || null },
  ];
  const homeCard = res?.role === 'owner'
    ? { label: 'You own this home', name: res.property.name, sub: `${res.property.area_name} · no rent` }
    : res?.role === 'tenant'
      ? { label: `You rent from @${res.landlord ?? 'a landlord'}`, name: res.property.name, sub: `${naira(res.rent)} a week · caution ${naira(res.caution)}` }
      : { label: 'Your home', name: home?.name ?? loc?.name ?? 'Your place', sub: loc && home ? loc.name : '' };

  return (
    <div className="phone-app__body houses">
      <Tabs tabs={tabs} value={tab} onChange={(id) => setTab(TAB_IDS.includes(id as Tab) ? (id as Tab) : 'home')} className="pp-tabs" tourPrefix="houses" />
      {tab === 'home' && (
        <>
          <div className={`house-card${res?.role === 'owner' ? ' house-card--own' : res?.role === 'tenant' ? ' house-card--let' : ''}`}>
            <span className="house-card__emoji" aria-hidden>{res ? res.property.emoji : home?.emoji ?? '🏠'}</span>
            <div className="grow">
              <div className="house-card__label">{homeCard.label}</div>
              <div className="house-card__name">{homeCard.name}</div>
              {homeCard.sub && <div className="house-card__sub">{homeCard.sub}</div>}
            </div>
          </div>
          {res?.role === 'tenant' && res.ends_at && (
            <section className="rent-owed" role="alert">
              <div className="rent-owed__top">
                <span aria-hidden>📜</span>
                <div className="grow">
                  <div className="rent-owed__title">Your landlord gave notice</div>
                  <div className="rent-owed__body">You must leave by {dateShort(res.ends_at)} ({daysLeft(res.ends_at, now)}). Your caution of {naira(res.caution)} comes back. Find a new home in Rent.</div>
                </div>
              </div>
            </section>
          )}

          {owed > 0 && (
            <section className="rent-owed" role="alert">
              <div className="rent-owed__top">
                <span aria-hidden>🚪</span>
                <div className="grow">
                  <div className="rent-owed__title">You owe {naira(owed)} rent</div>
                  <div className="rent-owed__body">
                    {res?.role === 'tenant' && prop
                      ? `Your landlord is waiting. At ${prop.settings.evict_owed_weeks} weeks of rent owed you are moved out. Sleep gives only ${sleepPct}% energy until you pay.`
                      : `The landlord keeps knocking: "Where my money?" Sleep gives only ${sleepPct}% energy until you pay.`}
                  </div>
                </div>
              </div>
              <Button variant="green" block loading={paying} disabled={p.cash + p.bank <= 0} onClick={() => void pay()}>
                {p.cash + p.bank <= 0 ? 'No money to pay yet'
                  : p.cash + p.bank >= owed ? `Pay ${naira(owed)} now` : `Pay ${naira(p.cash + p.bank)} now (part)`}
              </Button>
              <p className="rent-owed__note">Paid from your bank first, then cash.</p>
            </section>
          )}

          <div className="rent-rows">
            <div className="bank-row"><span>Weekly rent</span><b>{weekly > 0 ? naira(weekly) : 'None'}</b></div>
            {weekly > 0 && due && (
              <div className="bank-row">
                <span>Next rent day</span>
                <b className="rent-rows__due">
                  {WEEKDAYS[weekdayOf(due)]}, {dateLabel(due)} · {clockTime(due.hour, due.minute)}
                  <span>in about {realDuration(Math.max(0, (dueMs - now) / 1000))} real time</span>
                </b>
              </div>
            )}
            <div className="bank-row"><span>Rent owed</span><b className={owed > 0 ? 'is-bad' : 'is-good'}>{owed > 0 ? naira(owed) : 'All paid ✓'}</b></div>
          </div>
          <p className="phone-app__lead">
            {res?.role === 'owner' ? 'You own this home, so you pay no rent. The weekly house bill and ground rent still apply (Bank, Bills).'
              : weekly <= 0 ? 'You pay no rent here.'
                : res?.role === 'tenant' ? `Rent goes to your landlord every ${WEEKDAYS[catalog?.rent_weekday ?? 5]} at midnight, from your bank first, then cash.`
                  : enabled ? `Rent is collected every ${WEEKDAYS[catalog?.rent_weekday ?? 5]} at midnight, from your bank first, then cash. If you can't cover it, the rest becomes rent owed.`
                    : 'Rent collection is paused right now.'}
          </p>
          <HouseUpgrades state={state} />
          {tenants > 0 && (
            <button type="button" className="pp-link pp-link--block" onClick={() => setTab('mine')}>You have {tenants} tenant{tenants === 1 ? '' : 's'}: open My properties</button>
          )}
        </>
      )}
      {tab === 'rent' && prop && <RentTab data={prop} opts={opts} owed={owed} visiting={visiting} onMoved={() => setTab('home')} />}
      {tab === 'buy' && prop && <BuyTab data={prop} onBought={() => setTab('mine')} />}
      {tab === 'build' && prop && <BuildTab data={prop} onStarted={() => undefined} />}
      {tab === 'mine' && prop && <MineTab data={prop} onBuy={() => setTab('buy')} />}
      {tab === 'past' && <PastTab opts={opts} owed={owed} visiting={visiting} onChanged={() => void loadProp()} />}
      {tab !== 'home' && tab !== 'past' && !prop && <div className="panel-skel"><span /><span /></div>}
    </div>
  );
}
