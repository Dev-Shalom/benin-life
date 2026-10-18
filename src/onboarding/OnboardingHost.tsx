// Mounted once in the game screen (replaces the old JourneyGuide). Runs the tour that the intro queued, shows the
// "Take the tour?" prompt to players who have not done it yet (existing accounts, once), and renders the overlay.
import { useEffect } from 'react';
import { Logo } from '../ui';
import { useGame } from '../state/game';
import { useUi } from '../state/ui';
import { useIntro } from './introStore';
import Tour from './Tour';
import { isTourDone, markTourDone, useTour } from './tourStore';
import './tour.css';

const PROMPT_DELAY_MS = 3500;

export default function OnboardingHost() {
  const uid = useGame((s) => s.state?.profile.id ?? null);
  const tourDoneAt = useGame((s) => s.state?.profile.tour_done_at ?? null);
  const queued = useTour((s) => s.queued);
  const active = useTour((s) => s.active);
  const prompt = useTour((s) => s.prompt);
  const introPlaying = useIntro((s) => s.playing);
  const overlay = useUi((s) => s.overlay);
  const panelOpen = useUi((s) => s.panel !== null || s.selectedId !== null);

  // the intro just ended: start the tour once the HUD is on screen
  useEffect(() => {
    if (!queued || active || !uid) return;
    const id = window.setTimeout(() => useTour.getState().start(), 450);
    return () => window.clearTimeout(id);
  }, [queued, active, uid]);

  // existing players, once: a small prompt a few seconds after they land in the game
  useEffect(() => {
    if (!uid || introPlaying || queued || active) return;
    if (isTourDone({ id: uid, tour_done_at: tourDoneAt })) return;
    const id = window.setTimeout(() => {
      const ui = useUi.getState();
      if (ui.overlay || ui.panel || ui.selectedId) return; // never on top of something they opened
      useTour.getState().setPrompt(true);
    }, PROMPT_DELAY_MS);
    return () => window.clearTimeout(id);
  }, [uid, tourDoneAt, introPlaying, queued, active]);

  // the prompt goes away quietly if the player opens something else first
  useEffect(() => {
    if (prompt && (overlay || panelOpen)) useTour.getState().setPrompt(false);
  }, [prompt, overlay, panelOpen]);

  if (!uid) return null;
  const dismiss = () => { useTour.getState().setPrompt(false); markTourDone(uid); };
  const take = () => useTour.getState().start();

  return (
    <>
      <Tour />
      {prompt && !active && (
        <aside className="tour-prompt" role="dialog" aria-label="Take the tour?" data-tour-prompt>
          <div className="tour-prompt__row">
            <Logo size={44} title="" className="tour-prompt__logo" />
            <div>
              <h3>Take the tour?</h3>
              <p>A one-minute walk through Benin Life: needs, money, the map, your phone and more.</p>
            </div>
          </div>
          <div className="tour-prompt__btns">
            <button type="button" className="tour__btn tour__btn--ghost" onClick={dismiss}>Not now</button>
            <button type="button" className="tour__btn tour__btn--go" onClick={take}>Take the tour</button>
          </div>
        </aside>
      )}
    </>
  );
}
