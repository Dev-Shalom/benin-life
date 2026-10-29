// R12: the polling-unit line on the place card ("Election day" while voting is on) and the election-day banner on the game screen.
import { useEffect } from 'react';
import { useNow } from '../../lib/clock';
import { startPolitics, usePolitics } from '../../state/politics';
import { startOffices } from '../../state/offices';
import { useUi } from '../../state/ui';
import { Button } from '../../ui';

function span(sec: number): string {
  const s = Math.max(0, Math.round(sec));
  const d = Math.floor(s / 86400);
  const h = Math.floor((s % 86400) / 3600);
  const m = Math.floor((s % 3600) / 60);
  if (d > 0) return `${d} d ${h} h`;
  if (h > 0) return `${h} h ${m} min`;
  return `${Math.max(1, m)} min`;
}

/** Follows Benin Votes for the signed-in game (status, election-day banner, alerts). */
export function PoliticsHost() {
  useEffect(() => startPolitics(), []);
  useEffect(() => startOffices(), []);
  return null;
}

/** On a polling unit (place id pu_*): Election day, who votes here, and a Vote button. Renders nothing elsewhere. */
export function PollingStrip({ locId }: { locId: string }) {
  const s = usePolitics((x) => x.status);
  const now = useNow(30_000);
  const isUnit = locId.startsWith('pu_');
  useEffect(() => { if (isUnit) void usePolitics.getState().load(); }, [isUnit]);
  if (!isUnit) return null;
  const open = Boolean(s?.cycle?.voting_open);
  const mine = s?.me.ward.poll_unit === locId;
  const ward = s?.wards.find((w) => w.poll_unit === locId)?.name ?? 'this ward';
  return (
    <div className="bz-strip" data-testid="polling-strip">
      <span className="bz-strip__text">
        <b>🗳️ {open ? 'Election day' : 'Polling unit'} · {ward}</b>
        <small>
          {open ? `Voting is open for ${span((Date.parse(s?.cycle?.vote_end ?? '') - now) / 1000)}. ${mine ? 'This is your polling unit.' : `Your own polling unit is ${s?.me.ward.poll_unit_name ?? 'in your ward'}.`}`
            : 'This unit opens on voting day only. Check Benin Votes for the dates.'}
        </small>
      </span>
      <span className="bz-strip__btns">
        <Button size="sm" variant="gold" onClick={() => useUi.getState().openPhone('politics:vote')}>{open && mine ? 'Vote' : 'Benin Votes'}</Button>
      </span>
    </div>
  );
}

/** A banner above the place card while a phase needs the player: registration open, voting day. Taps open Benin Votes. */
export function ElectionBanner() {
  const s = usePolitics((x) => x.status);
  const now = useNow(30_000);
  const c = s?.cycle;
  if (!s || !s.enabled || !c) return null;
  if (c.status === 'campaign') return null;
  const left = (Date.parse(c.next_at) - now) / 1000;
  const voted = s.me.voted.length;
  const voting = c.voting_open;
  return (
    <div className="banners">
      <button type="button" className="banner banner--vote" data-testid="election-banner"
        onClick={() => useUi.getState().openPhone(voting ? 'politics:vote' : 'politics:elect')}>
        <span className="banner__icon" aria-hidden>{voting ? '🗳️' : '📣'}</span>
        <div className="grow">
          <div className="banner__title">{voting ? 'Election day' : 'Candidate registration is open'}</div>
          <div className="banner__sub">{voting ? (voted >= 3 ? 'You voted in every race. Thank you.' : `Go to ${s.me.ward.poll_unit_name ?? 'your polling unit'} and vote. Closes in ${span(left)}.`) : `Declare for office. Closes in ${span(left)}.`}</div>
        </div>
      </button>
    </div>
  );
}
