// The cinematic intro after a brand-new Sim is created (Intro.tsx). One tiny store so CreateSim can start it and
// the layer in App can play it above whatever screen is underneath.
import { create } from 'zustand';

interface IntroStore {
  playing: boolean;
  /** Called once, while the screen is fully white, so the route can change under the cover. */
  onCovered: (() => void) | null;
  play: (onCovered: () => void) => void;
  end: () => void;
}

export const useIntro = create<IntroStore>((set) => ({
  playing: false,
  onCovered: null,
  play: (onCovered) => set({ playing: true, onCovered }),
  end: () => set({ playing: false, onCovered: null }),
}));

/** Start the intro. `onCovered` runs when the screen has faded to white (navigate there). */
export const playIntro = (onCovered: () => void) => useIntro.getState().play(onCovered);
