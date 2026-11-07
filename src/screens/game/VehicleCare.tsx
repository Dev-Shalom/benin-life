// Drive 3 (docs/DRIVE.md): fuel and condition of the player's own vehicles, outside the drive.
//   * VehicleCarePanel: each vehicle with its tank and condition, refuel (the pump at a filling station, or petrol from the bag) and repair
//     (at the Mechanic Village, or a mechanic called out to you for more). Used in the garage sheet and on the station / mechanic place cards.
//   * VehicleStrip: the same panel on the place card of a filling station or the Mechanic Village (only when the player has a vehicle).
//   * FuelWarnHost + checkFuelBeforeTrip: before a trip by own vehicle, if the tank cannot cover it, a card with three ways on:
//     refuel first, continue anyway (it may run dry on the road), or pick another way to travel. A vehicle at condition 0 will not start
//     (the server refuses it and the travel card says so); a keke or walking always works.
// Every number comes from the server (vehicle_status, vehicle_trip_check); the buttons call vehicle_refuel / vehicle_repair.
import { useCallback, useEffect, useState } from 'react';
import { create } from 'zustand';
import { vehicleRefuel, vehicleRepair, vehicleStatus, vehicleTripCheck, type TripCheck, type VehicleInfo, type VehicleStatus } from '../../api/drive';
import { FuelIcon, WrenchIcon } from '../../art/drive3d/DriveDash';
import { errorMessage } from '../../lib/api';
import { naira } from '../../lib/format';
import { useGame } from '../../state/game';
import { useUi } from '../../state/ui';
import { Button, Sheet, toast } from '../../ui';
import './VehicleCare.css';

const CLASS_LABEL: Record<string, string> = { car: 'Car', suv: 'SUV', pickup: 'Pickup', motorcycle: 'Motorcycle', bicycle: 'Bicycle' };

function Bar({ value, tone, label, icon }: { value: number; tone: 'good' | 'warn' | 'bad'; label: string; icon: React.ReactNode }) {
  return (
    <div className="vc-bar">
      <span className="vc-bar__icon">{icon}</span>
      <span className="vc-bar__track" role="meter" aria-label={label} aria-valuemin={0} aria-valuemax={100} aria-valuenow={Math.round(value * 100)}>
        <i className={`is-${tone}`} style={{ width: `${Math.max(2, Math.round(value * 100))}%` }} />
      </span>
      <span className="vc-bar__label">{label}</span>
    </div>
  );
}

function condTone(c: number, low = 35): 'good' | 'warn' | 'bad' {
  return c < low ? 'bad' : c < 70 ? 'warn' : 'good';
}

function CarCard({ car, st, busy, onRefuel, onRepair }: {
  car: VehicleInfo;
  st: VehicleStatus;
  busy: string | null;
  onRefuel: (source: string, qty: number, key: string) => void;
  onRepair: (item: string, callout: boolean) => void;
}) {
  const fuelFrac = car.tank_l > 0 ? car.fuel_l / car.tank_l : 1;
  const free = Math.max(0, car.tank_l - car.fuel_l);
  const station = st.station;
  const canPump = st.fuel_on && car.driving && car.class !== 'bicycle' && station && !station.dry && free >= 1;
  const fillL = Math.floor(free);
  const canPour = st.fuel_on && car.driving && car.class !== 'bicycle' && st.bag_l > 0 && free >= 1;
  const needsRepair = st.damage_on && car.cond < 100;
  return (
    <article className="vc-car" data-testid={`vc-car-${car.id}`}>
      <header className="vc-car__head">
        <div className="grow">
          <b>{car.name}</b>
          <small>
            {CLASS_LABEL[car.class] ?? 'Vehicle'}
            {car.driving ? ' · the one you drive' : ''}
          </small>
        </div>
        {car.cond <= 0 && st.damage_on && <span className="chip bad">Won&rsquo;t start</span>}
      </header>
      {st.fuel_on && car.class !== 'bicycle' && (
        <Bar value={fuelFrac} tone={fuelFrac < 0.15 ? 'bad' : fuelFrac < 0.35 ? 'warn' : 'good'} icon={<FuelIcon />} label={`${car.fuel_l.toFixed(0)} / ${car.tank_l} L`} />
      )}
      {st.damage_on && <Bar value={car.cond / 100} tone={condTone(car.cond)} icon={<WrenchIcon />} label={`${Math.round(car.cond)}%`} />}
      <div className="vc-car__acts">
        {canPump && (
          <>
            <Button size="sm" variant="green" loading={busy === `pump10-${car.id}`} disabled={Boolean(busy)} onClick={() => onRefuel('pump', Math.min(10, fillL), 'pump10')}>
              {Math.min(10, fillL)} L · {naira(station.price * Math.min(10, fillL))}
            </Button>
            {fillL > 10 && (
              <Button size="sm" variant="ghost" loading={busy === `pumpfull-${car.id}`} disabled={Boolean(busy)} onClick={() => onRefuel('pump', fillL, 'pumpfull')}>
                Fill tank · {naira(station.price * fillL)}
              </Button>
            )}
          </>
        )}
        {canPour && (
          <Button size="sm" variant="ghost" loading={busy === `bag-${car.id}`} disabled={Boolean(busy)} onClick={() => onRefuel('bag', 0, 'bag')}>
            Pour from bag ({st.bag_l} L)
          </Button>
        )}
        {needsRepair &&
          (st.at_mechanic ? (
            <Button size="sm" variant="gold" loading={busy === `fix-${car.id}`} disabled={Boolean(busy)} onClick={() => onRepair(car.id, false)}>
              Repair · {naira(car.repair_cost)}
            </Button>
          ) : (
            st.callout_on && (
              <Button size="sm" variant="gold" loading={busy === `call-${car.id}`} disabled={Boolean(busy)} onClick={() => onRepair(car.id, true)}>
                Call a mechanic · {naira(car.callout_cost)}
              </Button>
            )
          ))}
      </div>
      {needsRepair && !st.at_mechanic && <p className="vc-hint">Cheaper at the Mechanic Village on Sapele Road: {naira(car.repair_cost)}.</p>}
      {car.driving && st.fuel_on && car.class !== 'bicycle' && !station && st.bag_l <= 0 && fuelFrac < 0.5 && (
        <p className="vc-hint">Fill up at any filling station on the map.</p>
      )}
      {station?.dry && car.driving && <p className="vc-hint">This station has no fuel today. Try another one.</p>}
    </article>
  );
}

