import { useEffect, useMemo, useState } from 'react';
import { AvatarPortrait, migrateAvatar } from '../../art/avatar3d';
import { Scene } from '../../art/Scene';
import { rpc } from '../../lib/api';
import { districtName } from '../../lib/format';
import { P, riskLabel } from '../../lib/pidgin';
import type { GameState, Location, PanelId, PublicPlayer } from '../../lib/types';
import { hasPanel, PANEL_LABELS } from '../../panels/registry';
import { useChat } from '../../state/chat';
import { useGame } from '../../state/game';
import { useUi } from '../../state/ui';
import { usePresenceStore, usePresentAt } from '../../state/presence';
import { Button, Icon, Sheet, Spinner, Tabs } from '../../ui';
import { PanelHost } from './PanelHost';
import type { PlayerStatus } from './status';
import { TravelPicker } from './TravelPicker';

export function LocationSheet({ state, status, night }: { state: GameState; status: PlayerStatus; night: boolean }) {
  const selectedId = useUi((s) => s.selectedId);
  const select = useUi((s) => s.select);
  const byId = useGame((s) => s.locationsById);
  // Keep the last location rendered while the sheet animates out.
  const [lastId, setLastId] = useState(selectedId);
  if (selectedId && selectedId !== lastId) setLastId(selectedId);
  const loc = byId[selectedId ?? lastId ?? ''] ?? (state.location.id === (selectedId ?? lastId) ? state.location : undefined);
  const close = () => select(null);
  const here = Boolean(loc) && state.location.id === loc!.id && !state.travel;

  return (
    <Sheet open={Boolean(selectedId && loc)} onClose={close} size={here ? 'tall' : 'auto'} className="loc-sheet"
      header={loc ? <LocationHeader loc={loc} night={night} here={here} /> : null}>
      {loc && <LocationBody key={loc.id} loc={loc} state={state} status={status} close={close} />}
    </Sheet>
  );
}

function LocationHeader({ loc, night, here }: { loc: Location; night: boolean; here: boolean }) {
  const day = riskLabel(loc.risk);
  const nite = riskLabel(loc.risk * (loc.night_risk_mult || 1));
  return (
    <div className="loc-head">
      <div className="loc-head__art">
        <Scene type={loc.scene} night={night} />
      </div>
      <div className="loc-head__shade" />
      <div className="loc-head__text">
        <div className="row" style={{ gap: 6, flexWrap: 'wrap' }}>
          <span className="loc-district"><Icon name="pin" size={12} /> {districtName(loc.district)}</span>
          {here && <span className="loc-here">{P.youAreHere}</span>}
        </div>
        <h3 className="loc-name">{loc.name}</h3>
        {loc.blurb && <p className="loc-blurb">{loc.blurb}</p>}
        <div className="loc-chips">
          <span className={`risk-chip risk-chip--${day.tone}${!night ? ' is-now' : ''}`}><Icon name="sun" size={12} /> {day.label}</span>
          <span className={`risk-chip risk-chip--${nite.tone}${night ? ' is-now' : ''}`}><Icon name="moon" size={12} /> {nite.label}</span>
          {loc.cctv && <span className="risk-chip risk-chip--info"><Icon name="camera" size={12} /> CCTV</span>}
          {loc.keke_ok && <span className="risk-chip risk-chip--info"><Icon name="keke" size={12} /> Keke access</span>}
        </div>
      </div>
    </div>
  );
}

function LocationBody({ loc, state, status, close }: { loc: Location; state: GameState; status: PlayerStatus; close: () => void }) {
  const here = state.location.id === loc.id && !state.travel;
  const tabs = useMemo(() => {
    const ids: PanelId[] = [...loc.actions.filter((a) => a !== 'chat'), 'chat'];
    return ids.filter((id, i) => ids.indexOf(id) === i && hasPanel(id));
  }, [loc.actions]);
  const [tab, setTab] = useState<PanelId | null>(() => {
    const want = useUi.getState().selectedTab;
    return want && tabs.includes(want) ? want : (tabs[0] ?? null);
  });
  const current = tab && tabs.includes(tab) ? tab : (tabs[0] ?? null);
  const chatUnread = useChat((s) => s.unread);

  if (!here) {
    // Only list what a player can actually do there today (jobs, shops... appear as they ship).
    const offers = tabs.filter((a) => a !== 'chat');
    return (
      <div className="loc-body">
        <TravelPicker dest={loc} cash={state.profile.cash} blockedReason={status.blockedReason} onStarted={close} />
        {offers.length > 0 && (
          <div className="loc-offers">
            <p className="loc-offers__title">Available here</p>
            <div className="row" style={{ flexWrap: 'wrap', gap: 6 }}>
              {offers.map((a) => (
                <span key={a} className="chip">{PANEL_LABELS[a] ?? a}</span>
              ))}
            </div>
          </div>
        )}
      </div>
    );
  }

  const atHome = loc.id === state.profile.home_location_id;
  return (
    <div className="loc-body">
      {!atHome && <GoInside />}
      <PeopleHere loc={loc} meId={state.profile.id} />
      {status.blockedReason && (
        <p className="travel-blocked"><Icon name="info" size={16} /> {status.blockedReason}</p>
      )}
      {tabs.length > 0 ? (
        <>
          <Tabs value={current ?? ''} onChange={(id) => setTab(id as PanelId)}
            tabs={tabs.map((id) => ({ id, label: PANEL_LABELS[id], badge: id === 'chat' && chatUnread > 0 ? (chatUnread > 9 ? '9+' : chatUnread) : null }))} className="loc-tabs" />
          <div className="loc-panel">
            {current && <PanelHost key={current} id={current} location={loc} close={close} />}
          </div>
        </>
      ) : (
        <p className="muted" style={{ padding: 16, textAlign: 'center' }}>{P.panelMissing}</p>
      )}
    </div>
  );
}

