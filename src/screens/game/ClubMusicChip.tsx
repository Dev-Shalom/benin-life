import { useState } from 'react';
import { usePrefs } from '../../lib/prefs';
import { startClubRadio, stopClubRadio, useClubAudio } from '../../lib/sound';

/** "Keep my own music playing" (docs/SOUND.md): in a club the radio never starts by itself. This small, dismissible chip
 *  is the only way to start it for this visit; its Play tap pauses the player's own music. Mounted per club visit. */
export function ClubMusicChip() {
  const own = usePrefs((s) => s.keepOwnMusic);
  const music = usePrefs((s) => s.music && !s.muted);
  const available = useClubAudio((s) => s.available);
  const optedIn = useClubAudio((s) => s.optedIn);
  const [dismissed, setDismissed] = useState(false);
  if (!own || !music || !available || dismissed) return null;
  if (optedIn) {
    return (
      <div className="club-music-chip is-on" role="status">
        <span className="club-music-chip__text">Club music is on</span>
        <button type="button" className="club-music-chip__btn" onClick={() => { stopClubRadio(); setDismissed(true); }}>Stop</button>
      </div>
    );
  }
  return (
    <div className="club-music-chip" role="region" aria-label="Club music">
      <span className="club-music-chip__text">Play the club music? This pauses your own music.</span>
      <button type="button" className="club-music-chip__btn is-primary" onClick={startClubRadio}>Play</button>
      <button type="button" className="club-music-chip__x" aria-label="Dismiss" onClick={() => setDismissed(true)}>×</button>
    </div>
  );
}
