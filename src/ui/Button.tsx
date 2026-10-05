import type { ButtonHTMLAttributes, ReactNode } from 'react';
import { Spinner } from './Spinner';
import { Icon } from './Icon';

export type ButtonVariant = 'primary' | 'gold' | 'green' | 'ghost' | 'danger' | 'dark';

export interface ButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: ButtonVariant;
  size?: 'sm' | 'md' | 'lg';
  block?: boolean;
  loading?: boolean;
  icon?: string;
  children?: ReactNode;
}

/** Pill button. primary/green = the green action, gold = money/premium, ghost = white secondary. `loading` disables + shows spinner. */
export function Button({
  variant = 'primary', size = 'md', block, loading, icon, children, className = '', disabled, type = 'button', ...rest
}: ButtonProps) {
  return (
    <button
      type={type}
      className={`bl-btn bl-btn--${variant} bl-btn--${size}${block ? ' bl-btn--block' : ''} ${className}`}
      disabled={disabled || loading}
      aria-busy={loading || undefined}
      {...rest}
    >
      {loading ? <Spinner size={size === 'sm' ? 14 : 18} /> : icon ? <Icon name={icon} size={size === 'sm' ? 16 : 20} /> : null}
      {children && <span className="bl-btn__label">{children}</span>}
    </button>
  );
}

/** Round icon-only button (HUD, close buttons). glass = white floating circle, plain = soft grey. */
export function IconButton({ icon, label, badge, className = '', variant = 'glass', size = 44, ...rest }: Omit<ButtonHTMLAttributes<HTMLButtonElement>, 'children'> & {
  icon: string; label: string; badge?: number | string | null; variant?: 'glass' | 'plain' | 'gold'; size?: number;
}) {
  return (
    <button type="button" aria-label={label} title={label} className={`bl-iconbtn bl-iconbtn--${variant} ${className}`}
      style={{ width: size, height: size }} {...rest}>
      <Icon name={icon} size={Math.round(size * 0.48)} />
      {badge ? <span className="bl-iconbtn__badge">{typeof badge === 'number' && badge > 99 ? '99+' : badge}</span> : null}
    </button>
  );
}
