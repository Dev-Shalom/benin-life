// Dev page for the drive scene (dev server only, no session):
//   /dev/drive?cam=chase|side|inside&h=14&mode=car&veh=camry_new&event=ambush|police|goslow|beggar&arrived=1&others=1&gfx=low&theme=dark
//   from=ekenwan_room&to=benin_airport (place ids are only used for their names and map positions)
import { useMemo } from 'react';
import { DriveView } from '../DriveView';
import { routeRoads, type CamMode } from '../model';
import type { DriveEvent } from '../../../api/drive';
import { usePrefs } from '../../../lib/prefs';

const EVENTS: Record<string, DriveEvent> = {
  ambush: {
    kind: 'ambush',
    title: 'Area boys',
    body: 'A few area boys step into the road and flag you down. "Oga, settle us small for the road."',
    choices: [
      { id: 'pay', label: 'Pay them ₦9,000', hint: 'Safe, but it costs.' },
      { id: 'drive', label: 'Drive off', hint: 'Risky: you might lose more.' },
      { id: 'police', label: 'Call police', hint: 'They may not come in time.' },
    ],
  },
  police: {
    kind: 'police',
    title: 'Police checkpoint',
    body: 'An officer waves you down at a checkpoint. "Good afternoon. Your particulars, please."',
    choices: [
      { id: 'papers', label: 'Show papers', hint: 'Honest. Usually fine.' },
      { id: 'settle', label: 'Settle ₦3,000', hint: 'Quick, but you pay.' },
      { id: 'argue', label: 'Argue', hint: 'Could cost you time and money.' },
    ],
  },
  goslow: {
    kind: 'goslow',
    title: 'Go-slow',
    body: 'Traffic is stuck bumper to bumper. Horns everywhere and nobody is moving.',
    choices: [
      { id: 'wait', label: 'Wait', hint: 'A little longer, no risk.' },
      { id: 'shortcut', label: 'Take a shortcut', hint: 'Could save time, could go wrong.' },
    ],
  },
  beggar: {
    kind: 'beggar',
    title: 'At the window',
    body: 'A hawker taps your window with a tray of pure water. Beside him, an old woman holds out her hand.',
    choices: [
      { id: 'give', label: 'Give ₦500', hint: 'Help the old woman.' },
      { id: 'water', label: 'Buy pure water ₦200', hint: 'Cold and cheap.' },
      { id: 'ignore', label: 'Ignore', hint: 'Keep driving.' },
    ],
  },
};

export default function DriveLab() {
  const q = useMemo(() => new URLSearchParams(window.location.search), []);
  const hour = Number(q.get('h') ?? 14);
  const dark = hour >= 19 || hour < 6;
  useMemo(() => {
    const th = q.get('theme');
    if (th === 'dark' || th === 'light') {
      document.documentElement.dataset.theme = th;
      usePrefs.setState({ theme: th });
    }
    const g = q.get('gfx');
    if (g === 'low' || g === 'high') usePrefs.setState({ graphics: g });
  }, [q]);
  const now = Date.now();
  const total = 80_000;
  const prog = Number(q.get('p') ?? 0.4);
  const from = { x: 461, y: 545 };
  const to = { x: 330, y: 612 };
  const roadsName = q.get('road');
  const roads = useMemo(() => {
    const r = routeRoads(from, to);
    return roadsName ? [{ name: roadsName, f0: 0, f1: 1 }] : r;
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [roadsName]);
  const ev = q.get('event');
  const arrived = q.has('arrived');
  return (
    <div className={`game${dark ? ' is-night' : ''}`} style={{ position: 'fixed', inset: 0 }}>
      <DriveView
        trip={{
          key: 'lab',
          fromName: q.get('fromName') ?? 'King’s Square',
          toName: q.get('toName') ?? 'Benin Airport',
          toScene: q.get('scene') ?? 'airport',
          mode: q.get('mode') ?? 'car',
          startedAt: now - total * prog,
          arrivesAt: now + total * (1 - prog),
          vehicleId: q.get('veh') ?? 'camry_new',
          roads,
        }}
        arrived={arrived}
        hour={hour}
        me={{ id: 'lab', name: 'You' }}
        onGoIn={() => undefined}
        onSkip={() => undefined}
        onTurnBack={() => undefined}
        onMap={() => undefined}
        demo={{
          event: ev ? EVENTS[ev] : undefined,
          startDist: Number(q.get('d') ?? 0),
          stopped: q.has('stopped'),
          cam: (q.get('cam') as CamMode | null) ?? 'chase',
          others: q.has('others'),
        }}
      />
    </div>
  );
}
