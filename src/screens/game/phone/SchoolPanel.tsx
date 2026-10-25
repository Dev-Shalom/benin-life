// Kids school and university (docs/KIDS_SCHOOL.md): the School panel inside a child card, the enrol picker, the WAEC result, the university card and the
// report cards (with Share). Everything is decided on the server (kids_school_*): this file only shows it. The block arrives with each child in kids_status.
import { useEffect, useState } from 'react';
import {
  kidsReportCards, kidsSchoolEnrol, kidsSchoolGear, kidsSchoolHomework, kidsSchoolLessons, kidsSchoolPay, kidsSchoolSchools,
  type KidChild, type KidSchool, type ReportCard, type SchoolGear, type SchoolOption, type Waec,
} from '../../../api/kids';
import { errorMessage } from '../../../lib/api';
import { serverNow } from '../../../lib/clock';
import { naira } from '../../../lib/format';
import { Button, Modal, toast } from '../../../ui';
import { dur, useTick } from './familyUtil';
import { Bar, BuyPanel, type Run } from './kidsShared';

const secs = (iso: string | null | undefined) => (iso ? (Date.parse(iso) - serverNow()) / 1000 : 0);
const shortName = (n: string) => n.split(' ').slice(0, 2).join(' ');
const LEVEL_WORD: Record<string, string> = { nursery: 'nursery', primary: 'primary', secondary: 'secondary', university: 'university' };
const TIER_WORD: Record<string, string> = { budget: 'Budget', mid: 'Mid-range', premium: 'Premium', public: 'Public', private: 'Private' };
const gradeTone = (g: number, pass: number) => (g < pass ? 'low' : g < pass + 12 ? 'mid' : 'ok');

// ------------------------------------------------------------------------------------------------ grades
function Grades({ s, name }: { s: KidSchool; name: string }) {
  const grades = s.grades ?? [];
  if (grades.length === 0) return null;
  const pass = s.pass_mark;
  const unpaid = s.fee ? !s.fee.paid : false;
  const avg = s.avg_now ?? 0;
  return (
    <div className={`fm-sch__grades${unpaid ? ' is-dim' : ''}`} data-testid="school-grades">
      <div className="fm-sch__sub"><b>Grades so far</b><small>{unpaid ? `Fee unpaid: ${name} will miss this class` : 'if the class ended now'}</small></div>
      <ul className="fm-sch__list" aria-label="Grades">
        {grades.map((g) => {
          const d = g.last === null ? null : g.g - g.last;
          return (
            <li key={g.name} className={`fm-grade is-${gradeTone(g.g, pass)}`} data-subject={g.name}>
              <span className="fm-grade__name">{g.name}</span>
              <Bar pct={g.g} cls="fm-bar--grade" />
              <span className="fm-grade__num">{g.g}</span>
              <small className={`fm-grade__delta${d === null || d === 0 ? '' : d > 0 ? ' is-up' : ' is-down'}`} aria-hidden>{d === null || d === 0 ? '' : d > 0 ? `+${d}` : d}</small>
            </li>
          );
        })}
      </ul>
      <p className={`fm-sch__avg is-${gradeTone(avg, pass)}`} data-testid="school-avg">
        Average <b>{avg}</b> · pass mark {pass} · {avg >= pass ? 'on track to be promoted' : 'would repeat the class'}
      </p>
    </div>
  );
}

// ------------------------------------------------------------------------------------------------ fee, helps
function FeeRow({ c, s, run, busy }: { c: KidChild; s: KidSchool; run: Run; busy: string | null }) {
  const f = s.fee;
  if (!f) return null;
  const name = c.name ?? 'Your child';
  if (f.paid) {
    return <div className="fm-sch__fee is-paid" data-testid="school-fee-paid"><span>✅ Fees paid</span><b>{naira(f.amount)}</b><small>{f.on_time ? 'in time' : 'a bit late'}</small></div>;
  }
  const left = secs(s.ends_at);
  return (
    <div className="fm-sch__fee is-due" data-testid="school-fee-due">
      <span className="fm-sch__feetxt">
        <b>Fees due: {naira(f.amount)}</b>
        <small>Pay before the class ends{left > 0 ? ` (${dur(left)} left)` : ''}, or {name} misses it and the grades drop.</small>
      </span>
      <Button variant="green" size="md" loading={busy === `sp:${c.id}`} disabled={busy !== null} onClick={() => run(`sp:${c.id}`, () => kidsSchoolPay(c.id))} data-testid="school-pay">
        Pay {naira(f.amount)}
      </Button>
    </div>
  );
}