/** Fuel and condition of every own vehicle, with refuel and repair. */
export function VehicleCarePanel({ title = 'Fuel & repairs', onlyDriving = false }: { title?: string; onlyDriving?: boolean }) {
  const refresh = useGame((s) => s.refresh);
  const [st, setSt] = useState<VehicleStatus | null>(null);
  const [err, setErr] = useState('');
  const [busy, setBusy] = useState<string | null>(null);
  const load = useCallback(async () => {
    try {
      setSt(await vehicleStatus());
      setErr('');
    } catch (e) {
      setErr(errorMessage(e));
    }
  }, []);
  useEffect(() => {
    void load();
  }, [load]);

  const refuel = async (car: VehicleInfo, source: string, qty: number, key: string) => {
    setBusy(`${key}-${car.id}`);
    try {
      let msg = '';
      if (source === 'bag') {
        // pour cans first, then single litres, until the tank or the bag is full / empty
        const r1 = await vehicleRefuel('petrol_can', 99).catch(() => null);
        const r2 = await vehicleRefuel('petrol', 99).catch(() => null);
        const r3 = await vehicleRefuel('petrol_bm', 99).catch(() => null);
        const poured = [r1, r2, r3].reduce((a, r) => a + (r?.litres ?? 0), 0);
        msg = poured > 0 ? `You poured ${poured} litres from your bag.${[r1, r2, r3].some((r) => r?.bad_batch) ? ' Eh! Some of that fuel was bad.' : ''}` : 'Nothing to pour.';
      } else {
        msg = (await vehicleRefuel('pump', qty)).message;
      }
      toast(msg, 'good');
      await Promise.all([load(), refresh()]);
    } catch (e) {
      toast(errorMessage(e), 'bad');
    } finally {
      setBusy(null);
    }
  };
  const repair = async (item: string, callout: boolean) => {
    setBusy(`${callout ? 'call' : 'fix'}-${item}`);
    try {
      toast((await vehicleRepair(item, callout)).message, 'good');
      await Promise.all([load(), refresh()]);
    } catch (e) {
      toast(errorMessage(e), 'bad');
    } finally {
      setBusy(null);
    }
  };

  if (err) return <p className="error-text">{err}</p>;
  if (!st) return <div className="panel-skel"><span /><span /></div>;
  const cars = onlyDriving ? st.cars.filter((c) => c.driving) : st.cars;
  if (!cars.length || (!st.fuel_on && !st.damage_on)) return null;
  return (
    <section className="vc" aria-label={title} data-testid="vehicle-care">
      <h4 className="vc__title">
        {title}
        {st.at_mechanic && <span className="chip good">At the mechanic</span>}
        {st.station && <span className="chip">At the pump · {naira(st.station.price)} / L</span>}
      </h4>
      {cars.map((c) => (
        <CarCard key={c.id} car={c} st={st} busy={busy} onRefuel={(s, q, k) => void refuel(c, s, q, k)} onRepair={(i, co) => void repair(i, co)} />
      ))}
    </section>
  );
}

