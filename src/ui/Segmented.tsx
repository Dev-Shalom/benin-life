import type { CSSProperties, ReactNode } from 'react';

export interface SegmentOption<T extends string> {
  id: T;
  label: ReactNode;
}

/** Pill segmented control with a sliding white thumb (e.g. Create account | Log in, Woman | Man). */
export function Segmented<T extends string>({ options, value, onChange, label, className = '' }: {
  options: SegmentOption<T>[];
  value: T;
  onChange: (id: T) => void;
  /** Accessible name for the group. */
  label?: string;
  className?: string;
}) {
  const index = Math.max(0, options.findIndex((o) => o.id === value));
  return (
    <div
      className={`bl-seg ${className}`}
      role="tablist"
      aria-label={label}
      style={{ '--n': options.length, '--i': index } as CSSProperties}
    >
      <span className="bl-seg__thumb" aria-hidden />
      {options.map((o) => (
        <button
          key={o.id}
          type="button"
          role="tab"
          aria-selected={o.id === value}
          className={`bl-seg__opt${o.id === value ? ' is-active' : ''}`}
          onClick={() => onChange(o.id)}
        >
          {o.label}
        </button>
      ))}
    </div>
  );
}