function Helps({ c, s, run, busy, at }: { c: KidChild; s: KidSchool; run: Run; busy: string | null; at: number }) {
  const [buy, setBuy] = useState<SchoolGear | null>(null);
  const hw = s.homework;
  const les = s.lessons;
  const gear = s.gear ?? [];
  const name = c.name ?? 'your child';
  const wait = hw ? Math.max(0, hw.wait - (serverNow() - at) / 1000) : 0;
  const anyBtn = Boolean(hw) || Boolean(les) || gear.length > 0;
  if (!anyBtn) return null;
  const gearPress = (g: SchoolGear) => {
    if (g.applied) return;
    if (!g.have) { setBuy(buy?.kind === g.kind ? null : g); return; }
    setBuy(null);
    run(`sg:${c.id}:${g.kind}`, () => kidsSchoolGear(c.id, g.kind));
  };
  return (
    <>
      <div className="fm-sch__helps" role="group" aria-label={`Help ${name} at school`}>
        {hw && (
          <button type="button" className={`fm-help${hw.can ? '' : ' is-off'}`} aria-disabled={!hw.can || busy !== null} disabled={busy !== null && busy.startsWith('sh:')}
            onClick={() => (hw.can ? run(`sh:${c.id}`, () => kidsSchoolHomework(c.id)) : toast(hw.mine_done ? `You already helped in this class. ${hw.count} of ${hw.max} parents have.` : `Somebody helped just now. Try again in ${dur(wait)}.`, 'info'))}
            data-testid="school-homework">
            <span className="fm-help__icon" aria-hidden>📚</span>
            <span className="fm-help__label">Homework</span>
            <small>{busy === `sh:${c.id}` ? '...' : hw.mine_done ? 'Done ✓' : wait > 0 ? dur(wait) : `+${hw.pts} grades`}</small>
          </button>
        )}
        {les && (
          <button type="button" className={`fm-help${les.can ? '' : ' is-off'}`} aria-disabled={!les.can || busy !== null} disabled={busy !== null && busy.startsWith('sl:')}
            onClick={() => (les.can ? run(`sl:${c.id}`, () => kidsSchoolLessons(c.id)) : toast(`${name} already has a tutor for this class.`, 'info'))} data-testid="school-lessons">
            <span className="fm-help__icon" aria-hidden>🧑🏾‍🏫</span>
            <span className="fm-help__label">Extra lessons</span>
            <small>{busy === `sl:${c.id}` ? '...' : les.bought ? 'Booked ✓' : naira(les.cost)}</small>
          </button>
        )}
        {gear.map((g) => (
          <button key={g.kind} type="button" className={`fm-help${g.applied ? ' is-off' : ''}${!g.have && !g.applied ? ' is-missing' : ''}${buy?.kind === g.kind ? ' is-open' : ''}`}
            aria-disabled={g.applied || busy !== null} disabled={busy !== null && busy.startsWith('sg:')} onClick={() => gearPress(g)} data-testid={`school-${g.kind}`}>
            <span className="fm-help__icon" aria-hidden>{g.icon ?? (g.kind === 'books' ? '📚' : '🎒')}</span>
            <span className="fm-help__label">{g.kind === 'books' ? 'Textbooks' : 'Bag & uniform'}</span>
            <small>{busy === `sg:${c.id}:${g.kind}` ? '...' : g.applied ? 'Done ✓' : g.have ? `Give · +${g.pts}` : 'Buy first'}</small>
          </button>
        ))}
      </div>
      {buy && <BuyPanel msg={`No ${buy.name.toLowerCase()} at home. Buy it at Oba Market or the supermarket.`} places={buy.buy} name={name} onClose={() => setBuy(null)} />}
    </>
  );
}

