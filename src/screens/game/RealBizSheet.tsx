// The showcase sheet of a real business (tap its pin on the map, or Discover): photos, description, contact buttons,
// "Visit in game" when it has an in-game company, Report, the terms. It is an ad only: no money moves here.
import { useEffect, useState } from 'react';
import { realBizGet, realBizReport, realBizTrack, realImageUrl, type RealShowcase } from '../../api/company';
import { errorMessage } from '../../lib/api';
import { useRealBiz } from '../../lib/realBiz';
import { Button, Sheet, toast } from '../../ui';
import { CompanyPublicSheet } from './phone/CompanyApp';
import './phone/CompanyApp.css';

const REASONS = ['Scam or fraud', 'Adult content', 'Gambling or crypto', 'Weapons or drugs', 'Wrong information', 'Something else'];
const digits = (p: string) => p.replace(/[^\d]/g, '');

export default function RealBizSheet() {
  const id = useRealBiz((s) => s.sheet);
  const close = useRealBiz((s) => s.close);
  const [biz, setBiz] = useState<RealShowcase | null | undefined>(undefined);
  const [report, setReport] = useState(false);
  const [co, setCo] = useState<number | null>(null);
  const [img, setImg] = useState(0);
  useEffect(() => {
    if (!id) return;
    setBiz(undefined); setImg(0); setReport(false);
    realBizGet(id).then((b) => { setBiz(b); if (b) realBizTrack(id, 'view'); }).catch(() => setBiz(null));
  }, [id]);
  const tap = () => { if (id) realBizTrack(id, 'tap'); };
  const send = async (reason: string) => {
    if (!id) return;
    try { toast((await realBizReport(id, reason)).message, 'good'); } catch (e) { toast(errorMessage(e), 'bad'); }
    setReport(false);
  };
  return (
    <>
      <Sheet open={Boolean(id)} onClose={close} className="co-sheet"
        header={<div className="co-showhead"><span className="co-showhead__logo" aria-hidden>{biz?.logo ?? '🏪'}</span>
          <span className="grow"><b>{biz?.name ?? 'Business'}</b><span className="co-verified">✔ Verified real business</span></span></div>}>
        {biz === undefined && <div className="panel-skel"><span /><span /><span /></div>}
        {biz === null && <p className="bz-hint">This listing is not on the map any more.</p>}
        {biz && (
          <div className="co-show" data-testid="real-showcase">
            {biz.images.length > 0 && (
              <div className="co-photos">
                <img src={realImageUrl(biz.images[img] ?? biz.images[0])} alt={`${biz.name} photo ${img + 1}`} />
                {biz.images.length > 1 && <div className="co-photos__dots">{biz.images.map((_, i) => <button key={i} type="button" aria-label={`Photo ${i + 1}`} className={i === img ? 'is-on' : ''} onClick={() => setImg(i)} />)}</div>}
              </div>
            )}
            <p className="co-meta">{biz.category_name} · {biz.area}</p>
            <p className="co-desc">{biz.descr}</p>
            <p className="co-meta">📍 {biz.address}</p>
            <div className="co-contacts">
              {biz.whatsapp && <a className="co-contact co-contact--wa" href={`https://wa.me/${digits(biz.whatsapp)}`} target="_blank" rel="noopener noreferrer" onClick={tap}>WhatsApp</a>}
              {biz.phone && <a className="co-contact" href={`tel:${biz.phone}`} onClick={tap}>Call</a>}
              {biz.instagram && <a className="co-contact" href={`https://instagram.com/${biz.instagram}`} target="_blank" rel="noopener noreferrer" onClick={tap}>Instagram</a>}
              {biz.website && <a className="co-contact" href={biz.website} target="_blank" rel="noopener noreferrer" onClick={tap}>Website</a>}
              {biz.company && <button type="button" className="co-contact co-contact--game" onClick={() => setCo(biz.company!.id)}>Visit in game</button>}
            </div>
            <p className="co-terms">{biz.terms} Contact: {biz.contact_email}. Benin Life only shows this ad: no payments between players and the business happen in the game. Do not share passwords or send money to strangers.</p>
            {!biz.mine && <Button size="sm" variant="ghost" onClick={() => setReport((r) => !r)}>Report</Button>}
            {report && <div className="co-report">{REASONS.map((r) => <button key={r} type="button" className="bz-chip" onClick={() => void send(r)}>{r}</button>)}</div>}
          </div>
        )}
      </Sheet>
      {co != null && <CompanyPublicSheet id={co} onClose={() => setCo(null)} />}
    </>
  );
}
