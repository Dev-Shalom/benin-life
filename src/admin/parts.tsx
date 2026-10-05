// Small building blocks shared by the admin sections.
import { useEffect, useState, type ButtonHTMLAttributes, type CSSProperties, type ReactNode } from 'react';
import { Icon } from '../ui';
import { showSlider, sliderStep, fmtNumber } from './util';

export function PageHead({ title, sub, actions }: { title: string; sub?: ReactNode; actions?: ReactNode }) {
  return (
    <header className="adm-pagehead">
      <div>
        <h1 className="adm-h1">{title}</h1>
        {sub && <p className="adm-sub">{sub}</p>}
      </div>
      {actions && <div className="adm-pagehead__actions">{actions}</div>}
    </header>
  );
}

export function LoadError({ error, onRetry }: { error: string; onRetry: () => void }) {
  return (
    <div className="adm-card adm-error">
      <Icon name="warning" size={18} /> <span>{error}</span>
      <button type="button" className="adm-link" onClick={onRetry}>Try again</button>
    </div>
  );
}

export function Skeleton({ rows = 4 }: { rows?: number }) {
  return (
    <div className="adm-card adm-skel" aria-busy="true" aria-label="Loading">
      {Array.from({ length: rows }, (_, i) => <div key={i} className="adm-skel__row" style={{ width: `${92 - i * 9}%` }} />)}
    </div>
  );
}

export function Badge({ tone = 'grey', children }: { tone?: 'grey' | 'green' | 'red' | 'amber' | 'blue' | 'violet'; children: ReactNode }) {
  return <span className={`adm-badge adm-badge--${tone}`}>{children}</span>;
}

/** Two-tap confirm for destructive actions (no browser dialogs; works well on phones). */
export function ConfirmButton({ children, confirmText = 'Tap again to confirm', onConfirm, tone = 'danger', disabled, small }: {
  children: ReactNode; confirmText?: string; onConfirm: () => void | Promise<void>; tone?: 'danger' | 'ghost' | 'primary';
  disabled?: boolean; small?: boolean;
}) {
  const [armed, setArmed] = useState(false);
  const [busy, setBusy] = useState(false);
  useEffect(() => {
    if (!armed) return;
    const t = window.setTimeout(() => setArmed(false), 3500);
    return () => window.clearTimeout(t);
  }, [armed]);
  return (
    <button type="button" disabled={disabled || busy}
      className={`adm-btn adm-btn--${armed ? 'danger' : tone}${small ? ' adm-btn--sm' : ''}${armed ? ' is-armed' : ''}`}
      onClick={async () => {
        if (!armed) { setArmed(true); return; }
        setArmed(false);
        setBusy(true);
        try { await onConfirm(); } finally { setBusy(false); }
      }}>
      {armed ? confirmText : children}
    </button>
  );
}

export function Btn({ children, tone = 'ghost', small, icon, ...rest }: ButtonHTMLAttributes<HTMLButtonElement> & {
  tone?: 'primary' | 'ghost' | 'danger' | 'quiet'; small?: boolean; icon?: string;
}) {
  return (
    <button type="button" {...rest} className={`adm-btn adm-btn--${tone}${small ? ' adm-btn--sm' : ''} ${rest.className ?? ''}`}>
      {icon && <Icon name={icon} size={small ? 14 : 16} />}
      {children}
    </button>
  );
}

/** Slider + exact number input. Emits numbers; shows min/max. */
export function NumberControl({ kind, value, min, max, onChange, invalid, id }: {
  kind: string; value: number | ''; min: number | null; max: number | null; onChange: (v: number | '') => void;
  invalid?: boolean; id?: string;
}) {
  const slider = showSlider(kind, min, max);
  const num = value === '' ? (min ?? 0) : value;
  return (
    <div className="adm-num">
      {slider && (
        <input type="range" className="adm-range" aria-label="Adjust" min={min!} max={max!}
          step={sliderStep(kind, min!, max!, num)} value={Math.min(max!, Math.max(min!, num))}
          style={{ '--p': `${((Math.min(max!, Math.max(min!, num)) - min!) / (max! - min!)) * 100}%` } as CSSProperties}
          onChange={(e) => onChange(Number(e.target.value))} />
      )}
      <label className={`adm-numbox${invalid ? ' is-invalid' : ''}`}>
        {kind === 'naira' && <span className="adm-numbox__affix">₦</span>}
        <input id={id} type="number" inputMode="decimal" step="any" value={value}
          min={min ?? undefined} max={max ?? undefined}
          onChange={(e) => onChange(e.target.value === '' ? '' : Number(e.target.value))} />
        {kind === 'percent' && <span className="adm-numbox__affix">%</span>}
        {kind === 'minutes' && <span className="adm-numbox__affix">min</span>}
      </label>
      {(min !== null || max !== null) && (
        <span className="adm-num__range">{min !== null ? fmtNumber(kind, min) : '…'} – {max !== null ? fmtNumber(kind, max) : '…'}</span>
      )}
    </div>
  );
}

export function Toggle({ checked, onChange, label }: { checked: boolean; onChange: (v: boolean) => void; label?: string }) {
  return (
    <button type="button" role="switch" aria-checked={checked} aria-label={label} className={`adm-toggle${checked ? ' is-on' : ''}`}
      onClick={() => onChange(!checked)}>
      <span className="adm-toggle__knob" />
    </button>
  );
}

/** JSON textarea that reports parse errors as you type. */
export function JsonControl({ value, onChange, rows = 4, expect = 'object' }: {
  value: string; onChange: (text: string, parsed: unknown, ok: boolean) => void; rows?: number; expect?: 'object' | 'any';
}) {
  const [err, setErr] = useState<string | null>(null);
  return (
    <div>
      <textarea className={`adm-input adm-mono${err ? ' is-invalid' : ''}`} rows={rows} spellCheck={false} value={value}
        onChange={(e) => {
          const t = e.target.value;
          try {
            const p = JSON.parse(t);
            if (expect === 'object' && (p === null || typeof p !== 'object' || Array.isArray(p))) throw new Error('Must be a JSON object: { … }');
            setErr(null);
            onChange(t, p, true);
          } catch (x) {
            setErr(x instanceof Error ? x.message.replace(/^JSON\.parse: /, '') : 'Invalid JSON');
            onChange(t, undefined, false);
          }
        }} />
      {err && <div className="adm-field__err">{err}</div>}
    </div>
  );
}

/** Side panel: a column on wide screens, a full-screen sheet on phones. */
export function DetailPane({ open, title, onClose, children, footer }: {
  open: boolean; title: ReactNode; onClose: () => void; children: ReactNode; footer?: ReactNode;
}) {
  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') onClose(); };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [open, onClose]);
  if (!open) return null;
  return (
    <aside className="adm-detail" aria-label="Details">
      <div className="adm-detail__head">
        <div className="adm-detail__title">{title}</div>
        <button type="button" className="adm-iconbtn" aria-label="Close" onClick={onClose}><Icon name="close" size={18} /></button>
      </div>
      <div className="adm-detail__body">{children}</div>
      {footer && <div className="adm-detail__foot">{footer}</div>}
    </aside>
  );
}
