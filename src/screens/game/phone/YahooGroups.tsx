// R6 group missions section of the Yahoo app (docs/YAHOO.md "R6"): create a group mission, invite online friends, see who is
// ready, start, and see the result with the split. Everything is decided on the server (yahoo_group_*); this only shows it.
// Abstract game mechanic: a bigger pot split evenly, a higher EFCC risk for the whole crew.
import { useEffect, useState } from 'react';
import {
  yahooGroupCancel, yahooGroupCreate, yahooGroupRespond, yahooGroupStart,
  type GroupMember, type GroupMission, type YahooGroup,
} from '../../../api/yahoo';
import { errorMessage } from '../../../lib/api';
import { useNow } from '../../../lib/clock';
import { countdown, naira, nairaShort, secondsUntil } from '../../../lib/format';
import { useGame } from '../../../state/game';
import { useYahoo } from '../../../state/yahoo';
import { Button, toast } from '../../../ui';

const MEMBER_LABEL: Record<GroupMember['status'], string> = {
  invited: 'Waiting', accepted: 'Ready', declined: 'Passed', dropped: 'Dropped', expired: 'Missed',
};

function oddsTone(p: number): string {
  return p >= 30 ? 'is-hot' : p >= 18 ? 'is-warm' : 'is-cool';
}
const pct = (p: number) => `${Math.round(p * 10) / 10}%`;
const dur = (s: number) => (s >= 60 ? `${Math.floor(s / 60)}m${s % 60 ? ` ${s % 60}s` : ''}` : `${s}s`);

function Members({ g }: { g: YahooGroup }) {
  return (
    <ul className="yh-gm__members">
      {g.members.map((m) => (
        <li key={m.id} className={`is-${m.status}`}>
          <span className="grow"><b>@{m.username}</b>{m.host ? ' · host' : ''}{m.me ? ' · you' : ''}{m.level ? <small>Yahoo lvl {m.level}</small> : null}</span>
          {g.status === 'paid' && m.status === 'accepted' ? <em className="is-in">+{nairaShort(m.payout)}</em>
            : g.status === 'caught' && m.status === 'accepted' ? <em className="is-out">EFCC{m.seized > 0 ? ` −${nairaShort(m.seized)}` : ''}</em>
              : <em>{MEMBER_LABEL[m.status]}</em>}
        </li>
      ))}
    </ul>
  );
}

