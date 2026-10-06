import { isShortened, naira, nairaShort } from '../lib/format';
import { Icon } from './Icon';

/** Naira amount with optional cash/bank glyph. `short` uses ₦12.5K style; hover shows the full amount. */
export function Money({ amount, kind, short, className = '', delta }: {
  amount: number; kind?: 'cash' | 'bank'; short?: boolean; className?: string; delta?: boolean;
}) {
  const tone = delta ? (amount > 0 ? ' bl-money--up' : amount < 0 ? ' bl-money--down' : '') : '';
  const text = short ? nairaShort(amount) : naira(amount);
  const title = short && isShortened(amount) ? naira(amount) : undefined;
  return (
    <span className={`bl-money${tone} ${className}`} title={title}>
      {kind && <Icon name={kind} size={16} />}
      <span>{delta && amount > 0 ? '+' : ''}{text}</span>
    </span>
  );
}
