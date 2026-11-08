// Accessible accordion: one open at a time, a button per question, the answer is a labelled region.
// Height animates with grid-template-rows (public/mk/mk.css), not a measured pixel height.
import { useId, useState, type ReactNode } from 'react';
import { Ph } from './Ph';

export function Accordion({ items }: { items: { q: string; a: ReactNode }[] }) {
  const uid = useId();
  const [open, setOpen] = useState<number | null>(null);
  return (
    <div className="mk-acc">
      {items.map((it, i) => {
        const isOpen = open === i;
        return (
          <div key={it.q} className={`mk-acc__item${isOpen ? ' is-open' : ''}`}>
            <h3>
              <button type="button" id={`${uid}-b${i}`} aria-expanded={isOpen} aria-controls={`${uid}-p${i}`} onClick={() => setOpen(isOpen ? null : i)}>
                {it.q}
                <Ph name="caretDown" />
              </button>
            </h3>
            <div id={`${uid}-p${i}`} role="region" aria-labelledby={`${uid}-b${i}`} className="mk-acc__panel" inert={!isOpen}>
              <div>
                <p>{it.a}</p>
              </div>
            </div>
          </div>
        );
      })}
    </div>
  );
}