function LastResult({ s }: { s: KidSchool }) {
  const l = s.last;
  if (!l) return null;
  const cls = l.promoted ? 'is-pass' : 'is-repeat';
  return (
    <p className={`fm-sch__last ${cls}`} data-testid="school-last" data-promoted={l.promoted ? '1' : '0'}>
      <span aria-hidden>{l.promoted ? '✅' : '↩︎'}</span>
      <span><b>{l.promoted ? 'Promoted' : 'Repeating'}</b> {l.class_name}{l.attended ? ` · average ${Math.round(l.avg)}` : ' · missed (fee unpaid)'}</span>
    </p>
  );
}

// ------------------------------------------------------------------------------------------------ WAEC and university
function WaecCard({ w, name }: { w: Waec; name: string }) {
  return (
    <div className={`fm-waec ${w.pass ? 'is-pass' : 'is-fail'}`} data-testid="school-waec">
      <span className="fm-waec__kicker">WAEC result</span>
      <b className="fm-waec__text">{w.pass ? `${name} passed: ${w.text}` : `${name} got ${w.text}`}</b>
      <ul className="fm-waec__papers" aria-label="WAEC papers">
        {w.papers.map((p) => (
          <li key={p.id} className={p.credit ? 'is-credit' : ''}><span>{p.name}</span><b>{p.letter}</b></li>
        ))}
      </ul>
      <p className="fm-fine">{w.pass ? 'A credit is C6 or better. Passing WAEC lets the parents send them to university on day 21.' : `${w.need} credits including Maths and English are needed. ${name} will move out on day 21.`}</p>
    </div>
  );
}

function UniCard({ c, s, run, busy, at }: { c: KidChild; s: KidSchool; run: Run; busy: string | null; at: number }) {
  const u = s.uni;
  if (!u) return null;
  const name = c.name ?? 'Your child';
  const left = secs(s.ends_at);
  return (
    <div className="fm-uni" data-testid="school-uni">
      <div className="fm-sch__head">
        <span className="fm-sch__icon" aria-hidden>{s.school?.icon ?? '🎓'}</span>
        <span className="fm-sch__title">
          <b>{u.level_name} · {u.course}</b>
          <small>{s.school?.name}{u.repeats > 0 ? ` · repeat ${u.repeats} of ${u.max_repeats}` : ''}</small>
          {left > 0 && <small className="fm-sch__left">⏳ {dur(left)} left in this level</small>}
        </span>
      </div>
      <FeeRow c={c} s={s} run={run} busy={busy} />
      <Grades s={s} name={name} />
      <Helps c={c} s={s} run={run} busy={busy} at={at} />
      <LastResult s={s} />
      <p className="fm-fine">400 level is the last. {u.max_repeats} repeats are allowed; after that {name} leaves university. Send pocket money and attention above to keep {name} well.</p>
    </div>
  );
}

