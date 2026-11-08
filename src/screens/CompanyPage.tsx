// Public company card (playbeninlife.app/c/<id>): works signed out. Shows only public facts: name, logo, industry, areas, stars, owner, 7-evening sales.
// Marketing look (docs/FRONTEND.md): the card itself is the game's PublicCard, framed in the graphite and bronze page.
import { useEffect, useState } from 'react';
import { Link, useParams } from 'react-router-dom';
import { companyPublic, type PublicCompany } from '../api/company';
import { PublicCard } from './game/phone/CompanyApp';
import { MkFooter, MkNav, MkRoot } from './mk/Shell';
import '../screens/game/phone/BusinessApp.css';
import '../screens/game/phone/CompanyApp.css';

export default function CompanyPage() {
  const { id } = useParams();
  const [c, setC] = useState<PublicCompany | null | undefined>(undefined);
  useEffect(() => {
    const n = Number(id);
    if (!Number.isInteger(n) || n < 1) { setC(null); return; }
    companyPublic(n).then(setC).catch(() => setC(null));
  }, [id]);
  useEffect(() => { if (c) document.title = `${c.name} · Benin Life`; }, [c]);
  return (
    <MkRoot className="cp">
      <MkNav>
        <Link to="/auth?mode=signup" className="mk-btn mk-btn--primary mk-btn--sm">Start playing</Link>
      </MkNav>
      <main id="main" className="mk-wrap cp-main">
        <div className="cp-card">
          {c === undefined && <div className="panel-skel"><span /><span /></div>}
          {c === null && (
            <div className="cp-missing">
              <h1 className="mk-display">We could not find that company.</h1>
              <p>The link may be wrong, or the company has closed.</p>
            </div>
          )}
          {c && <PublicCard c={c} />}
          <Link to="/play" className="mk-btn mk-btn--primary mk-btn--block">Play Benin Life</Link>
        </div>
      </main>
      <MkFooter />
    </MkRoot>
  );
}