export default function YahooGroups({ onGo, locationId }: { onGo: (id: string) => void; locationId: string }) {
  const gs = useYahoo((x) => x.groups);
  const refresh = useGame((x) => x.refresh);
  const now = useNow(1000);
  const [pick, setPick] = useState<string | null>(null);
  const [friends, setFriends] = useState<string[]>([]);
  const [busy, setBusy] = useState<string | null>(null);
  const [hidden, setHidden] = useState<number | null>(null);

  useEffect(() => { void useYahoo.getState().loadGroups(); }, [locationId]);

  if (!gs) return null;
  if (!gs.enabled && !gs.group && gs.invites.length === 0) {
    return <><h4 className="yh-h">Group missions</h4><p className="yh-fine">Group missions are off for now.</p></>;
  }

  const sync = (r: { group: YahooGroup; message: string } | null) => {
    if (r) toast(r.message, 'info');
    void useYahoo.getState().loadGroups();
    void refresh();
  };
  const act = async (key: string, fn: () => Promise<{ group: YahooGroup; message: string }>) => {
    setBusy(key);
    try { sync(await fn()); } catch (e) { toast(errorMessage(e), 'bad'); void useYahoo.getState().loadGroups(); } finally { setBusy(null); }
  };

  const mission: GroupMission | undefined = gs.missions.find((m) => m.id === pick) ?? gs.missions[0];
  const here = gs.places.find((p) => p.id === locationId);
  const g = gs.group;
  const last = gs.last && gs.last.id !== hidden && !g ? gs.last : null;
  const maxInvites = mission ? mission.max_members - 1 : 3;
  const toggle = (id: string) => setFriends((cur) => (cur.includes(id) ? cur.filter((x) => x !== id) : cur.length < maxInvites ? [...cur, id] : cur));
  const mCd = mission ? secondsUntil(mission.cooldown_until, now) : 0;
  const createWhy = !gs.has_laptop ? 'Need a laptop'
    : !gs.spot.ok ? (gs.spot.hint === 'no_mifi' ? 'Need MiFi' : 'Go to HK Quarters')
      : mission && !mission.level_ok ? `Needs Yahoo lvl ${mission.min_yahoo_level}`
        : mission && mission.daily_cap && (mission.cap_left ?? 0) <= 0 ? 'Done for today'
          : mCd > 0 ? `Wait ${countdown(mCd)}`
          : friends.length < 1 ? 'Pick a friend' : null;

  return (
    <section data-testid="yahoo-groups" aria-label="Group missions">
      <h4 className="yh-h">Group missions</h4>

      {/* invites to me */}
      {gs.invites.map((inv) => {
        const left = secondsUntil(inv.start_at, now);
        return (
          <div key={inv.id} className="yh-gm yh-gm--invite" data-testid="yahoo-invite">
            <div className="yh-gm__head">
              <span className="yh-gm__icon" aria-hidden>{inv.icon}</span>
              <span className="grow"><b>@{inv.host} invite you</b><small>{inv.name} · {inv.ready} ready · starts in {countdown(Math.max(0, left))}</small></span>
              <span className={`yh-odds ${oddsTone(inv.caught_pct)}`}>🚨 {pct(inv.caught_pct)}</span>
            </div>
            <Members g={inv} />
            <p className="yh-fine">Your share: {nairaShort(inv.per_min)}–{nairaShort(inv.per_max)}. Be at HK Quarters or home on MiFi, with a laptop.</p>
            <div className="yh-gm__btns">
              <Button size="sm" variant="gold" loading={busy === `a${inv.id}`} disabled={busy !== null} data-testid="yahoo-invite-accept"
                onClick={() => void act(`a${inv.id}`, () => yahooGroupRespond(inv.id, true))}>Join the crew</Button>
              <Button size="sm" variant="ghost" loading={busy === `p${inv.id}`} disabled={busy !== null}
                onClick={() => void act(`p${inv.id}`, () => yahooGroupRespond(inv.id, false))}>Pass</Button>
            </div>
          </div>
        );
      })}

      {/* my open group */}
      {g && (
        <div className={`yh-gm yh-gm--${g.status}`} data-testid="yahoo-group">
          <div className="yh-gm__head">
            <span className="yh-gm__icon" aria-hidden>{g.icon}</span>
            <span className="grow">
              <b>{g.name}</b>
              <small>
                {g.status === 'inviting'
                  ? `Waiting for the crew · starts in ${countdown(Math.max(0, secondsUntil(g.start_at, now)))} or when all answer`
                  : `Running · ${countdown(Math.max(0, secondsUntil(g.resolve_at, now)))} left`}
              </small>
            </span>
            <span className={`yh-odds ${oddsTone(g.caught_pct)}`} title={g.caught_pct !== g.base_caught_pct ? `Base ${pct(g.base_caught_pct)}, cut by the crew's average Yahoo level` : undefined}>
              🚨 {pct(g.caught_pct)}{g.caught_pct !== g.base_caught_pct ? <s>{pct(g.base_caught_pct)}</s> : null}
            </span>
          </div>
          {g.status === 'running' && (
            <div className="yh-run__bar" aria-hidden>
              <span style={{ transform: `scaleX(${Math.min(1, Math.max(0, 1 - secondsUntil(g.resolve_at, now) / Math.max(1, g.duration_seconds)))})` }} />
            </div>
          )}
          <Members g={g} />
          <p className="yh-fine">
            {g.ready} of {g.min_members}+ ready · each share about {nairaShort(g.per_min)}–{nairaShort(g.per_max)}. Caught = the whole crew gets the EFCC case.
          </p>
          {g.status === 'inviting' && (
            <div className="yh-gm__btns">
              {g.i_am_host ? <>
                <Button size="sm" variant="gold" disabled={g.ready < g.min_members || busy !== null} loading={busy === 'start'} data-testid="yahoo-group-start"
                  onClick={() => void act('start', () => yahooGroupStart(g.id))}>{g.ready < g.min_members ? `Need ${g.min_members} ready` : 'Start now'}</Button>
                <Button size="sm" variant="ghost" disabled={busy !== null} loading={busy === 'cancel'} onClick={() => void act('cancel', () => yahooGroupCancel(g.id))}>Cancel</Button>
              </> : (
                <Button size="sm" variant="ghost" disabled={busy !== null} loading={busy === 'leave'} onClick={() => void act('leave', () => yahooGroupRespond(g.id, false))}>Leave</Button>
              )}
            </div>
          )}
        </div>
      )}

      {/* the last result with the split */}
      {last && (
        <div className={`yh-gm yh-gm--${last.status}`} data-testid="yahoo-group-result">
          <div className="yh-gm__head">
            <span className="yh-gm__icon" aria-hidden>{last.status === 'paid' ? '✅' : '🚨'}</span>
            <span className="grow">
              <b>{last.name}: {last.status === 'paid' ? 'paid' : 'EFCC caught the crew'}</b>
              <small>{last.status === 'paid' ? `Pot ${naira(last.pot)} split ${last.members.filter((m) => m.status === 'accepted').length} ways: ${naira(last.per_member)} each` : 'Everybody got the EFCC case.'}</small>
            </span>
          </div>
          <Members g={last} />
          <div className="yh-gm__btns"><Button size="sm" variant="ghost" onClick={() => setHidden(last.id)}>Okay</Button></div>
        </div>
      )}

      {/* start one */}
      {!g && mission && (
        <div className="yh-gm" data-testid="yahoo-group-new">
          <p className="yh-fine yh-fine--top">
            Work a format with friends: bigger pot split evenly, but the whole crew shares the EFCC risk.
            Everybody needs a laptop and must be at {gs.places.map((p) => p.name).join(' or ') || 'HK Quarters'} or home on MiFi.
          </p>
          <p className={`yh-where${gs.spot.ok ? ' is-ok' : ''}`}>
            {gs.spot.ok ? '🟢 ' : '🔴 '}{gs.spot.message}
            {!gs.spot.ok && gs.places.filter((p) => p.id !== here?.id).map((p) => (
              <button key={p.id} type="button" className="yh-link" onClick={() => onGo(p.id)}>Go to {p.name}</button>
            ))}
          </p>
          <div className="yh-gm__missions" role="radiogroup" aria-label="Mission">
            {gs.missions.map((m) => (
              <button key={m.id} type="button" role="radio" aria-checked={mission.id === m.id} className={`yh-gm__mission${mission.id === m.id ? ' is-on' : ''}${m.level_ok ? '' : ' is-locked'}`}
                onClick={() => { setPick(m.id); setFriends((cur) => cur.slice(0, m.max_members - 1)); }} data-testid={`yahoo-mission-${m.id}`}>
                <span aria-hidden>{m.icon}</span>
                <span className="grow">
                  <b>{m.name}</b>
                  <small>{m.min_members}–{m.max_members} players · {dur(m.duration_seconds)} · pot {nairaShort(m.reward_min)}–{nairaShort(m.reward_max)}{m.min_yahoo_level > 1 ? ` · Yahoo lvl ${m.min_yahoo_level}+` : ''}{m.daily_cap ? ` · ${m.cap_left ?? 0}/${m.daily_cap} left today` : ''}</small>
                </span>
                <span className={`yh-odds ${oddsTone(m.caught_pct)}`}>🚨 {pct(m.caught_pct)}</span>
              </button>
            ))}
          </div>
          <p className="yh-fine">{mission.blurb} Pot grows {gs.bonus_pct}% for each extra member; the crew's average Yahoo level lowers the risk.</p>
          <h5 className="yh-gm__sub">Invite friends ({friends.length}/{maxInvites})</h5>
          {gs.friends.length === 0 ? <p className="yh-fine">No friends yet. Add friends from Messages first.</p> : (
            <div className="yh-gm__friends">
              {gs.friends.map((f) => (
                <button key={f.id} type="button" className={`yh-gm__friend${friends.includes(f.id) ? ' is-on' : ''}`} disabled={!f.online}
                  aria-pressed={friends.includes(f.id)} onClick={() => toggle(f.id)} data-testid="yahoo-friend">
                  <span className={`yh-dot${f.online ? ' is-online' : ''}`} aria-hidden />
                  @{f.username}
                  <small>{!f.online ? 'offline' : f.ready ? 'ready' : 'not at HK / home'}</small>
                </button>
              ))}
            </div>
          )}
          <Button block variant="gold" disabled={Boolean(createWhy) || busy !== null} loading={busy === 'create'} data-testid="yahoo-group-create"
            onClick={() => void act('create', async () => { const r = await yahooGroupCreate(mission.id, friends); setFriends([]); return r; })}>
            {createWhy ?? `Start ${mission.name}`}
          </Button>
        </div>
      )}
    </section>
  );
}