// ------------------------------------------------------------------------------------------------ enrol
function EnrolPicker({ c, onClose, run, busy }: { c: KidChild; onClose: () => void; run: Run; busy: string | null }) {
  const [opts, setOpts] = useState<{ level: string | null; schools: SchoolOption[] } | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const [sel, setSel] = useState<string | null>(null);
  useEffect(() => {
    let live = true;
    kidsSchoolSchools(c.id).then((r) => { if (live) { setOpts(r); setSel(r.schools.find((x) => x.current)?.id ?? null); } }).catch((e) => { if (live) setErr(errorMessage(e)); });
    return () => { live = false; };
  }, [c.id]);
  const pick = opts?.schools.find((x) => x.id === sel) ?? null;
  const name = c.name ?? 'your child';
  const go = () => {
    if (!pick || pick.current) return;
    run(`se:${c.id}`, () => kidsSchoolEnrol(c.id, pick.id));
    onClose();
  };
  return (
    <Modal open onClose={onClose} title={`Pick a ${opts?.level ? LEVEL_WORD[opts.level] : ''} school for ${name}`}
      actions={<>
        <Button variant="ghost" onClick={onClose}>Not now</Button>
        <Button variant="green" disabled={!pick || pick.current || busy !== null} onClick={go} data-testid="school-enrol-go">{pick ? (pick.current ? 'Already there' : `Enrol at ${shortName(pick.name)}`) : 'Pick a school'}</Button>
      </>}>
      <div className="fm-enrol" data-testid="school-picker">
        <p className="fm-fine">Each class has a fee. A better school costs more and lifts every grade. You can change school between classes, before the fee is paid.</p>
        {err && <p className="fm-warn">{err}</p>}
        {!opts && !err && <div className="panel-skel"><span /><span /></div>}
        {opts && opts.schools.length === 0 && <p className="fm-warn">No school is open for this level right now. Check back soon.</p>}
        <ul className="fm-schools" role="radiogroup" aria-label="Schools">
          {opts?.schools.map((o) => (
            <li key={o.id}>
              <button type="button" role="radio" aria-checked={sel === o.id} className={`fm-school${sel === o.id ? ' is-on' : ''}`} onClick={() => setSel(o.id)} data-testid={`school-opt-${o.id}`}>
                <span className="fm-school__icon" aria-hidden>{o.icon}</span>
                <span className="fm-school__txt">
                  <b>{o.name}</b>
                  <small>{o.blurb}</small>
                  <span className="fm-school__meta">
                    <i className={`fm-tier fm-tier--${o.tier}`}>{TIER_WORD[o.tier] ?? o.tier}</i>
                    <i>{naira(o.fee)} a {o.levels.includes('university') ? 'level' : 'class'}</i>
                    <i>{o.quality > 0 ? `+${o.quality}% grades` : 'no grade boost'}</i>
                    {o.area && <i>{o.area}</i>}
                    {o.current && <i className="is-now">current</i>}
                  </span>
                </span>
              </button>
            </li>
          ))}
        </ul>
      </div>
    </Modal>
  );
}

// ------------------------------------------------------------------------------------------------ report cards
function shareText(name: string, r: ReportCard): string {
  return [
    `${name}'s ${r.title.toLowerCase()}${r.school ? ` · ${r.school}` : ''}`,
    r.grades.map((g) => `${g.name} ${g.g}`).join(' · '),
    `Average ${Math.round(r.avg)} · ${r.position}${r.extra ? ` · ${r.extra}` : ''}`,
    `"${r.remark}" ${r.teacher}`,
    '#BeninLife',
  ].join('\n');
}

function ReportCardView({ name, r }: { name: string; r: ReportCard }) {
  const stamp = r.stage === 'university' ? (r.promoted ? 'GRADUATED' : 'LEFT UNI') : r.promoted ? 'PROMOTED' : 'LEFT SCHOOL';
  const share = async () => {
    const text = shareText(name, r);
    try {
      if (typeof navigator.share === 'function') {
        await navigator.share({ title: `${name}'s ${r.title}`, text });
        return;
      }
    } catch (e) {
      if ((e as { name?: string }).name === 'AbortError') return;
    }
    try {
      await navigator.clipboard.writeText(text);
      toast('Report card copied. Paste it anywhere to share 📋', 'good');
    } catch {
      toast(text, 'info');
    }
  };
  return (
    <article className={`fm-rc fm-rc--${r.position.replace(' ', '-').toLowerCase()}`} data-testid="report-card" data-stage={r.stage}>
      <header className="fm-rc__head">
        <small>{r.school || 'School'}</small>
        <b>{r.title}</b>
      </header>
      <p className="fm-rc__name">{name}</p>
      <ul className="fm-rc__grades" aria-label="Grades">
        {r.grades.map((g) => (
          <li key={g.name}><span>{g.name}</span><Bar pct={g.g} cls="fm-bar--grade" /><b>{g.g}</b></li>
        ))}
      </ul>
      <div className="fm-rc__total"><span>Average <b>{Math.round(r.avg)}</b></span><span className="fm-rc__pos" data-testid="report-position">{r.position}</span></div>
      {r.extra && <p className="fm-rc__extra">{r.extra}</p>}
      <blockquote className="fm-rc__remark">“{r.remark}”<footer>{r.teacher}, class teacher</footer></blockquote>
      <span className={`fm-rc__stamp${r.promoted ? '' : ' is-no'}`} aria-hidden>{stamp}</span>
      <Button variant="green" block onClick={() => void share()} data-testid="report-share">Share report card</Button>
    </article>
  );
}

