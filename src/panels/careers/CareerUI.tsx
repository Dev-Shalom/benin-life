// V1-3 shared career UI: job card, performance + promotion, track list, and the actions behind them.
// Used by the Work panel (location sheet), the phone's Jobs app and the Sim sheet's Career tab.
import { useState } from 'react';
import { naira } from '../../lib/format';
import { shiftLength } from './careerHooks';
import type { CareerJob, CareerRequirement, JobTrack } from '../../lib/types';
import { Button, Icon } from '../../ui';
import { shortName } from '../../art/map/mapGeo';
import { perfHint, useItemSellers } from './careerHooks';
import { useGame } from '../../state/game';
import { useUi } from '../../state/ui';

export function JobCard({ job }: { job: CareerJob }) {
  return (
    <section className="sim-card career-card job-card">
      <span className="career-card__emoji" aria-hidden>{job.emoji}</span>
      <div className="grow">
        <div className="muted job-card__eyebrow">{job.track_name} · Level {job.level} of {job.top_level}</div>
        <div className="career-card__title">{job.title}</div>
        <div className="muted job-card__sub">{naira(job.pay_per_shift)} per shift · {shiftLength(job.shift_game_minutes)}</div>
      </div>
    </section>
  );
}

export function PerfBar({ perf }: { perf: number }) {
  const tone = perf >= 85 ? 'good' : perf >= 65 ? 'ok' : 'low';
  return (
    <div className="job-meter">
      <div className="job-meter__top"><span>Performance</span><b>{perf}%</b></div>
      <div className={`job-meter__track job-meter__track--${tone}`} role="meter" aria-label="Performance"
        aria-valuemin={0} aria-valuemax={120} aria-valuenow={perf}>
        <span style={{ width: `${Math.min(100, (perf / 120) * 100)}%` }} />
      </div>
      <p className="job-meter__hint">{perfHint(perf)}</p>
    </div>
  );
}

function ReqList({ reqs }: { reqs: CareerRequirement[] }) {
  if (!reqs.length) return null;
  return (
    <ul className="req-list">
      {reqs.map((r) => (
        <li key={r.key + (r.track ?? '')} className={r.met ? 'is-met' : undefined}>
          <span className="req-list__dot" aria-hidden>{r.met ? <Icon name="check" size={12} stroke={3} /> : null}</span>
          <span>
            {r.label}
            {r.key === 'degree' && !r.met && <span className="req-list__hint"> · reach Graduate Assistant in Education (UNIBEN)</span>}
            {r.key === 'item' && !r.met && <ItemShopLink item={r.item} />}
          </span>
        </li>
      ))}
    </ul>
  );
}

/** "Buy one at Bronze Tech Hub": opens the nearest place that sells the item on its Shop tab (V1-4). */
function ItemShopLink({ item }: { item?: string }) {
  const sellers = useItemSellers(item);
  const byId = useGame((s) => s.locationsById);
  const here = useGame((s) => s.state?.location);
  const closeAll = useUi((s) => s.closeAll);
  const select = useUi((s) => s.select);
  const setMapOpen = useUi((s) => s.setMapOpen);
  if (!sellers?.length) return null;
  const near = [...sellers].filter((id) => byId[id])
    .sort((a, b) => (here ? Math.hypot(byId[a].x - here.x, byId[a].y - here.y) - Math.hypot(byId[b].x - here.x, byId[b].y - here.y) : 0))[0];
  if (!near) return null;
  const go = () => {
    closeAll();
    if (here?.id !== near) setMapOpen(true);
    select(near, 'shop');
  };
  return (
    <button type="button" className="req-list__link" onClick={go}>
      Buy one at {shortName(near, byId[near].name)} <Icon name="chevronRight" size={12} stroke={2.8} />
    </button>
  );
}

export function Promotion({ job }: { job: CareerJob }) {
  if (!job.next || job.xp_to_next == null) {
    return <p className="job-top">🏆 Top of the ladder. You are the {job.title}.</p>;
  }
  const pct = Math.min(100, (job.xp / job.xp_to_next) * 100);
  const ready = job.xp >= job.xp_to_next;
  return (
    <div className="job-meter">
      <div className="job-meter__top"><span>Next: <b>{job.next.title}</b> · {naira(job.next.pay_per_shift)}</span><b>{Math.floor(pct)}%</b></div>
      <div className="job-meter__track job-meter__track--xp" role="progressbar" aria-label="Promotion progress"
        aria-valuemin={0} aria-valuemax={job.xp_to_next} aria-valuenow={job.xp}>
        <span style={{ width: `${pct}%` }} />
      </div>
      <p className="job-meter__hint">
        {ready ? 'Ready for promotion as soon as you meet everything below.' : `${job.xp} / ${job.xp_to_next} XP. Every good shift counts.`}
      </p>
      <ReqList reqs={job.next.requirements} />
    </div>
  );
}

