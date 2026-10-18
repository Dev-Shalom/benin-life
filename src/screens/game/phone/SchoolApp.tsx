// R4 School app (docs/SCHOOL.md): every course with fee, classes, progress, where to go, what the certificate unlocks and one button
// (Enrol / Start class / Go to <place>). Behaves like the Hustles app: classes run on the server, you cannot stop one halfway,
// missing days never resets progress.
import { useEffect, useState } from 'react';
import { courseEnrol, courseStartClass, type Certificate, type Course } from '../../../api/school';
import { errorMessage } from '../../../lib/api';
import { useNow } from '../../../lib/clock';
import { countdown, naira, secondsUntil } from '../../../lib/format';
import type { GameState } from '../../../lib/types';
import { useGame } from '../../../state/game';
import { useSchool } from '../../../state/school';
import { toast } from '../../../ui';
import './SchoolApp.css';

function CourseCard({ c, free, now, busy, onEnrol, onStart, onGo }: {
  c: Course; free: boolean; now: number; busy: string | null; onEnrol: (c: Course) => void; onStart: (c: Course) => void; onGo: (id: string) => void;
}) {
  const nearest = c.places.find((p) => p.open) ?? c.places[0];
  const where = c.places.map((p) => p.name.replace(/\s*\(.*\)$/, '')).slice(0, 2).join(' · ') || c.where_text;
  const wait = c.next_class_at ? Math.max(0, secondsUntil(c.next_class_at, now)) : 0;
  const pct = c.classes > 0 ? Math.round((c.done / c.classes) * 100) : 0;
  const blocker = c.locked && c.locked.hint !== 'wrong_place' ? c.locked : null;
  let action: React.ReactNode;
  if (c.state === 'completed') {
    action = <p className="sc-done">✅ Done. {c.cert ? `${c.cert.icon} ${c.cert.name} certificate earned.` : 'Well done.'}</p>;
  } else if (c.state === 'new') {
    const lock = c.enrol_why;
    action = (
      <button type="button" className="sc-btn" data-testid={`course-enrol-${c.id}`} disabled={Boolean(lock) || busy === c.id} onClick={() => onEnrol(c)}>
        {lock ? lock.short : `Enrol · ${naira(c.fee)}`}
      </button>
    );
  } else if (!c.here && c.here_why?.hint === 'wrong_place' && nearest) {
    action = <button type="button" className="sc-btn sc-btn--ghost" onClick={() => onGo(nearest.id)}>Go to {nearest.name.replace(/\s*\(.*\)$/, '')}</button>;
  } else if (blocker && blocker.hint === 'cooldown') {
    action = <button type="button" className="sc-btn sc-btn--ghost" disabled>Next class in {countdown(wait > 0 ? wait : blocker.wait_seconds ?? 0)}</button>;
  } else if (blocker) {
    action = <button type="button" className="sc-btn sc-btn--ghost" disabled>{blocker.short}</button>;
  } else if (!c.here && c.here_why) {
    action = <button type="button" className="sc-btn sc-btn--ghost" disabled>{c.here_why.short}</button>;
  } else if (!free) {
    action = <button type="button" className="sc-btn sc-btn--ghost" disabled>Busy</button>;
  } else {
    action = (
      <button type="button" className="sc-btn" data-testid={`course-start-${c.id}`} disabled={busy === c.id} onClick={() => onStart(c)}>
        {c.final_next && c.exam ? `Sit the exam · ${c.class_seconds}s` : `Start class ${c.done + 1} · ${c.class_seconds}s`}
      </button>
    );
  }
  return (
    <article className={`sc-card sc-card--${c.state}`} data-testid={`course-${c.id}`}>
      <div className="sc-card__top">
        <span className="sc-card__icon" aria-hidden>{c.icon}</span>
        <span className="sc-card__main">
          <b>{c.name}</b>
          <small>{c.blurb}</small>
        </span>
      </div>
      {c.state !== 'new' && (
        <div className="sc-prog" aria-label={`${c.done} of ${c.classes} classes`}>
          <div className="sc-bar"><span style={{ width: `${pct}%` }} /></div>
          <small>{c.done}/{c.classes} classes{c.module_now && c.state === 'enrolled' ? ` · ${c.module_now}` : ''}{c.state === 'enrolled' && c.exam && c.exam.fails > 0 ? ` · exam retake (${c.exam.fails} fail${c.exam.fails === 1 ? '' : 's'})` : ''}</small>
        </div>
      )}
      <div className="sc-chips">
        <span className="sc-chip is-pay">{c.fee > 0 ? naira(c.fee) : 'Free'}</span>
        <span className="sc-chip">📚 {c.classes} classes</span>
        <span className="sc-chip">⏱ {c.class_game_minutes >= 60 ? `${Math.round(c.class_game_minutes / 6) / 10}h` : `${c.class_game_minutes}m`} class · {c.class_seconds}s</span>
        <span className="sc-chip">{c.cooldown_days > 0 ? `1 class every ${c.cooldown_days === 1 ? 'game day' : `${c.cooldown_days} game days`}` : 'No wait between classes'}</span>
        <span className="sc-chip">📍 {where}</span>
        {c.hours && <span className="sc-chip">🕗 {c.hours}</span>}
        <span className="sc-chip">⚡ −{c.energy_cost} energy</span>
        {c.skill && <span className="sc-chip is-ok">{c.skill.icon} +{c.skill.xp_per_class} {c.skill.name} XP / class</span>}
        {c.exam && <span className="sc-chip is-risk" title={c.exam.text}>📝 Final exam: {Math.round(c.exam.chance_now)}% pass chance now</span>}
        {c.prereq.certs.map((p) => <span key={p.id} className={`sc-chip${p.ok ? ' is-ok' : ' is-need'}`}>{p.ok ? '✓' : '🔒'} {p.name} certificate first</span>)}
        {c.prereq.skill && <span className={`sc-chip${c.prereq.skill.ok ? ' is-ok' : ' is-need'}`}>{c.prereq.skill.ok ? '✓' : '🔒'} {c.prereq.skill.icon} {c.prereq.skill.name} lvl {c.prereq.skill.need} (you: {c.prereq.skill.have})</span>}
      </div>
      {c.unlocks.length > 0 && (
        <ul className="sc-unlocks" aria-label="What the certificate unlocks">
          {c.unlocks.map((u) => <li key={u}>{u}</li>)}
        </ul>
      )}
      {action}
    </article>
  );
}

