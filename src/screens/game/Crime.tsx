// C1 pickpocket + jail choices (docs/CRIME.md).
// <CrimeHost/>       follows my crime state (src/state/crime.ts) and shows the "Police don catch you!" popup (same card as the
//                    A2 broadcast / gift popup) while my jail case is open and undecided: Bail · Go to jail · Try to escape.
// <JailCaseButtons/> Bail (current price) + Try to escape on the jail banner while a case is open.
// <PlacePlayerSheet/> tap a real player inside a place: friend button + Steal (only within crime.steal_range_m metres of
//                    them on my screen; the server checks same public place, recently seen, cooldowns, newbies).
import { useEffect, useState } from 'react';
import { AvatarPortrait } from '../../art/avatar3d';
import { jailCaseBail, jailCaseEscape, jailCaseGoToJail, stealAttempt, type JailCase } from '../../api/crime';
import { errorMessage } from '../../lib/api';
import { serverNow } from '../../lib/clock';
import { useConfig } from '../../lib/config';
import { countdown, naira } from '../../lib/format';
import { playCue } from '../../lib/sound';
import type { AvatarConfig } from '../../lib/types';
import { startCrime, useCrime } from '../../state/crime';
import { useGame } from '../../state/game';
import { Button, Modal, Sheet, toast } from '../../ui';
import { SocialPlayerButton } from './SocialPlayerButton';

type Choice = 'bail' | 'jail' | 'escape';

/** Bail / go to jail / escape, shared by the popup and the jail banner. */
function useCaseActions() {
  const [busy, setBusy] = useState<Choice | null>(null);
  const setCase = useCrime((s) => s.setCase);
  const run = async (what: Choice) => {
    if (busy) return;
    setBusy(what);
    try {
      if (what === 'bail') {
        const r = await jailCaseBail();
        playCue('money');
        toast(`${r.message} Paid ${naira(r.paid)}.`, 'good');
        setCase(null);
      } else if (what === 'jail') {
        const r = await jailCaseGoToJail();
        toast(r.message, 'info');
        setCase(r.case);
      } else {
        const r = await jailCaseEscape();
        if (r.escaped) {
          playCue('done');
          toast(`🏃 ${r.message}`, 'good');
          setCase(null);
        } else {
          playCue('error');
          toast(r.message, 'bad');
          if (r.case) setCase(r.case);
        }
      }
    } catch (e) {
      toast(errorMessage(e), 'bad');
      void useCrime.getState().load();
    } finally {
      setBusy(null);
      void useGame.getState().refresh();
    }
  };
  return { busy, run };
}

function useSecondsLeft(until: string | null | undefined): number {
  const [, tick] = useState(0);
  useEffect(() => {
    if (!until) return;
    const id = window.setInterval(() => tick((n) => n + 1), 1000);
    return () => window.clearInterval(id);
  }, [until]);
  return until ? Math.max(0, Math.ceil((Date.parse(until) - serverNow()) / 1000)) : 0;
}

export function CrimeHost() {
  const c = useCrime((s) => s.case);
  useEffect(() => startCrime(), []);
  const show = Boolean(c && c.status === 'open' && !c.decided);
  return <CaughtPopup c={show ? c : null} />;
}

function CaughtPopup({ c }: { c: JailCase | null }) {
  const { busy, run } = useCaseActions();
  const left = useSecondsLeft(c?.jail_until);
  const cash = useGame((s) => (s.state ? s.state.profile.cash + s.state.profile.bank : 0));
  if (!c) return null;
  const afford = cash >= c.bail_amount;
  const again = c.escape_attempts > 0;
  return (
    <Modal open dismissable={false} onClose={() => undefined} tone="bad"
      art={<div className="bcast-art bcast-art--warning crime-art" aria-hidden>🚓</div>}
      title={<span className="bcast-title"><small className="bcast-kicker">{again ? `Escape failed ×${c.escape_attempts}` : 'Caught in the act'}</small>
        {again ? 'Dem catch you again!' : 'Police don catch you!'}</span>}
      actions={
        <div className="crime-actions">
          <Button variant="gold" block disabled={!afford || busy !== null} loading={busy === 'bail'} onClick={() => void run('bail')}
            data-testid="crime-bail">
            Bail yourself · {naira(c.bail_amount)}
          </Button>
          {!afford && <small className="crime-note">You have {naira(cash)} (bank + cash). Bail takes bank first, then cash.</small>}
          <Button variant="ghost" block disabled={busy !== null} loading={busy === 'jail'} onClick={() => void run('jail')} data-testid="crime-jail">
            {again ? 'Stay in jail' : 'Go to jail'} · {countdown(left || c.jail_seconds)}
          </Button>
          <Button variant="danger" block disabled={busy !== null} loading={busy === 'escape'} onClick={() => void run('escape')} data-testid="crime-escape">
            {again ? 'Try to escape again' : 'Try to escape'}
          </Button>
        </div>
      }>
      <p className="bcast-body">
        {c.reason}. {again
          ? `Your jail time is now ${countdown(c.jail_seconds)} and bail don rise to ${naira(c.bail_amount)}.`
          : 'Pay bail and walk free, sit your time in the cell, or try to run.'}
      </p>
      <p className="crime-odds">
        Escape: {Math.round(100 - c.escape_caught_pct)}% chance. If dem catch you, jail time ×{c.escape_time_mult} and bail ×{c.escape_bail_mult}.
      </p>
    </Modal>
  );
}

