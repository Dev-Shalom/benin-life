// V1-5 shared bits for the Bank panel, the PoS panel and the phone Bank app (docs/BANK.md).
import { naira, nairaShort } from '../../lib/format';
import type { GameState } from '../../lib/types';

/** Cash + bank tiles. */
export function Balances({ state }: { state: GameState }) {
  return (
    <div className="bankx__bals">
      <div className="bankx__bal">
        <span className="bankx__bal-label">💵 Cash on you</span>
        <b>{naira(state.profile.cash)}</b>
      </div>
      <div className="bankx__bal bankx__bal--bank">
        <span className="bankx__bal-label">🏦 In the bank</span>
        <b>{naira(state.profile.bank)}</b>
      </div>
    </div>
  );
}

/** Amount field with quick chips (₦1k / ₦5k / All). `max` is what "All" fills in. */
export function AmountBox({ value, onChange, max, min, label = 'Amount' }: {
  value: string;
  onChange: (v: string) => void;
  max: number;
  min: number;
  label?: string;
}) {
  const n = Number(value) || 0;
  const chips: [number, string][] = [[1000, '₦1k'], [5000, '₦5k']];
  return (
    <div className="bankx__amount">
      <label className="bankx__amount-field">
        <span className="bankx__amount-label">{label}</span>
        <span className="bankx__amount-input">
          <span aria-hidden>₦</span>
          <input className="input" inputMode="numeric" pattern="[0-9]*" placeholder="0" value={value}
            aria-label={label}
            onChange={(e) => onChange(e.target.value.replace(/[^0-9]/g, '').replace(/^0+(?=\d)/, '').slice(0, 10))} />
        </span>
      </label>
      <div className="bankx__chips">
        {chips.map(([c, label]) => (
          <button key={c} type="button" className={`bankx__chip${n === c ? ' is-on' : ''}`} disabled={c > max}
            onClick={() => onChange(String(c))}>
            {label}
          </button>
        ))}
        <button type="button" className={`bankx__chip${n === max && max > 0 ? ' is-on' : ''}`} disabled={max < min}
          onClick={() => onChange(String(max))}>
          All{max >= min ? ` · ${nairaShort(max)}` : ''}
        </button>
      </div>
    </div>
  );
}
