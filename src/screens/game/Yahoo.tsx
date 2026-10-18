// Y1 Yahoo (docs/YAHOO.md).
// <YahooHost/>   follows my Yahoo state (src/state/yahoo.ts): finishes a job whose timer ran out (also after a reload),
//                shows the outcome (toast; EFCC caught opens the C1 jail popup with EFCC copy).
// <YahooBadge/>  the rank badge (G-boy and up) for the Sim sheet and the tap-a-player sheet.
import { useEffect } from 'react';
import { startCrew } from '../../state/crew';
import { startYahoo } from '../../state/yahoo';

export function YahooHost() {
  useEffect(() => startYahoo(), []);
  return null;
}

export function YahooBadge({ rank }: { rank: { id: string; name: string; icon: string } | null | undefined }) {
  if (!rank || rank.id === 'aspirant') return null;
  return <span className="yahoo-badge" data-testid="yahoo-badge" title={`Yahoo rank: ${rank.name}`}><span aria-hidden>{rank.icon}</span>{rank.name}</span>;
}


/** R11: follows my crew (invites, a job lobby, a running job that must be settled when its time is up). */
export function CrewHost() {
  useEffect(() => startCrew(), []);
  return null;
}
