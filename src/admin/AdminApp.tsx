// /admin (V1-7): owner dashboard. Lazy chunk, loaded by src/screens/AdminRoute.tsx for admins only.
// The route gate is just a door: every RPC used here re-checks bl_is_admin() on the server.
import { NavLink, Navigate, Route, Routes, Link } from 'react-router-dom';
import { Icon } from '../ui';
import { ensureConfig } from '../lib/config';
import { useGame } from '../state/game';
import Overview from './Overview';
import Settings from './Settings';
import Content from './Content';
import Players from './Players';
import Chat from './Chat';
import Audit from './Audit';
import Payments from './Payments';
import './admin.css';

const NAV = [
  { to: '/admin', label: 'Overview', icon: 'star', end: true },
  { to: '/admin/settings', label: 'Settings', icon: 'gear' },
  { to: '/admin/content', label: 'Content', icon: 'file' },
  { to: '/admin/players', label: 'Players', icon: 'people' },
  { to: '/admin/payments', label: 'Payments', icon: 'cash' },
  { to: '/admin/chat', label: 'Chat', icon: 'chat' },
  { to: '/admin/audit', label: 'Audit', icon: 'clock' },
];

export default function AdminApp() {
  ensureConfig();
  const name = useGame((s) => s.state?.profile.username);
  return (
    <div className="adm">
      <aside className="adm-side">
        <div className="adm-brand">
          <span className="adm-brand__mark" aria-hidden><Icon name="crown" size={18} /></span>
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
          <span className="adm-brand__mark" aria-hidden><Icon name="crown" size={16} /></span>
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
          <Route path="*" element={<Navigate to="/admin" replace />} />
        </Routes>
      </main>

      <nav className="adm-tabbar" aria-label="Admin sections">
        {NAV.map((n) => (
          <NavLink key={n.to} to={n.to} end={n.end} className={({ isActive }) => `adm-tabbar__item${isActive ? ' is-active' : ''}`}>
            <Icon name={n.icon} size={20} />
            <span>{n.label}</span>
          </NavLink>
        ))}
      </nav>
    </div>
  );
}
