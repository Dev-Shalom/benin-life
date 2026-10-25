// Kids (docs/LOVE.md, stage 2): the "Kids" part of the Family tab. Everything is decided on the server (kids_*): this file only shows it.
// The needs bars, the cooldowns and the reasons all come from ONE read, kids_status(), loaded while the phone is open.
import {
  kidsAccept, kidsCare, kidsReclaim, kidsTry, kidsWithdraw,
  type KidAction, type KidChild, type KidCouple, type KidNeed, type KidsStatus,
} from '../../../api/kids';
import { serverNow } from '../../../lib/clock';
import { naira } from '../../../lib/format';
import { Button, EmptyState, toast } from '../../../ui';
import { ago, dur, face, useTick } from './familyUtil';

type Run = (key: string, fn: () => Promise<{ message?: string }>) => void;

const NEEDS: { key: KidNeed; icon: string; label: string }[] = [
  { key: 'hunger', icon: '🍼', label: 'Hunger' },
  { key: 'sleep', icon: '😴', label: 'Sleep' },
  { key: 'fun', icon: '🎈', label: 'Fun' },
  { key: 'health', icon: '🩺', label: 'Health' },
  { key: 'love', icon: '🤗', label: 'Love' },
];
const ACTIONS: { key: KidAction; icon: string; label: string }[] = [
  { key: 'feed', icon: '🍼', label: 'Feed' },
  { key: 'sleep', icon: '😴', label: 'Sleep' },
  { key: 'play', icon: '🎈', label: 'Play' },
  { key: 'medicine', icon: '💊', label: 'Medicine' },
  { key: 'cuddle', icon: '🤗', label: 'Cuddle' },
];
const DID: Record<KidAction, string> = { feed: 'fed', sleep: 'put to bed', play: 'played with', medicine: 'gave medicine to', cuddle: 'cuddled' };

const tone = (v: number, low: number) => (v < low ? 'low' : v < 60 ? 'mid' : 'ok');
const hoursLeft = (iso: string | null) => (iso ? (Date.parse(iso) - serverNow()) / 1000 : 0);

function Bar({ pct, cls = '' }: { pct: number; cls?: string }) {
  return <div className={`fm-bar ${cls}`} aria-hidden><span className="fm-bar__fill" style={{ transform: `scaleX(${Math.max(0, Math.min(100, pct)) / 100})` }} /></div>;
}

// ------------------------------------------------------------------------------------------------ pieces
function Expecting({ c }: { c: KidChild }) {
  useTick(true);
  const total = Math.max(1, (Date.parse(c.due_at) - Date.parse(c.conceived_at)) / 1000);
  const left = hoursLeft(c.due_at);
  const pct = Math.max(0, Math.min(100, ((total - left) / total) * 100));
  return (
    <article className="fm-card fm-expect" data-testid="kids-expecting">
      <span className="fm-expect__icon" aria-hidden>🍼</span>
      <b>Expecting a little one</b>
      <p className="fm-fine">{c.partner ? `You and @${c.partner.username} are waiting for your baby.` : 'Your baby is on the way.'}</p>
      <div className="fm-expect__count"><span>{left > 0 ? dur(left) : 'Any moment now'}</span><small>{left > 0 ? 'until your baby arrives' : 'Open the app again to meet them'}</small></div>
      <Bar pct={pct} cls="fm-bar--baby" />
    </article>
  );
}

