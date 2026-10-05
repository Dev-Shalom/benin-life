import { useEffect, useRef, useState } from 'react';
import { rpc, errorMessage } from '../../lib/api';
import { countdown, naira } from '../../lib/format';
import { MODE_META } from '../../lib/pidgin';
import type { GameState } from '../../lib/types';
import { useGame } from '../../state/game';
import { useUi } from '../../state/ui';
import { Button, Icon, Modal, ProgressRing, toast } from '../../ui';
import type { PlayerStatus } from './status';

interface ArriveResult {
  message?: string;
  robbed?: { amount: number; injured?: boolean } | null;
}

const MODE_ICON: Record<string, string> = { walk: 'walk', keke: 'keke', bus: 'bus', drop: 'drop', car: 'car' };

export function StatusBanners({ state, status }: { state: GameState; status: PlayerStatus }) {
  const p = state.profile;
  const refresh = useGame((s) => s.refresh);
  const byId = useGame((s) => s.locationsById);
  const openPanel = useUi((s) => s.openPanel);
  const select = useUi((s) => s.select);
  const [robbed, setRobbed] = useState<{ amount: number; injured: boolean; where: string } | null>(null);
  const arriving = useRef<string | null>(null);
  const tries = useRef(0);
  const [retryTick, setRetryTick] = useState(0);

  // Auto-arrive when the timer runs out.
  const travel = state.travel;
  const travelKey = travel ? `${travel.to}@${travel.arrives_at}` : null;
  const due = Boolean(travel) && status.travelLeft <= 0;
  useEffect(() => {
    if (!due || !travelKey || arriving.current === travelKey) return;
    arriving.current = travelKey;
    const dest = byId[travel!.to]?.name ?? 'your destination';
    (async () => {
      try {
        const res = await rpc<ArriveResult>('travel_arrive');
        tries.current = 0;
        if (res?.robbed && Number(res.robbed.amount) > 0) {
          setRobbed({ amount: Number(res.robbed.amount), injured: Boolean(res.robbed.injured), where: dest });
        } else {
          toast(res?.message ?? `You don reach ${dest}!`, 'good');
        }
      } catch (e) {
        // Clock skew or a race — retry a few times, then surface the message.
        tries.current += 1;
        if (tries.current < 4) {
          window.setTimeout(() => {
            arriving.current = null;
            setRetryTick((t) => t + 1);
          }, 2000);
        } else {
          toast(errorMessage(e), 'bad');
        }
      } finally {
        await refresh();
      }
    })();
  }, [due, travelKey, travel, byId, refresh, retryTick]);

  // When a timer (busy/jail/hospital) expires, pull fresh state.
  const timersDone = (p.busy_until || p.jailed_until || p.hospitalized_until) && status.busyLeft <= 0 && status.jailLeft <= 0 && status.hospLeft <= 0;
  const lastDone = useRef<string | null>(null);
  useEffect(() => {
    const key = `${p.busy_until}|${p.jailed_until}|${p.hospitalized_until}`;
    if (!timersDone || lastDone.current === key) return;
    lastDone.current = key;
    void refresh();
  }, [timersDone, p.busy_until, p.jailed_until, p.hospitalized_until, refresh]);

  // Ring start: busy_started_at from the server; for rows from before that column existed,
  // fall back to the moment this client first saw the timer.
  const [seen, setSeen] = useState<{ key: string; at: number } | null>(null);
  if (p.busy_until && seen?.key !== p.busy_until) setSeen({ key: p.busy_until, at: status.now });
  const busyStart = status.busyStartMs ?? (seen && seen.key === p.busy_until ? seen.at : null);

  const policeHq = Object.values(byId).find((l) => l.scene === 'police')?.id;
  const hospital = Object.values(byId).find((l) => l.id === 'ubth')?.id ?? Object.values(byId).find((l) => l.scene === 'hospital')?.id;

  return (
    <>
      <div className="banners">
        {travel && (
          <div className="banner banner--travel">
            <span className="banner__icon"><Icon name={MODE_ICON[travel.mode] ?? 'road'} size={20} /></span>
            <div className="grow">
              <div className="banner__title">
                {MODE_META[travel.mode]?.label ?? 'On the road'} → {byId[travel.to]?.name ?? 'somewhere'}
              </div>
              <div className="banner__bar"><span style={{ width: `${status.travelProgress * 100}%` }} /></div>
            </div>
            <span className="banner__time">{status.travelLeft > 0 ? countdown(status.travelLeft) : 'Reaching…'}</span>
          </div>
        )}
        {status.busyLeft > 0 && status.busyEndMs !== null && (
          <div className="banner banner--busy">
            <ProgressRing className="banner__ring" startMs={busyStart ?? status.now} endMs={status.busyEndMs}
              nowMs={status.now} size={44} stroke={4} label={p.busy_label ?? 'Busy'}>
              <Icon name="clock" size={18} />
            </ProgressRing>
            <div className="grow banner__title">{p.busy_label ? `${p.busy_label}…` : 'You dey busy…'}</div>
            <span className="banner__time">{countdown(status.busyLeft)}</span>
          </div>
        )}
        {status.jailLeft > 0 && (
          <div className="banner banner--jail">
            <span className="banner__icon"><Icon name="lock" size={20} /></span>
            <div className="grow">
              <div className="banner__title">You dey police cell</div>
              {p.jail_reason && <div className="banner__sub">{p.jail_reason}</div>}
            </div>
            <span className="banner__time">{countdown(status.jailLeft)}</span>
            <Button size="sm" variant="gold" onClick={() => openPanel('police', undefined, policeHq)}>Bail</Button>
          </div>
        )}
        {status.hospLeft > 0 && (
          <div className="banner banner--hosp">
            <span className="banner__icon"><Icon name="cross" size={18} /></span>
            <div className="grow banner__title">Doctor say make you rest for hospital</div>
            <span className="banner__time">{countdown(status.hospLeft)}</span>
          </div>
        )}
      </div>

      <Modal
        open={Boolean(robbed)}
        onClose={() => setRobbed(null)}
        tone="bad"
        art={<RobbedArt />}
        title="Omo! Dem don rob you!"
        actions={
          <>
            {policeHq && (
              <Button variant="dark" icon="shield" onClick={() => { setRobbed(null); select(policeHq); }}>
                Show me Police HQ
              </Button>
            )}
            {robbed?.injured && hospital && (
              <Button variant="green" icon="cross" onClick={() => { setRobbed(null); select(hospital); }}>
                Find hospital
              </Button>
            )}
            <Button onClick={() => setRobbed(null)}>I don hear — life go on</Button>
          </>
        }
      >
        {robbed && (
          <>
            <p>
              Some area boys catch you as you dey reach <b>{robbed.where}</b>. Dem collect{' '}
              <b className="robbed-amount">{naira(robbed.amount)}</b> from your pocket.
            </p>
            {robbed.injured && <p>Dem rough you small — your body dey pain. Make you check UBTH or Mercy Clinic.</p>}
            <p className="muted" style={{ fontSize: 13 }}>Tip: Keep your money for bank. Bank money no dey rob.</p>
          </>
        )}
      </Modal>
    </>
  );
}

