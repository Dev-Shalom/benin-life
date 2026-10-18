// R8: the Upgrade section of the phone's Houses app (docs/HOUSE_UPGRADES.md): what the builders are on (progress bar,
// scaffold icon), what your home already has, and every upgrade you can buy with its price, build time, effect and a
// preview of what changes in the 3D home. Tap a card to open it, then "Start building".
import { useEffect, useState } from 'react';
import { houseUpgradeBuy, type UpgradeAvailable, type UpgradeBuilding, type UpgradeCard, type UpgradeCategory } from '../../../api/upgrades';
import { FINISH_NAMES } from '../../../art/home3d';
import { errorMessage } from '../../../lib/api';
import { naira, nairaShort, realDuration } from '../../../lib/format';
import { NEED_META, type NeedKey } from '../../../lib/pidgin';
import type { GameState } from '../../../lib/types';
import { useGame } from '../../../state/game';
import { useUpgrades } from '../../../state/upgrades';
import { Button, toast } from '../../../ui';

const CATEGORY: Record<UpgradeCategory, { label: string; emoji: string }> = {
  tier: { label: 'Upgrade the whole home', emoji: '🏗️' },
  extension: { label: 'Extensions', emoji: '🛏️' },
  quarters: { label: 'Boys\' quarters', emoji: '🏚️' },
  garage: { label: 'Garage and parking', emoji: '🚗' },
  power: { label: 'Power', emoji: '⚡' },
  water: { label: 'Water', emoji: '💧' },
  security: { label: 'Security', emoji: '🔒' },
  finish: { label: 'Finish', emoji: '🎨' },
};
const ORDER: UpgradeCategory[] = ['tier', 'extension', 'quarters', 'garage', 'power', 'water', 'security', 'finish'];
const ACT: Record<string, string> = {
  sleep: 'Sleep', nap: 'Nap', watch_tv: 'TV', relax_sofa: 'Sofa', bathe: 'Bath', use_toilet: 'Toilet',
  sit_rest: 'Rest', cook_home: 'Cooking', cold_drink: 'Fridge', listen_radio: 'Radio',
};

/** "Sleep: Energy +2", one chip per activity and need. */
export function bonusChips(bonus: UpgradeCard['bonus']): { key: string; text: string; good: boolean }[] {
  const out: { key: string; text: string; good: boolean }[] = [];
  for (const [act, needs] of Object.entries(bonus ?? {})) {
    for (const [need, v] of Object.entries(needs)) {
      const meta = NEED_META[need as NeedKey];
      const good = meta?.inverted ? v < 0 : v > 0;
      out.push({ key: `${act}.${need}`, text: `${ACT[act] ?? act}: ${meta?.short ?? need} ${v > 0 ? '+' : ''}${v}`, good });
    }
  }
  return out;
}

const minutesLabel = (m: number) => (m <= 0 ? 'Instant' : realDuration(m * 60));

function Chips({ card }: { card: UpgradeCard }) {
  const chips = bonusChips(card.bonus);
  return chips.length ? (
    <div className="upg-chips">
      {chips.map((c) => <span key={c.key} className={`chip ${c.good ? 'good' : 'bad'}`}>{c.text}</span>)}
    </div>
  ) : null;
}

function Building({ b, now }: { b: UpgradeBuilding; now: number }) {
  const start = Date.parse(b.started_at);
  const end = Date.parse(b.ready_at);
  const pct = Number.isNaN(start) || Number.isNaN(end) || end <= start ? b.progress : Math.max(0, Math.min(100, ((now - start) / (end - start)) * 100));
  const left = Number.isNaN(end) ? b.seconds_left : Math.max(0, (end - now) / 1000);
  return (
    <div className="upg-build" data-testid="upg-building">
      <span className="upg-build__scaffold" aria-hidden>🏗️</span>
      <div className="grow">
        <div className="upg-build__title">Builders working: {b.name}</div>
        <div className="upg-bar" role="progressbar" aria-valuemin={0} aria-valuemax={100} aria-valuenow={Math.round(pct)} aria-label={`${b.name} progress`}>
          <span style={{ width: `${pct}%` }} />
        </div>
        <div className="upg-build__sub">{left > 0 ? `${Math.round(pct)}% · about ${realDuration(left)} left` : 'Finishing up…'}</div>
      </div>
    </div>
  );
}