function HaveBaby({ couple, kids, at, run, busy }: { couple: KidCouple; kids: KidsStatus; at: number; run: Run; busy: string | null }) {
  useTick(true);
  const rules = kids.rules;
  const out = kids.outgoing.find((i) => i.rel_id === couple.rel_id && i.state === 'pending');
  const coming = kids.incoming.find((i) => i.rel_id === couple.rel_id);
  const expecting = kids.children.some((c) => c.status === 'expecting' && c.rel_id === couple.rel_id);
  if (expecting || coming) return null;
  const name = couple.partner.username;
  if (out) {
    const left = hoursLeft(out.expires_at);
    return (
      <article className="fm-card fm-ask fm-ask--out" data-testid="kids-waiting">
        <span className="fm-ask__who">
          {face(couple.partner.avatar, 40)}
          <span className="fm-ask__txt"><b>Waiting for @{name}</b><small>You asked about a baby. {left > 0 ? `${dur(left)} left to answer.` : 'No reply yet.'}</small></span>
        </span>
        <Button variant="ghost" size="sm" loading={busy === `kw:${out.id}`} disabled={busy !== null} onClick={() => run(`kw:${out.id}`, () => kidsWithdraw(out.id))}>Take back</Button>
      </article>
    );
  }
  const declined = kids.outgoing.find((i) => i.rel_id === couple.rel_id && i.state === 'declined');
  const why = couple.why;
  if (!couple.can_try) {
    const soon = why?.code === 'too_soon';
    return (
      <article className="fm-card fm-baby is-locked" data-testid="kids-locked">
        <span className="fm-baby__icon" aria-hidden>👶</span>
        <b>{soon ? 'Not just yet' : 'A baby is not possible right now'}</b>
        <p className="fm-fine">{why?.msg ?? 'Check back soon.'}</p>
        {soon && (
          <div className="fm-level">
            <div className="fm-level__row"><span>Together as a couple</span><span>{couple.couple_days} of {couple.min_days} days</span></div>
            <Bar pct={(couple.couple_days / Math.max(1, couple.min_days)) * 100} />
          </div>
        )}
      </article>
    );
  }
  const wait = Math.max(0, couple.invite_wait_seconds - (serverNow() - at) / 1000);
  return (
    <article className="fm-card fm-baby" data-testid="kids-have-baby">
      <span className="fm-baby__icon" aria-hidden>👶</span>
      <b>Have a baby</b>
      <p className="fm-fine">Ask @{name} to try for a baby. You both have to say yes{rules && rules.try_cost_each > 0 ? `, and you each pay ${naira(rules.try_cost_each)}` : ''}. Then you wait about {rules?.pregnancy_days ?? 7} days for your little one, and look after them together.</p>
      {declined && <p className="fm-warn">@{name} would like to wait a little. That is okay.</p>}
      <Button variant="green" size="lg" loading={busy === `try:${couple.rel_id}`} disabled={busy !== null || wait > 0} onClick={() => run(`try:${couple.rel_id}`, () => kidsTry(couple.rel_id))} data-testid="kids-try">
        {wait > 0 ? `Ask again in ${dur(wait)}` : `Ask @${name} 👶`}
      </Button>
      {rules && <p className="fm-fine">Up to {rules.max_per_couple} children at a time per couple. They grow up in {rules.grow_days} days.</p>}
    </article>
  );
}

function Invite({ kids, run, busy }: { kids: KidsStatus; run: Run; busy: string | null }) {
  useTick(kids.incoming.length > 0);
  if (!kids.incoming.length) return null;
  return (
    <>
      {kids.incoming.map((i) => (
        <article key={i.id} className="fm-card fm-ask" data-testid="kids-invite">
          <span className="fm-ask__who">
            {face(i.from.avatar, 48)}
            <span className="fm-ask__txt">
              <b>@{i.from.username} would like a baby 👶</b>
              <small>You both have to agree{kids.rules && kids.rules.try_cost_each > 0 ? ` and you each pay ${naira(kids.rules.try_cost_each)}` : ''}. {dur(hoursLeft(i.expires_at))} left to answer.</small>
            </span>
          </span>
          <span className="fm-ask__btns">
            <Button variant="green" size="md" loading={busy === `ka:${i.id}`} disabled={busy !== null} onClick={() => run(`ka:${i.id}`, () => kidsAccept(i.id, true))} data-testid="kids-accept">Yes, let's try</Button>
            <Button variant="ghost" size="md" loading={busy === `kn:${i.id}`} disabled={busy !== null} onClick={() => run(`kn:${i.id}`, () => kidsAccept(i.id, false))}>Not yet</Button>
          </span>
        </article>
      ))}
    </>
  );
}

