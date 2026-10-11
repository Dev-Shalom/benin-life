import { useEffect } from 'react';
import { initNet, selectReconnecting, useNet } from '../state/net';

/** S1: slim "Reconnecting…" banner. Never blocks the game; disappears by itself when calls work again. */
export function NetBanner() {
  useEffect(() => initNet(), []);
  const show = useNet(selectReconnecting);
  const offline = useNet((s) => s.browserOffline);
  const busy = useNet((s) => s.busy);
  if (!show) return null;
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
