// V1-4 shared shop UI: item effect chips and the item card used by the Shop tab, the Bag and Chowdeck.
import { useState } from 'react';
import { naira } from '../../lib/format';
import { NEED_KEYS, NEED_META, type NeedKey } from '../../lib/pidgin';
import type { ItemBase, ItemEffects } from '../../lib/types';
import { Button, Icon } from '../../ui';

const BOOST_LABEL: Record<string, string> = { bathe: 'Better bath at home' };

/** Need chips (+12 Hunger…), a boost chip (soap) or a "keeps" chip for gadgets. */
export function ItemEffectChips({ effects, kind }: { effects: ItemEffects; kind?: string }) {
  const needs = Object.entries(effects).filter(([k, v]) => (NEED_KEYS as string[]).includes(k) && typeof v === 'number' && v !== 0);
  const boosts = effects.boost ? Object.entries(effects.boost) : [];
  return (
    <div className="item__chips">
      {needs.map(([k, v]) => {
        const meta = NEED_META[k as NeedKey];
        const good = meta.inverted ? (v as number) < 0 : (v as number) > 0;
        return (
          <span key={k} className={`chip ${good ? 'good' : 'bad'}`}>
            <span aria-hidden>{meta.emoji}</span> {meta.short} {(v as number) > 0 ? '+' : ''}{Math.round(v as number)}
          </span>
        );
      })}
      {boosts.map(([act, eff]) => (
        <span key={act} className="chip good">
          <span aria-hidden>✨</span> {BOOST_LABEL[act] ?? `Boosts ${act.replace(/_/g, ' ')}`}
          {Object.entries(eff).filter(([k, v]) => k in NEED_META && v > 0).sort((a, b) => b[1] - a[1]).slice(0, 1)
            .map(([k, v]) => ` · ${NEED_META[k as NeedKey].short} +${v}`)}
        </span>
      ))}
      {kind === 'keep' && <span className="chip">Yours to keep</span>}
    </div>
  );
}

export function ItemIcon({ item }: { item: Pick<ItemBase, 'icon' | 'category'> }) {
  return <span className={`item__icon item__icon--${item.category}`} aria-hidden>{item.icon || '📦'}</span>;
}

function Stepper({ value, max, onChange }: { value: number; max: number; onChange: (n: number) => void }) {
  return (
    <span className="qty" role="group" aria-label="Quantity">
      <button type="button" className="qty__btn" onClick={() => onChange(Math.max(1, value - 1))} disabled={value <= 1} aria-label="One less">
        <span aria-hidden className="qty__minus" />
      </button>
      <span className="qty__val" aria-live="polite">{value}</span>
      <button type="button" className="qty__btn" onClick={() => onChange(Math.min(max, value + 1))} disabled={value >= max} aria-label="One more">
        <Icon name="plus" size={14} stroke={3} />
      </button>
    </span>
  );
}

/**
 * One item row. `price` is per item; with `maxQty` > 1 a quantity stepper appears and the button shows the total.
 * `blocked` (a reason) disables the button and shows the reason as its label.
 */
export function ItemCard({ item, price, priceNote, owned, kind, maxQty = 1, action, actionVariant = 'green', blocked, busy, onAction, extra, note }: {
  item: ItemBase;
  price?: number;
  priceNote?: string;
  owned?: number;
  kind?: string;
  maxQty?: number;
  action: string;
  actionVariant?: 'green' | 'primary' | 'gold' | 'ghost';
  blocked?: string | null;
  busy?: boolean;
  onAction: (qty: number) => void;
  extra?: React.ReactNode;
  /** Shown instead of the button when `action` is empty. */
  note?: string;
}) {
  const [qty, setQty] = useState(1);
  const total = price != null ? price * qty : null;
  return (
    <article className={`item${blocked ? ' is-locked' : ''}`}>
      <div className="item__top">
        <ItemIcon item={item} />
        <div className="grow">
          <h4 className="item__name">
            {item.name}
            {owned ? <span className="item__owned">×{owned} in Bag</span> : null}
          </h4>
          <p className="item__desc">{item.description}</p>
        </div>
        {price != null && (
          <div className="item__price">
            <b>{naira(price)}</b>
            {priceNote && <span>{priceNote}</span>}
          </div>
        )}
      </div>
      <ItemEffectChips effects={item.effects} kind={kind} />
      {!action && note && <p className="item__note">{note}</p>}
      <div className="item__actions">
        {extra}
        <span className="grow" />
        {action && maxQty > 1 && !blocked && <Stepper value={qty} max={maxQty} onChange={setQty} />}
        {action ? (
          <Button size="sm" variant={actionVariant} loading={busy} disabled={Boolean(blocked)} onClick={() => onAction(qty)}>
            {blocked ?? (total != null && qty > 1 ? `${action} · ${naira(total)}` : action)}
          </Button>
        ) : null}
      </div>
    </article>
  );
}
