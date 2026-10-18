// R8: "builders working" pill over your own home while an upgrade is being built (scaffold icon + progress bar).
// Tap = open the Houses app on the Upgrade section. Only the owner has the data (guests see the scaffolding in 3D only).
import { useEffect, useState } from 'react';
import { realDuration } from '../../lib/format';
import { useUi } from '../../state/ui';
import type { UpgradeBuilding } from '../../api/upgrades';
import { useUpgrades } from '../../state/upgrades';

const NONE: UpgradeBuilding[] = []; // a stable empty list (a fresh [] each render would loop the store selector)

export function BuildersPill() {
  const building = useUpgrades((s) => s.data?.building ?? NONE);
  const [now, setNow] = useState(() => Date.now());
  useEffect(() => {
    if (!building.length) return;
    const t = window.setInterval(() => setNow(Date.now()), 5000);
    return () => window.clearInterval(t);
  }, [building.length]);
  const b = building[0];
  if (!b) return null;
  const start = Date.parse(b.started_at);
  const end = Date.parse(b.ready_at);
  const pct = Number.isNaN(start) || Number.isNaN(end) || end <= start ? b.progress : Math.max(0, Math.min(100, ((now - start) / (end - start)) * 100));
  const left = Number.isNaN(end) ? b.seconds_left : Math.max(0, (end - now) / 1000);
  return (
    <button type="button" className="builders-pill" data-testid="builders-pill" aria-label={`Builders working on ${b.name}, ${Math.round(pct)} percent`}
      onClick={() => useUi.getState().openPhone('houses')}>
      <span aria-hidden>🏗️</span>
      <span>{b.name}</span>
      <span className="builders-pill__bar" aria-hidden><span style={{ width: `${pct}%` }} /></span>
      <span>{left > 0 ? realDuration(left) : 'almost'}</span>
    </button>
  );
}
