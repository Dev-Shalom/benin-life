import { useEffect, useMemo, useState } from 'react';
import type { Dream, GameState } from '../../lib/types';
import { useCatalog } from '../../state/catalog';
import './JourneyGuide.css';

const steps = [
  { eyebrow: 'YOUR FIRST DAY', title: 'A new life in Benin City', icon: '🌇' },
  { eyebrow: 'MAKE IT YOURS', title: 'Your home, your starting point', icon: '🏠' },
  { eyebrow: 'FIND YOUR WAY', title: 'The city is open to explore', icon: '🗺️' },
  { eyebrow: 'KEEP YOUR STORY MOVING', title: 'Build a life one week at a time', icon: '📖' },
];

function dreamName(id: string | null | undefined, dreams: Dream[] | undefined) {
  if (!id) return 'your own goal';
  return dreams?.find((item) => item.id === id)?.name ?? id.replace(/[_-]+/g, ' ');
}

export default function JourneyGuide({ state, onFinish }: { state: GameState; onFinish: (explore: boolean) => void }) {
  const uid = state.profile.id;
  const [step, setStep] = useState(0);
  const [open, setOpen] = useState(false);
  const catalog = useCatalog((s) => s.catalog);
  const loadCatalog = useCatalog((s) => s.loadCatalog);
  const origin = state.profile.origin === 'nepo' ? 'NEPO' : 'LAPO';
  const startingPlace = state.location.name;
  const dream = useMemo(() => dreamName(state.profile.dream, catalog?.dreams), [state.profile.dream, catalog?.dreams]);

  useEffect(() => {
    try {
      const done = window.localStorage.getItem(`bl.journey.done.${uid}`);
      const pending = window.localStorage.getItem(`bl.journey.pending.${uid}`);
      setOpen(pending === '1' && done !== '1');
    } catch { setOpen(false); }
    void loadCatalog();
  }, [uid, loadCatalog]);

  if (!open) return null;

  const finish = (explore: boolean) => {
    try {
      window.localStorage.setItem(`bl.journey.done.${uid}`, '1');
      window.localStorage.removeItem(`bl.journey.pending.${uid}`);
    } catch { /* private browsing */ }
    setOpen(false);
    onFinish(explore);
  };

  const copy = [
    origin === 'LAPO'
      ? `You are starting at ${startingPlace} with a modest safety net. Keep your energy up, find steady work, and take small steps toward ${dream}.`
      : `You have a stronger safety net to begin with. Use it thoughtfully: meet people around town, build your plans, and move toward ${dream}.`,
    'Your home is your base. Check your needs, use the furniture and activities available to you, and keep an eye on rent day. Your origin affects the starter home and what is inside.',
    'Use the Map tab to find work, markets, landmarks and other places. Check opening hours before travelling; a closed venue will tell you when it opens. At a place, meet the people there and join its location chat.',
    'Use the phone for Jobs, Stories, rides and other working services. Stories bring a new community choice each game week; your lifetime dream gives your choices a longer direction. Chat with players where you meet them, and look for events on the map.',
  ];

  return (
    <div className="journey-guide" role="dialog" aria-modal="true" aria-labelledby="journey-title">
      <div className="journey-guide__backdrop" />
      <section className="journey-guide__card">
        <div className="journey-guide__art" aria-hidden>
          <div className="journey-guide__sun" />
          <span className="journey-guide__icon">{steps[step].icon}</span>
          <span className="journey-guide__city">BENIN CITY · EDO STATE</span>
          <span className="journey-guide__origin">{origin} LIFE</span>
        </div>
        <div className="journey-guide__body">
          <div className="journey-guide__eyebrow">{steps[step].eyebrow}<span>{step + 1} / {steps.length}</span></div>
          <h2 id="journey-title">{steps[step].title}</h2>
          <p>{copy[step]}{step === 0 && <span className="journey-guide__local">Your choices shape this life. Benin City is the setting; your story is yours.</span>}</p>
          <div className="journey-guide__progress" aria-label={`Guide step ${step + 1} of ${steps.length}`}>
            {steps.map((item, i) => <span key={item.eyebrow} className={i <= step ? 'is-active' : ''} />)}
          </div>
          <div className="journey-guide__actions">
            <button type="button" className="journey-guide__skip" onClick={() => finish(false)}>Skip tour</button>
            {step < steps.length - 1
              ? <button type="button" className="journey-guide__next" onClick={() => setStep((value) => value + 1)}>Next <span aria-hidden>→</span></button>
              : <button type="button" className="journey-guide__next" onClick={() => finish(true)}>Explore the map <span aria-hidden>→</span></button>}
          </div>
        </div>
      </section>
    </div>
  );
}
