// "Things to do": activities offered at this location's scene. P1-SHELL.
import { useEffect, useState } from 'react';
import { supabase } from '../lib/supabase';
import { rpc, errorMessage } from '../lib/api';
import { useGameClock } from '../lib/clock';
import { activitySeconds, secondsLabel, useActionConfig } from '../lib/live';
import { naira } from '../lib/format';
import { NEED_KEYS, NEED_META, type NeedKey } from '../lib/pidgin';
import type { PanelProps } from '../lib/types';
import { Button, EmptyState, Icon, toast } from '../ui';

interface Activity {
  id: string;
  name: string;
  scenes: string[];
  home_only: boolean;
  cost: number;
  game_minutes: number;
  max_seconds?: number | null;
  min_seconds?: number | null;
  scale_by_need?: boolean | null;
  effects: Record<string, number> | null;
  night_only: boolean;
  sort: number;
  description?: string | null;
}

function EffectChips({ effects }: { effects: Record<string, number> | null }) {
  if (!effects) return null;
  const entries = Object.entries(effects).filter(([, v]) => typeof v === 'number' && v !== 0);
  return (
    <div className="act__effects">
      {entries.map(([k, v]) => {
        const isNeed = (NEED_KEYS as string[]).includes(k);
        const meta = isNeed ? NEED_META[k as NeedKey] : null;
        const good = meta?.inverted ? v < 0 : v > 0;
        const label = meta ? meta.short : k.replace(/_/g, ' ');
        const val = k === 'cash' || k === 'bank' ? naira(v) : `${v > 0 ? '+' : ''}${Math.round(v)}`;
        return (
          <span key={k} className={`chip ${good ? 'good' : 'bad'}`}>
            {meta && <span aria-hidden>{meta.emoji}</span>}
            {label} {val}
          </span>
        );
      })}
    </div>
  );
}

export default function ActivitiesPanel({ state, location, refresh, close }: PanelProps) {
  const [list, setList] = useState<Activity[] | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const [busyId, setBusyId] = useState<string | null>(null);
  const { clock } = useGameClock(5000);
  const cfg = useActionConfig();
  const atHome = state.profile.home_location_id === location.id;

  useEffect(() => {
    let alive = true;
    (async () => {
      const { data, error } = await supabase
        .from('activities')
        .select('*')
        .contains('scenes', [location.scene])
        .order('sort');
      if (!alive) return;
      if (error) {
        setErr("Couldn't load activities. Check your connection.");
        setList([]);
        return;
      }
      setList(((data ?? []) as Activity[]).filter((a) => !a.home_only || atHome));
    })();
    return () => {
      alive = false;
    };
  }, [location.scene, atHome]);

  const doIt = async (a: Activity) => {
    setBusyId(a.id);
    try {
      const res = await rpc<{ message?: string }>('do_activity', { p_activity: a.id });
      toast(res?.message ?? 'Done!', 'good');
      await refresh();
      close(); // like the home furniture sheet: show the city and the progress ring
    } catch (e) {
      toast(errorMessage(e), 'bad');
    } finally {
      setBusyId(null);
    }
  };

  if (!list) {
    return (
      <div className="panel-skel">
        <span />
        <span />
        <span />
      </div>
    );
  }
  if (list.length === 0) {
    return (
      <EmptyState icon="sparkle" title="Nothing to do here right now"
        body={err ?? (location.scene.startsWith('home') && !atHome ? "This is someone else's home. You can only relax at your own place." : 'Try another spot. Benin City is big.')} />
    );
  }

  return (
    <div className="acts">
      {list.map((a) => {
        const nightLocked = a.night_only && !clock.is_night;
        const broke = a.cost > state.profile.cash;
        const disabled = nightLocked || broke;
        return (
          <article key={a.id} className={`act${disabled ? ' is-locked' : ''}`}>
            <div className="act__top">
              <div className="grow">
                <h4 className="act__name">{a.name}</h4>
                {a.description && <p className="act__desc">{a.description}</p>}
                <div className="act__meta">
                  <span className="chip"><Icon name="clock" size={12} /> {secondsLabel(activitySeconds(a, state.profile, cfg))}</span>
                  <span className="chip">{a.cost > 0 ? naira(a.cost) : 'Free'}</span>
                  {a.night_only && <span className="chip warn"><Icon name="moon" size={12} /> Night only</span>}
                </div>
              </div>
              <Button size="sm" variant={a.cost > 0 ? 'primary' : 'green'} loading={busyId === a.id}
                disabled={disabled || (busyId !== null && busyId !== a.id)} onClick={() => void doIt(a)}>
                {nightLocked ? 'Night only' : broke ? 'Not enough cash' : 'Do it'}
              </Button>
            </div>
            <EffectChips effects={a.effects} />
          </article>
        );
      })}
    </div>
  );
}
