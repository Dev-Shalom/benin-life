// Kitchen tab of the Chowdeck app (step C, docs/COOKING.md): recipes, ingredients you hold, a pot size, Cook. The server checks
// and removes the ingredients, puts the portions in the Bag and gives the XP; this screen only asks and shows.
import { useEffect, useMemo, useState } from 'react';
import { cookOverview, cookShare, cookStart, type CookOverview, type CookRecipe, type CookResult } from '../../../api/cooking';
import { itemUse } from '../../../api/shops';
import { errorMessage } from '../../../lib/api';
import { useGameClock } from '../../../lib/clock';
import { nairaShort } from '../../../lib/format';
import type { GameState } from '../../../lib/types';
import { useGame } from '../../../state/game';
import { Button, toast } from '../../../ui';
import './CookingApp.css';

const POT_NAME = ['', 'Small pot', 'Medium pot', 'Big pot'];

function Chips({ r }: { r: { hunger: number; energy: number; mood: number } }) {
  return (
    <span className="ck-chips">
      <span className="ck-chip is-good">🍲 Hunger +{Math.round(r.hunger)}</span>
      {r.energy !== 0 && <span className="ck-chip is-good">⚡ Energy {r.energy > 0 ? '+' : ''}{Math.round(r.energy)}</span>}
      {r.mood !== 0 && <span className="ck-chip is-good">😊 Mood {r.mood > 0 ? '+' : ''}{Math.round(r.mood)}</span>}
    </span>
  );
}

function Recipe({ r, pots, ov, busyNow, busy, onCook }: {
  r: CookRecipe; pots: number; ov: CookOverview; busyNow: boolean; busy: boolean; onCook: (r: CookRecipe) => void;
}) {
  const missing = r.ingredients.filter((i) => i.have < i.need * pots);
  const locked = !r.level_ok || !r.cert_ok;
  const reason = !ov.enabled ? 'Kitchen closed'
    : !r.level_ok ? `Needs Cooking level ${r.min_level}`
    : !r.cert_ok ? `Needs ${r.cert_name ?? 'a'} certificate`
    : busyNow ? 'Busy right now'
    : !ov.at_home ? 'Go home to cook'
    : !ov.stove ? 'No stove at home'
    : missing.length > 0 ? 'Missing ingredients'
    : null;
  const minutes = Math.max(1, Math.round(r.minutes * (1 + (pots - 1) * ov.pot_extra_pct / 100)));
  return (
    <article className={`ck-recipe${locked ? ' is-locked' : ''}`} data-testid={`recipe-${r.id}`}>
      <div className="ck-recipe__top">
        <span className="ck-recipe__emoji" aria-hidden>{r.emoji}</span>
        <div className="ck-recipe__main">
          <h4>{r.name}</h4>
          <p>{r.blurb}</p>
        </div>
        <span className={`ck-lvl${r.level_ok ? '' : ' is-need'}`}>Lv {r.min_level}</span>
      </div>
      <div className="ck-meta">
        <span className="ck-chip">🍽️ {r.portions * pots} portions</span>
        <span className="ck-chip">⏱️ {minutes} min</span>
        <span className="ck-chip">≈ {nairaShort(Math.round(r.cost_per_portion))} a portion</span>
        {r.cert && <span className={`ck-chip${r.cert_ok ? ' is-ok' : ' is-need'}`}>🎓 {r.cert_name}</span>}
      </div>
      <Chips r={r} />
      <ul className="ck-ing" aria-label="Ingredients">
        {r.ingredients.map((i) => {
          const need = i.need * pots;
          const ok = i.have >= need;
          return (
            <li key={i.id} className={ok ? 'is-ok' : 'is-short'}>
              <span aria-hidden>{i.icon ?? '🥣'}</span>
              <span className="ck-ing__name">{i.name.split(',')[0]}</span>
              <b>{i.have}/{need}</b>
            </li>
          );
        })}
      </ul>
      <Button size="sm" variant={reason ? 'ghost' : 'green'} block disabled={Boolean(reason)} loading={busy} onClick={() => onCook(r)} data-testid={`cook-${r.id}`}>
        {reason ?? `Cook ${r.portions * pots} ${r.portions * pots === 1 ? 'portion' : 'portions'}`}
      </Button>
    </article>
  );
}

