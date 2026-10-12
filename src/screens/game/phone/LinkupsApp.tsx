// D2 Link-ups app (docs/LINKUPS.md): who you're into, your current link-up / partner, who is out tonight (at a club),
// the people you've met with their spark, how it works (prices) and your history. NPC adults only; never other players.
import { useEffect } from 'react';
import type { LinkupAction } from '../../../api/linkups';
import { useNow } from '../../../lib/clock';
import { naira, nairaShort, timeAgo } from '../../../lib/format';
import type { GameState } from '../../../lib/types';
import { useLinkups } from '../../../state/linkups';
import { minutesLeft, NpcFace, NpcRow, SparkMeter, useLinkupStart, WantPicker } from '../Linkups';

function where(a: LinkupAction): string {
  return a.kind === 'drinks' ? 'Clubs & lounges' : a.kind === 'date' ? 'Hotel restaurants · mall food court' : 'Hotel suites';
}

export default function LinkupsApp({ state, onGo }: { state: GameState; onGo: (id: string) => void }) {
  const s = useLinkups((x) => x.status);
  const run = useLinkups((x) => x.run);
  const now = useNow(1000);
  const [busy, start] = useLinkupStart();

  useEffect(() => { void useLinkups.getState().load(); }, [state.profile.location_id]);

  if (!s) return <div className="phone-app__body"><div className="panel-skel"><span /><span /><span /></div></div>;
  const free = !run && !(state.profile.busy_until && Date.parse(state.profile.busy_until) > now) && !state.travel;
  const drinks = s.actions.find((a) => a.kind === 'drinks');
  const dinner = s.actions.find((a) => a.kind === 'date');
  const hotels = s.actions.find((a) => a.kind === 'hotel')?.places ?? [];
  const clubs = drinks?.places ?? [];
  const cur = s.current;

  return (
    <div className="phone-app__body lu-app" data-testid="linkups-app">
      <section className="lu-hero">
        <div className="lu-hero__top">
          <span className="lu-hero__label">Link-ups with</span>
          <WantPicker want={s.want} />
        </div>
        <div className="lu-hero__stats">
          {s.stats.linkups} yes{s.stats.linkups === 1 ? '' : 'es'} · {s.stats.nights} night{s.stats.nights === 1 ? '' : 's'} out
          {s.stats.breakups ? ` · ${s.stats.breakups} heartbreak${s.stats.breakups === 1 ? '' : 's'}` : ''}
          {s.attraction ? ` · 🪔 attraction +${s.attraction}` : ''}
        </div>
      </section>

      {run && (
        <div className="lu-run" data-testid="lu-running">
          <span aria-hidden>{run.icon}</span>
          <span className="grow">{run.name} with {run.npc_name}<div className="lu-fade__bar"><span style={{ transform: `scaleX(${Math.min(1, Math.max(0, (now - Date.parse(run.started_at)) / Math.max(1, Date.parse(run.resolve_at) - Date.parse(run.started_at))))})` }} /></div></span>
        </div>
      )}

      {s.partner && (
        <section className="lu-card" data-testid="lu-partner">
          <h4 className="lu-card__title">💑 Your partner</h4>
          <div className="lu-with">
            <NpcFace npc={s.partner} size={52} />
            <div className="lu-with__main">
              <b>{s.partner.name}, {s.partner.age}</b>
              <small>{s.partner.vibe}</small>
              <SparkMeter spark={s.partner.spark} />
            </div>
          </div>
          <p className="lu-fine">Partners don't need drinks: take them out any time. A night with someone else? They fit find out.</p>
        </section>
      )}

      <section className="lu-card" data-testid="lu-current">
        <h4 className="lu-card__title">Current link-up {cur && !cur.partner && cur.yes_until && <small>{minutesLeft(cur.yes_until, now)} left</small>}</h4>
        {cur && !cur.partner ? (
          <>
            <div className="lu-with">
              <NpcFace npc={cur} size={52} />
              <div className="lu-with__main">
                <b>{cur.name}, {cur.age}</b>
                <small>Said yes 💞 · {cur.vibe}</small>
                <SparkMeter spark={cur.spark} />
              </div>
            </div>
            <p className="lu-fine">Take {cur.name} to dinner, or straight to a hotel suite.</p>
            <div className="lu-go">
              {dinner?.places.map((p) => <button key={p.id} type="button" onClick={() => onGo(p.id)}>🍽️ {p.name}</button>)}
              {hotels.filter((h) => !dinner?.places.some((p) => p.id === h.id)).map((p) => <button key={p.id} type="button" onClick={() => onGo(p.id)}>🛏️ {p.name}</button>)}
            </div>
          </>
        ) : (
          <>
            <p className="lu-fine" style={{ marginTop: 0 }}>Nobody yet. Clubs open at night: buy someone drinks and shoot your shot.</p>
            <div className="lu-go">
              {clubs.map((p) => <button key={p.id} type="button" onClick={() => onGo(p.id)}>🪩 {p.name}</button>)}
            </div>
          </>
        )}
      </section>

      {s.here && (
        <section className="lu-card" data-testid="lu-here">
          <h4 className="lu-card__title">Out tonight · {s.place?.name}</h4>
          <div className="lu-sheet">
            {s.here.length === 0 && <p className="lu-fine">Nobody you fancy is out here right now.</p>}
            {s.here.map((h) => (
              <NpcRow key={h.id} h={h} drinks={drinks} now={now} busy={busy} free={free} onBuy={(id) => { if (drinks) void start(drinks, id); }} />
            ))}
          </div>
        </section>
      )}

      <section className="lu-card">
        <h4 className="lu-card__title">People you've met <small>{s.people.length}</small></h4>
        {s.people.length === 0 && <p className="lu-fine" style={{ marginTop: 0 }}>Nobody yet. The people you buy drinks for show up here.</p>}
        {s.people.map((p) => (
          <div key={p.id} className="lu-person" data-testid={`lu-person-${p.id}`}>
            <NpcFace npc={p} size={40} />
            <div className="lu-person__main">
              <b>{p.name}</b>, {p.age}{' '}
              {p.partner ? <span className="lu-tag lu-tag--partner">Partner</span>
                : p.yes_until ? <span className="lu-tag lu-tag--yes">Said yes</span>
                  : p.ended_at ? <span className="lu-tag lu-tag--ex">Ex</span> : null}
              <small>{p.vibe} · 💚 {p.likes} · 🚫 {p.hates}</small>
              <small>{p.drinks} drink{p.drinks === 1 ? '' : 's'} · {p.dinners} dinner{p.dinners === 1 ? '' : 's'} · {p.nights} night{p.nights === 1 ? '' : 's'}</small>
              <SparkMeter spark={p.spark} small />
            </div>
          </div>
        ))}
        {!s.partner && <p className="lu-fine">{s.steady.dinners} dinner dates and {s.steady.spark}+ spark with the same person and you two become an item.</p>}
      </section>

      <section className="lu-card">
        <h4 className="lu-card__title">How e dey work</h4>
        <ol className="lu-flow">
          {s.actions.map((a) => (
            <li key={a.id}>
              <span aria-hidden>{a.icon}</span>
              <span><b>{a.name}</b>{a.min_rank ? ` · ${a.rank_name ?? a.min_rank}+` : ''}<small>{where(a)}{a.needs_yes ? ' · needs a yes' : ' · they fit say yes or no'}{a.morning ? ' · fade to black' : ''}</small></span>
              <span className="lu-price" title={naira(a.price)}>{a.price >= 100000 ? nairaShort(a.price) : naira(a.price)}</span>
            </li>
          ))}
        </ol>
        <p className="lu-fine">Morning after a hotel night: sometimes your wallet don waka. Every link-up is with an adult NPC. Never with other players.</p>
      </section>

      {s.history.length > 0 && (
        <section className="lu-card">
          <h4 className="lu-card__title">History</h4>
          <ul className="lu-hist">
            {s.history.map((h) => (
              <li key={h.id}>
                <span aria-hidden>{h.icon}</span>
                <span>{h.name} · {h.npc_name}{h.status === 'yes' ? ' · said yes 💞' : h.status === 'no' ? ' · said no' : ''}</span>
                <span>{timeAgo(h.started_at, now)}</span>
              </li>
            ))}
          </ul>
        </section>
      )}
    </div>
  );
}
