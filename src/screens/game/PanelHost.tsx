import { Suspense, useState } from 'react';
import { loadPanel, PANEL_LABELS } from '../../panels/registry';
import type { Location, PanelId } from '../../lib/types';
import { P } from '../../lib/pidgin';
import { useGame } from '../../state/game';
import { useUi } from '../../state/ui';
import { EmptyState, ErrorBoundary, Sheet } from '../../ui';

export function PanelSkeleton() {
  return (
    <div className="panel-skel" aria-label={P.loading}>
      <span />
      <span />
      <span />
    </div>
  );
}

/** Renders a registry panel with PanelProps, lazy + crash-proof. */
export function PanelHost({ id, location, close, params }: {
  id: PanelId; location: Location; close: () => void; params?: Record<string, unknown>;
}) {
  const state = useGame((s) => s.state);
  const refresh = useGame((s) => s.refresh);
  const Comp = loadPanel(id);
  if (!state) return null;
  if (!Comp) return <EmptyState icon="sparkle" title={`${PANEL_LABELS[id]} never ready`} body={P.panelMissing} />;
  return (
    <ErrorBoundary resetKey={`${id}:${location.id}`}>
      <Suspense fallback={<PanelSkeleton />}>
        <Comp state={state} location={location} refresh={refresh} close={close} params={params} />
      </Suspense>
    </ErrorBoundary>
  );
}

/** Sheet for global panels (inventory, wallet, messages, crimes, profile, rob, police bail…). */
export function GlobalPanelSheet() {
  const open = useUi((s) => s.panel);
  const closePanel = useUi((s) => s.closePanel);
  const state = useGame((s) => s.state);
  const byId = useGame((s) => s.locationsById);
  // Keep the last panel rendered while the sheet animates out.
  const [last, setLast] = useState(open);
  if (open && open !== last) setLast(open);
  const panel = open ?? last;
  const location = panel?.locationId ? (byId[panel.locationId] ?? state?.location) : state?.location;
  return (
    <Sheet open={Boolean(open)} onClose={closePanel} title={panel ? PANEL_LABELS[panel.id] : ''} size="tall">
      {panel && location && (
        <PanelHost key={`${panel.id}:${JSON.stringify(panel.params ?? {})}`} id={panel.id} location={location} close={closePanel} params={panel.params} />
      )}
    </Sheet>
  );
}
