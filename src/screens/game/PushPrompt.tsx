// P1: one gentle "want a ping?" card per device (docs/NOTIFICATIONS.md). It NEVER shows on load. It opens only
//   * after the player's first DM is sent (DmConversation calls pushPromptAfterDm), or
//   * a few real minutes into a session (a timer started by this component),
// and only when this browser can do push, the permission is still undecided, and the card was never shown before.
// "Turn on" runs the normal browser permission step; "Not now" is final (Settings -> Notifications stays).
import { useEffect } from 'react';
import { create } from 'zustand';
import { errorMessage } from '../../lib/api';
import { enablePlayerPush, pushSupport } from '../../lib/push';
import { Button, toast } from '../../ui';

const KEY = 'bl.pushPrompt.v1';
const AFTER_MS = 4 * 60 * 1000;

const seen = () => {
  try { return localStorage.getItem(KEY) !== null; } catch { return true; }
};
const remember = (v: string) => {
  try { localStorage.setItem(KEY, v); } catch { /* blocked storage: it may show again next visit */ }
};

interface PromptStore { open: boolean; busy: boolean; show: () => void; hide: () => void }
const usePrompt = create<PromptStore>((set) => ({
  open: false, busy: false,
  show: () => set({ open: true }),
  hide: () => set({ open: false, busy: false }),
}));

/** Show the card if (and only if) it makes sense. Safe to call as often as you like. */
export function maybeAskForPush(): void {
  if (usePrompt.getState().open || seen()) return;
  if (pushSupport() !== 'ok') return; // iPhone not installed, unsupported or blocked: Settings explains
  if (Notification.permission !== 'default') return;
  remember('shown');
  usePrompt.getState().show();
}

/** Called after the player sends a DM: the best moment to ask. */
export const pushPromptAfterDm = () => window.setTimeout(maybeAskForPush, 1500);

export function PushPrompt() {
  const { open, busy } = usePrompt();
  useEffect(() => {
    if (seen()) return;
    const t = window.setTimeout(maybeAskForPush, AFTER_MS);
    return () => window.clearTimeout(t);
  }, []);
  if (!open) return null;
  const turnOn = async () => {
    usePrompt.setState({ busy: true });
    try {
      await enablePlayerPush();
      remember('on');
      toast('Notifications on. Pick which ones in Settings.', 'good');
    } catch (e) {
      toast(errorMessage(e), 'info');
    }
    usePrompt.getState().hide();
  };
  const later = () => { remember('later'); usePrompt.getState().hide(); };
  return (
    <div className="push-prompt" role="dialog" aria-label="Notifications">
      <div className="push-prompt__icon" aria-hidden>🔔</div>
      <div className="push-prompt__text">
        <b>Make we ping you?</b>
        <span>Get a notification when someone messages you or sends you money. You choose which ones in Settings.</span>
      </div>
      <div className="push-prompt__actions">
        <Button size="sm" variant="ghost" onClick={later} disabled={busy}>Not now</Button>
        <Button size="sm" variant="green" onClick={() => void turnOn()} loading={busy}>Turn on</Button>
      </div>
    </div>
  );
}