function CertStrip({ certs }: { certs: Certificate[] }) {
  return (
    <section className="sc-top" data-testid="school-certs">
      <div className="sc-top__head"><small>My certificates</small><b>{certs.length}</b></div>
      {certs.length === 0
        ? <p>No certificate yet. Enrol, attend the classes, and e go open better jobs.</p>
        : <ul className="sc-certs">{certs.map((c) => <li key={c.id} className="sc-cert"><span aria-hidden>{c.icon}</span> {c.name}</li>)}</ul>}
    </section>
  );
}

export default function SchoolApp({ state, onGo }: { state: GameState; onGo: (id: string) => void }) {
  const s = useSchool((x) => x.status);
  const run = useSchool((x) => x.run);
  const last = useSchool((x) => x.last);
  const refresh = useGame((x) => x.refresh);
  const now = useNow(1000);
  const [busy, setBusy] = useState<string | null>(null);

  useEffect(() => { void useSchool.getState().load(); }, [state.profile.location_id]);

  if (!s) return <div className="phone-app__body sc"><div className="sc-skel"><span /><span /><span /></div></div>;
  if (!s.enabled) return <div className="phone-app__body sc"><p className="sc-note">School is switched off for now.</p></div>;
  const free = !run && !(state.profile.busy_until && Date.parse(state.profile.busy_until) > now)
    && !(state.profile.jailed_until && Date.parse(state.profile.jailed_until) > now) && !state.travel;

  const enrol = async (c: Course) => {
    setBusy(c.id);
    try {
      const r = await courseEnrol(c.id);
      toast(r.message, 'good');
      await Promise.all([useSchool.getState().load(), refresh()]);
    } catch (e) { toast(errorMessage(e), 'bad'); void useSchool.getState().load(); } finally { setBusy(null); }
  };
  const start = async (c: Course) => {
    setBusy(c.id);
    try {
      const r = await courseStartClass(c.id);
      toast(r.message, 'info');
      useSchool.getState().started({ id: r.run_id, course_id: r.course_id, name: r.name, icon: r.icon, class_no: r.class_no, started_at: r.started_at,
        resolve_at: r.resolve_at, status: 'running', outcome: null, xp: 0, message: null });
      void refresh();
    } catch (e) { toast(errorMessage(e), 'bad'); void useSchool.getState().load(); } finally { setBusy(null); }
  };

  const runLeft = run ? secondsUntil(run.resolve_at, now) : 0;
  const runPct = run ? Math.min(100, Math.max(0, (1 - runLeft / Math.max(1, (Date.parse(run.resolve_at) - Date.parse(run.started_at)) / 1000)) * 100)) : 0;
  const groups: { id: string; title: string; list: Course[] }[] = [
    { id: 'now', title: 'In progress', list: s.courses.filter((c) => c.state === 'enrolled') },
    { id: 'new', title: 'Available', list: s.courses.filter((c) => c.state === 'new') },
    { id: 'done', title: 'Completed', list: s.courses.filter((c) => c.state === 'completed') },
  ];
  return (
    <div className="phone-app__body sc" data-testid="school-app">
      <CertStrip certs={s.certificates} />
      {run && (
        <section className="sc-run" role="status" data-testid="class-run">
          <span aria-hidden>{run.icon}</span>
          <span className="sc-run__main"><b>{run.name} · class {run.class_no}</b><div className="sc-bar"><span style={{ width: `${runPct}%` }} /></div></span>
          <span className="sc-run__t">{countdown(runLeft)}</span>
        </section>
      )}
      {!run && last && last.status === 'done' && (
        <p className={`sc-last${last.outcome === 'fail' ? ' is-bad' : ''}`}>{last.icon} {last.message}</p>
      )}
      {groups.map((g) => g.list.length > 0 && (
        <section key={g.id}>
          <h4 className="sc-h">{g.title}</h4>
          {g.list.map((c) => <CourseCard key={c.id} c={c} free={free} now={now} busy={busy} onEnrol={(x) => void enrol(x)} onStart={(x) => void start(x)} onGo={onGo} />)}
        </section>
      ))}
      <p className="sc-note">Classes happen at the course&apos;s place and cannot be stopped halfway. Miss some days? Your progress is safe. Fees, classes, exams and pay bonuses are set by the admin.</p>
    </div>
  );
}