export function ShiftStats({ job }: { job: CareerJob }) {
  return (
    <div className="job-stats">
      <div><b>{job.shifts_today}/{job.max_shifts_per_day}</b><span>Shifts today</span></div>
      <div><b>{job.shifts_in_level}</b><span>At this level</span></div>
      <div><b>{job.total_shifts}</b><span>All shifts</span></div>
    </div>
  );
}

function TrackRow({ t, current, hasJob, busy, onApply }: {
  t: JobTrack; current: boolean; hasJob: boolean; busy: string | null; onApply: (id: string) => void;
}) {
  const [open, setOpen] = useState(false);
  const [confirm, setConfirm] = useState(false);
  const entry = t.levels.find((l) => l.level === t.entry_level) ?? t.levels[0];
  const names = t.locations.map((l) => shortName(l.id, l.name));
  const where = names.length > 2 ? `${names.slice(0, 2).join(' · ')} +${names.length - 2} more` : names.join(' · ');
  const apply = () => {
    if (hasJob && !confirm) {
      setConfirm(true);
      return;
    }
    setConfirm(false);
    onApply(t.id);
  };
  return (
    <article className={`track${current ? ' is-current' : ''}`}>
      <div className="track__top">
        <span className="track__emoji" aria-hidden>{t.emoji}</span>
        <div className="grow">
          <h4 className="track__name">{t.name}</h4>
          <p className="track__where"><Icon name="pin" size={12} /> {where}</p>
          {entry && (
            <p className="track__pay">
              Start as <b>{entry.title}</b>{t.entry_level > 1 ? ` (level ${t.entry_level})` : ''} · {naira(entry.pay_per_shift)} a shift
            </p>
          )}
        </div>
        {current ? (
          <span className="chip good">Your job</span>
        ) : (
          <Button size="sm" variant={confirm ? 'gold' : 'green'} loading={busy === `apply:${t.id}`}
            disabled={busy !== null && busy !== `apply:${t.id}`} onClick={apply}>
            {confirm ? 'Tap to switch' : hasJob ? 'Switch' : 'Apply'}
          </Button>
        )}
      </div>
      <button type="button" className="track__more" onClick={() => setOpen(!open)} aria-expanded={open}>
        {open ? 'Hide the ladder' : `See all ${t.levels.length} levels`}
        <Icon name={open ? 'chevronUp' : 'chevronDown'} size={14} stroke={2.6} />
      </button>
      {open && (
        <>
          <p className="track__desc">{t.description}</p>
          <ol className="ladder">
            {t.levels.map((l) => (
              <li key={l.level}>
                <span className="ladder__lvl">{l.level}</span>
                <span className="grow">
                  <span className="ladder__title">{l.title}</span>
                  {l.requirements.length > 0 && (
                    <span className="ladder__req">{l.requirements.map((r) => (r.met ? '✓ ' : '') + r.label).join(' · ')}</span>
                  )}
                </span>
                <span className="ladder__pay">{naira(l.pay_per_shift)}</span>
              </li>
            ))}
          </ol>
        </>
      )}
    </article>
  );
}

export function TrackList({ tracks, current, busy, onApply }: {
  tracks: JobTrack[]; current: string | null; busy: string | null; onApply: (id: string) => void;
}) {
  return (
    <div className="tracks">
      {tracks.map((t) => (
        <TrackRow key={t.id} t={t} current={t.id === current} hasJob={Boolean(current)} busy={busy} onApply={onApply} />
      ))}
    </div>
  );
}

/** Two-tap quit button. */
export function QuitButton({ busy, onQuit }: { busy: boolean; onQuit: () => void }) {
  const [confirm, setConfirm] = useState(false);
  return (
    <Button variant={confirm ? 'danger' : 'ghost'} size="sm" loading={busy}
      onClick={() => (confirm ? (setConfirm(false), onQuit()) : setConfirm(true))}>
      {confirm ? 'Tap again to resign' : 'Quit job'}
    </Button>
  );
}