function ChildCard({ c, kids, at, run, busy, onName }: { c: KidChild; kids: KidsStatus; at: number; run: Run; busy: string | null; onName: (c: KidChild) => void }) {
  useTick(true);
  const rules = kids.rules;
  const low = rules?.alert_below ?? 30;
  const name = c.name ?? 'Your baby';
  const away = c.status === 'with_relatives';
  const needsYou = c.needy.length > 0 && !away;
  const elapsed = (serverNow() - at) / 1000;
  const grows = c.age_days !== null && rules ? Math.max(0, rules.grow_days - c.age_days) : null;
  const removalLeft = c.removal_at ? hoursLeft(c.removal_at) : null;
  const nameLeft = !c.name && c.name_due_at ? hoursLeft(c.name_due_at) : null;
  const cls = `fm-kid${c.gender ? ` is-${c.gender}` : ''}${needsYou ? ' is-needy' : ''}${c.sick ? ' is-sick' : ''}${away ? ' is-away' : ''}`;

  const press = (a: KidAction, info: KidChild['actions'][KidAction], left: number) => {
    if (!info) return;
    if (!info.ok && !(info.code === 'cooldown' && left <= 0)) { toast(info.code === 'cooldown' ? `Easy. You can do that again in ${dur(left)}.` : info.msg, 'info'); return; }
    run(`care:${c.id}:${a}`, () => kidsCare(c.id, a));
  };

  return (
    <article className={cls} data-testid="kids-child" data-child={c.id}>
      <div className="fm-kid__head">
        <span className="fm-kid__face" aria-hidden>
          <span className="fm-kid__emoji">{c.stage?.emoji ?? '👶'}</span>
          {c.sick && <span className="fm-kid__badge">🤒</span>}
          {away && <span className="fm-kid__badge">🏠</span>}
        </span>
        <span className="fm-kid__who">
          {c.name ? <b>{c.name}</b> : <b>Your new baby</b>}
          <small>{c.stage?.name ?? 'Baby'} · {c.age_days === 0 ? 'born today' : `${c.age_days} ${c.age_days === 1 ? 'day' : 'days'} old`}{c.partner ? ` · with @${c.partner.username}` : ' · you are on your own'}</small>
          {needsYou && <span className="fm-kid__pill" data-testid="kids-needs-you">needs you!</span>}
          {away && <span className="fm-kid__pill is-calm">with relatives</span>}
        </span>
      </div>

      {!c.name && !away && (
        <button type="button" className="fm-kid__name" onClick={() => onName(c)} data-testid="kids-name">
          <span aria-hidden>✏️</span>
          <span><b>Name your baby</b><small>{nameLeft !== null && nameLeft > 0 ? `If nobody picks, the game names them in ${dur(nameLeft)}.` : 'Pick a name and Boy or Girl.'}</small></span>
        </button>
      )}

      {away && c.relatives && (
        <div className="fm-kid__banner">
          <b>💛 {name} is staying with relatives</b>
          <p className="fm-fine">Nobody could look after them for a while, so family stepped in. They are safe and loved.{c.relatives.can_reclaim ? ` You can bring ${name} home once.` : ''}</p>
          {c.relatives.can_reclaim ? (
            <Button variant="green" size="lg" loading={busy === `rc:${c.id}`} disabled={busy !== null} onClick={() => run(`rc:${c.id}`, () => kidsReclaim(c.id))} data-testid="kids-reclaim">
              Bring {name} home {c.relatives.cost > 0 ? naira(c.relatives.cost) : ''}
            </Button>
          ) : <p className="fm-fine">{c.relatives.wait_seconds - elapsed > 0 ? `You can bring them home in ${dur(c.relatives.wait_seconds - elapsed)}.` : 'Open the app again to bring them home.'}</p>}
        </div>
      )}

      {c.sick && !away && (
        <div className="fm-kid__banner is-sick" data-testid="kids-sick">
          <b>🤒 {name} is unwell</b>
          <p className="fm-fine">To help {name} get better, give medicine and a cuddle. Either parent can do it.</p>
          <span className="fm-steps"><span className={c.sick_med ? 'is-done' : ''}>{c.sick_med ? '✓' : '○'} Medicine</span><span className={c.sick_cuddle ? 'is-done' : ''}>{c.sick_cuddle ? '✓' : '○'} Cuddle</span></span>
        </div>
      )}

      {!away && (
        <ul className="fm-needs" aria-label="Needs">
          {NEEDS.map((n) => {
            const v = c.needs[n.key] ?? 0;
            return (
              <li key={n.key} className={`fm-need is-${tone(v, low)}`} data-need={n.key}>
                <span className="fm-need__label"><span aria-hidden>{n.icon}</span> {n.label}</span>
                <Bar pct={v} cls="fm-bar--need" />
                <span className="fm-need__num">{v}</span>
              </li>
            );
          })}
        </ul>
      )}

      {!away && (
        <div className="fm-care" role="group" aria-label={`Look after ${name}`}>
          {ACTIONS.map((a) => {
            const info = c.actions[a.key];
            if (!info) return null;
            const left = info.code === 'cooldown' ? info.wait - elapsed : 0;
            const ok = info.ok || (info.code === 'cooldown' && left <= 0);
            const sub = ok ? (info.cost > 0 ? naira(info.cost) : 'Free') : info.code === 'cooldown' ? dur(left) : info.code === 'not_needed' ? (a.key === 'medicine' ? 'Not unwell' : 'All good') : '';
            return (
              <button key={a.key} type="button" className={`fm-care__btn${ok ? '' : ' is-off'}`} aria-disabled={!ok || busy !== null} disabled={busy !== null && busy.startsWith('care:')}
                onClick={() => press(a.key, info, left)} data-testid={`kids-${a.key}`} data-ok={ok ? '1' : '0'}
                title={ok ? undefined : info.msg}>
                <span className="fm-care__icon" aria-hidden>{a.icon}</span>
                <span className="fm-care__label">{a.label}</span>
                <small>{busy === `care:${c.id}:${a.key}` ? '...' : sub}</small>
              </button>
            );
          })}
        </div>
      )}

      {!away && removalLeft !== null && removalLeft < 3 * 86400 && (
        <p className="fm-warn">Nobody has looked after {name} for a while. If it stays that way, relatives take them in in about {dur(removalLeft)}.</p>
      )}
      {!away && grows !== null && <p className="fm-fine">{grows > 0 ? `Grows up in about ${grows} ${grows === 1 ? 'day' : 'days'}.` : 'Almost grown up.'}</p>}

      {c.log.length > 0 && (
        <details className="fm-kid__log">
          <summary>Who looked after {c.name ?? 'them'}</summary>
          <ul className="fm-recent" data-testid="kids-log">
            {c.log.map((l) => (
              <li key={l.id}><span aria-hidden>{ACTIONS.find((a) => a.key === l.action)?.icon}</span><b>{l.mine ? 'You' : `@${l.who}`} {DID[l.action]} {c.name ?? 'the baby'}</b><small>{ago(l.created_at)}</small></li>
            ))}
          </ul>
        </details>
      )}
    </article>
  );
}

