// "My Office" phone app: only for people who hold a seat RIGHT NOW (office_mine). Everything a holder can do in office, in one place.
//   Industry offices: levers, official statement, approval, recent changes (IndustryHolder).
//   Political offices: their existing Benin Votes powers (Governor: Commissioners, announcement, policy; Councillor: ward notice), reusing the
//   same component and RPCs. Benin Votes -> Government stays the public view of who holds what.
// The server re-checks the seat on every RPC behind this screen, so a stale app or an old link can do nothing.
import { useEffect } from 'react';
import { useNow } from '../../../lib/clock';
import { nairaShort } from '../../../lib/format';
import { useGame } from '../../../state/game';
import { useOffices } from '../../../state/offices';
import { usePolitics } from '../../../state/politics';
import { OfficeTag } from '../../../ui';
import { IndustryHolder } from './IndustryOffices';
import { MyOffice } from './PoliticsApp';
import './PoliticsApp.css';
import './IndustryOffices.css';

const OFFICE_KINDS = /^(ind_|pol_(won|appointed|sacked|removed|ward_notice))/;

export default function OfficeApp({ onGo: _onGo }: { onGo: (id: string) => void }) {
  const mine = useOffices((o) => o.mine);
  const pol = usePolitics((p) => p.status);
  const events = useGame((g) => g.events);
  const now = useNow(60_000);
  useEffect(() => { void useOffices.getState().load(); void usePolitics.getState().load(); }, []);
  if (!mine) return <div className="phone-app__body"><div className="panel-skel"><span /><span /><span /></div></div>;
  if (!mine.holds) return <div className="phone-app__body"><p className="phone-app__lead">You no longer hold this office.</p></div>;
  const left = mine.term_end ? Math.max(0, (Date.parse(mine.term_end) - now) / 86400000) : 0;
  const alerts = events.filter((e) => OFFICE_KINDS.test(e.kind)).slice(0, 5);
  return (
    <div className="phone-app__body po-body" data-testid="office-app">
      <div className="po-app">
        <div className="my-office__head" data-testid="office-head">
          <small>My Office</small>
          <b><OfficeTag title={mine.title} />{mine.office}</b>
          <div className="my-office__stats">
            <span><small>Term left</small><strong>{left >= 1 ? `${Math.floor(left)} d ${Math.floor((left % 1) * 24)} h` : `${Math.max(1, Math.round(left * 24))} h`}</strong></span>
            <span><small>Salary a day</small><strong>{nairaShort(mine.salary_per_day ?? 0)}</strong></span>
            <span><small>Kind</small><strong>{mine.kind === 'industry' ? 'Industry' : 'Government'}</strong></span>
          </div>
        </div>
        {mine.kind === 'industry' ? <IndustryHolder /> : pol?.me.office ? <MyOffice s={pol} h={pol.me.office} /> : <div className="panel-skel"><span /><span /></div>}
        <section className="po-card" data-testid="office-alerts">
          <h4>Office alerts</h4>
          {alerts.length === 0 ? <p className="po-fine">Nothing new. Alerts about your seat show here and in the Alerts app.</p> : (
            <ul className="my-office__alerts">{alerts.map((e) => <li key={e.id}><b>{e.title}</b>{e.body && <small>{e.body}</small>}</li>)}</ul>
          )}
        </section>
      </div>
    </div>
  );
}
