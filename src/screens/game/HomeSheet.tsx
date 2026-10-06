// Tapped furniture in the 3D home -> the matching home activities (activities table, home_only,
// grouped by ACTIVITY_GROUP) -> do_activity. The Sim walks to the piece when the activity starts.
import { useEffect, useMemo, useState } from 'react';
import { activityGroup, GROUP_META, type HomeGroup } from '../../art/home3d';
import { rpc, errorMessage } from '../../lib/api';
import { useGameClock } from '../../lib/clock';
import { activitySeconds, secondsLabel, useActionConfig } from '../../lib/live';
import { naira } from '../../lib/format';
import { homeAct, scaleEffects } from '../../lib/furniture';
import { NEED_KEYS, NEED_META, type NeedKey } from '../../lib/pidgin';
import type { GameState } from '../../lib/types';
import { useCatalog, type ActivityRow } from '../../state/catalog';
import { useGame } from '../../state/game';
import { useUi } from '../../state/ui';
import { Button, Icon, Sheet, toast } from '../../ui';
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
  const refresh = useGame((s) => s.refresh);
  const activities = useCatalog((s) => s.activities);
  const loadActivities = useCatalog((s) => s.loadActivities);
  const { clock } = useGameClock(5000);
  const cfg = useActionConfig();
  const [busyId, setBusyId] = useState<string | null>(null);
  const [last, setLast] = useState(pick);
  if (pick && pick !== last) setLast(pick);
  const shown = pick ?? last;
  const group = shown?.group ?? 'seat';
  const meta = GROUP_META[group];

  useEffect(() => {
    void loadActivities();
  }, [loadActivities]);

  // what the Sim's furniture allows (label, reason); things it can do first
  const list = useMemo(
    () =>
      homeActivities(activities, state.location.scene)
        .filter((a) => SHOWS[group].includes(activityGroup(a.id)))
        .map((a) => ({ a, v: homeAct(state, a) }))
        .sort((x, y) => Number(y.v.ok) - Number(x.v.ok)),
    [activities, state, group],
  );

  const close = () => pickHome(null);
  const doIt = async (a: ActivityRow) => {
    setBusyId(a.id);
    try {
      const res = await rpc<{ message?: string }>('do_activity', { p_activity: a.id });
      toast(res?.message ?? 'Done!', 'good');
      close();
      await refresh();
    } catch (e) {
      toast(errorMessage(e), 'bad');
    } finally {
      setBusyId(null);
    }
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
      {status.blockedReason && <p className="travel-blocked"><Icon name="info" size={16} /> {status.blockedReason}</p>}
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
          {list.map(({ a, v }) => {
            const nightLocked = a.night_only && !clock.is_night;
            const broke = a.cost > state.profile.cash;
            const missing = !v.ok;
            const disabled = missing || nightLocked || broke || !status.free;
            return (
              <article key={a.id} className={`act${missing || nightLocked || broke ? ' is-locked' : ''}`}>
                <div className="act__top">
                  <div className="grow">
                    <h4 className="act__name">{v.label}</h4>
                    {missing && v.reason && <p className="act__desc act__need">{v.reason}</p>}
                    <div className="act__meta">
                      <span className="chip"><Icon name="clock" size={12} /> {secondsLabel(activitySeconds(a, state.profile, cfg))}</span>
                      <span className="chip">{a.cost > 0 ? naira(a.cost) : 'Free'}</span>
                    </div>
                  </div>
                  <Button size="sm" variant="green" loading={busyId === a.id}
                    disabled={disabled || (busyId !== null && busyId !== a.id)} onClick={() => void doIt(a)}>
                    {missing ? 'Not yet' : nightLocked ? 'Night only' : broke ? 'Not enough cash' : 'Do it'}
                  </Button>
                </div>
                <Effects effects={scaleEffects(a.effects, v.pct)} />
              </article>
            );
          })}
        </div>
      )}
    </Sheet>
  );
}
