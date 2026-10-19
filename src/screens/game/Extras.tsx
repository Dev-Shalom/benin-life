// The keyboard shortcuts help sheet and the dock's Buy sheet (R4; V1-4 adds the Bag and Chowdeck;
// B1: the furniture catalogue with room tabs and LAPO/Mid/Nepo filter, and Arrange / My items).
import { useEffect, useMemo, useState } from 'react';
import { SHORTCUTS } from './shortcuts';
import { useGame } from '../../state/game';
import { useUi } from '../../state/ui';
import { useCatalog, type ShopFurniture } from '../../state/catalog';
import { furnitureBuy, furnitureSell, furnitureSellQuote, type FurnitureSellQuote } from '../../api/furniture';
import { Thumb } from '../../art/thumbs/Thumb';
import { getCfg } from '../../lib/config';
import { errorMessage } from '../../lib/api';
import { cameWithHouse, furnitureKey, type HomeLayout, type HomeLayoutId, type OwnedPiece, type SavedHomePosition } from '../../art/home3d/model';
import { naira, nairaShort } from '../../lib/format';
import { grossPrice, noteFor } from '../../lib/tax';
import { Button, Icon, Modal, Segmented, Sheet, toast } from '../../ui';
import { SellToPlayersButton } from './SellToPlayers';

export function ShortcutsSheet() {
  const overlay = useUi((s) => s.overlay);
  const setOverlay = useUi((s) => s.setOverlay);
  return (
    <Sheet open={overlay === 'shortcuts'} onClose={() => setOverlay(null)}
      header={
        <div className="home-sheet__head">
          <span className="home-sheet__emoji" aria-hidden>⌨️</span>
          <div>
            <h3 className="bl-sheet__title">Keyboard shortcuts</h3>
            <p className="bl-sheet__sub">Play Benin Life without a mouse</p>
          </div>
        </div>
      }>
      <dl className="kbd-list">
        {SHORTCUTS.map(([k, label]) => (
          <div key={k} className="kbd-list__row">
            <dt><kbd>{k}</kbd></dt>
            <dd>{label}</dd>
          </div>
        ))}
      </dl>
    </Sheet>
  );
}

type BuyTab = 'shop' | 'arrange' | 'bag';
type Cat = ShopFurniture['category'];
type TierFilter = 'all' | ShopFurniture['tier'];

const CATS: [Cat, string, string][] = [
  ['living', 'Parlour', '🛋️'],
  ['bedroom', 'Bedroom', '🛏️'],
  ['kitchen', 'Kitchen', '🍳'],
  ['bathroom', 'Bathroom', '🛁'],
  ['utility', 'Outside', '⚡'],
  ['decor', 'Decor', '🖼️'],
];
const TIERS: { id: TierFilter; label: string }[] = [
  { id: 'all', label: 'All' },
  { id: 'lapo', label: 'LAPO' },
  { id: 'mid', label: 'Mid' },
  { id: 'nepo', label: 'Nepo' },
];
const ACT_LABEL: Record<string, string> = {
  sleep: 'Sleep', nap: 'Nap', cook_home: 'Cooking', bathe: 'Bath', watch_tv: 'TV', listen_radio: 'Music',
  relax_sofa: 'Relax', sit_rest: 'Sit', cold_drink: 'Cold drink',
};
const ACT_USE: Record<string, string> = {
  sleep: 'sleep', nap: 'nap', cook_home: 'cook', bathe: 'bathe', watch_tv: 'watch TV', listen_radio: 'play music',
  relax_sofa: 'relax', sit_rest: 'sit and rest', cold_drink: 'cold drinks',
};
const NEED_LABEL: Record<string, string> = { energy: 'energy', hunger: 'belle', hygiene: 'clean', fun: 'fun', stress: 'stress', social: 'social', health: 'health' };

