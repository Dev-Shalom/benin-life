// "Work" tab in the location sheet (action id `jobs`, V1-3). If the player's job works here: the job
// card + "Work a shift". Below: the jobs hiring at this place (apply / switch).
import { gameDuration, naira } from '../lib/format';
import { useGameClock } from '../lib/clock';
import { getCfg } from '../lib/config';
import type { PanelProps } from '../lib/types';
import { Button, EmptyState } from '../ui';
import { JobCard, PerfBar, Promotion, TrackList } from './careers/CareerUI';
import { realLength, useCareerActions, useJobsCatalog } from './careers/careerHooks';

export default function JobsPanel({ state, location, close }: PanelProps) {
  const { cat, err } = useJobsCatalog();
  const { busy, apply, work } = useCareerActions(close);
  const { now } = useGameClock(5000); // re-render so the busy state clears with the timer
  const job = state.career?.job ?? null;
  const worksHere = Boolean(job?.locations.some((l) => l.id === location.id));
  const hiring = (cat?.tracks ?? []).filter((t) => t.locations.some((l) => l.id === location.id));
  const p = state.profile;
  const busyNow = Boolean(p.busy_until && Date.parse(p.busy_until) > now);
  const capped = job ? job.shifts_today >= job.max_shifts_per_day : false;
  const tired = p.energy < Number(getCfg('career.min_energy', 15));
  const hungry = p.hunger < Number(getCfg('career.min_hunger', 10));

  return (
    <div className="jobs-panel stack">
      {job && worksHere && (
        <section className="work-box">
          <JobCard job={job} />
          <PerfBar perf={job.perf_now} />
          <Button variant="green" size="lg" block loading={busy === 'work'} disabled={busyNow || capped || tired || hungry || Boolean(job.pending)}
            onClick={() => void work()}>
            {capped ? 'Done for today. Come back tomorrow' : busyNow ? 'You are busy right now'
              : tired ? 'Too tired to work. Rest first' : hungry ? 'Too hungry to work. Eat first'
              : `Work a shift · ${naira(job.pay_now ?? job.pay_per_shift)} · ${gameDuration(job.shift_game_minutes)}`}
          </Button>
          <p className="work-box__meta">About {realLength(job.shift_game_minutes)} in real time · shift {Math.min(job.shifts_today + 1, job.max_shifts_per_day)} of {job.max_shifts_per_day} today</p>
          <Promotion job={job} />
        </section>
      )}
      {job && !worksHere && (
        <p className="work-note">
          You work as <b>{job.title}</b> at {job.locations.map((l) => l.name).join(' or ')}. Go there to start a shift.
        </p>
      )}
      {!cat && !err && <div className="panel-skel"><span /><span /></div>}
      {err && <EmptyState icon="info" title="Couldn't load jobs" body={err} />}
      {cat && hiring.length > 0 && (
        <>
          <h4 className="jobs-panel__head">{worksHere ? 'Also hiring here' : 'Hiring here'}</h4>
          <TrackList tracks={hiring.filter((t) => !(worksHere && t.id === job?.track))} current={cat.current} busy={busy} onApply={(id) => void apply(id)} />
        </>
      )}
      {cat && hiring.length === 0 && !worksHere && (
        <EmptyState icon="sparkle" title="Nobody is hiring here yet"
          body="More jobs are coming to this spot. Open the Jobs app on your phone to see who is hiring across Benin." />
      )}
    </div>
  );
}
