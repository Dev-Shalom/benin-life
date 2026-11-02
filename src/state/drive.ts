// Drive scene: the one flag the rest of the app needs (docs/DRIVE.md).
// `hold` is true while a road-event card waits for an answer, so the auto-arrive in StatusBanners does not end the
// trip under the card (the server accepts the answer after the clock ran out and the arrival is re-timed from then).
import { create } from 'zustand';

interface DriveStore {
  hold: boolean;
  setHold: (v: boolean) => void;
}

export const useDrive = create<DriveStore>((set) => ({ hold: false, setHold: (hold) => set({ hold }) }));