/** Jail banner extras while a case is open: Bail (current price) and Try to escape. */
export function JailCaseButtons() {
  const c = useCrime((s) => s.case);
  const { busy, run } = useCaseActions();
  const cash = useGame((s) => (s.state ? s.state.profile.cash + s.state.profile.bank : 0));
  if (!c || c.status !== 'open') return null;
  return (
    <span className="crime-banner-actions">
      <Button size="sm" variant="gold" disabled={cash < c.bail_amount || busy !== null} loading={busy === 'bail'}
        onClick={() => void run('bail')} title={`Bail ${naira(c.bail_amount)}`}>
        Bail {naira(c.bail_amount)}
      </Button>
      <Button size="sm" variant="danger" disabled={busy !== null} loading={busy === 'escape'} onClick={() => void run('escape')}>Escape</Button>
    </span>
  );
}

export interface PlacePlayer { id: string; username: string; avatar: AvatarConfig | null }

export function PlacePlayerSheet({ person, metres, free, onClose }: {
  person: PlacePlayer | null;
  /** Distance on my screen between my Sim and theirs (null = unknown, e.g. picked from a list). */
  metres: number | null;
  /** I can act now (not busy / jailed / travelling). */
  free: boolean;
  onClose: () => void;
}) {
  const { cfg } = useConfig();
  const enabled = cfg<boolean>('crime.steal_enabled', true);
  const range = Math.max(0.5, Number(cfg('crime.steal_range_m', 3)) || 3);
  const secs = Math.max(1, Number(cfg('crime.steal_seconds', 4)) || 4);
  const cooldownUntil = useCrime((s) => s.cooldownUntil);
  const cdLeft = useSecondsLeft(cooldownUntil);
  const [sending, setSending] = useState(false);
  const near = metres !== null && metres <= range;

  const steal = async () => {
    if (!person || sending) return;
    setSending(true);
    try {
      const r = await stealAttempt(person.id);
      toast(r.message, 'info');
      useCrime.getState().started({ id: r.attempt_id, resolve_at: r.busy_until, target: r.target });
      useCrime.setState({ cooldownUntil: null });
      onClose();
    } catch (e) {
      toast(errorMessage(e), 'bad');
    } finally {
      setSending(false);
      void useGame.getState().refresh();
    }
  };

  const meta = !near
    ? metres === null ? 'Walk up to them in the place first' : `Walk closer: within ${range} m (you're ${Math.round(metres)} m away)`
    : !free ? 'Finish what you are doing first'
      : cdLeft > 0 ? `Cool down: ${countdown(cdLeft)}`
        : `${secs}s · risky: police dey around`;

  const header = person && (
    <div className="ix-head">
      <span className="ix-head__face">{person.avatar && <AvatarPortrait config={person.avatar} size={56} />}</span>
      <span className="ix-head__text">
        <b>@{person.username}</b>
        <small>{metres !== null ? `About ${Math.max(1, Math.round(metres))} m from you` : 'Here with you'}</small>
      </span>
    </div>
  );

  return (
    <Sheet open={Boolean(person)} onClose={onClose} header={header} className="ix-sheet crime-sheet">
      {person && (
        <div className="ix-grid">
          <div className="crime-friend"><SocialPlayerButton userId={person.id} /></div>
          {enabled && (
            <button type="button" className="ix-tile crime-steal" data-testid="steal" disabled={!near || !free || cdLeft > 0 || sending}
              onClick={() => void steal()}>
              <span className="ix-tile__icon" aria-hidden>🫳</span>
              <span className="ix-tile__label">{sending ? 'Reaching…' : 'Steal'}</span>
              <small className="ix-tile__meta">{meta}</small>
            </button>
          )}
          {enabled && <p className="ix-note">Pickpocket their cash. If the police catch you, na bail, jail or run.</p>}
        </div>
      )}
    </Sheet>
  );
}