function ReportCardsModal({ childId, name, onClose }: { childId: number; name: string; onClose: () => void }) {
  const [cards, setCards] = useState<ReportCard[] | null>(null);
  const [err, setErr] = useState<string | null>(null);
  useEffect(() => {
    let live = true;
    kidsReportCards(childId).then((r) => { if (live) setCards(r.cards); }).catch((e) => { if (live) setErr(errorMessage(e)); });
    return () => { live = false; };
  }, [childId]);
  return (
    <Modal open onClose={onClose} title={`${name}'s report cards`} actions={<Button variant="ghost" onClick={onClose}>Close</Button>}>
      <div className="fm-rcs" data-testid="report-cards">
        {err && <p className="fm-warn">{err}</p>}
        {!cards && !err && <div className="panel-skel"><span /><span /></div>}
        {cards && cards.length === 0 && <p className="fm-fine">No report cards yet. The first one comes at the end of Nursery.</p>}
        {cards?.map((r) => <ReportCardView key={r.id} name={name} r={r} />)}
      </div>
    </Modal>
  );
}

/** "Report cards (3)" link: opens the list. Used inside the School panel and on grown-up children. */
export function ReportCardsButton({ childId, name, count }: { childId: number; name: string; count: number }) {
  const [open, setOpen] = useState(false);
  if (count <= 0) return null;
  return (
    <>
      <button type="button" className="fm-sch__link" onClick={() => setOpen(true)} data-testid="school-cards">📋 Report cards ({count})</button>
      {open && <ReportCardsModal childId={childId} name={name} onClose={() => setOpen(false)} />}
    </>
  );
}

