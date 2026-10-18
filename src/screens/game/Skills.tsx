// R3 Skills (docs/SKILLS.md): the Skills tab of the Sim sheet and <SkillHost/> (the level-up toast with confetti).
// All numbers come from skills_status(); the client never sends XP.
import { useEffect } from 'react';
import { useSkills } from '../../state/skills';
import { useUi } from '../../state/ui';
import type { SkillRow } from '../../api/skills';
import './Skills.css';

const KIND_ICON: Record<string, string> = { hustle: '💪', yahoo: '💻', career: '💼', activity: '📍' };

function SkillCardView({ s, max }: { s: SkillRow; max: number }) {
  const atMax = s.next_xp == null;
  return (
    <article className="sk-card" data-testid={`skill-${s.id}`}>
      <div className="sk-card__top">
        <span className="sk-card__icon" aria-hidden>{s.icon}</span>
        <span className="sk-card__main">
          <b>{s.name}</b>
          <small>{s.blurb}</small>
        </span>
        <span className="sk-lvl" aria-label={`Level ${s.level} of ${max}`}><small>Lvl</small>{s.level}</span>
      </div>
      <div className="sk-bar" role="progressbar" aria-valuemin={0} aria-valuemax={100} aria-valuenow={Math.round(s.pct)} aria-label={`${s.name} XP`}>
        <i style={{ width: `${Math.max(2, Math.min(100, s.pct))}%` }} />
      </div>
      <div className="sk-xp">
        <span>{s.xp.toLocaleString('en-NG')} XP</span>
        <span>{atMax ? 'Max level' : `${(s.next_xp! - s.xp).toLocaleString('en-NG')} to level ${s.level + 1}`}</span>
      </div>
      <div className="sk-chips">
        {s.pay_pct != null && s.pay_pct > 0 && <span className="sk-chip is-ok">+{s.pay_pct}% hustle pay</span>}
        {s.caught_cut_pct != null && <span className="sk-chip is-ok">EFCC chance −{s.caught_cut_pct}%</span>}
      </div>
      <p className="sk-next">
        <b>{atMax ? 'Maxed out. Respect!' : `Level ${s.level + 1} gives:`}</b>{' '}
        {!atMax && (s.next_unlocks.length ? s.next_unlocks.join(' · ') : 'Keep training, e dey show.')}
      </p>
      <p className="sk-train"><span aria-hidden>🎯</span> {s.train_text || 'Train by doing the actions below.'}</p>
      {s.train.length > 0 && (
        <div className="sk-chips">
          {s.train.slice(0, 6).map((t) => (
            <span key={`${t.kind}:${t.ref}`} className="sk-chip">{KIND_ICON[t.kind] ?? '•'} {t.name} +{t.xp}</span>
          ))}
        </div>
      )}
    </article>
  );
}

export function SkillsTab() {
  const status = useSkills((s) => s.status);
  const load = useSkills((s) => s.load);
  useEffect(() => { void load(); }, [load]);
  if (!status) return <div className="sim-tab stack"><div className="sk-skel" /><div className="sk-skel" /></div>;
  if (!status.enabled) return <div className="sim-tab stack"><p className="muted">Skills are switched off for now.</p></div>;
  return (
    <div className="sim-tab stack" data-testid="skills-tab">
      <p className="muted sk-intro">Hustle, drive, cook, DJ. Every run trains a skill. Higher levels pay more and open the big jobs.</p>
      {status.skills.map((s) => <SkillCardView key={s.id} s={s} max={status.max_level} />)}
    </div>
  );
}

/** The level-up toast: shows the newest skill_up, with confetti, then slides away. */
export function SkillHost() {
  const lu = useSkills((s) => s.queue[0]);
  const dismiss = useSkills((s) => s.dismiss);
  const openSim = useUi((s) => s.openSim);
  useEffect(() => {
    if (!lu) return;
    const t = window.setTimeout(dismiss, 6500);
    return () => window.clearTimeout(t);
  }, [lu, dismiss]);
  if (!lu) return null;
  return (
    <button type="button" key={lu.id} className="sk-up" data-testid="skill-levelup" onClick={() => { dismiss(); openSim('skills'); }}
      aria-live="polite" aria-label={`${lu.name} level ${lu.level}. Open Skills`}>
      <span className="sk-up__confetti" aria-hidden>{Array.from({ length: 22 }, (_, i) => <i key={i} style={{ ['--i' as string]: i }} />)}</span>
      <span className="sk-up__icon" aria-hidden>{lu.icon}</span>
      <span className="sk-up__text">
        <small>Level up!</small>
        <b>{lu.name} level {lu.level}</b>
        <em>{lu.unlocks.length ? lu.unlocks.join(' · ') : 'Keep training, e dey show.'}</em>
      </span>
    </button>
  );
}
