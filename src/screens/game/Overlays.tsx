import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { AvatarPortrait } from '../../art/avatar3d';
import { naira, timeAgo, titleCase } from '../../lib/format';
import { P, randomTip } from '../../lib/pidgin';
import { eventTone, useGame } from '../../state/game';
import { useUi } from '../../state/ui';
import { Button, EmptyState, Icon, Sheet } from '../../ui';

export function AlertsSheet() {
  const overlay = useUi((s) => s.overlay);
  const setOverlay = useUi((s) => s.setOverlay);
  const events = useGame((s) => s.events);
  const lastRead = useGame((s) => s.lastReadEventId);
  const markEventsRead = useGame((s) => s.markEventsRead);
  const open = overlay === 'alerts';

  // Opening the list marks everything as read (client-side; events have no client update policy).
  useEffect(() => {
    if (open) {
      const id = window.setTimeout(markEventsRead, 1200);
      return () => window.clearTimeout(id);
    }
  }, [open, markEventsRead]);

  return (
    <Sheet open={open} onClose={() => setOverlay(null)} title="Alerts" subtitle="What has happened to you lately" size="tall">
      {events.length === 0 ? (
        <EmptyState icon="bell" title="No alerts yet" body="Paydays, police visits, ready harvests and more will show up here." />
      ) : (
        <ul className="alerts">
          {events.map((e) => {
            const tone = eventTone(e.kind);
            return (
              <li key={e.id} className={`alert alert--${tone}${e.id > lastRead && !e.read ? ' is-new' : ''}`}>
                <span className="alert__icon">
                  <Icon name={tone === 'bad' ? 'warning' : tone === 'good' ? 'sparkle' : 'bell'} size={16} />
                </span>
                <div className="grow">
                  <div className="alert__title">{e.title}</div>
                  {e.body && <div className="alert__body">{e.body}</div>}
                  <div className="alert__meta">{titleCase(e.kind)} · {timeAgo(e.created_at)}</div>
                </div>
              </li>
            );
          })}
        </ul>
      )}
    </Sheet>
  );
}

export function SettingsSheet() {
  const overlay = useUi((s) => s.overlay);
  const setOverlay = useUi((s) => s.setOverlay);
  const state = useGame((s) => s.state);
  const session = useGame((s) => s.session);
  const signOut = useGame((s) => s.signOut);
  const nav = useNavigate();
  const [tip] = useState(randomTip);
  const p = state?.profile;

  return (
    <Sheet open={overlay === 'settings'} onClose={() => setOverlay(null)} title="Settings">
      {p && (
        <div className="stack">
          <div className="settings-me card">
            <span className="hud-portrait"><AvatarPortrait config={p.avatar} size={56} /></span>
            <div className="grow">
              <b style={{ fontSize: 18 }}>{p.username}</b>
              <div className="muted" style={{ fontSize: 13 }}>{session?.user.email}</div>
              <div className="row" style={{ marginTop: 6, flexWrap: 'wrap', gap: 6 }}>
                <span className="chip"><Icon name="cash" size={12} /> {naira(p.cash)}</span>
                <span className="chip"><Icon name="bank" size={12} /> {naira(p.bank)}</span>
                <span className="chip"><Icon name="star" size={12} /> Cred {p.street_cred}</span>
              </div>
            </div>
          </div>
          <div className="card tip-card">
            <Icon name="info" size={18} />
            <p>{tip}</p>
          </div>
          {p.is_admin && (
            <Button variant="gold" icon="crown" block onClick={() => nav('/admin')}>Open admin panel</Button>
          )}
          <Button variant="ghost" icon="logout" block onClick={() => { setOverlay(null); void signOut(); }}>
            {P.logout}
          </Button>
          <p className="hint" style={{ textAlign: 'center' }}>
            <span className="age-badge">18+</span> {P.ageNote}
          </p>
        </div>
      )}
    </Sheet>
  );
}
