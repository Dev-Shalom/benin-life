// E2 referral link (docs/HUSTLES.md): playbeninlife.app/?ref=CODE. The code is kept in localStorage from the first visit
// until the Sim exists, then claimed once (the server decides: new accounts only, one per account, caps per inviter).
import { referralClaim } from '../api/hustles';

const KEY = 'bl.ref';
const RE = /^[A-Za-z0-9]{4,12}$/;

/** Read ?ref= from the address and remember it. Call once at start-up. */
export function captureReferral(): void {
  try {
    const code = new URLSearchParams(window.location.search).get('ref');
    if (code && RE.test(code.trim())) window.localStorage.setItem(KEY, code.trim().toUpperCase());
  } catch {
    /* storage blocked: the signup metadata carries the code instead */
  }
}

export function storedReferral(): string | null {
  try {
    const v = window.localStorage.getItem(KEY);
    return v && RE.test(v) ? v : null;
  } catch {
    return null;
  }
}

function clearReferral() {
  try {
    window.localStorage.removeItem(KEY);
  } catch {
    /* nothing to clear */
  }
}

/** Claim the remembered code. Any answer from the server (accepted or refused) ends it; network errors keep it for later. */
export async function claimStoredReferral(): Promise<void> {
  const code = storedReferral();
  if (!code) return;
  try {
    await referralClaim(code);
    clearReferral();
  } catch (e) {
    const hint = (e as { hint?: string }).hint;
    if (hint === 'no_profile') return; // the Sim is not created yet: try again later
    if (hint) clearReferral();
  }
}
