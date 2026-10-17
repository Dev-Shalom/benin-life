// E2 hustles (docs/HUSTLES.md): <HustleHost/> follows my hustle state (finishes a hustle whose timer ran out, also after a
// reload) and, for a player who came in with a referral link, claims the code once (silently).
import { useEffect } from 'react';
import { claimStoredReferral } from '../../lib/referral';
import { startHustles } from '../../state/hustles';

export function HustleHost() {
  useEffect(() => startHustles(), []);
  useEffect(() => { void claimStoredReferral(); }, []);
  return null;
}
