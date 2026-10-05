// Creator steps 2, 3 and 5: Personality (pick 2 traits), Dream (pick 1), Choose where to live.
import { naira } from '../../lib/format';
import { CREATOR } from '../../lib/pidgin';
import type { Dream, StartHomeOption, Trait } from '../../lib/types';

/** Skeleton cards while the catalog loads (same shape as the real cards, so nothing jumps). */
export function CardSkeleton({ count, variant }: { count: number; variant: 'trait' | 'row' }) {
  return (
    <div className={variant === 'trait' ? 'trait-grid' : 'pick-list'} aria-busy="true" aria-label={CREATOR.loading}>
      {Array.from({ length: count }, (_, i) => (
        <div key={i} className={`pick-skel pick-skel--${variant}`} />
      ))}
    </div>
  );
}

export function TraitPanel({ name, traits, picked, need, onToggle }: {
  name: string;
  traits: Trait[] | null;
  picked: string[];
  need: number;
  onToggle: (id: string) => void;
}) {
  return (
    <div className="pick">
      <p className="pick__ask">{CREATOR.traitsAsk(need, name)}</p>
      {!traits ? (
        <CardSkeleton count={6} variant="trait" />
      ) : (
        <div className="trait-grid">
          {traits.map((t) => {
            const idx = picked.indexOf(t.id);
            const on = idx >= 0;
            return (
              <button key={t.id} type="button" className={`trait-card${on ? ' is-active' : ''}`} aria-pressed={on} onClick={() => onToggle(t.id)}>
                <span className="trait-card__top">
                  <span className="trait-card__emoji" aria-hidden>{t.emoji}</span>
                  <span className="trait-card__tick" aria-hidden>{on ? idx + 1 : ''}</span>
                </span>
                <span className="trait-card__name">{t.name}</span>
                <span className="trait-card__desc">{t.description}</span>
              </button>
            );
          })}
        </div>
      )}
    </div>
  );
}

export function DreamPanel({ name, dreams, picked, onPick }: {
  name: string;
  dreams: Dream[] | null;
  picked: string | null;
  onPick: (id: string) => void;
}) {
  return (
    <div className="pick">
      <p className="pick__ask">{CREATOR.dreamAsk(name)}</p>
      {!dreams ? (
        <CardSkeleton count={5} variant="row" />
      ) : (
        <div className="pick-list" role="radiogroup" aria-label={CREATOR.dreamAsk(name)}>
          {dreams.map((d) => {
            const on = picked === d.id;
            return (
              <button key={d.id} type="button" role="radio" aria-checked={on} className={`dream-card${on ? ' is-active' : ''}`} onClick={() => onPick(d.id)}>
                <span className="dream-card__emoji" aria-hidden>{d.emoji}</span>
                <span className="dream-card__text">
                  <span className="dream-card__name">{d.name}</span>
                  <span className="dream-card__desc">{d.description}</span>
                </span>
              </button>
            );
          })}
        </div>
      )}
    </div>
  );
}

const TAG_TONE: Record<string, string> = {
  'Student life': 'blue',
  'Hard start': 'amber',
  Balanced: 'green',
  'Big spender': 'violet',
};

export function HomePanel({ name, homes, picked, onPick, rentDay, originChip }: {
  name: string;
  homes: StartHomeOption[];
  picked: string | null;
  onPick: (id: string) => void;
  rentDay: string;
  originChip: React.ReactNode;
}) {
  return (
    <div className="pick">
      <div className="pick__head">{originChip}</div>
      <p className="pick__ask">{CREATOR.homeAsk(name, rentDay)}</p>
      <div className="pick-list" role="radiogroup" aria-label={CREATOR.chooseHome}>
        {homes.map((h) => {
          const on = picked === h.id;
          const locked = !h.allowed;
          return (
            <button
              key={h.id}
              type="button"
              role="radio"
              aria-checked={on}
              aria-disabled={locked || undefined}
              className={`home-card${on ? ' is-active' : ''}${locked ? ' is-locked' : ''}`}
              onClick={() => !locked && onPick(h.id)}
            >
              <span className="home-card__head">
                <span className="home-card__emoji" aria-hidden>{h.emoji}</span>
                <span className="home-card__title">
                  <span className="home-card__name">{h.name}</span>
                  <span className="home-card__district">{h.district}</span>
                </span>
                <span className={`tag-pill tag-pill--${TAG_TONE[h.tag] ?? 'grey'}`}>{h.tag}</span>
              </span>
              <span className="home-card__desc">{h.description}</span>
              {locked ? (
                <span className="home-card__quip">{h.locked_quip}</span>
              ) : (
                <span className="home-card__money">
                  <b>{CREATOR.startWith(naira(h.start_cash))}</b>
                  <span>{CREATOR.rent(naira(h.weekly_rent))}</span>
                </span>
              )}
            </button>
          );
        })}
      </div>
    </div>
  );
}