/** On the place card of a filling station or the Mechanic Village. */
export function VehicleStrip({ locId }: { locId: string }) {
  const here = locId.startsWith('fs_') || locId === 'mechanic_village';
  if (!here) return null;
  return <VehicleCarePanel title={locId === 'mechanic_village' ? 'Mechanic' : 'Fill your vehicle'} onlyDriving={locId !== 'mechanic_village'} />;
}

// ---------------------------------------------------------------- the warning before a trip
interface FuelWarnStore {
  warn: { check: TripCheck; destName: string; go: () => Promise<void> } | null;
  open: (w: { check: TripCheck; destName: string; go: () => Promise<void> }) => void;
  close: () => void;
}
export const useFuelWarn = create<FuelWarnStore>((set) => ({
  warn: null,
  open: (warn) => set({ warn }),
  close: () => set({ warn: null }),
}));

/** Before a trip by own vehicle: true = go on now; false = the warning card is open and will start the trip itself if the player says so. */
export async function checkFuelBeforeTrip(dest: string, destName: string, go: () => Promise<void>): Promise<boolean> {
  let check: TripCheck;
  try {
    check = await vehicleTripCheck(dest);
  } catch {
    return true; // an old server: no fuel system
  }
  if (!check.applies || check.enough !== false) return true;
  useFuelWarn.getState().open({ check, destName, go });
  return false;
}

export function FuelWarnHost() {
  const warn = useFuelWarn((s) => s.warn);
  const close = useFuelWarn((s) => s.close);
  const setMapOpen = useUi((s) => s.setMapOpen);
  const refresh = useGame((s) => s.refresh);
  const [busy, setBusy] = useState<string | null>(null);
  if (!warn) return <Sheet open={false} onClose={close} />;
  const c = warn.check;
  const short = Math.max(1, Math.ceil(c.short_l ?? 0));
  const pct = c.tank_l ? Math.round(((c.fuel_l ?? 0) / c.tank_l) * 100) : 0;
  const canPump = Boolean(c.station && !c.station.dry);
  const canPour = (c.bag_l ?? 0) > 0;

  const refuelFirst = async () => {
    setBusy('refuel');
    try {
      if (canPump) {
        toast((await vehicleRefuel('pump', Math.min((c.tank_l ?? 45) - (c.fuel_l ?? 0), short + 5))).message, 'good');
      } else if (canPour) {
        await vehicleRefuel('petrol_can', 99).catch(() => null);
        await vehicleRefuel('petrol', 99).catch(() => null);
        toast('You poured the petrol from your bag.', 'good');
      } else {
        close();
        setMapOpen(true);
        toast('Find a filling station on the map (the fuel pump pins).', 'info');
        return;
      }
      await refresh();
      close();
      await warn.go();
    } catch (e) {
      toast(errorMessage(e), 'bad');
    } finally {
      setBusy(null);
    }
  };
  const goAnyway = async () => {
    setBusy('go');
    try {
      close();
      await warn.go();
    } finally {
      setBusy(null);
    }
  };
  return (
    <Sheet open onClose={close} className="vc-warn" title="Not enough fuel" subtitle={`The trip to ${warn.destName} needs about ${c.need_l?.toFixed(1)} L. You have ${c.fuel_l?.toFixed(1)} L.`}>
      <div className="vc-warn__gauge" data-testid="fuel-warn">
        <FuelIcon size={18} />
        <span className="vc-bar__track">
          <i className={pct < 15 ? 'is-bad' : 'is-warn'} style={{ width: `${Math.max(3, pct)}%` }} />
        </span>
        <b>{pct}%</b>
      </div>
      <p className="vc-warn__body">If you go on, the tank will run dry on the road. Then you push, call a mechanic or hitch a keke.</p>
      <div className="vc-warn__acts">
        <Button block variant="green" loading={busy === 'refuel'} disabled={Boolean(busy)} onClick={() => void refuelFirst()}>
          {canPump && c.station ? `Refuel first · ${short + 5} L · ${naira(c.station.price * (short + 5))}` : canPour ? `Refuel first · pour ${c.bag_l} L from your bag` : 'Refuel first · find a filling station'}
        </Button>
        <Button block variant="ghost" loading={busy === 'go'} disabled={Boolean(busy)} onClick={() => void goAnyway()}>
          Continue anyway
        </Button>
        <Button block variant="ghost" disabled={Boolean(busy)} onClick={close}>
          Switch to another way to travel
        </Button>
      </div>
    </Sheet>
  );
}