function Dish({ d, partner, left, onEat, onShare, busy }: {
  d: CookOverview['dishes'][number]; partner: string | null; left: number; busy: string | null;
  onEat: (id: string) => void; onShare: (id: string, n: number) => void;
}) {
  const [n, setN] = useState(1);
  const max = Math.max(1, Math.min(d.qty, left));
  const nn = Math.min(n, max);
  const e = d.effects;
  return (
    <li className="ck-dish" data-testid={`dish-${d.id}`}>
      <span className="ck-dish__emoji" aria-hidden>{d.icon ?? '🍲'}</span>
      <span className="ck-dish__main">
        <b>{d.name}</b>
        <small>×{d.qty} in your Bag · hunger +{Math.round(e.hunger ?? 0)}</small>
      </span>
      <Button size="sm" variant="green" loading={busy === `eat:${d.id}`} onClick={() => onEat(d.id)}>Eat</Button>
      {partner && left > 0 && (
        <span className="ck-share">
          <button type="button" className="ck-step" onClick={() => setN(Math.max(1, nn - 1))} disabled={nn <= 1} aria-label="One less">−</button>
          <span className="ck-share__n" aria-live="polite">{nn}</span>
          <button type="button" className="ck-step" onClick={() => setN(Math.min(max, nn + 1))} disabled={nn >= max} aria-label="One more">+</button>
          <Button size="sm" variant="ghost" loading={busy === `share:${d.id}`} onClick={() => onShare(d.id, nn)}>Send</Button>
        </span>
      )}
    </li>
  );
}

