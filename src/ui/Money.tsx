import { naira, nairaShort } from '../lib/format';
import { Icon } from './Icon';

/** Naira amount with optional cash/bank glyph. `short` uses ₦12.5k style. */
export function Money({ amount, kind, short, className = '', delta }: {
  amount: number; kind?: 'cash' | 'bank'; short?: boolean; className?: string; delta?: boolean;
}) {
  const tone = delta ? (amount > 0 ? ' bl-money--up' : amount < 0 ? ' bl-money--down' : '') : '';
  const text = short ? nairaShort(amount) : naira(amount);
  return (
    <span className={`bl-money${tone} ${className}`}>
      {kind && <Icon name={kind} size={16} />}
      <span>{delta && amount > 0 ? '+' : ''}{text}</span>
    </span>
  );
}