/** "Sleep +8 energy" — the strongest perk of a piece, for its card. */
function perkLine(it: ShopFurniture): string | null {
  if (it.rest_pct > 100 && it.activities.includes('sleep')) return `Sleep ×${(it.rest_pct / 100).toFixed(2).replace(/0$/, '')} rest`;
  let best: string | null = null;
  let score = 0;
  for (const [act, eff] of Object.entries(it.bonus ?? {})) {
    const nums = Object.entries(eff).filter(([, v]) => typeof v === 'number' && v !== 0);
    const sc = nums.reduce((n, [, v]) => n + Math.abs(v), 0);
    if (!nums.length || sc <= score) continue;
    score = sc;
    best = `${ACT_LABEL[act] ?? act} ${nums.slice(0, 2).map(([k, v]) => `${v > 0 ? '+' : '−'}${Math.abs(v)} ${NEED_LABEL[k] ?? k}`).join(' ')}`;
  }
  if (best) return best;
  if (it.activities.length) return `Lets you: ${it.activities.map((a) => ACT_USE[a] ?? a).join(', ')}`;
  return null;
}

export interface BuyHome {
  layout: HomeLayout;
  pieces: OwnedPiece[];
  positions: Record<string, SavedHomePosition>;
  layoutId: HomeLayoutId;
}

/** H2: what selling one piece pays (furniture.resale_pct of the price, rounded down to ₦100), like furniture_sell.
 * H4: a piece that came with the house uses furniture.included_resale_pct (the server caps it; the dialog asks
 * furniture_sell_quote for the real amount and shows this only while that loads). */
export function furniturePayout(price: number, included = false): number {
  const pct = Math.max(0, Math.min(100, Number(included ? getCfg('furniture.included_resale_pct', 25) : getCfg('furniture.resale_pct', 45))));
  return Math.floor((price * pct) / 100 / 100) * 100;
}

interface MineRow {
  key: string; id: string; kind: string; color: string | null; name: string; emoji: string; placed: boolean; price: number; canSell: boolean;
  /** H4: came with the house (starter piece or one of the home's built-ins). */
  included: boolean;
}

