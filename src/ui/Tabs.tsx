import { useEffect, useRef, type ReactNode } from 'react';

export interface TabItem { id: string; label: string; badge?: number | string | null; icon?: ReactNode }

/** Horizontally scrollable pill tabs; active tab scrolls into view. */
export function Tabs({ tabs, value, onChange, className = '' }: {
  tabs: TabItem[]; value: string; onChange: (id: string) => void; className?: string;
}) {
  const ref = useRef<HTMLDivElement>(null);
  useEffect(() => {
    const el = ref.current?.querySelector<HTMLElement>('[aria-selected="true"]');
    el?.scrollIntoView({ block: 'nearest', inline: 'center', behavior: 'smooth' });
  }, [value]);
  return (
    <div className={`bl-tabs ${className}`} role="tablist" ref={ref}>
      {tabs.map((t) => (
        <button key={t.id} type="button" role="tab" aria-selected={t.id === value}
          className={`bl-tab${t.id === value ? ' is-active' : ''}`} onClick={() => onChange(t.id)}>
          {t.icon}
          {t.label}
          {t.badge ? <span className="bl-tab__badge">{t.badge}</span> : null}
        </button>
      ))}
    </div>
  );
}