// ------------------------------------------------------------------------------------------------ the section
export function KidsSection({ kids, err, at, run, busy, onName, onRetry }: {
  kids: KidsStatus | null; err: string | null; at: number; run: Run; busy: string | null; onName: (c: KidChild) => void; onRetry: () => void;
}) {
  if (!kids) {
    return (
      <section className="fm-sect" data-testid="kids-section">
        <h3 className="fm-h">Kids</h3>
        {err ? <EmptyState icon="warning" title="Could not load Kids" body={err} action={<Button variant="green" onClick={onRetry}>Try again</Button>} /> : <div className="panel-skel"><span /><span /></div>}
      </section>
    );
  }
  if (!kids.enabled) {
    return (
      <section className="fm-sect" data-testid="kids-section">
        <h3 className="fm-h">Kids</h3>
        <article className="fm-card fm-note"><b>Kids are resting 🍼</b><p>Babies and child care are switched off for now. Your children are safe, and their clocks are paused until it is back.</p></article>
      </section>
    );
  }
  const expecting = kids.children.filter((c) => c.status === 'expecting');
  const living = kids.children.filter((c) => c.status !== 'expecting');
  const noCouple = kids.couples.length === 0;
  return (
    <section className="fm-sect" data-testid="kids-section">
      <h3 className="fm-h">Kids {kids.attention > 0 && <span className="fm-count" data-testid="kids-attention">{kids.attention}</span>}</h3>
      <Invite kids={kids} run={run} busy={busy} />
      {expecting.map((c) => <Expecting key={c.id} c={c} />)}
      {living.map((c) => <ChildCard key={c.id} c={c} kids={kids} at={at} run={run} busy={busy} onName={onName} />)}
      {kids.couples.map((cp) => <HaveBaby key={cp.rel_id} couple={cp} kids={kids} at={at} run={run} busy={busy} />)}
      {noCouple && living.length === 0 && expecting.length === 0 && (
        <article className="fm-card fm-kids" data-testid="fm-kids">
          <span className="fm-kids__icon" aria-hidden>🍼</span>
          <b>Babies come with a couple</b>
          <p>When you and somebody you like become a couple, you can try for a baby together and look after them. Build your bond in Us first.</p>
        </article>
      )}
      {kids.grown.length > 0 && (
        <article className="fm-card fm-proud" data-testid="kids-proud">
          <span className="fm-proud__badge">🏅 Proud parent{kids.proud > 1 ? ` × ${kids.proud}` : ''}</span>
          <ul className="fm-recent">
            {kids.grown.map((g) => <li key={g.id}><span aria-hidden>🎓</span><b>{g.name ?? 'Your child'} grew up and moved out</b><small>{ago(g.grown_at)}</small></li>)}
          </ul>
          <p className="fm-fine">Your name shows the badge on your profile if you share your relationship.</p>
        </article>
      )}
    </section>
  );
}
