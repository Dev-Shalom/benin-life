import { useEffect, useState } from 'react';
import { socialAddFriend, socialCancelFriendRequest, socialFriendStatus, socialRespondFriend, type FriendStatus } from '../../api/social';
import { errorMessage } from '../../lib/api';
import { useUi } from '../../state/ui';
import { Button, toast } from '../../ui';

/** Small friend action shown beside a real player in the local People lists. */
export function SocialPlayerButton({ userId, onChanged }: { userId: string; onChanged?: () => void }) {
  const openPhone = useUi((s) => s.openPhone);
  const [status, setStatus] = useState<FriendStatus | null>(null);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    let alive = true;
    setStatus(null);
    socialFriendStatus(userId).then((s) => alive && setStatus(s)).catch(() => alive && setStatus('none'));
    return () => { alive = false; };
  }, [userId]);

  const act = async () => {
    if (!status || status === 'self' || status === 'blocked') return;
    if (status === 'friend') {
      openPhone('messages');
      return;
    }
    setBusy(true);
    try {
      if (status === 'incoming') {
        const result = await socialRespondFriend(userId, true);
        setStatus('friend');
        toast(result.message, 'good');
        onChanged?.();
      } else if (status === 'outgoing') {
        const result = await socialCancelFriendRequest(userId);
        setStatus('none');
        toast(result.message, 'info');
        onChanged?.();
      } else {
        const result = await socialAddFriend(userId);
        setStatus((result.status as FriendStatus) ?? 'outgoing');
        toast(result.message, 'good');
        onChanged?.();
      }
    } catch (e) {
      toast(errorMessage(e), 'bad');
    } finally {
      setBusy(false);
    }
  };

  const label = !status ? 'Checking…'
    : status === 'friend' ? 'Message'
      : status === 'incoming' ? 'Accept request'
        : status === 'outgoing' ? 'Cancel request'
          : status === 'blocked' ? 'Blocked' : 'Add friend';

  return <Button size="sm" variant={status === 'incoming' || status === 'none' ? 'green' : 'ghost'}
    disabled={!status || status === 'blocked' || status === 'self' || busy} loading={busy} onClick={() => void act()}>
    {label}
  </Button>;
}
