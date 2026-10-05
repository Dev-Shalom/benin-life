import { useLayoutEffect, useRef, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { Avatar } from '../../art/avatar/Avatar';
import { clockTime, countdown, nairaShort } from '../../lib/format';
import { rpc, errorMessage } from '../../lib/api';
import { NEED_KEYS, ORIGIN_UI, originCopy } from '../../lib/pidgin';
import type { ClaimAllowanceResult, GameClock, GameState } from '../../lib/types';
import { useGame } from '../../state/game';
import { useUi } from '../../state/ui';
import { Icon, IconButton, NeedBar, toast } from '../../ui';
import type { PlayerStatus } from './status';

export function Hud({ state, clock, status }: { state: GameState; clock: GameClock; status: PlayerStatus }) {
  const p = state.profile;
  const openPanel = useUi((s) => s.openPanel);
  const setOverlay = useUi((s) => s.setOverlay);
  const needsOpen = useUi((s) => s.needsOpen);
  const toggleNeeds = useUi((s) => s.toggleNeeds);
  const unread = useGame((s) => s.unread);
  const nav = useNavigate();
  const refresh = useGame((s) => s.refresh);
  const origin = state.origin ?? null;
  const tier = origin?.id ?? p.origin;
  const badge = tier ? originCopy(tier, origin?.name ?? tier, origin?.tagline ?? '').badge : null;
  const [claiming, setClaiming] = useState(false);
  const topRef = useRef<HTMLDivElement>(null);

  // Publish the HUD's real bottom edge so game toasts sit below it even when the needs panel
  // is open or the chips row wraps (see .bl-toaster in game.css).
  useLayoutEffect(() => {
    const el = topRef.current;
    if (!el) return;
    const root = document.documentElement;
    const sync = () => root.style.setProperty('--hud-bottom', `${Math.round(el.getBoundingClientRect().bottom)}px`);
    sync();
    const ro = new ResizeObserver(sync);
    ro.observe(el);
    window.addEventListener('resize', sync);
    return () => {
      ro.disconnect();
      window.removeEventListener('resize', sync);
      root.style.removeProperty('--hud-bottom');
    };
  }, []);

  const claimDad = async () => {
    if (claiming) return;
    setClaiming(true);
    try {
      const r = await rpc<ClaimAllowanceResult>('claim_allowance');
      toast(r.message, 'good');
      await refresh();
    } catch (e) {
      toast(errorMessage(e), 'bad');
    } finally {
      setClaiming(false);
    }
  };

  return (
    <>
      <div className="hud-top" ref={topRef}>
        <div className="hud-card">
          <button type="button" className="hud-id" onClick={() => openPanel('profile', { targetId: p.id })} aria-label="My profile">
            <span className="hud-portrait-wrap">
              <span className="hud-portrait">
                <Avatar config={p.avatar} view="portrait" size={46} />
              </span>
              {badge && (
                <span className={`origin-chip origin-chip--${tier === 'nepo' ? 'nepo' : tier === 'lapo' ? 'lapo' : 'other'}`}
                  title={origin?.name}>
                  {badge}
                </span>
              )}
            </span>
            <span className="hud-id__text">
              <span className="hud-name">{p.username}</span>
              <span className={`hud-clock${clock.is_night ? ' is-night' : ''}`}>
                <Icon name={clock.is_night ? 'moon' : 'sun'} size={14} />
                Day {clock.day} · {clockTime(clock.hour, clock.minute)}
              </span>
            </span>
          </button>
          <div className="hud-money">
            <button type="button" className="hud-cash" onClick={() => openPanel('wallet')} aria-label="Cash, open wallet">
              <Icon name="cash" size={16} />
              <span>{nairaShort(p.cash)}</span>
              <span className="hud-plus"><Icon name="plus" size={12} stroke={3} /></span>
            </button>
            <button type="button" className="hud-bank"
              onClick={() => toast("Move bank money at Bronze Bank (GRA) or any PoS. Money in the bank can't be stolen.", 'info')}
              aria-label="Bank balance">
              <Icon name="bank" size={14} />
              <span>{nairaShort(p.bank)}</span>
            </button>
          </div>
        </div>

        <button type="button" className={`hud-needs${needsOpen ? ' is-open' : ''}`} onClick={toggleNeeds} aria-expanded={needsOpen}
          aria-label="Needs">
          {needsOpen ? (
            <div className="hud-needs__full">
              {NEED_KEYS.map((k) => (
                <NeedBar key={k} need={k} value={p[k]} />
              ))}
              <span className="hud-needs__hint"><Icon name="chevronUp" size={14} /> Hide</span>
            </div>
          ) : (
            <div className="hud-needs__mini">
              {NEED_KEYS.map((k) => (
                <NeedBar key={k} need={k} value={p[k]} compact />
              ))}
            </div>
          )}
        </button>

        {(status.protLeft > 0 || origin?.allowance_claimable) && (
          <div className="hud-chips">
            {status.protLeft > 0 && (
              <div className="hud-protect" title="New player protection: nobody can rob you yet">
                <Icon name="shield" size={14} /> Protected · {countdown(status.protLeft)}
              </div>
            )}
            {origin?.allowance_claimable && (
              <button type="button" className="hud-dad" onClick={() => void claimDad()} disabled={claiming}
                title={ORIGIN_UI.collectDad} aria-label={`${ORIGIN_UI.collectDad} (${nairaShort(origin.allowance_daily)})`}>
                <Icon name="sparkle" size={14} />
                {ORIGIN_UI.dadChip}
                <span className="hud-dad__amt">{nairaShort(origin.allowance_daily)}</span>
              </button>
            )}
          </div>
        )}
      </div>

      <nav className="hud-side" aria-label="Game menu">
        <IconButton icon="bag" label="Bag" onClick={() => openPanel('inventory')} />
        <IconButton icon="chat" label="Messages" onClick={() => openPanel('messages')} />
        <IconButton icon="file" label="Case File" onClick={() => openPanel('crimes')} />
        <IconButton icon="bell" label="Alerts" badge={unread} onClick={() => setOverlay('alerts')} />
        <IconButton icon="gear" label="Settings" onClick={() => setOverlay('settings')} />
        {p.is_admin && <IconButton icon="crown" label="Admin" variant="gold" onClick={() => nav('/admin')} />}
      </nav>
    </>
  );
}