function RobbedArt() {
  return (
    <svg viewBox="0 0 160 110" width="160" height="110" aria-hidden>
      <defs>
        <linearGradient id="robbed-pocket" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stopColor="#4a4f8f" />
          <stop offset="100%" stopColor="#262a5c" />
        </linearGradient>
        <radialGradient id="robbed-coin" cx="35%" cy="30%" r="70%">
          <stop offset="0%" stopColor="#fff0b8" />
          <stop offset="55%" stopColor="#d9a441" />
          <stop offset="100%" stopColor="#8a5a22" />
        </radialGradient>
      </defs>
      <ellipse cx="80" cy="102" rx="46" ry="6" fill="#7c3216" opacity="0.25" />
      <path d="M48 30 H112 L106 86 C104 96 96 100 80 100 C64 100 56 96 54 86 Z" fill="url(#robbed-pocket)" />
      <path d="M56 30 C60 52 100 52 104 30" fill="#f1e2c8" stroke="#c9b28c" strokeWidth="2" />
      <path d="M62 34 C68 46 92 46 98 34" fill="none" stroke="#c9b28c" strokeWidth="1.5" strokeDasharray="3 3" />
      <g>
        <circle cx="38" cy="22" r="9" fill="url(#robbed-coin)" />
        <circle cx="124" cy="16" r="7" fill="url(#robbed-coin)" />
        <circle cx="134" cy="44" r="5" fill="url(#robbed-coin)" />
        <path d="M30 10 l-6 -6 M46 8 l3 -7 M120 4 l2 -4 M140 30 l6 -4" stroke="#d2342a" strokeWidth="2.5" strokeLinecap="round" />
      </g>
      <path d="M70 66 q4 -4 8 0 M84 66 q4 -4 8 0" stroke="#f3d28a" strokeWidth="2" fill="none" strokeLinecap="round" opacity="0.7" />
    </svg>
  );
}
