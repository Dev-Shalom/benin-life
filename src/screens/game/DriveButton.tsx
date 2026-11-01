// Fix it 10: "Drive this car" / "Driving" on a car row (Phone -> Cars -> My cars and the garage sheet).
import { useEffect, useState } from 'react';
import { errorMessage } from '../../lib/api';
import { usePrimaryCar } from '../../state/primaryCar';
import { Button, toast } from '../../ui';

/** `only`: it is the only vehicle owned, so it is the one being driven anyway. */
export function DriveButton({ itemId, only }: { itemId: string; only?: boolean }) {
  const driving = usePrimaryCar((s) => s.driving);
  const load = usePrimaryCar((s) => s.load);
  const [busy, setBusy] = useState(false);
  useEffect(() => { void load(); }, [load]);
  if (driving === itemId || (only && driving == null)) return <span className="chip good" data-testid="driving-badge">🚗 Driving</span>;
  return (
    <Button size="sm" variant="green" loading={busy} data-testid="drive-this-car" onClick={async () => {
      setBusy(true);
      try { toast(await usePrimaryCar.getState().set(itemId), 'good'); } catch (e) { toast(errorMessage(e), 'bad'); } finally { setBusy(false); }
    }}>Drive this car</Button>
  );
}