export function BuySheet({ tab, onTab, home, onBought, onSold, onArrange }: {
  tab: BuyTab;
  onTab: (t: BuyTab) => void;
  /** The player's own home when they are in it (null = away / visiting: buying still delivers). */
  home: BuyHome | null;
  onBought: (key: string) => void;
  /** H2: a piece was sold (reload the furniture + positions). */
  onSold: () => void;
  onArrange: (key: string | null) => void;
}) {
  const overlay = useUi((s) => s.overlay);
  const setOverlay = useUi((s) => s.setOverlay);
  const openPanel = useUi((s) => s.openPanel);
  const openPhone = useUi((s) => s.openPhone);
  const inv = useGame((s) => s.state?.inventory);
  const profile = useGame((s) => s.state?.profile);
  const shop = useCatalog((s) => s.shop);
  const loadShop = useCatalog((s) => s.loadShop);
  const owned = useCatalog((s) => s.furniture);
  const [cat, setCat] = useState<Cat>('living');
  const [tier, setTier] = useState<TierFilter>('all');
  const [confirm, setConfirm] = useState<string | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [selling, setSelling] = useState<MineRow | null>(null);
  const [sellBusy, setSellBusy] = useState(false);
  // H4: the server's quote for the piece being sold (came-with-house pieces are capped)
  const [quote, setQuote] = useState<FurnitureSellQuote | null>(null);
  const sellingKey = selling?.key ?? null;
  useEffect(() => {
    setQuote(null);
    if (!sellingKey) return;
    let alive = true;
    furnitureSellQuote(sellingKey).then((q) => { if (alive) setQuote(q); }).catch(() => {});
    return () => { alive = false; };
  }, [sellingKey]);
  const open = overlay === 'buy';
  useEffect(() => {
    if (open) void loadShop();
    if (!open) setConfirm(null);
  }, [open, loadShop]);
  const count = (inv ?? []).reduce((n, i) => n + i.qty, 0);
  const preview = (inv ?? []).slice(0, 4).map((i) => i.icon || '📦').join(' ');
  const money = (profile?.cash ?? 0) + Math.max(0, profile?.bank ?? 0);
  const ownedQty = (id: string) => owned?.find((o) => o.id === id)?.qty ?? 0;
  const items = useMemo(() => (shop ?? []).filter((it) => it.category === cat && (tier === 'all' || it.tier === tier)), [shop, cat, tier]);

  const buy = async (it: ShopFurniture) => {
    if (confirm !== it.id) { setConfirm(it.id); return; }
    setConfirm(null);
    setBusy(it.id);
    try {
      const r = await furnitureBuy(it.id);
      toast(home ? r.message : `${r.name} don land for your house. Place am when you reach home.`, 'good');
      void useGame.getState().refresh();
      onBought(r.furniture_key);
    } catch (e) {
      toast(e instanceof Error ? e.message : 'Could not buy that.', 'bad');
    } finally {
      setBusy(null);
    }
  };

  // My items: every owned copy, placed or waiting in the inventory
  const mine = useMemo(() => {
    if (!home) return [];
    const placed = new Set(home.layout.furniture.map((f) => f.id));
    const rows: MineRow[] = [];
    for (const p of home.pieces) {
      const cat = shop?.find((s2) => s2.id === p.id);
      const qty = Math.max(1, p.qty ?? 1);
      for (let c = 1; c <= qty; c++) {
        const key = furnitureKey(p.id, c);
        rows.push({
          key, id: p.id, kind: p.kind, color: p.color ?? null, emoji: cat?.emoji ?? '🪑',
          name: (p.name ?? p.id) + (qty > 1 ? ` #${c}` : ''), placed: placed.has(key), price: cat?.price ?? 0,
          // H4: everything can be sold, including what came with the house (at furniture.included_resale_pct)
          canSell: (cat?.price ?? 0) > 0,
          included: cameWithHouse(p, c),
        });
      }
    }
    return rows.sort((a, b) => Number(a.placed) - Number(b.placed));
  }, [home, shop]);

  const sell = async () => {
    if (!selling) return;
    setSellBusy(true);
    try {
      const r = await furnitureSell(selling.key);
      toast(r.message, 'good');
      setSelling(null);
      void useGame.getState().refresh();
      onSold();
    } catch (e) {
      toast(errorMessage(e), 'bad');
    } finally {
      setSellBusy(false);
    }
  };

  return (
    <Sheet open={open} onClose={() => setOverlay(null)} className="buy-sheet"
      header={
        <div className="buy-sheet__headwrap">
          <div className="home-sheet__head">
            <span className="home-sheet__emoji" aria-hidden>🛍️</span>
            <div className="grow">
              <h3 className="bl-sheet__title">Buy</h3>
              <p className="bl-sheet__sub">Furnish your house · {nairaShort(money)} to spend</p>
            </div>
          </div>
          <Segmented<BuyTab> label="Buy sections" className="buy-seg" value={tab} onChange={onTab}
            options={[{ id: 'shop', label: 'Furniture' }, { id: 'arrange', label: 'Arrange' }, { id: 'bag', label: 'Bag & food' }]} />
        </div>
      }>
      {tab === 'shop' && (
        <>
          <div className="buy-cats" role="tablist" aria-label="Rooms">
            {CATS.map(([id, label, emoji]) => (
              <button key={id} type="button" role="tab" aria-selected={cat === id} className={`buy-cat${cat === id ? ' is-active' : ''}`} onClick={() => setCat(id)}>
                <span aria-hidden>{emoji}</span> {label}
              </button>
            ))}
          </div>
          <div className="buy-tiers" role="radiogroup" aria-label="Budget">
            {TIERS.map((t) => (
              <button key={t.id} type="button" role="radio" aria-checked={tier === t.id} className={`buy-tier buy-tier--${t.id}${tier === t.id ? ' is-active' : ''}`} onClick={() => setTier(t.id)}>{t.label}</button>
            ))}
          </div>
          {!shop ? <p className="muted buy-note">Loading the catalogue…</p> : (
            <div className="buy-grid buy-grid--shop">
              {items.map((it) => {
                const have = ownedQty(it.id);
                const maxed = have >= it.max_qty;
                const gross = grossPrice('furniture', it.price);
                const broke = money < gross;
                const perk = perkLine(it);
                return (
                  <div key={it.id} className={`buy-card buy-card--${it.tier}`}>
                    <Thumb spec={{ type: 'furniture', kind: it.kind, color: it.color }} fallback={it.emoji} className="buy-card__thumb" />
                    <span className={`buy-card__tier buy-card__tier--${it.tier}`}>{it.tier === 'mid' ? 'Mid' : it.tier.toUpperCase()}</span>
                    <span className="buy-card__name">{it.name}</span>
                    {perk && <span className="buy-card__perk">{perk}</span>}
                    <span className="buy-card__price" title={naira(gross)}>{naira(gross)}</span>
                    {noteFor('furniture', it.price) && <span className="buy-card__tax">{noteFor('furniture', it.price)}</span>}
                    {have > 0 && <span className="buy-card__owned">You have {have}{it.max_qty > 1 ? ` of ${it.max_qty}` : ''}</span>}
                    <button type="button" className={`buy-card__btn${confirm === it.id ? ' is-confirm' : ''}`} disabled={maxed || broke || busy !== null}
                      onClick={() => void buy(it)}>
                      {busy === it.id ? 'Buying…' : maxed ? 'Owned' : broke ? 'Not enough money' : confirm === it.id ? `Pay ${nairaShort(gross)}` : 'Buy'}
                    </button>
                  </div>
                );
              })}
            </div>
          )}
          <p className="muted buy-note">Prices from Benin and Lagos shops (2025/26). Every piece lands in your house: place it, move it, store it.</p>
        </>
      )}
      {tab === 'arrange' && (
        home ? (
          <div className="buy-arrange">
            <button type="button" className="buy-choice buy-choice--arrange" onClick={() => onArrange(null)}>
              <span className="buy-choice__emoji" aria-hidden>🧭</span>
              <span className="grow">
                <span className="buy-choice__title">Arrange home</span>
                <span className="buy-choice__sub">Tap a piece in the room, then move it with the arrows</span>
              </span>
              <Icon name="chevronRight" size={18} stroke={2.4} />
            </button>
            <div className="sim-section-head"><h4>My items</h4><span className="muted">{mine.filter((m) => !m.placed).length} in storage</span></div>
            <ul className="buy-mine">
              {mine.map((m) => (
                <li key={m.key} className="buy-mine__row">
                  <Thumb spec={{ type: 'furniture', kind: m.kind, color: m.color }} fallback={m.emoji} className="buy-mine__emoji" />
                  <span className="grow">
                    <span className="buy-mine__name">{m.name}</span>
                    <span className={`buy-mine__state${m.placed ? '' : ' is-stored'}`}>
                      {m.placed ? 'In the room' : 'In storage'}
                      {m.included && <span className="buy-mine__came"> · Came with the house</span>}
                    </span>
                  </span>
                  {m.canSell && (
                    <button type="button" className="buy-mine__btn buy-mine__btn--sell" onClick={() => setSelling(m)}>Sell to shop</button>
                  )}
                  {m.canSell && !m.included && (
                    <SellToPlayersButton kind="furniture" refId={m.id} itemKey={m.key} name={m.name} icon={m.emoji} label="Sell to players" onListed={onSold} />
                  )}
                  <button type="button" className="buy-mine__btn" onClick={() => onArrange(m.key)}>{m.placed ? 'Move' : 'Place'}</button>
                </li>
              ))}
            </ul>
          </div>
        ) : (
          <p className="buy-tip"><span aria-hidden>🏠</span> Go home to arrange your furniture. Anything you buy now waits for you there.</p>
        )
      )}
      {tab === 'bag' && (
        <div className="buy-choices">
          <button type="button" className="buy-choice" onClick={() => { setOverlay(null); openPanel('inventory'); }}>
            <span className="buy-choice__emoji" aria-hidden>🎒</span>
            <span className="grow">
              <span className="buy-choice__title">Bag</span>
              <span className="buy-choice__sub">{count > 0 ? `${count} ${count === 1 ? 'thing' : 'things'} · ${preview}` : 'Empty for now'} · eat, use, sell</span>
            </span>
            <Icon name="chevronRight" size={18} stroke={2.4} />
          </button>
          <button type="button" className="buy-choice" onClick={() => openPhone('food')}>
            <span className="buy-choice__emoji" aria-hidden>🛵</span>
            <span className="grow">
              <span className="buy-choice__title">Chowdeck</span>
              <span className="buy-choice__sub">Order food to wherever you are</span>
            </span>
            <Icon name="chevronRight" size={18} stroke={2.4} />
          </button>
          <p className="buy-tip"><span aria-hidden>🛒</span> Markets, bukas, motor parks and PoS stands sell food, drinks, airtime and more: open the place on the map and tap <b>Shop</b>.</p>
        </div>
      )}
      <Modal open={selling !== null} onClose={() => !sellBusy && setSelling(null)} title={selling ? `Sell ${selling.name}?` : ''}
        art={selling ? <Thumb spec={{ type: 'furniture', kind: selling.kind, color: selling.color }} fallback={<span className="sell-dialog__emoji">{selling.emoji}</span>} className="sell-dialog__thumb" /> : null}
        actions={
          <>
            <Button variant="ghost" disabled={sellBusy} onClick={() => setSelling(null)}>Keep it</Button>
            <Button variant="gold" loading={sellBusy} disabled={quote !== null && quote.payout <= 0} onClick={() => void sell()}>
              {quote && quote.payout <= 0 ? 'Nobody will pay' : `Sell for ${selling ? naira(quote ? quote.payout : furniturePayout(selling.price, selling.included)) : ''}`}
            </Button>
          </>
        }>
        {selling && (
          <div className="sell-dialog">
            {selling.included && <p className="sell-dialog__came"><span aria-hidden>🏠</span> Came with the house</p>}
            <div className="sell-dialog__row"><span>Shop price</span><span>{naira(selling.price)}</span></div>
            <div className="sell-dialog__row">
              <span>{selling.included ? 'Buyer pays (came with the house)' : 'Fairly-used buyer pays'}</span>
              <span>{Math.round(quote ? quote.pct : Number(selling.included ? getCfg('furniture.included_resale_pct', 25) : getCfg('furniture.resale_pct', 45)))}%</span>
            </div>
            {quote?.capped && (
              <div className="sell-dialog__row"><span>Landlord's limit left</span><span>{naira(Math.max(0, quote.left ?? 0))}</span></div>
            )}
            <div className="sell-dialog__row sell-dialog__row--total">
              <span>You get (cash)</span><b>{naira(quote ? quote.payout : furniturePayout(selling.price, selling.included))}</b>
            </div>
            <p className="sell-dialog__note">
              {quote?.capped
                ? (quote.payout > 0
                  ? 'The landlord takes the rest: selling what came with a home pays at most part of its move-in fee.'
                  : 'You have already made the most you can from what came with your homes. Keep it or store it.')
                : selling.placed ? 'It leaves the room for good.' : 'It leaves My items for good.'}
            </p>
          </div>
        )}
      </Modal>
    </Sheet>
  );
}
