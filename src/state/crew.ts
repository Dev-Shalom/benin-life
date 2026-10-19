// R11 crew state (docs/CREWS.md): my crew status. The server is the source of truth (crew_status also starts a lobby whose countdown
// ended and settles a job whose time is up), so this store only asks it: at start, while a lobby or job is open (every few seconds),
// when a crew alert arrives, and once when a running job's timer runs out.
import { create } from 'zustand';
import { crewStatus, type CrewStatus } from '../api/crews';
import { serverNow } from '../lib/clock';
import { useGame } from './game';
import { canPoll } from '../lib/activity';

interface CrewStore {
  status: CrewStatus | null;
  load: () => Promise<void>;
}

let loading: Promise<void> | null = null;
let timer: number | null = null;

function schedule(s: CrewStatus | null) {
  if (timer != null) window.clearTimeout(timer);
  timer = null;
  const r = s?.crew?.run;
  const at = r ? (r.status === 'running' ? r.resolve_at : r.status === 'lobby' ? r.lobby_until : null) : null;
  if (!at) return;
  timer = window.setTimeout(() => { void useCrew.getState().load(); }, Math.max(0, Date.parse(at) - serverNow()) + 500);
}

export const useCrew = create<CrewStore>((set) => ({
  status: null,
  load: () => {
    if (loading) return loading;
    loading = (async () => {
      try {
        const s = await crewStatus();
        set({ status: s });
        schedule(s);
        if (s.crew?.last_run && s.crew.last_run.resolved_at && Date.now() - Date.parse(s.crew.last_run.resolved_at) < 15000) void useGame.getState().refresh();
      } catch { /* offline: the next trigger tries again */ }
    })().finally(() => { loading = null; });
    return loading;
  },
}));

const CREW_EVENTS = new Set(['crew_invite', 'crew_joined', 'crew_left', 'crew_kicked', 'crew_rank', 'crew_job_lobby', 'crew_job_start', 'crew_job_paid', 'crew_job_caught',
  'crew_job_busted', 'crew_job_cancel', 'crew_job_drop', 'crew_level_up', 'crew_disbanded', 'crew_renamed', 'crew_weekly_prize']);
let started = false;

/** Follow my crew for the signed-in game. Returns a stop function. */
export function startCrew(): () => void {
  if (started) return () => undefined;
  started = true;
  void useCrew.getState().load();
  const poll = window.setInterval(() => {
    const s = useCrew.getState().status;
    if (!canPoll() || !s || !(s.crew?.run || s.invites.length > 0)) return;
    void useCrew.getState().load();
  }, 8000); // IO: 5 s -> 8 s, and silent while hidden or AFK
  let lastEvent = useGame.getState().events[0]?.id ?? 0;
  const unsub = useGame.subscribe((g) => {
    const top = g.events[0];
    if (top && top.id > lastEvent) {
      const fresh = g.events.filter((e) => e.id > lastEvent);
      lastEvent = top.id;
      if (fresh.some((e) => CREW_EVENTS.has(e.kind))) void useCrew.getState().load();
    }
  });
  return () => {
    started = false;
    unsub();
    window.clearInterval(poll);
    if (timer != null) window.clearTimeout(timer);
    timer = null;
    useCrew.setState({ status: null });
  };
}