export default function KitchenTab({ state, onShop }: { state: GameState; onShop: () => void }) {
  const refresh = useGame((s) => s.refresh);
  const [ov, setOv] = useState<CookOverview | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const [pots, setPots] = useState(1);
  const [busy, setBusy] = useState<string | null>(null);
  const [last, setLast] = useState<CookResult | null>(null);
  const { now } = useGameClock(2000);
  const p = state.profile;
  const busyNow = Boolean(p.busy_until && Date.parse(p.busy_until) > now);
  const [tick, setTick] = useState(0);
  const load = () => setTick((t) => t + 1);
  const bagKey = useMemo(() => (state.inventory ?? []).map((i) => `${i.id}:${i.qty}`).join(','), [state.inventory]);

  useEffect(() => {
    let alive = true;
    cookOverview()
      .then((o) => alive && (setOv(o), setErr(null)))
      .catch((e) => alive && setErr(errorMessage(e)));
    return () => { alive = false; };
  }, [tick, p.location_id, bagKey]);

  const run = async (key: string, fn: () => Promise<{ message: string }>) => {
    setBusy(key);
    try {
      const r = await fn();
      toast(r.message, 'good');
      await refresh();
      load();
      return r;
    } catch (e) {
      toast(errorMessage(e), 'bad');
      return null;
    } finally {
      setBusy(null);
    }
  };

  const cook = async (r: CookRecipe) => {
    const res = await run(`cook:${r.id}`, async () => {
      const x = await cookStart(r.id, pots);
      setLast(x);
      return x;
    });
    if (!res) setLast(null);
  };

  if (!ov && !err) return <div className="panel-skel"><span /><span /><span /></div>;
  if (!ov) return <p className="phone-app__lead">{err}</p>;

  const maxPot = Math.max(1, ov.max_pot);
  const lvlPct = ov.level_next ? Math.max(0, Math.min(100, ((ov.xp - ov.level_from) / Math.max(1, ov.level_next - ov.level_from)) * 100)) : 100;
  const homeBlock = !ov.at_home ? 'You are away from home. Go home to cook on your stove.' : !ov.stove ? 'Your home has no stove or cooker. Buy one in the Buy sheet.' : null;
  const lastRecipe = last ? ov.recipes.find((x) => x.id === last.recipe) : null;
  const visible = [...ov.recipes].sort((a, b) => Number(b.level_ok && b.cert_ok) - Number(a.level_ok && a.cert_ok) || a.min_level - b.min_level || a.sort - b.sort);

  return (
    <div className="ck" data-testid="kitchen">
      <section className="ck-top">
        <div className="ck-top__row">
          <div>
            <small>Cooking skill</small>
            <b className="ck-top__lvl">{ov.skills_on ? `Level ${ov.level}` : 'All dishes open'}</b>
          </div>
          <span className={`ck-pill ${ov.at_home && ov.stove ? 'is-ok' : 'is-away'}`}>{ov.at_home ? (ov.stove ? '🔥 Stove ready' : '🚫 No stove') : '🏠 Away from home'}</span>
        </div>
        {ov.skills_on && (
          <>
            <div className="ck-bar" aria-hidden><span style={{ width: `${lvlPct}%` }} /></div>
            <small>
              {ov.level_next ? `${ov.xp - ov.level_from} / ${ov.level_next - ov.level_from} XP to level ${(ov.level ?? 1) + 1}` : 'Top level'}
              {' · '}today {ov.xp_today}/{ov.xp_cap} XP
            </small>
          </>
        )}
        {ov.catering.has
          ? <p className="ck-top__note">🎓 {ov.catering.name} certificate: you cook {Math.round(ov.catering.time_cut_pct)}% faster.</p>
          : ov.catering.full_cut_pct > 0 && <p className="ck-top__note">🎓 The {ov.catering.name} course (School app) unlocks Black soup and cooks {Math.round(ov.catering.full_cut_pct)}% faster.</p>}
        {homeBlock && <p className="ck-top__warn">{homeBlock}</p>}
      </section>

      {last && lastRecipe && (
        <section className="ck-done" role="status" data-testid="cook-result">
          <span className="ck-done__emoji" aria-hidden>{lastRecipe.emoji}</span>
          <div className="ck-done__main">
            <b>{last.portions} {last.portions === 1 ? 'portion' : 'portions'} of {lastRecipe.name}</b>
            <small>Cooked. {last.owned} now in your Bag.{last.xp.gain > 0 ? ` Cooking +${last.xp.gain} XP.` : last.xp.capped ? ' No more Cooking XP today.' : ''}</small>
            {last.xp.up && <small className="ck-done__up">🌟 Cooking level {last.xp.level}!</small>}
          </div>
          <Button size="sm" variant="green" loading={busy === `eat:${last.dish}`} disabled={busyNow} onClick={() => void run(`eat:${last.dish}`, () => itemUse(last.dish))}>Eat one</Button>
        </section>
      )}

      <section className="ck-pots">
        <div className="ck-pots__row" role="group" aria-label="Pot size">
          {Array.from({ length: maxPot }, (_, i) => i + 1).map((n) => (
            <button key={n} type="button" className={`ck-pot${pots === n ? ' is-on' : ''}`} onClick={() => setPots(n)} aria-pressed={pots === n}>
              <b>{POT_NAME[n] ?? `Pot ×${n}`}</b>
              <small>×{n} batch{n > 1 ? 'es' : ''}</small>
            </button>
          ))}
        </div>
        {maxPot > 1 && <small className="ck-fine">A bigger pot makes more portions from more ingredients and takes {ov.pot_extra_pct}% longer for each extra batch. Share portions with a partner or feed your children.</small>}
      </section>

      <div className="ck-list">
        {visible.map((r) => (
          <Recipe key={r.id} r={r} pots={pots} ov={ov} busyNow={busyNow} busy={busy === `cook:${r.id}`} onCook={(x) => void cook(x)} />
        ))}
      </div>
      <Button variant="ghost" block icon="bag" onClick={onShop}>Missing something? See today's prices</Button>

      <h4 className="ck-h">Your cooked food</h4>
      {ov.dishes.length === 0 ? (
        <p className="ck-empty">Nothing cooked yet. Cook a pot and the portions land in your Bag.</p>
      ) : (
        <ul className="ck-dishes">
          {ov.dishes.map((d) => (
            <Dish key={d.id} d={d} partner={ov.partner?.username ?? null} left={Math.max(0, ov.share_cap - ov.shared_today)} busy={busy}
              onEat={(id) => void run(`eat:${id}`, () => itemUse(id))}
              onShare={(id, n) => void run(`share:${id}`, () => cookShare(id, n))} />
          ))}
        </ul>
      )}
      {ov.dishes.length > 0 && (
        <p className="ck-fine">
          {ov.partner ? `Send portions to @${ov.partner.username} (${ov.shared_today}/${ov.share_cap} today).` : 'Link up in the Family app to share food with a partner.'}
          {ov.kid_meal && ` Feeding a child from Nursery up? A cooked portion is used instead of lunch money and fills them ${Math.round(ov.kid_boost_pct)}% more.`}
        </p>
      )}
    </div>
  );
}
