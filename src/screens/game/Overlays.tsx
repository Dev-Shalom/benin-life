import { useEffect } from 'react';
import { timeAgo, titleCase } from '../../lib/format';
import { eventTone, useGame } from '../../state/game';
import { useUi } from '../../state/ui';
import { EmptyState, Icon, Sheet } from '../../ui';
import { useBroadcasts } from '../../state/broadcasts';
import { BroadcastList } from './Broadcasts';

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

  const hasBroadcasts = useBroadcasts((s) => s.rows.length > 0);
  if (events.length === 0 && !hasBroadcasts) {
    return <EmptyState icon="bell" title="No alerts yet" body="Paydays, police visits, ready harvests and more will show up here." />;
  }
  return (
    <>
    <BroadcastList active={active} />
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
              {(e.kind.startsWith('love_') || e.kind.startsWith('kids_')) && (
                <button type="button" className="alert__go" onClick={() => {
                  const ui = useUi.getState();
                  ui.closeAll();
                  ui.openPhone(e.kind === 'love_ask' ? 'family:linkups' : e.kind === 'love_couple' || e.kind.startsWith('kids_') ? 'family:family' : 'family:us');
                }}>Open Family</button>
              )}
              {(e.kind === 'place_invite' || e.kind === 'lounge_guest') && typeof e.data?.location_id === 'string' && (
                <button type="button" className="alert__go" onClick={() => {
                  const ui = useUi.getState();
                  ui.closeAll();
                  ui.setMapOpen(true);
                  ui.select(String(e.data.location_id));
                }}>Go there</button>
              )}
            </div>
          </li>
        );
      })}
    </ul>
    </>
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
