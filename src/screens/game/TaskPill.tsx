// M2 task pill + queue, in the left column (with the wish chips), so the middle of the screen stays clear.
// Pill: icon, short name, a thin live progress bar, seconds left, a small x. While the Sim walks to a
// task it reads "Walking to the bed…" (the server timer has not started yet). Under it: the queue as
// small chips (icon + name, ↑ to move up, x to drop). Live progress (bars, shift pay) keeps working:
// the bar is the server's busy window, interpolated ~10×/s.
import { naira } from '../../lib/format';
import { busyFraction, useLiveNow } from '../../lib/live';
import type { GameState } from '../../lib/types';
import { useCatalog } from '../../state/catalog';
import { activityIcon, useTasks, WALK_TO } from '../../state/tasks';
import type { PlayerStatus } from './status';
import { stopRunning } from './TaskRunner';

function shortName(s: string): string {
  return s.length > 22 ? `${s.slice(0, 21).trimEnd()}…` : s;
}

export function TaskPill({ state, status }: { state: GameState; status: PlayerStatus }) {
  const p = state.profile;
  const current = useTasks((s) => s.current);
  const queue = useTasks((s) => s.queue);
  const remove = useTasks((s) => s.remove);
  const moveUp = useTasks((s) => s.moveUp);
  const setCurrent = useTasks((s) => s.setCurrent);
  const activities = useCatalog((s) => s.activities);

  const ticking = status.busyLeft > 0 && status.busyEndMs !== null;
  const now = Math.max(useLiveNow(ticking), status.now);
  // the live clock decides (status.busyLeft only ticks once a second)
  const busy = ticking && status.busyEndMs! > now;
  const shift = Boolean(p.job_shift_ends_at && p.busy_until && p.job_shift_ends_at === p.busy_until);

  let pill: React.ReactNode = null;
  if (busy) {
    const end = status.busyEndMs!;
    const start = status.busyStartMs;
    const frac = busyFraction(p, now) ?? (start && end > start ? Math.min(1, Math.max(0, (now - start) / (end - start))) : 0);
    const left = Math.max(0, Math.ceil((end - now) / 1000));
    const act = activities?.find((a) => a.name === p.busy_label);
    const icon = shift ? (state.career?.job?.emoji ?? '💼') : activityIcon(act?.id ?? (current?.phase === 'running' ? current.id : null), '⏳');
    const label = p.busy_label ?? 'Busy';
    const pay = shift ? Math.floor((Number(p.job_shift_pay ?? 0) * frac) / 10) * 10 : 0;
    const xp = shift ? Math.floor(Number(p.job_shift_xp ?? 0) * frac) : 0;
    pill = (
      <div className="task-pill" role="status" aria-label={`${label}, ${left} seconds left`}>
        <span className="task-pill__icon" aria-hidden>{icon}</span>
        <span className="task-pill__body">
          <span className="task-pill__row">
            <span className="task-pill__name" title={label}>{shortName(label)}</span>
            <span className="task-pill__time">{left}s</span>
          </span>
          {shift && (
            <span className="task-pill__sub">
              +{naira(pay)}{Number(p.job_shift_xp ?? 0) > 0 && <> · +{xp} XP</>}
            </span>
          )}
          <span className="task-pill__bar"><span style={{ transform: `scaleX(${frac})` }} /></span>
        </span>
        {!shift && (
          <button type="button" className="task-pill__x" onClick={() => void stopRunning()} aria-label={`Stop ${label}`} title="Stop">
            <XIcon />
          </button>
        )}
      </div>
    );
  } else if (current && !(current.phase === 'running' && current.busyUntil && Date.parse(current.busyUntil) <= now)) {
    // 'running' with no busy timer seen yet = the RPC answered, fresh state is on its way
    const walking = current.phase === 'walking';
    const label = walking ? `Walking to ${current.group ? WALK_TO[current.group] : 'it'}…` : 'Starting…';
    pill = (
      <div className={`task-pill is-${walking ? 'walking' : 'starting'}`} role="status">
        <span className="task-pill__icon" aria-hidden>{current.icon}</span>
        <span className="task-pill__body">
          <span className="task-pill__row">
            <span className="task-pill__name" title={current.name}>{shortName(current.name)}</span>
          </span>
          <span className="task-pill__sub">{walking ? label : 'Starting…'}</span>
          <span className="task-pill__bar is-waiting"><span /></span>
        </span>
        {walking && (
          <button type="button" className="task-pill__x" onClick={() => setCurrent(null)} aria-label={`Cancel ${current.name}`} title="Cancel">
            <XIcon />
          </button>
        )}
      </div>
    );
  }

  if (!pill && queue.length === 0) return null;
  return (
    <div className="task-col">
      {pill}
      {queue.length > 0 && (
        <ol className="task-queue" aria-label={`Up next (${queue.length})`}>
          {queue.map((q, i) => (
            <li key={q.uid} className="task-chip">
              <span className="task-chip__icon" aria-hidden>{q.icon}</span>
              <span className="task-chip__name" title={q.name}>{shortName(q.name)}</span>
              {i > 0 && (
                <button type="button" className="task-chip__btn" onClick={() => moveUp(q.uid)} aria-label={`Move ${q.name} up`} title="Move up">
                  <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round" aria-hidden><path d="M6 15l6-6 6 6" /></svg>
                </button>
              )}
              <button type="button" className="task-chip__btn" onClick={() => remove(q.uid)} aria-label={`Remove ${q.name} from the queue`} title="Remove">
                <XIcon size={11} />
              </button>
            </li>
          ))}
        </ol>
      )}
    </div>
  );
}

function XIcon({ size = 13 }: { size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="3" strokeLinecap="round" aria-hidden>
      <path d="M6 6l12 12M18 6L6 18" />
    </svg>
  );
}
