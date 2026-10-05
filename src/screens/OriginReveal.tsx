// Origin reveal (P1-ORIGIN): shown once, right after create_profile, before entering the game.
// Timeline is pure CSS (see "Origin reveal" in screens.css): coin toss ~1.2s → title, home card,
// perks stagger in → "Oya enter Benin". Tap during the toss to skip. Reduced motion = fades only.
import { useEffect, useMemo, useState, type CSSProperties } from 'react';
import { Avatar } from '../art/avatar/Avatar';
import { Scene } from '../art/Scene';
import { naira } from '../lib/format';
import { ORIGIN_UI, originCopy } from '../lib/pidgin';
import type { GameState } from '../lib/types';
import { Button, Icon } from '../ui';

interface Perk {
  icon: string;
  label: string;
  value: string;
}

const COIN_FACE: Record<string, { icon: string; label: string }> = {
  nepo: { icon: 'crown', label: 'NEPO' },
  lapo: { icon: 'bolt', label: 'LAPO' },
};

const CONFETTI_COLORS = ['#f3d28a', '#d9a441', '#f06a55', '#d2342a', '#fbf3e4', '#b0793a'];

/** Deterministic burst so renders are stable (no Math.random in render). */
function confettiPieces(n: number) {
  return Array.from({ length: n }, (_, i) => {
    const a = (i / n) * Math.PI * 2 + (i % 3) * 0.35;
    const dist = 90 + ((i * 37) % 70);
    return {
      '--bx': `${Math.round(Math.cos(a) * dist)}px`,
      '--by': `${Math.round(Math.sin(a) * dist * 0.7 - 40)}px`,
      '--rot': `${(i * 67) % 360}deg`,
      '--dl': `${(i % 5) * 30}ms`,
      background: CONFETTI_COLORS[i % CONFETTI_COLORS.length],
    } as CSSProperties;
  });
}

function stagger(ms: number): CSSProperties {
  return { '--d': `${ms}ms` } as CSSProperties;
}

export default function OriginReveal({ state, onDone }: { state: GameState; onDone: () => void }) {
  const p = state.profile;
  const o = state.origin ?? null;
  const tier = o?.id ?? p.origin ?? 'lapo';
  const copy = originCopy(tier, o?.name ?? 'LAPO baby', o?.tagline ?? '');
  const gold = tier === 'nepo';
  const home = state.location;
  const [skipped, setSkipped] = useState(false);
  const [tossed, setTossed] = useState(false);

  // Warm the game chunk while the player enjoys the moment.
  useEffect(() => {
    void import('./Game');
  }, []);

  const front = COIN_FACE[tier] ?? { icon: 'star', label: (copy.badge || tier).toUpperCase() };
  const backTier = tier === 'lapo' ? 'nepo' : 'lapo';
  const back = COIN_FACE[backTier];

  const perks = useMemo<Perk[]>(() => {
    const list: Perk[] = [{ icon: 'cash', label: ORIGIN_UI.cash, value: naira(p.cash) }];
    if (p.bank > 0) list.push({ icon: 'bank', label: ORIGIN_UI.bank, value: naira(p.bank) });
    for (const it of o?.items ?? []) {
      list.push({ icon: it.category === 'vehicle' ? 'car' : it.category === 'gadget' ? 'laptop' : 'bag', label: it.name, value: 'Na your own' });
    }
    if (o && o.allowance_daily > 0)
      list.push({ icon: 'sparkle', label: ORIGIN_UI.allowance, value: `${naira(o.allowance_daily)} ${ORIGIN_UI.perDay}` });
    if (o && o.career_head_start > 0) list.push({ icon: 'star', label: ORIGIN_UI.headStart, value: ORIGIN_UI.levels(o.career_head_start) });
    if (o?.perks?.micro_loan_access === 'easy') list.push({ icon: 'shield', label: ORIGIN_UI.easyLoan, value: ORIGIN_UI.easyLoanValue });
    if (!o?.items?.length) list.push({ icon: 'bag', label: ORIGIN_UI.emptyBag, value: ORIGIN_UI.emptyBagValue });
    return list;
  }, [p.cash, p.bank, o]);

  const confetti = useMemo(() => (gold ? confettiPieces(18) : []), [gold]);
  const line = copy.line.replace('{home}', home.name);

  return (
    <div
      className={`reveal reveal--${gold ? 'gold' : 'warm'}${skipped ? ' is-skipped' : ''}`}
      role="dialog"
      aria-modal="true"
      aria-labelledby="reveal-title"
      onClick={() => {
        if (!tossed && !skipped) setSkipped(true);
      }}
    >
      {!skipped && !tossed && (
        <div
          className="reveal__toss"
          aria-hidden
          onAnimationEnd={(e) => {
            if (e.animationName === 'reveal-toss-out' || e.animationName === 'reveal-fade-out') setTossed(true);
          }}
        >
          <div className="reveal__coin">
            <div className={`reveal__face reveal__face--${tier in COIN_FACE ? tier : 'other'}`}>
              <Icon name={front.icon} size={34} stroke={2.4} />
              <span>{front.label}</span>
            </div>
            <div className={`reveal__face reveal__face--back reveal__face--${backTier}`}>
              <Icon name={back.icon} size={34} stroke={2.4} />
              <span>{back.label}</span>
            </div>
          </div>
          <p className="reveal__rolling">{ORIGIN_UI.rolling}</p>
          <p className="reveal__skip">{ORIGIN_UI.skip}</p>
        </div>
      )}

      <div className="reveal__inner">
        <header className="reveal__head">
          <div className="reveal__rays" aria-hidden />
          {gold && (
            <div className="reveal__confetti" aria-hidden>
              {confetti.map((s, i) => (
                <i key={i} style={s} />
              ))}
            </div>
          )}
          <p className="reveal__kicker reveal__in" style={stagger(0)}>{copy.kicker}</p>
          <h1 id="reveal-title" className="reveal__title reveal__pop">
            <span className={`reveal__medal reveal__medal--${tier in COIN_FACE ? tier : 'other'}`} aria-hidden>
              <Icon name={front.icon} size={20} stroke={2.6} />
            </span>
            {copy.title}
          </h1>
          <p className="reveal__line reveal__in" style={stagger(90)}>{line}</p>
        </header>

        <figure className="reveal__card reveal__in" style={stagger(160)}>
          <div className="reveal__scene">
            <Scene type={home.scene} night={state.clock.is_night} />
          </div>
          <div className="reveal__avatar">
            <Avatar config={p.avatar} view="full" />
          </div>
          <figcaption className="reveal__home">
            <Icon name="home" size={14} stroke={2.4} />
            <span>
              <small>{ORIGIN_UI.home}</small>
              {home.name}
            </span>
          </figcaption>
        </figure>

        <ul className="reveal__perks">
          {perks.map((k, i) => (
            <li key={k.label} className="reveal__perk reveal__in" style={stagger(260 + i * 60)}>
              <span className="reveal__perk-icon"><Icon name={k.icon} size={16} stroke={2.3} /></span>
              <span className="reveal__perk-text">
                <small>{k.label}</small>
                <b>{k.value}</b>
              </span>
            </li>
          ))}
        </ul>

        <p className="reveal__cheer reveal__in" style={stagger(300 + perks.length * 60)}>{copy.cheer}</p>

        <div className="reveal__cta reveal__in" style={stagger(380 + perks.length * 60)}>
          <Button variant={gold ? 'gold' : 'green'} size="lg" block onClick={onDone}>
            {ORIGIN_UI.enter} <Icon name="chevronRight" size={18} />
          </Button>
        </div>
      </div>
    </div>
  );
}
