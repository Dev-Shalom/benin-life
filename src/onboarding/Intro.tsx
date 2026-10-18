// Cinematic intro (docs/ONBOARDING.md): the screen fades to white, "Welcome to Benin Life" fades in over the logo,
// holds ~2.5 s, fades out, then the white lifts onto the game. Tap, click or any key skips it.
// prefers-reduced-motion: plain fades only (no rise, no scale). A soft sound swell plays when audio is unlocked
// and not muted (playSwell in lib/sound.ts decides). The tour starts after it (tourStore.queueFull).
import { useEffect, useRef, useState } from 'react';
import { useIntro } from './introStore';
import { useTour } from './tourStore';
import { playSwell } from '../lib/sound';
import './intro.css';

type Phase = 'cover' | 'title' | 'hold' | 'out' | 'reveal';

// timings (ms)
const T_COVER = 750; // fade to white
const T_TITLE = 1000; // title fades in
const T_HOLD = 2500; // title holds
const T_OUT = 650; // title fades out
const T_REVEAL = 1000; // white lifts onto the game
const T_SKIP = 380;

const sleep = (ms: number) => new Promise<void>((r) => window.setTimeout(r, ms));
const reduced = () => window.matchMedia('(prefers-reduced-motion: reduce)').matches;

export default function Intro() {
  const playing = useIntro((s) => s.playing);
  const [phase, setPhase] = useState<Phase>('cover');
  const [on, setOn] = useState(false);
  const [fast, setFast] = useState(false); // skipped: quicker fade
  const skipped = useRef(false);
  const coveredRef = useRef(false);

  useEffect(() => {
    if (!playing) return;
    let alive = true;
    skipped.current = false;
    coveredRef.current = false;
    setPhase('cover');
    setOn(false);
    setFast(false);

    const cover = () => {
      if (coveredRef.current) return;
      coveredRef.current = true;
      useIntro.getState().onCovered?.();
    };
    /** Wait unless skipped. Returns true if the intro should keep going. */
    const wait = async (ms: number) => {
      const end = performance.now() + ms;
      while (alive && !skipped.current && performance.now() < end) await sleep(Math.min(60, end - performance.now()));
      return alive && !skipped.current;
    };

    (async () => {
      await sleep(30);
      if (!alive) return;
      setOn(true); // white fades in
      await wait(T_COVER);
      cover();
      if (alive && !skipped.current) {
        setPhase('title');
        playSwell();
        await wait(T_TITLE);
      }
      if (alive && !skipped.current) { setPhase('hold'); await wait(T_HOLD); }
      if (alive && !skipped.current) { setPhase('out'); await wait(T_OUT); }
      if (!alive) return;
      cover(); // skipped before the cover finished: still change the route
      // do not lift the white until the game screen exists (it loads in the background)
      const t0 = performance.now();
      while (alive && performance.now() - t0 < 9000 && !document.querySelector('.pill-bar')) await sleep(100);
      if (!alive) return;
      setPhase('reveal');
      setOn(false);
      await sleep(skipped.current ? T_SKIP : T_REVEAL);
      if (!alive) return;
      useIntro.getState().end();
      useTour.getState().queueFull();
    })();

    return () => { alive = false; };
  }, [playing]);

  // tap / click / key skips
  useEffect(() => {
    if (!playing) return;
    const skip = () => { skipped.current = true; setFast(true); };
    window.addEventListener('keydown', skip, true);
    return () => window.removeEventListener('keydown', skip, true);
  }, [playing]);

  if (!playing) return null;
  const rm = reduced();
  return (
    <div
      className={`intro${on ? ' is-on' : ''} intro--${phase}${rm ? ' is-reduced' : ''}${fast ? ' is-skipped' : ''}`}
      role="dialog"
      aria-label="Welcome to Benin Life"
      data-intro-phase={phase}
      onPointerDown={() => { skipped.current = true; setFast(true); }}
    >
      <div className="intro__stage">
        <img className="intro__logo" src="/brand/logo-medallion.svg" alt="" width="148" height="148" draggable={false} />
        <h1 className="intro__title">Welcome to <span>Benin Life</span></h1>
        <p className="intro__sub">Experience life in Benin</p>
      </div>
      <p className="intro__skip" aria-hidden>Tap to skip</p>
    </div>
  );
}
