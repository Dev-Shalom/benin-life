import { useEffect } from 'react';
import { initNet, selectReconnecting, useNet } from '../state/net';
import { useRealtime } from '../lib/realtime';
import { useGame } from '../state/game';

/** S1: slim "Reconnecting…" banner. Never blocks the game; disappears by itself when calls work again.
 *  F1: a calmer pill while the tab polls instead of using Realtime (plan limit full, or the owner's switch). */
export function NetBanner() {
  useEffect(() => initNet(), []);
  const show = useNet(selectReconnecting);
  const offline = useNet((s) => s.browserOffline);
  const busy = useNet((s) => s.busy);
  const polling = useRealtime((s) => s.mode === 'poll');
  const signedIn = useGame((s) => Boolean(s.session));
  if (!show) {
    if (!polling || !signedIn) return null;
    return (
      <div className="bl-netbanner is-calm" role="status" aria-live="polite" data-testid="poll-pill">
        <span className="bl-netbanner-dot" aria-hidden />
        Busy right now — live updates slowed
      </div>
    );
  }
  const text = offline
    ? 'You are offline. We go reconnect once your network is back.'
    : busy
      ? 'Plenty people dey play now. Reconnecting…'
      : 'Network wahala. Reconnecting…';
  return (
    <div className="bl-netbanner" role="status" aria-live="polite">
      <span className="bl-netbanner-dot" aria-hidden />
      {text}
    </div>
  );
}
