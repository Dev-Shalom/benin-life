// Public company card (playbeninlife.app/c/<id>): works signed out. Shows only public facts: name, logo, industry, areas, stars, owner, 7-evening sales.
import { useEffect, useState } from 'react';
import { Link, useParams } from 'react-router-dom';
import { companyPublic, type PublicCompany } from '../api/company';
import { PublicCard } from './game/phone/CompanyApp';
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
    <div className="co-page">
      <div className="co-page__card">
        {c === undefined && <div className="panel-skel"><span /><span /></div>}
        {c === null && <p className="bz-hint">We could not find that company.</p>}
        {c && <PublicCard c={c} />}
        <Link to="/play" className="co-contact co-contact--game">Play Benin Life</Link>
      </div>
    </div>
  );
}
