// P1: Settings -> Notifications (docs/NOTIFICATIONS.md). A master switch and one switch per category. The master switch
// is the permission step: turning it on asks the browser, saves this device and tells the server "send me pings";
// turning it off tells the server to send nothing (any device). Categories are saved per player on the server.
import { useCallback, useEffect, useState } from 'react';
import { errorMessage } from '../../lib/api';
import {
  disablePlayerPush, enablePlayerPush, needsIosInstall, pushState, pushSupport, setPushPrefs,
  type PushCategory, type PushPrefs,
} from '../../lib/push';
import { Button, Switch, toast } from '../../ui';

const CATEGORIES: { id: PushCategory; label: string; hint: string }[] = [
  { id: 'messages', label: 'Messages', hint: 'DMs and house chat, when you are not looking at it.' },
  { id: 'money', label: 'Money received', hint: 'Transfers, gifts and tips.' },
  { id: 'friends', label: 'Friends & invites', hint: 'Friend requests, house invites and knocks at your door.' },
  { id: 'events', label: 'Game events', hint: 'Club events starting, hype at your club, weekly top earner, referral reward.' },
  { id: 'admin', label: 'Announcements', hint: 'News from the Benin Life team.' },
];

export function NotificationsSettings() {
  const [prefs, setPrefs] = useState<PushPrefs | null>(null);
  const [busy, setBusy] = useState(false);
  const [failed, setFailed] = useState(false);
  const support = pushSupport();
  const ios = needsIosInstall();

  const load = useCallback(() => {
    pushState().then((p) => { setPrefs(p); setFailed(false); }).catch(() => setFailed(true));
  }, []);
  useEffect(load, [load]);

  const granted = typeof Notification !== 'undefined' && Notification.permission === 'granted';
  // "On" means the server will send AND this browser is allowed and saved
  const masterOn = Boolean(prefs?.master && prefs.devices > 0 && granted);
  const globalOff = prefs ? !prefs.global.enabled : false;
  const canAsk = support === 'ok';

  const toggleMaster = async (on: boolean) => {
    if (busy) return;
    setBusy(true);
    try {
      if (on) {
        setPrefs(await enablePlayerPush());
        toast('Notifications on for this phone.', 'good');
      } else {
        setPrefs(await disablePlayerPush());
        toast('Notifications off. You will not get any.', 'info');
      }
    } catch (e) {
      toast(errorMessage(e), 'bad');
      load();
    } finally {
      setBusy(false);
    }
  };

  const toggleCategory = async (id: PushCategory, on: boolean) => {
    if (!prefs) return;
    const before = prefs;
    setPrefs({ ...prefs, [id]: on });
    try {
      setPrefs(await setPushPrefs({ [id]: on }));
    } catch (e) {
      setPrefs(before);
      toast(errorMessage(e), 'bad');
    }
  };

  return (
    <section aria-labelledby="notif-head">
      <h4 className="settings-head" id="notif-head">Notifications</h4>
      {ios && (
        <p className="notif-note notif-note--warn">
          <b>On iPhone:</b> notifications work only after you add Benin Life to your Home Screen (iOS 16.4 or newer).
          In Safari tap <b>Share</b>, then <b>Add to Home Screen</b>, open the game from that icon, and come back here to turn them on.
        </p>
      )}
      {!ios && support === 'unsupported' && (
        <p className="notif-note">This browser cannot show notifications. Chrome on Android or the installed app can.</p>
      )}
      {!ios && support === 'denied' && (
        <p className="notif-note notif-note--warn">Notifications are blocked for this site. Allow them in your browser settings, then come back and switch this on.</p>
      )}
      {failed && !prefs && <p className="notif-note">Could not load your notification settings.</p>}
      {failed && !prefs && <Button size="sm" variant="ghost" onClick={load}>Try again</Button>}
      <div className="settings-list">
        <Switch
          label="Allow notifications"
          hint={globalOff ? 'Switched off by the team for now.' : 'A ping on this phone when something happens and you are not in the game.'}
          checked={masterOn}
          disabled={busy || !prefs || (!masterOn && !canAsk && !granted) || globalOff}
          onChange={(v) => void toggleMaster(v)}
        />
      </div>
      {prefs && (
        <div className={`notif-cats${masterOn ? '' : ' is-off'}`} aria-disabled={!masterOn}>
          {CATEGORIES.map((c) => (
            <Switch
              key={c.id}
              label={c.label}
              hint={prefs.global[c.id] ? c.hint : `${c.hint} Off for everyone for now.`}
              checked={prefs[c.id] && prefs.global[c.id]}
              disabled={!masterOn || !prefs.global[c.id]}
              onChange={(v) => void toggleCategory(c.id, v)}
            />
          ))}
        </div>
      )}
      <p className="notif-global">Pings never include private details. A chat sends one ping at a time, then bundles the rest.</p>
    </section>
  );
}