function PeopleHere({ loc, meId }: { loc: Location; meId: string }) {
  const openPanel = useUi((s) => s.openPanel);
  const [people, setPeople] = useState<PublicPlayer[] | null>(null);
  const [picked, setPicked] = useState<string | null>(null);

  // S1: the list reloads the moment someone connects at / leaves this place (Realtime Presence),
  // with a slow poll as a safety net. While presence is live, only connected players are shown.
  const presentHere = usePresentAt(loc.id);
  const presenceLive = usePresenceStore((s) => s.online !== null);
  const connected = usePresenceStore((s) => s.ids);
  useEffect(() => {
    let alive = true;
    const load = async () => {
      try {
        const list = await rpc<PublicPlayer[]>('players_here', { p_location: loc.id });
        if (alive) setPeople((list ?? []).filter((x) => x.id !== meId).map((x) => ({ ...x, avatar: migrateAvatar(x.avatar) })));
      } catch {
        if (alive) setPeople([]);
      }
    };
    const t = window.setTimeout(load, 250); // debounce presence bursts
    const id = window.setInterval(load, presenceLive ? 120_000 : 30_000);
    return () => {
      alive = false;
      window.clearTimeout(t);
      window.clearInterval(id);
    };
  }, [loc.id, meId, presentHere, presenceLive]);
  const shown = people && presenceLive ? people.filter((x) => connected.has(x.id)) : people;

  const person = shown?.find((x) => x.id === picked);
  const canRob = hasPanel('rob');
  const canProfile = hasPanel('profile');

  return (
    <section className="people">
      <div className="people__head">
        <Icon name="people" size={16} />
        <span>People here</span>
        {shown && <span className="chip">{shown.length}</span>}
      </div>
      {!shown ? (
        <div className="people__row"><Spinner size={18} /></div>
      ) : shown.length === 0 ? (
        <p className="people__empty">{P.noPeople}</p>
      ) : (
        <div className="people__row">
          {shown.map((x) => (
            <button key={x.id} type="button" className={`person${picked === x.id ? ' is-active' : ''}`}
              onClick={() => setPicked(picked === x.id ? null : x.id)}>
              <span className="person__face"><AvatarPortrait config={x.avatar} size={44} /></span>
              <span className="person__name">{x.username}</span>
            </button>
          ))}
        </div>
      )}
      {person && (
        <div className="person-card">
          <span className="person__face"><AvatarPortrait config={person.avatar} size={48} /></span>
          <div className="grow">
            <b>{person.username}</b>
            <div className="muted" style={{ fontSize: 13 }}><Icon name="star" size={12} style={{ display: 'inline' }} /> Street cred {person.street_cred}</div>
          </div>
          {canProfile && (
            <Button size="sm" variant="ghost" onClick={() => openPanel('profile', { targetId: person.id })}>Profile</Button>
          )}
          {canRob && (
            <Button size="sm" variant="danger" icon="mask" onClick={() => openPanel('rob', { targetId: person.id }, loc.id)}>Rob</Button>
          )}
        </div>
      )}
    </section>
  );
}

/** L2: from the map (or the sheet over the interior), step inside the place you are at. */
function GoInside() {
  const mapOpen = useUi((s) => s.mapOpen);
  const setMapOpen = useUi((s) => s.setMapOpen);
  const closeAll = useUi((s) => s.closeAll);
  if (!mapOpen) return null;
  return (
    <button type="button" className="where-enter loc-enter" onClick={() => { closeAll(); setMapOpen(false); }}>
      Go inside <Icon name="chevronRight" size={14} />
    </button>
  );
}
