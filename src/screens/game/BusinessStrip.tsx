// R10: the business line on the place card and the map place sheet. "Owned by @x", the level, and what a visit means:
// spending here pays the owner a share. The owner also gets Collect takings, Work a shift and a shortcut to the app.
import { useCallback, useEffect, useState } from 'react';
import { businessAt, businessCollect, businessWork, type BusinessAt } from '../../api/business';
import { errorMessage } from '../../lib/api';
import { naira } from '../../lib/format';
import { useGame } from '../../state/game';
import { useUi } from '../../state/ui';
import { Button, toast } from '../../ui';
import './phone/BusinessApp.css';

export function OwnerChip({ locId }: { locId: string }) {
  const owner = useGame((s) => s.locationsById[locId]?.biz_owner);
  if (!owner) return null;
  return <span className="bz-ownerchip" data-testid="owned-by">🏷️ Owned by @{owner}</span>;
}

export function BusinessStrip({ locId, compact = false }: { locId: string; compact?: boolean }) {
  const rec = useGame((s) => s.locationsById[locId]);
  const [b, setB] = useState<BusinessAt | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const load = useCallback(() => { businessAt(locId).then(setB).catch(() => setB(null)); }, [locId]);
  useEffect(() => {
    if (!rec?.biz_id) { setB(null); return; }
    load();
  }, [rec?.biz_id, rec?.biz_owner, rec?.biz_level, load]);
  if (!rec?.biz_id || !b) return null;
  const run = async (key: string, fn: () => Promise<{ message: string }>) => {
    setBusy(key);
    try {
      toast((await fn()).message, 'good');
      await useGame.getState().refresh();
    } catch (e) { toast(errorMessage(e), 'bad'); } finally { setBusy(null); load(); }
  };
  return (
    <div className="bz-strip" data-testid="business-strip">
      <span className="bz-strip__text">
        <b>{b.icon} {b.mine ? 'Your business' : `Owned by @${b.owner}`}</b> · Level {b.level}
        <small>
          {b.setting_up ? 'Still being set up.' : b.mine
            ? `Takings waiting: ${naira(b.takings ?? 0)}${b.boost ? ' · shift boost on' : ''}`
            : `${b.cut_pct}% of what you spend here goes to @${b.owner}.`}
        </small>
      </span>
      {b.mine && !compact && (
        <span className="bz-strip__btns">
          <Button size="sm" variant="gold" disabled={(b.takings ?? 0) < 1} loading={busy === 'c'} onClick={() => void run('c', () => businessCollect(b.id))}>Collect</Button>
          <Button size="sm" variant="ghost" disabled={b.setting_up} loading={busy === 'w'} onClick={() => void run('w', () => businessWork(b.id))}>Work a shift</Button>
          <Button size="sm" variant="ghost" onClick={() => useUi.getState().openPhone('business')}>Manage</Button>
        </span>
      )}
    </div>
  );
}
