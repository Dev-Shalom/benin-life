// R4 School (docs/SCHOOL.md): <SchoolHost/> follows my class state (finishes a class whose timer ran out, also after a reload) and shows the
// graduation toast with confetti, plus <CertificatesCard/> for the Sim sheet profile.
import { useEffect } from 'react';
import { startSchool, useSchool } from '../../state/school';
import { useUi } from '../../state/ui';
import './School.css';

export function SchoolHost() {
  const g = useSchool((s) => s.queue[0]);
  const dismiss = useSchool((s) => s.dismiss);
  const openPhone = useUi((s) => s.openPhone);
  useEffect(() => startSchool(), []);
  useEffect(() => {
    if (!g) return;
    const t = window.setTimeout(dismiss, 7500);
    return () => window.clearTimeout(t);
  }, [g, dismiss]);
  if (!g) return null;
  return (
    <button type="button" key={g.id} className="sc-grad" data-testid="graduation-toast" onClick={() => { dismiss(); openPhone('school'); }}
      aria-live="polite" aria-label={`${g.title} Open School`}>
      <span className="sc-grad__confetti" aria-hidden>{Array.from({ length: 28 }, (_, i) => <i key={i} style={{ ['--i' as string]: i }} />)}</span>
      <span className="sc-grad__icon" aria-hidden>{g.icon}</span>
      <span className="sc-grad__text">
        <small>Graduation!</small>
        <b>{g.title}</b>
        <em>{g.unlocks.length ? g.unlocks.slice(0, 3).join(' · ') : 'E don show for your profile.'}</em>
      </span>
    </button>
  );
}

/** The Sim sheet's Profile tab: the certificates I hold (empty state points at the School app). */
export function CertificatesCard() {
  const status = useSchool((s) => s.status);
  const openPhone = useUi((s) => s.openPhone);
  useEffect(() => { if (!status) void useSchool.getState().load(); }, [status]);
  if (status && !status.enabled) return null;
  const certs = status?.certificates ?? [];
  return (
    <section className="sim-card" data-testid="sim-certificates">
      <h4 className="sim-card__title">Certificates</h4>
      {certs.length === 0 ? (
        <div className="sc-cert-empty">
          <span aria-hidden>🎓</span>
          <span className="grow muted">No certificates yet. Learn something and get better jobs.</span>
          <button type="button" className="sc-link" onClick={() => openPhone('school')}>School</button>
        </div>
      ) : (
        <ul className="sc-certs">
          {certs.map((c) => (
            <li key={c.id} className="sc-cert" data-testid={`cert-${c.id}`}>
              <span aria-hidden>{c.icon}</span>
              <b>{c.name}</b>
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}
