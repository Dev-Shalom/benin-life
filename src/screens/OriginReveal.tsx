// Birth lottery reveal (P1-ORIGIN, rebuilt for the R3b creator). Rendered inside the creator's bottom
// sheet, right after create_profile_v2 rolled the origin. No home is chosen yet, so it lists what the
// origin gives (bank, items, Dad's allowance, LAPO's easy loan) and never any percentages.
//
// Timeline is pure CSS (see "Birth lottery" in screens.css): a coin toss of about 1.2 s, then the
// big tile, title and perk rows stagger in. Tap the toss to skip. `replay={false}` (coming back
// to this step later) shows the result straight away. Reduced motion: no toss movement, fades only.
import { useState, type CSSProperties } from 'react';
import { naira } from '../lib/format';
import { ORIGIN_UI, originCopy } from '../lib/pidgin';
import type { GameState } from '../lib/types';

interface Perk {
  emoji: string;
  text: string;
}

const COIN: Record<string, string> = { nepo: 'NEPO', lapo: 'LAPO' };

function stagger(ms: number): CSSProperties {
  return { '--d': `${ms}ms` } as CSSProperties;
}

/** What this origin gives, as plain sentences. Built from the server's origin info only. */
function originPerks(state: GameState): Perk[] {
  const o = state.origin;
  if (!o) return [{ emoji: '🏠', text: ORIGIN_UI.cashByHome }];
  const list: Perk[] = [];
  if (o.start_bank > 0) list.push({ emoji: '🏦', text: ORIGIN_UI.bank(naira(o.start_bank)) });
  for (const it of o.items ?? []) {
    list.push({
      emoji: it.category === 'vehicle' ? '🚗' : it.category === 'gadget' ? '💻' : '🎁',
      text: ORIGIN_UI.item(it.name),
    });
  }
  if (o.allowance_daily > 0)
    list.push({
      emoji: '💸',
      text: ORIGIN_UI.allowance(naira(o.allowance_daily)),
    });
  if (o.career_head_start > 0) list.push({ emoji: '⭐', text: ORIGIN_UI.headStart(o.career_head_start) });
  if (o.perks?.micro_loan_access === 'easy') list.push({ emoji: '🤝', text: ORIGIN_UI.easyLoan });
  if (o.start_bank <= 0) list.push({ emoji: '🏦', text: ORIGIN_UI.noBank });
  if (!o.items?.length) list.push({ emoji: '🎒', text: ORIGIN_UI.emptyBag });
  list.push({ emoji: '🏠', text: ORIGIN_UI.cashByHome });
  return list;
}

export default function OriginReveal({ state, replay = true }: { state: GameState; replay?: boolean }) {
  const p = state.profile;
  const o = state.origin ?? null;
  const tier = o?.id ?? p.origin ?? 'lapo';
  const copy = originCopy(tier, o?.name ?? 'LAPO baby', o?.tagline ?? '');
  const gold = tier === 'nepo';
  const [skipped, setSkipped] = useState(!replay);
  const [tossed, setTossed] = useState(!replay);
  const perks = originPerks(state);
  const front = COIN[tier] ?? copy.badge.toUpperCase();
  const back = tier === 'nepo' ? 'LAPO' : 'NEPO';

  return (
    <section
      className={`lottery lottery--${gold ? 'gold' : 'warm'}${skipped ? ' is-skipped' : ''}`}
      aria-labelledby="lottery-title"
      aria-live="polite"
    >
      <p className="lottery__ask">{ORIGIN_UI.ask(p.username)}</p>

      <div className="lottery__stage">
        {!tossed && (
          <button
            type="button"
            className="lottery__toss"
            aria-label={ORIGIN_UI.skip}
            onClick={() => setSkipped(true)}
            onAnimationEnd={(e) => {
              if (e.target === e.currentTarget) setTossed(true);
            }}
          >
            <span className="lottery__coin" aria-hidden>
              <span className={`lottery__face lottery__face--${tier === 'nepo' ? 'nepo' : 'lapo'}`}>{front}</span>
              <span className={`lottery__face lottery__face--back lottery__face--${tier === 'nepo' ? 'lapo' : 'nepo'}`}>
                {back}
              </span>
            </span>
            <span className="lottery__rolling">{ORIGIN_UI.rolling}</span>
            <span className="lottery__skip">{ORIGIN_UI.skip}</span>
          </button>
        )}

        <div className="lottery__result" aria-hidden={!tossed && !skipped ? true : undefined}>
          <div className="lottery__tile lottery__pop" aria-hidden>
            <span>{copy.emoji}</span>
          </div>
          <h2 id="lottery-title" className="lottery__title lottery__in" style={stagger(60)}>
            {copy.title}
          </h2>
          <p className="lottery__line lottery__in" style={stagger(120)}>
            {copy.line}
          </p>
          <ul className="lottery__perks">
            {perks.map((k, i) => (
              <li key={k.text} className="lottery__perk lottery__in" style={stagger(200 + i * 55)}>
                <span className="lottery__perk-emoji" aria-hidden>
                  {k.emoji}
                </span>
                <span>{k.text}</span>
              </li>
            ))}
          </ul>
          <p className="lottery__once lottery__in" style={stagger(240 + perks.length * 55)}>
            {ORIGIN_UI.once}
          </p>
        </div>
      </div>
    </section>
  );
}