export default function HouseUpgrades({ state }: { state: GameState }) {
  const data = useUpgrades((s) => s.data);
  const load = useUpgrades((s) => s.load);
  const bump = useUpgrades((s) => s.bump);
  const refresh = useGame((s) => s.refresh);
  const [open, setOpen] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [now, setNow] = useState(() => Date.now());
  useEffect(() => { void load(); }, [load]);
  useEffect(() => {
    if (!data?.building.length) return;
    const t = window.setInterval(() => setNow(Date.now()), 5000);
    return () => window.clearInterval(t);
  }, [data?.building.length]);
  if (!data || !data.enabled) return null;
  if (data.kind === 'hostel') {
    return (
      <section className="upg" aria-label="Home upgrades">
        <div className="upg__title">Upgrade your home</div>
        <p className="phone-app__lead">Hostel rooms belong to UNIBEN, so no renovations. Rent a place of your own first.</p>
      </section>
    );
  }

  const cash = state.profile.cash + state.profile.bank;
  const buy = async (u: UpgradeAvailable) => {
    setBusy(true);
    try {
      const r = await houseUpgradeBuy(u.id);
      toast(r.message, 'good');
      setOpen(null);
      bump();
      await Promise.all([load(), refresh()]);
    } catch (e) {
      toast(errorMessage(e), 'bad');
    } finally {
      setBusy(false);
    }
  };

  const groups = ORDER.map((c) => ({ c, list: data.available.filter((u) => u.category === c && u.state !== 'owned') })).filter((g) => g.list.length);
  const builders = data.building_count >= data.max_builds;
  return (
    <section className="upg" aria-label="Home upgrades" data-testid="upgrades">
      <div className="upg__title">🏗️ Upgrade your home</div>
      <p className="phone-app__lead">
        Extend or improve the home you live in instead of moving. The landlord must agree, so every job has a {data.landlord_fee_pct}% consent fee.
        If you ever move, you get {data.resale_pct}% of what you spent on upgrades back.
      </p>
      {data.reason && <p className="upg__notice" role="status">{data.reason}</p>}

      {data.building.map((b) => <Building key={b.id} b={b} now={now} />)}

      {(data.done.some((d) => d.category !== 'tier') || data.finish > 0) && (
        <div className="upg-have">
          <div className="upg-have__head">
            <b>Your home has</b>
            {data.sale_value > 0 && <span title={naira(data.sale_value)}>Worth {nairaShort(data.sale_value)} on moving</span>}
          </div>
          <div className="upg-have__list">
            {data.done.filter((d) => d.category !== 'tier' && d.category !== 'finish').map((d) => <span key={d.id} className="chip">{d.emoji} {d.name}</span>)}
            <span className="chip">🎨 {FINISH_NAMES[Math.max(0, Math.min(3, data.finish))]}</span>
          </div>
        </div>
      )}

      {groups.map(({ c, list }) => (
        <div key={c} className="upg-group">
          <div className="upg-group__title"><span aria-hidden>{CATEGORY[c].emoji}</span> {CATEGORY[c].label}</div>
          {list.map((u) => {
            const isOpen = open === u.id;
            const building = u.state === 'building';
            const locked = u.state === 'locked';
            const poor = cash < u.total;
            const why = building ? 'The builders are on it.' : locked ? u.locked : null;
            return (
              <article key={u.id} className={`upg-card${isOpen ? ' is-open' : ''}${locked || building ? ' is-locked' : ''}`}>
                <button type="button" className="upg-card__head" aria-expanded={isOpen} onClick={() => setOpen(isOpen ? null : u.id)}>
                  <span className="garage-opt__emoji" aria-hidden>{u.emoji}</span>
                  <span className="grow">
                    <span className="garage-opt__title">{u.name}</span>
                    <span className="garage-opt__sub">{u.description}</span>
                    <span className="garage-opt__meta">{why ?? `${minutesLabel(u.minutes)} to build`}</span>
                  </span>
                  <span className="garage-opt__price" title={naira(u.total)}>{nairaShort(u.total)}<small>{u.minutes > 0 ? ` · ${minutesLabel(u.minutes)}` : ''}</small></span>
                </button>
                {isOpen && (
                  <div className="upg-card__body">
                    <p className="upg-card__preview"><b>What you will see:</b> {u.preview}</p>
                    {u.to_home && (
                      <p className="upg-card__preview">
                        Becomes a <b>{u.to_home.name}</b> ({u.to_home.area} m²), rent {naira(u.to_home.weekly_rent)} a week. Same address, your furniture and garage stay.
                      </p>
                    )}
                    <Chips card={u} />
                    <div className="rent-rows">
                      <div className="bank-row"><span>Works</span><b>{naira(u.price)}</b></div>
                      {u.rent_fee > 0 && <div className="bank-row"><span>Rent difference (move-in weeks)</span><b>{naira(u.rent_fee)}</b></div>}
                      <div className="bank-row"><span>Landlord consent fee</span><b>{naira(u.landlord_fee)}</b></div>
                      <div className="bank-row"><span>Total</span><b>{naira(u.total)}</b></div>
                      <div className="bank-row"><span>Builders need</span><b>{minutesLabel(u.minutes)}</b></div>
                    </div>
                    <Button variant="green" block loading={busy}
                      disabled={!data.can_upgrade || locked || building || builders || poor}
                      onClick={() => void buy(u)}>
                      {!data.can_upgrade ? 'Not right now' : locked ? (u.locked ?? 'Locked') : building ? 'Building…'
                        : builders ? 'Builders are busy' : poor ? `Need ${nairaShort(u.total - cash)} more`
                          : u.minutes > 0 ? `Start building · ${nairaShort(u.total)}` : `Build now · ${nairaShort(u.total)}`}
                    </Button>
                    <p className="rent-owed__note">Paid from your bank first, then cash.</p>
                  </div>
                )}
              </article>
            );
          })}
        </div>
      ))}
      {groups.length === 0 && <p className="phone-app__lead">Everything on the list is built. Your home is fully upgraded.</p>}
    </section>
  );
}
