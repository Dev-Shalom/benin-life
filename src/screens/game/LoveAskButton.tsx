import { useEffect, useState } from 'react';
import { loveAsk, lovePublic, type PublicLove } from '../../api/love';
import { errorMessage } from '../../lib/api';
import { useUi } from '../../state/ui';
import { Button, toast } from '../../ui';

/** "Ask out" beside a player's card. Only shown when that player is open to link-ups (public flag); with a partner it shows "💞 With @name" instead.
 *  One cheap get_public_profile call per selected player; every rule is checked again on the server (love_ask). */
export function LoveAskButton({ userId }: { userId: string }) {
  const openPhone = useUi((s) => s.openPhone);
  const [got, setGot] = useState<{ id: string; info: PublicLove } | null>(null);
  const [busy, setBusy] = useState(false);
  const [sentTo, setSentTo] = useState<string | null>(null);
  const info = got?.id === userId ? got.info : null; // a different player: nothing until their profile arrives
  const sent = sentTo === userId;

  useEffect(() => {
    let alive = true;
    lovePublic(userId).then((p) => alive && setGot({ id: userId, info: p })).catch(() => alive && setGot({ id: userId, info: {} }));
    return () => { alive = false; };
  }, [userId]);

  if (!info) return null;
  const proud = (info.proud_parent ?? 0) > 0 ? <span className="love-with" title="Raised a child who grew up">{info.proud_tier === 'gold' ? '🥇 Gold' : info.proud_tier === 'silver' ? '🥈 Silver' : info.proud_tier === 'bronze' ? '🥉 Bronze' : '🏅'} Proud parent{(info.proud_parent ?? 0) > 1 ? ` × ${info.proud_parent}` : ''}</span> : null;
  if (info.relationship) {
    return <>
      <span className="love-with" title="Relationship status">{info.relationship.status === 'couple' ? '💞 With' : '💬 Talking to'} @{info.relationship.partner.username}</span>
      {proud}
    </>;
  }
  if (!info.love_open) return proud;
  const ask = async () => {
    setBusy(true);
    try {
      const r = await loveAsk(userId);
      setSentTo(userId);
      toast(r.message, 'good');
    } catch (e) {
      toast(errorMessage(e), 'bad');
    } finally {
      setBusy(false);
    }
  };
  return <>
    {proud}
    {sent
      ? <Button size="sm" variant="ghost" onClick={() => openPhone('family:linkups')}>Asked 💞</Button>
      : <Button size="sm" variant="green" loading={busy} disabled={busy} onClick={() => void ask()} data-testid="love-ask-profile">Ask out 💞</Button>}
  </>;
}
