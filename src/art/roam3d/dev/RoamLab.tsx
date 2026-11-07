// Dev page for free roam (dev server only, no session):
//   /dev/roam?start=oba_market&hour=14&theme=dark&gfx=low&fp=1&dest=police_hq&open=1&debug=1&fps=1
//   x=500&y=545&h=1.57 (position + heading, map space) yaw= pitch= dist= (camera) run=1 say=... note=... warm=6
import { useMemo } from 'react';
import { usePrefs } from '../../../lib/prefs';
import { DEV_LOCATIONS } from '../../city3d/dev/fixture';
import { inArea } from '../area';
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
  const places = useMemo(() => DEV_LOCATIONS.filter((l) => inArea(l.x, l.y)).map((l) => ({ id: l.id, name: l.name, scene: l.scene, x: l.x, y: l.y })), []);
  const num = (k: string) => (q.has(k) ? Number(q.get(k)) : undefined);
  const dark = hour >= 19 || hour < 6;
  return (
    <div className={`game${dark ? ' is-night' : ''}`} style={{ position: 'fixed', inset: 0 }}>
      <RoamView
        places={places}
        startId={q.get('start')}
        avatar={null}
        hour={hour}
        onGoIn={(id) => `Dev page: would open ${id}`}
        onLeave={() => undefined}
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
        }}
      />
    </div>
  );
}
