// Benin Gist shared bits (docs/GIST.md): faces, gist text (#tags and @names are tappable), the group tile, a back header and the
// report sheet. Everything here renders inside the phone frame, like MiniSheet.
import { useState, type ReactNode } from 'react';
import { AvatarPortrait } from '../../../../art/avatar3d';
import { gistReport, type GistUser, type ReportKind } from '../../../../api/gist';
import { errorMessage } from '../../../../lib/api';
import type { AvatarConfig } from '../../../../lib/types';
import { Button, Icon, toast } from '../../../../ui';
import { MiniSheet } from '../DmConversation';
import './gist.css';

export function Face({ user, size = 44, onClick }: { user: Pick<GistUser, 'username' | 'avatar'>; size?: number; onClick?: () => void }) {
  const inner = (
    <span className="gist-face" style={{ width: size, height: size }}>
      {user.avatar ? <AvatarPortrait config={user.avatar as AvatarConfig} size={size} /> : <b>{user.username.slice(0, 1).toUpperCase()}</b>}
    </span>
  );
  return onClick ? <button type="button" className="gist-face-btn" aria-label={`@${user.username}'s profile`} onClick={onClick}>{inner}</button> : inner;
}

const TOKEN = /(#[A-Za-z0-9_]{2,24}|@[A-Za-z0-9_]{3,20})/g;

/** Gist text: #tags open that tag's feed, @names open that player's profile (by username). */
export function GistText({ text, onTag, onMention }: { text: string; onTag?: (tag: string) => void; onMention?: (username: string) => void }) {
  const parts = text.split(TOKEN);
  return (
    <>
      {parts.map((p, i) => {
        if (i % 2 === 0) return p;
        if (p.startsWith('#')) {
          return <button key={i} type="button" className="gist-tag" onClick={() => onTag?.(p.slice(1).toLowerCase())}>{p}</button>;
        }
        return <button key={i} type="button" className="gist-mention" onClick={() => onMention?.(p.slice(1))}>{p}</button>;
      })}
    </>
  );
}

const TILE_COLORS = ['#e5effc', '#e3f5ea', '#fdf3c4', '#fde7e4', '#efe7fb', '#e0f4f4', '#fff0dc', '#f0f3d8'];
export function groupTint(id: number) { return TILE_COLORS[Math.abs(id) % TILE_COLORS.length]; }

export function GroupTile({ id, emoji, size = 56 }: { id: number; emoji: string; size?: number }) {
  return <span className="gist-tile" style={{ width: size, height: size, background: groupTint(id), fontSize: Math.round(size * 0.5) }} aria-hidden>{emoji}</span>;
}

/** Full-width page header with a back arrow (used by post, profile, group and settings pages). */
export function PageHead({ title, sub, onBack, right, lead }: { title: ReactNode; sub?: ReactNode; onBack: () => void; right?: ReactNode; lead?: ReactNode }) {
  return (
    <header className="gist-pagehead">
      <button type="button" className="msgs-iconbtn msgs-iconbtn--bare" onClick={onBack} aria-label="Back"><Icon name="back" size={22} stroke={2.6} /></button>
      {lead}
      <div className="gist-pagehead__text">
        <h2>{title}</h2>
        {sub && <small>{sub}</small>}
      </div>
      {right}
    </header>
  );
}

const REASONS = ['Spam or scam', 'Rude or hateful', 'Not safe for work', 'Something else'];

/** Report a gist, comment, group or group message. One report per player per target; a moderator reviews it in Admin -> Gist. */
export function ReportSheet({ kind, id, onClose, onDone }: { kind: ReportKind; id: number; onClose: () => void; onDone?: (hidden: boolean) => void }) {
  const [busy, setBusy] = useState(false);
  const send = async (reason: string) => {
    setBusy(true);
    try {
      const r = await gistReport(kind, id, reason);
      toast(r.message, 'good');
      onDone?.(r.hidden);
      onClose();
    } catch (e) { toast(errorMessage(e), 'bad'); setBusy(false); }
  };
  const what = kind === 'post' ? 'gist' : kind;
  return (
    <MiniSheet title={`Report this ${what}`} onClose={onClose}>
      <div className="dm-sheet__body gist-reasons">
        <p className="dm-sheet__lead">Why are you reporting it? A moderator will look. Your name is not shown.</p>
        {REASONS.map((r) => <Button key={r} variant="ghost" block disabled={busy} onClick={() => void send(r)}>{r}</Button>)}
      </div>
    </MiniSheet>
  );
}

/** "12" / "1.2K" for counters. */
export function count(n: number) {
  if (n < 1000) return String(n);
  return `${(n / 1000).toFixed(n < 10_000 ? 1 : 0).replace(/\.0$/, '')}K`;
}
