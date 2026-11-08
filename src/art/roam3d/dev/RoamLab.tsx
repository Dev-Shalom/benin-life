// Dev page for free roam (dev server only, no session):
//   /dev/roam?start=oba_market&hour=14&theme=dark&gfx=low&fp=1&dest=police_hq&open=1&debug=1&fps=1
//   x=500&y=545&h=1.57 (position + heading, map space) yaw= pitch= dist= (camera) run=1 say=... note=... warm=6
//   phase 2: car=<item id, e.g. kia_rio_used | gwagon_g63 | bajaj_boxer | bicycle> puts your car at the kerb (here=1 right beside you),
//   drive=1 starts in the seat, rain=1, cam2=chase|inside (driving camera), sheet=search|keke, dry=1 (out of fuel card), fuel=0..1, cond=0..100
import { useMemo } from 'react';
import { usePrefs } from '../../../lib/prefs';
import { DEV_LOCATIONS } from '../../city3d/dev/fixture';
import type { RoamCarCtl, RoamKekeCtl } from '../RoamView';
import { RoamView } from '../RoamView';

export default function RoamLab() {
  const q = useMemo(() => new URLSearchParams(window.location.search), []);
  const hour = Number(q.get('hour') ?? 14);
  useMemo(() => {
    const th = q.get('theme');
    if (th === 'dark' || th === 'light') {
      document.documentElement.dataset.theme = th;
      usePrefs.setState({ theme: th });
    }
    const g = q.get('gfx');
    if (g === 'low' || g === 'high') usePrefs.setState({ graphics: g });
  }, [q]);
  const places = useMemo(() => DEV_LOCATIONS.map((l) => ({ id: l.id, name: l.name, scene: l.scene, x: l.x, y: l.y, active: l.id !== 'benin_airport', keke_ok: l.keke_ok })), []);
  const num = (k: string) => (q.has(k) ? Number(q.get(k)) : undefined);
  const dark = hour >= 19 || hour < 6;
  const item = q.get('car') ?? undefined;
  const fuel = num('fuel');
  const cond = num('cond');
  const carCtl: RoamCarCtl | undefined = item
    ? {
        info: {
          has_car: true, enabled: true, item, name: 'Toyota Camry', class: item === 'bicycle' ? 'bicycle' : item === 'bajaj_boxer' ? 'motorcycle' : 'car',
          fuel_l: (fuel ?? 0.7) * 45, tank_l: 45, cond: cond ?? 100, fuel_on: true, rain: q.get('rain') === '1', mode: 'walk',
        },
        fuelPerM: (0.11 * 8) / 1000,
        mechanicCost: 3500,
        readyS: 0,
        setMode: async (mode) => ({ ok: true, mode, fuel_l: (fuel ?? 0.7) * 45, cond: cond ?? 100 }),
        report: async (r) => ({ ok: true, dist_m: r.dist_m, fuel_l: Math.max(0, (fuel ?? 0.7) * 45 - r.dist_m * 0.00088), cond: cond ?? 100, damage: 0 }),
        dry: async (c) => ({ ok: true, choice: c, message: c === 'push' ? 'You and two strangers push the car to the kerb.' : 'The mechanic is on his way.', cash_delta: 0, wait_s: 5, fuel_l: c === 'mechanic' ? 8 : 0 }),
      }
    : undefined;
  const keke: RoamKekeCtl = { enabled: true, hail: async (id) => `Dev page: a keke would take you to ${id}` };
  return (
    <div className={`game${dark ? ' is-night' : ''}`} style={{ position: 'fixed', inset: 0 }}>
      <RoamView
        places={places}
        startId={q.get('start')}
        avatar={null}
        hour={hour}
        onGoIn={(id) => `Dev page: would open ${id}`}
        onLeave={() => undefined}
        car={carCtl}
        keke={keke}
        demo={{
          dest: q.get('dest') ?? undefined,
          fp: q.get('fp') === '1',
          debug: q.get('debug') === '1',
          x: num('x'),
          y: num('y'),
          h: num('h'),
          cam: { yaw: num('yaw'), pitch: num('pitch'), dist: num('dist') },
          miniOpen: q.get('open') === '1',
          fps: q.get('fps') === '1',
          warm: num('warm'),
          say: q.get('say') ?? undefined,
          note: q.get('note') ?? undefined,
          run: q.get('run') === '1',
          vehicle: item,
          carHere: q.get('here') === '1',
          drive: q.get('drive') === '1',
          rain: q.get('rain') === '1',
          cam2: q.get('cam2') === 'inside' ? 'inside' : q.get('cam2') === 'chase' ? 'chase' : undefined,
          sheet: q.get('sheet') === 'search' ? 'search' : q.get('sheet') === 'keke' ? 'keke' : undefined,
          dry: q.get('dry') === '1',
          tier: q.get('gfx') === 'low' ? 'low' : q.get('gfx') === 'high' ? 'high' : undefined,
        }}
      />
    </div>
  );
}
