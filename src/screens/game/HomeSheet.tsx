// Tapped furniture in the 3D home -> the matching home activities (activities table, home_only,
// grouped by ACTIVITY_GROUP) -> the M2 action queue: the Sim walks to the piece first, and do_activity
// (the server timer) starts on arrival (game/TaskRunner.ts). While something runs, "Add to queue".
import { useEffect, useMemo, useState } from 'react';
import { activityGroup, GROUP_META, type HomeGroup } from '../../art/home3d';
import { useGameClock } from '../../lib/clock';
import { activitySeconds, secondsLabel, useActionConfig } from '../../lib/live';
import { naira } from '../../lib/format';
import { NEED_KEYS, NEED_META, type NeedKey } from '../../lib/pidgin';
import type { GameState } from '../../lib/types';
import { hasFurnitureFor, useCatalog, type ActivityRow } from '../../state/catalog';
import { useTasks } from '../../state/tasks';
import { queueTask } from './TaskRunner';
import { useUi } from '../../state/ui';
import { Button, Icon, Sheet } from '../../ui';
import type { PlayerStatus } from './status';

/** Which groups a tapped piece shows (relaxing spots also list TV/radio). */
const SHOWS: Record<HomeGroup, HomeGroup[]> = {
  bed: ['bed'],
  kitchen: ['kitchen'],
  bath: ['bath'],
  toilet: ['toilet'],
  media: ['media'],
  seat: ['seat', 'media'],
  wardrobe: [],
};

function homeActivities(list: ActivityRow[] | null, scene: string): ActivityRow[] {
  return (list ?? []).filter((a) => a.home_only && a.scenes.includes(scene));
}

function Effects({ effects }: { effects: Record<string, number> | null }) {
  if (!effects) return null;
  const rows = Object.entries(effects).filter(([k, v]) => typeof v === 'number' && v !== 0 && (NEED_KEYS as string[]).includes(k));
  return (
    <div className="act__effects">
      {rows.map(([k, v]) => {
        const meta = NEED_META[k as NeedKey];
        const good = meta.inverted ? v < 0 : v > 0;
        return (
          <span key={k} className={`chip ${good ? 'good' : 'bad'}`}>
            <span aria-hidden>{meta.emoji}</span> {meta.short} {v > 0 ? '+' : ''}{Math.round(v)}
          </span>
        );
      })}
    </div>
  );
}

export function HomeSheet({ state, status }: { state: GameState; status: PlayerStatus }) {
  const pick = useUi((s) => s.homePick);
  const pickHome = useUi((s) => s.pickHome);
  const setOverlay = useUi((s) => s.setOverlay);
  const queued = useTasks((s) => (s.current ? 1 : 0) + s.queue.length);
  const activities = useCatalog((s) => s.activities);
  const loadActivities = useCatalog((s) => s.loadActivities);
  const furniture = useCatalog((s) => s.furniture);
  const { clock } = useGameClock(5000);
  const cfg = useActionConfig();
  const [last, setLast] = useState(pick);
  if (pick && pick !== last) setLast(pick);
  const shown = pick ?? last;
  const group = shown?.group ?? 'seat';
  const meta = GROUP_META[group];

  useEffect(() => {
    void loadActivities();
  }, [loadActivities]);

  // A piece of the player's own furniture lists what it hosts (the stool: sit and rest; a seat also
  // lists TV/radio); house fixtures and wish chips go by group. Furniture-only actions need the piece.
  const hosted = shown?.activities;
  const list = useMemo(
    () => homeActivities(activities, state.location.scene)
      .filter((a) => (hosted ? hosted.includes(a.id) || (group === 'seat' && activityGroup(a.id) === 'media') : SHOWS[group].includes(activityGroup(a.id))))
      .filter((a) => hasFurnitureFor(a, furniture)),
    [activities, state.location.scene, group, hosted, furniture],
  );

  const close = () => pickHome(null);
  // idle: close the sheet so the walk shows; busy: line it up and keep the sheet open for more
  const idle = status.free && queued === 0;
  const blocked = status.traveling || status.jailLeft > 0 || status.hospLeft > 0;
  const doIt = (a: ActivityRow) => {
    const r = queueTask(a, state.location.id);
    if (r === 'now') close();
  };

  return (
    <Sheet open={Boolean(pick)} onClose={close} className="home-sheet"
      header={
        <div className="home-sheet__head">
          <span className="home-sheet__emoji" aria-hidden>{meta.emoji}</span>
          <div>
            <h3 className="bl-sheet__title">{meta.label}</h3>
            <p className="bl-sheet__sub">{state.location.name}</p>
          </div>
        </div>
      }>
      {blocked && status.blockedReason && <p className="travel-blocked"><Icon name="info" size={16} /> {status.blockedReason}</p>}
      {group === 'wardrobe' ? (
        <div className="stack">
          <p className="muted">Try on a new look. Your outfit, hair and accessories can all change.</p>
          <Button variant="green" block icon="user" onClick={() => { close(); setOverlay('look'); }}>Change your look</Button>
        </div>
      ) : !activities ? (
        <div className="panel-skel"><span /><span /></div>
      ) : list.length === 0 ? (
        <p className="muted home-sheet__empty">{meta.empty}</p>
      ) : (
        <div className="acts">
          {list.map((a) => {
            const nightLocked = a.night_only && !clock.is_night;
            const broke = a.cost > state.profile.cash;
            const disabled = nightLocked || broke || blocked;
            return (
              <article key={a.id} className={`act${nightLocked || broke ? ' is-locked' : ''}`}>
                <div className="act__top">
                  <div className="grow">
                    <h4 className="act__name">{a.name}</h4>
                    <div className="act__meta">
                      <span className="chip"><Icon name="clock" size={12} /> {secondsLabel(activitySeconds(a, state.profile, cfg))}</span>
                      <span className="chip">{a.cost > 0 ? naira(a.cost) : 'Free'}</span>
                    </div>
                  </div>
                  <Button size="sm" variant="green" disabled={disabled} onClick={() => doIt(a)}>
                    {nightLocked ? 'Night only' : broke ? 'Not enough cash' : idle ? 'Do it' : 'Add to queue'}
                  </Button>
                </div>
                <Effects effects={a.effects} />
              </article>
            );
          })}
        </div>
      )}
    </Sheet>
  );
}