// ------------------------------------------------------------------------------------------------ the panel
export function SchoolPanel({ c, run, busy, at }: { c: KidChild; run: Run; busy: string | null; at: number }) {
  useTick(true);
  const [pick, setPick] = useState(false);
  const s = c.school;
  if (!s || !s.enabled) return null;
  const name = c.name ?? 'Your child';
  if (c.status === 'with_relatives') {
    return s.state === 'none' ? null : <section className="fm-sch is-calm" data-testid="school-panel"><b>🎒 School is paused while {name} stays with relatives</b></section>;
  }

  if (s.state === 'none') {
    if (s.can_enrol) {
      return (
        <section className="fm-sch fm-sch--start" data-testid="school-panel" data-state="none">
          <div className="fm-sch__head"><span className="fm-sch__icon" aria-hidden>🎒</span><span className="fm-sch__title"><b>School</b><small>{name} is old enough for {s.level ? LEVEL_WORD[s.level] : ''} school</small></span></div>
          <p className="fm-fine">Pick a school, pay each class fee and help with homework. The grades decide how {name} turns out when they grow up.</p>
          <Button variant="green" size="lg" block onClick={() => setPick(true)} data-testid="school-find">Find a school 🏫</Button>
          {pick && <EnrolPicker c={c} onClose={() => setPick(false)} run={run} busy={busy} />}
        </section>
      );
    }
    const left = secs(s.starts_at);
    return (
      <section className="fm-sch is-calm" data-testid="school-panel" data-state="none">
        <b>🎒 School</b>
        <p className="fm-fine">School starts at Nursery{left > 0 ? `, in about ${dur(left)}` : ''}. You will choose a school here.</p>
      </section>
    );
  }

  if (s.state === 'university') return <section className="fm-sch fm-sch--uni" data-testid="school-panel" data-state="university"><UniCard c={c} s={s} run={run} busy={busy} at={at} /><div className="fm-sch__foot"><ReportCardsButton childId={c.id} name={name} count={s.cards} /></div></section>;

  if (s.state === 'deciding') {
    const left = secs(s.uni?.deadline);
    return (
      <section className="fm-sch fm-sch--uni" data-testid="school-panel" data-state="deciding">
        <div className="fm-sch__head"><span className="fm-sch__icon" aria-hidden>🎓</span><span className="fm-sch__title"><b>University or work?</b><small>{name} passed WAEC</small></span></div>
        {s.waec && <WaecCard w={s.waec} name={name} />}
        <p className="fm-warn" data-testid="school-deciding">You and {c.partner ? `@${c.partner.username}` : 'the other parent'} each got a card: UNIBEN, Edo Royal University or work. The first to answer decides{left > 0 ? `, within ${dur(left)}` : ''}.</p>
        <div className="fm-sch__foot"><ReportCardsButton childId={c.id} name={name} count={s.cards} /></div>
      </section>
    );
  }

  const cls = s.class;
  const toStart = secs(s.starts_at);
  return (
    <section className="fm-sch" data-testid="school-panel" data-state={s.state} data-class={cls?.code}>
      <div className="fm-sch__head">
        <span className="fm-sch__icon" aria-hidden>{s.school?.icon ?? '🎒'}</span>
        <span className="fm-sch__title">
          <b>{s.state === 'finished' ? 'Secondary school done' : `${cls?.name ?? 'School'}${s.school ? ` · ${shortName(s.school.name)}` : ''}`}</b>
          <small>{s.school?.name ?? 'No school yet'}{(s.attempt ?? 1) > 1 && s.state === 'learning' ? ` · try ${s.attempt}` : ''}</small>
          {s.state === 'learning' && secs(s.ends_at) > 0 && <small className="fm-sch__left">⏳ {dur(secs(s.ends_at))} left in this class</small>}
        </span>
      </div>

      {s.state === 'need_school' && (
        <div className="fm-sch__need" data-testid="school-need">
          <p className="fm-warn">{name} is ready for <b>{cls?.name}</b>. {s.school ? `${shortName(s.school.name)} does not teach ${s.level}` : 'Pick a school'}: choose a {s.level ? LEVEL_WORD[s.level] : ''} school so the class can start.</p>
          <Button variant="green" size="lg" block onClick={() => setPick(true)} data-testid="school-find">Pick a school 🏫</Button>
        </div>
      )}
      {s.state === 'waiting' && <p className="fm-fine" data-testid="school-waiting">Next class: <b>{cls?.name}</b> starts {toStart > 0 ? `in ${dur(toStart)}` : 'any moment now'}.</p>}
      {s.state === 'learning' && <><FeeRow c={c} s={s} run={run} busy={busy} /><Grades s={s} name={name} /></>}
      {s.state === 'finished' && s.waec && <WaecCard w={s.waec} name={name} />}
      {(s.state === 'learning' || s.state === 'waiting' || s.state === 'need_school') && <Helps c={c} s={s} run={run} busy={busy} at={at} />}
      {s.request && s.request.status === 'open' && s.state === 'learning' && <p className="fm-sch__req" data-testid="school-request">🏫 The school sent a request. Check the card that popped up: Pay, Later or Ignore.</p>}
      <LastResult s={s} />
      <div className="fm-sch__foot">
        <ReportCardsButton childId={c.id} name={name} count={s.cards} />
        {s.can_switch && s.state === 'learning' && <button type="button" className="fm-sch__link" onClick={() => setPick(true)} data-testid="school-switch">Change school</button>}
      </div>
      {pick && <EnrolPicker c={c} onClose={() => setPick(false)} run={run} busy={busy} />}
    </section>
  );
}
