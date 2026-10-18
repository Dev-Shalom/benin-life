// /admin (V1-7): owner dashboard. Lazy chunk, loaded by src/screens/AdminRoute.tsx for admins only.
// The route gate is just a door: every RPC used here re-checks bl_is_admin() on the server.
import { useEffect, useRef, useState } from 'react';
import { NavLink, Navigate, Route, Routes, Link } from 'react-router-dom';
import { rpc } from '../lib/api';
import { chime, flushAdminPush } from '../lib/push';
import { Icon, Logo } from '../ui';
import { ensureConfig } from '../lib/config';
import { useGame } from '../state/game';
import Overview from './Overview';
import Settings from './Settings';
import Content from './Content';
import Players from './Players';
import Chat from './Chat';
import Audit from './Audit';
import Payments from './Payments';
import Ads from './Ads';
import Feedback from './Feedback';
import Broadcast from './Broadcast';
import Earn from './Earn';
import Music from './Music';
import Market from './Market';
import Business from './Business';
import Crews from './Crews';
import Elections from './Elections';
import './admin.css';

const NAV = [
  { to: '/admin', label: 'Overview', icon: 'star', end: true },
  { to: '/admin/settings', label: 'Settings', icon: 'gear' },
  { to: '/admin/content', label: 'Content', icon: 'file' },
  { to: '/admin/players', label: 'Players', icon: 'people' },
  { to: '/admin/broadcast', label: 'Broadcast', icon: 'send' },
  { to: '/admin/earn', label: 'Earn', icon: 'cash' },
  { to: '/admin/music', label: 'Music', icon: 'music' },
  { to: '/admin/market', label: 'Market', icon: 'cash' },
  { to: '/admin/business', label: 'Business', icon: 'cash' },
  { to: '/admin/crews', label: 'Crews', icon: 'people' },
  { to: '/admin/elections', label: 'Elections', icon: 'star' },
  { to: '/admin/payments', label: 'Payments', icon: 'cash' },
  { to: '/admin/ads', label: 'Ads', icon: 'bell' },
  { to: '/admin/feedback', label: 'Feedback', icon: 'mail' },
  { to: '/admin/chat', label: 'Chat', icon: 'chat' },
  { to: '/admin/audit', label: 'Audit', icon: 'clock' },
];

/**
 * H3 fallback when Web Push is unavailable (iPhone not installed, blocked, desktop): poll the admin inbox every
 * 30 s while the admin page is open, show the unread count on the Ads tab and play a chime when it grows.
 * Also pushes anything queued (finished ads) so subscribed phones hear about it.
 */
function useAdminUnread(): number {
  const [unread, setUnread] = useState(0);
  const last = useRef<number | null>(null);
  useEffect(() => {
    let alive = true;
    const poll = async () => {
      try {
        const r = await rpc<{ unread: number; last_id: number }>('admin_notifications', { p_limit: 1 });
        if (!alive) return;
        if (last.current != null && r.last_id > last.current && r.unread > 0) {
          chime();
          flushAdminPush();
        }
        last.current = r.last_id;
        setUnread(r.unread);
        document.title = r.unread ? `(${r.unread}) Benin Life admin` : 'Benin Life admin';
      } catch { /* offline: try again */ }
    };
    void poll();
    flushAdminPush();
    const t = window.setInterval(() => { if (document.visibilityState === 'visible') void poll(); }, 30_000);
    const onSeen = () => void poll();
    window.addEventListener('bl-admin-seen', onSeen);
    return () => {
      alive = false;
      window.clearInterval(t);
      window.removeEventListener('bl-admin-seen', onSeen);
    };
  }, []);
  return unread;
}

export default function AdminApp() {
  ensureConfig();
  const name = useGame((s) => s.state?.profile.username);
  const unread = useAdminUnread();
  return (
    <div className="adm">
      <aside className="adm-side">
        <div className="adm-brand">
          <Logo size={34} title="" className="adm-brand__logo" />
          <span>
            <b>Benin Life</b>
            <small>Admin</small>
          </span>
        </div>
        <nav className="adm-nav" aria-label="Admin sections">
          {NAV.map((n) => (
            <NavLink key={n.to} to={n.to} end={n.end} className={({ isActive }) => `adm-nav__item${isActive ? ' is-active' : ''}`}>
              <Icon name={n.icon} size={18} />
              <span>{n.label}</span>
              {n.to === '/admin/ads' && unread > 0 && <span className="adm-nav__badge" aria-label={`${unread} new alerts`}>{unread > 99 ? '99+' : unread}</span>}
            </NavLink>
          ))}
        </nav>
        <div className="adm-side__foot">
          <span className="adm-sub">Signed in as <b>@{name}</b></span>
          <Link to="/play" className="adm-btn adm-btn--ghost"><Icon name="back" size={16} /> Back to game</Link>
        </div>
      </aside>

      <header className="adm-top">
        <div className="adm-brand">
          <Logo size={30} title="Benin Life" className="adm-brand__logo" />
          <b>Admin</b>
        </div>
        <Link to="/play" className="adm-btn adm-btn--ghost adm-btn--sm"><Icon name="back" size={14} /> Back to game</Link>
      </header>

      <main className="adm-main">
        <Routes>
          <Route index element={<Overview />} />
          <Route path="settings" element={<Settings />} />
          <Route path="content" element={<Content />} />
          <Route path="players" element={<Players />} />
          <Route path="chat" element={<Chat />} />
          <Route path="audit" element={<Audit />} />
          <Route path="payments" element={<Payments />} />
          <Route path="ads" element={<Ads />} />
          <Route path="feedback" element={<Feedback />} />
          <Route path="broadcast" element={<Broadcast />} />
          <Route path="earn" element={<Earn />} />
          <Route path="music" element={<Music />} />
          <Route path="market" element={<Market />} />
          <Route path="business" element={<Business />} />
          <Route path="crews" element={<Crews />} />
          <Route path="elections" element={<Elections />} />
          <Route path="*" element={<Navigate to="/admin" replace />} />
        </Routes>
      </main>

      <nav className="adm-tabbar" aria-label="Admin sections">
        {NAV.map((n) => (
          <NavLink key={n.to} to={n.to} end={n.end} className={({ isActive }) => `adm-tabbar__item${isActive ? ' is-active' : ''}`}>
            <Icon name={n.icon} size={20} />
            <span>{n.label}</span>
            {n.to === '/admin/ads' && unread > 0 && <span className="adm-tabbar__badge">{unread > 9 ? '9+' : unread}</span>}
          </NavLink>
        ))}
      </nav>
    </div>
  );
}
