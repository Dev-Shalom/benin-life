// Dev page (dev server only, no session) for the drive 3 vehicle screens: /dev/vehicle?view=care|warn&theme=dark
// The RPCs (vehicle_status, vehicle_trip_check) are answered by the screenshot script; the page only lays the screens out.
import { useEffect, useMemo } from 'react';
import { usePrefs } from '../../../lib/prefs';
import { Sheet } from '../../../ui';
import { FuelWarnHost, useFuelWarn, VehicleCarePanel } from '../VehicleCare';

export default function VehicleLab() {
  const q = useMemo(() => new URLSearchParams(window.location.search), []);
  useMemo(() => {
    const th = q.get('theme');
    if (th === 'dark' || th === 'light') {
      document.documentElement.dataset.theme = th;
      usePrefs.setState({ theme: th });
    }
  }, [q]);
  const view = q.get('view') ?? 'care';
  useEffect(() => {
    if (view !== 'warn') return;
    useFuelWarn.getState().open({
      destName: 'Oba Market',
      go: async () => undefined,
      check: { applies: true, item: 'camry_new', class: 'car', fuel_l: 3.2, tank_l: 45, need_l: 6.4, short_l: 3.2, enough: false, cond: 92, bag_l: 0, station: null, km: 11.6 },
    });
  }, [view]);
  return (
    <div className="game" style={{ position: 'fixed', inset: 0, background: 'var(--bg)' }}>
      {view === 'care' && (
        <Sheet open onClose={() => undefined} title="Your garage" subtitle="Carport · fits 1 car.">
          <VehicleCarePanel />
        </Sheet>
      )}
      <FuelWarnHost />
    </div>
  );
}
