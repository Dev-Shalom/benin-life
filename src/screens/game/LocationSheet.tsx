import { useEffect, useMemo, useState } from 'react';
import { Avatar } from '../../art/avatar/Avatar';
import { normalizeAvatar } from '../../art/avatar/catalog';
import { Scene } from '../../art/Scene';
import { rpc } from '../../lib/api';
import { titleCase } from '../../lib/format';
import { P, riskLabel } from '../../lib/pidgin';
import type { GameState, Location, PanelId, PublicPlayer } from '../../lib/types';
import { hasPanel, PANEL_LABELS } from '../../panels/registry';
import { useGame } from '../../state/game';
import { useUi } from '../../state/ui';
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
          <span className="loc-district"><Icon name="pin" size={12} /> {titleCase(loc.district)}</span>
          {here && <span className="loc-here">{P.youDeyHere}</span>}
        </div>
        <h3 className="loc-name">{loc.name}</h3>
        {loc.blurb && <p className="loc-blurb">{loc.blurb}</p>}
        <div className="loc-chips">
          <span className={`risk-chip risk-chip--${day.tone}${!night ? ' is-now' : ''}`}><Icon name="sun" size={12} /> {day.label}</span>
          <span className={`risk-chip risk-chip--${nite.tone}${night ? ' is-now' : ''}`}><Icon name="moon" size={12} /> {nite.label}</span>
          {loc.cctv && <span className="risk-chip risk-chip--info"><Icon name="camera" size={12} /> CCTV dey</span>}
          {loc.keke_ok && <span className="risk-chip risk-chip--info"><Icon name="keke" size={12} /> Keke fit reach</span>}
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
  const [tab, setTab] = useState<PanelId | null>(tabs[0] ?? null);
  const current = tab && tabs.includes(tab) ? tab : (tabs[0] ?? null);

  if (!here) {
    return (
      <div className="loc-body">
        <TravelPicker dest={loc} cash={state.profile.cash} blockedReason={status.blockedReason} onStarted={close} />
        {loc.actions.length > 0 && (
          <div className="loc-offers">
            <p className="loc-offers__title">Wetin dey here</p>
            <div className="row" style={{ flexWrap: 'wrap', gap: 6 }}>
              {loc.actions.map((a) => (
                <span key={a} className="chip">{PANEL_LABELS[a] ?? a}</span>
              ))}
            </div>
          </div>
        )}
      </div>
    );
  }

  return (
    <div className="loc-body">
      <PeopleHere loc={loc} meId={state.profile.id} />
      {status.blockedReason && (
        <p className="travel-blocked"><Icon name="info" size={16} /> {status.blockedReason}</p>
      )}
      {tabs.length > 0 ? (
        <>
          <Tabs value={current ?? ''} onChange={(id) => setTab(id as PanelId)}
            tabs={tabs.map((id) => ({ id, label: PANEL_LABELS[id] }))} className="loc-tabs" />
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

  useEffect(() => {
    let alive = true;
    const load = async () => {
      try {
        const list = await rpc<PublicPlayer[]>('players_here', { p_location: loc.id });
        if (alive) setPeople((list ?? []).filter((x) => x.id !== meId));
      } catch {
        if (alive) setPeople([]);
      }
    };
    void load();
    const id = window.setInterval(load, 30_000);
    return () => {
      alive = false;
      window.clearInterval(id);
    };
  }, [loc.id, meId]);

  const person = people?.find((x) => x.id === picked);
  const canRob = hasPanel('rob');
  const canProfile = hasPanel('profile');

  return (
    <section className="people">
      <div className="people__head">
        <Icon name="people" size={16} />
        <span>People here</span>
        {people && <span className="chip">{people.length}</span>}
      </div>
      {!people ? (
        <div className="people__row"><Spinner size={18} /></div>
      ) : people.length === 0 ? (
        <p className="people__empty">{P.noPeople}</p>
      ) : (
        <div className="people__row">
          {people.map((x) => (
            <button key={x.id} type="button" className={`person${picked === x.id ? ' is-active' : ''}`}
              onClick={() => setPicked(picked === x.id ? null : x.id)}>
              <span className="person__face"><Avatar config={normalizeAvatar(x.avatar)} view="portrait" size={44} /></span>
              <span className="person__name">{x.username}</span>
            </button>
          ))}
        </div>
      )}
      {person && (
        <div className="person-card">
          <span className="person__face"><Avatar config={normalizeAvatar(person.avatar)} view="portrait" size={48} /></span>
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
