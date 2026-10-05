// On/off switch row (settings). The whole row is the control; role="switch" for screen readers.
import type { ReactNode } from 'react';

export function Switch({ checked, onChange, label, hint, disabled }: {
  checked: boolean; onChange: (v: boolean) => void; label: ReactNode; hint?: ReactNode; disabled?: boolean;
}) {
  return (
    <button type="button" role="switch" aria-checked={checked} disabled={disabled} className={`bl-switch-row${checked ? ' is-on' : ''}`}
      onClick={() => onChange(!checked)}>
      <span className="bl-switch-row__text">
        <span className="bl-switch-row__label">{label}</span>
        {hint && <span className="bl-switch-row__hint">{hint}</span>}
      </span>
      <span className="bl-switch" aria-hidden><span /></span>
    </button>
  );
}
