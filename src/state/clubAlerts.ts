// Fix it 3: "Club spray alerts" (docs/FIXIT.md). Per player, kept on the server (club_alert_prefs). Defaults until loaded:
// the shout-out inside your own club is ON; the app-wide strip for another club and phone pushes are OFF.
import { create } from 'zustand';
import { rpc } from '../lib/api';

export interface ClubAlertPrefs { toasts: boolean; strip: boolean; push: boolean }
export const DEFAULT_CLUB_ALERTS: ClubAlertPrefs = { toasts: true, strip: false, push: false };

export const useClubAlerts = create<ClubAlertPrefs & { loaded: boolean }>(() => ({ ...DEFAULT_CLUB_ALERTS, loaded: false }));

export async function loadClubAlerts(): Promise<void> {
  try {
    const p = await rpc<ClubAlertPrefs>('club_alert_prefs_get');
    useClubAlerts.setState({ toasts: p.toasts, strip: p.strip, push: p.push, loaded: true });
  } catch { /* offline: defaults stay */ }
}

export async function saveClubAlerts(patch: Partial<ClubAlertPrefs>): Promise<void> {
  const before = useClubAlerts.getState();
  useClubAlerts.setState(patch);
  try {
    const p = await rpc<ClubAlertPrefs>('club_alert_prefs_set', { p_prefs: patch });
    useClubAlerts.setState({ toasts: p.toasts, strip: p.strip, push: p.push, loaded: true });
  } catch (e) {
    useClubAlerts.setState({ toasts: before.toasts, strip: before.strip, push: before.push });
    throw e;
  }
}
