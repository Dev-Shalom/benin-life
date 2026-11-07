// Dev page for the drive scene (dev server only, no session):
//   /dev/drive?cam=chase|side|inside&h=14&mode=car|bus|keke|drop&veh=camry_new&event=ambush|police|goslow|beggar&arrived=1&others=1&gfx=low&theme=dark
//   steer=1 (steering pad on) rain=1 fuel=<litres>&tank=<litres>&cond=<0..100>&before=<litres at start>&need=<litres the trip burns>
//   from=ekenwan_room&to=oba_market&total=90&p=0.4 (route between two places, trip seconds, progress) &s=<track metres> (start there)
import { useMemo } from 'react';
import { DriveView } from '../DriveView';
import type { CamMode } from '../model';
import { buildTrack } from '../track';
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
  dry: {
    kind: 'dry',
    title: 'Out of fuel',
    body: 'The engine coughs and dies. The needle sits on empty and you roll to a stop by the roadside.',
    choices: [
      { id: 'push', label: 'Push the car', hint: 'Free, but it costs time and sweat.' },
      { id: 'mechanic', label: 'Call a mechanic ₦12,000', hint: 'He brings a can. You wait for him.' },
      { id: 'keke', label: 'Hitch a keke ₦3,000', hint: 'Cheaper, but you arrive later.' },
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

/** A few places of the real game (id, name, scene, map position) so the lab can drive between them. */
const P = (id: string, name: string, scene: string, x: number, y: number) => ({ id, name, scene, x, y });
const PLACES: Record<string, { id: string; name: string; scene: string; x: number; y: number }> = Object.fromEntries(
  [
    P('ekenwan_room', 'Ekenwan Face-Me-I-Face-You', 'home_face_me', 298, 562),
    P('oba_market', 'Oba Market', 'market', 448, 452),
    P('uniben', 'UNIBEN Ugbowo Campus', 'campus', 480, 125),
    P('national_museum', 'Benin National Museum', 'museum', 500, 500),
    P('oba_palace', 'Oba’s Palace', 'palace', 432, 512),
    P('ubth', 'UBTH (Teaching Hospital)', 'hospital', 440, 165),
    P('police_hq', 'Police Command HQ (GRA)', 'police', 510, 604),
    P('mercy_clinic', 'Mercy Clinic', 'hospital', 560, 365),
    P('bronze_tech_hub', 'Bronze Tech Hub', 'office', 535, 190),
    P('benin_city_mall', 'Benin City Mall', 'mall', 575, 665),
    P('mama_ebo', 'Mama Ebo Pepper Rice', 'buka', 405, 588),
    P('babas_shrine', 'Baba’s Shrine', 'shrine', 760, 730),
    P('ramat_park', 'Ramat Park Junction', 'motorpark', 680, 415),
    P('aduwawa_park', 'Aduwawa Motor Park', 'motorpark', 820, 335),
    P('santana_market', 'Santana Market', 'market', 560, 700),
    P('golden_tulip', 'Golden Tulip Essential', 'hotel', 486, 670),
    P('uselu_market', 'Uselu Market', 'market', 480, 235),
    P('ogbemudia_stadium', 'Samuel Ogbemudia Stadium', 'stadium', 372, 532),
  ].map((p) => [p.id, p]),
);

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
  const total = Number(q.get('total') ?? 90) * 1000;
  const fromId = q.get('from') ?? 'ekenwan_room';
  const toId = q.get('to') ?? 'oba_market';
  const from = PLACES[fromId] ?? PLACES.ekenwan_room;
  const to = PLACES[toId] ?? PLACES.oba_market;
  const mode = q.get('mode') ?? 'car';
  const veh = q.get('veh') ?? 'camry_new';
  const track = useMemo(
    () => buildTrack({ from, to, mode, totalSec: total / 1000, vehicleId: mode === 'car' ? veh : null }),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [fromId, toId, mode, total],
  );
  const prog = q.has('s') ? Math.min(0.999, track.tOfS(Number(q.get('s'))) / (total / 1000)) : Number(q.get('p') ?? 0.4);
  const ev = q.get('event');
  const arrived = q.has('arrived');
  return (
    <div className={`game${dark ? ' is-night' : ''}`} style={{ position: 'fixed', inset: 0 }}>
      <DriveView
        trip={{
          key: 'lab',
          fromName: from.name,
          toName: to.name,
          toScene: to.scene,
          toId: to.id,
          toX: to.x,
          toY: to.y,
          mode,
          startedAt: now - total * prog,
          arrivesAt: now + total * (1 - prog),
          vehicleId: veh,
          track,
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
          startS: q.has('s') ? Number(q.get('s')) : undefined,
          stopped: q.has('stopped'),
          cam: (q.get('cam') as CamMode | null) ?? 'chase',
          others: q.has('others'),
          steer: q.has('steer'),
          rain: q.has('rain'),
          vehicle:
            mode === 'car' && (q.has('cond') || q.has('fuel') || q.has('before'))
              ? {
                  fuel: Number(q.get('fuel') ?? 30),
                  tank: Number(q.get('tank') ?? 45),
                  cond: Number(q.get('cond') ?? 100),
                  before: q.has('before') ? Number(q.get('before')) : undefined,
                  need: q.has('need') ? Number(q.get('need')) : undefined,
                }
              : undefined,
        }}
      />
    </div>
  );
}
