import { useEffect } from 'react';
import { timeAgo, titleCase } from '../../lib/format';
import { eventTone, useGame } from '../../state/game';
import { useUi } from '../../state/ui';
import { EmptyState, Icon, Sheet } from '../../ui';

/** The alerts list (used by the Alerts sheet and the phone's Alerts app). Opening it marks everything read. */
export function AlertsList({ active }: { active: boolean }) {
  const events = useGame((s) => s.events);
  const lastRead = useGame((s) => s.lastReadEventId);
  const markEventsRead = useGame((s) => s.markEventsRead);

  // Opening the list marks everything as read (client-side; events have no client update policy).
  useEffect(() => {
    if (active) {
      const id = window.setTimeout(markEventsRead, 1200);
      return () => window.clearTimeout(id);
    }
  }, [active, markEventsRead]);

  if (events.length === 0) {
    return <EmptyState icon="bell" title="No alerts yet" body="Paydays, police visits, ready harvests and more will show up here." />;
  }
  return (
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
  );
}

export function AlertsSheet() {
  const overlay = useUi((s) => s.overlay);
  const setOverlay = useUi((s) => s.setOverlay);
  const open = overlay === 'alerts';
  return (
    <Sheet open={open} onClose={() => setOverlay(null)} title="Alerts" subtitle="What has happened to you lately" size="tall">
      <AlertsList active={open} />
    </Sheet>
  );
}
