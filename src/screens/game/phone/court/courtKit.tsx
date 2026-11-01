// Court app shared bits (docs/COURT.md): faces, the case card, the lawyer card, rank badge, clock helpers.
// Look: the UI pass cards. A small grey label, a big bold main line, a meta line, a divider, then the people row.
import { useEffect, useState, type ReactNode } from 'react';
import { AvatarPortrait } from '../../../../art/avatar3d';
import { KIND_ICON, roleLabel, type CourtCard, type CourtLawyer, type CourtPerson } from '../../../../api/court';
import { naira } from '../../../../lib/format';
import type { AvatarConfig } from '../../../../lib/types';

export function useNow(ms = 1000): number {
  const [now, setNow] = useState(() => Date.now());
  useEffect(() => {
    const t = window.setInterval(() => setNow(Date.now()), ms);
    return () => window.clearInterval(t);
  }, [ms]);
  return now;
}

export const hhmm = (iso: string | null | undefined) =>
  iso ? new Date(iso).toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit', timeZone: 'Africa/Lagos' }) : '';
export const dayTime = (iso: string | null | undefined) =>
  iso ? new Date(iso).toLocaleString('en-GB', { weekday: 'short', day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit', timeZone: 'Africa/Lagos' }) : '';

export function mmss(totalSeconds: number): string {
  const s = Math.max(0, Math.floor(totalSeconds));
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  const r = s % 60;
  return h > 0 ? `${h}:${String(m).padStart(2, '0')}:${String(r).padStart(2, '0')}` : `${m}:${String(r).padStart(2, '0')}`;
}

export function Face({ who, size = 44 }: { who: Pick<CourtPerson, 'username' | 'avatar'> | null; size?: number }) {
  return (
    <span className="ct-face" style={{ width: size, height: size }}>
      {who?.avatar ? <AvatarPortrait config={who.avatar as AvatarConfig} size={size} /> : <b>{(who?.username ?? '?').slice(0, 1).toUpperCase()}</b>}
    </span>
  );
}

export function RankBadge({ rank }: { rank: string }) {
  const tone = rank === 'Senior Advocate' ? 'gold' : rank === 'Barrister' ? 'violet' : rank === 'Advocate' ? 'green' : 'grey';
  return <span className={`ct-rank ct-rank--${tone}`}>{rank}</span>;
}

export function Badge({ tone, children }: { tone: 'live' | 'ruled' | 'soon' | 'win' | 'lose' | 'grey'; children: ReactNode }) {
  return <span className={`ct-badge ct-badge--${tone}`}>{children}</span>;
}

export function Name({ p }: { p: CourtPerson | null }) {
  if (!p) return <span className="ct-name">nobody yet</span>;
  return <span className="ct-name">{p.title && <em>{p.title} </em>}@{p.username}</span>;
}

/** The two sides of a case: avatars with names, "vs" in the middle. */
export function Sides({ c, size = 44 }: { c: Pick<CourtCard, 'plaintiff' | 'defendant'>; size?: number }) {
  return (
    <div className="ct-sides">
      <div className="ct-side"><Face who={c.plaintiff} size={size} /><span><small>Plaintiff</small><Name p={c.plaintiff} /></span></div>
      <span className="ct-vs" aria-hidden>vs</span>
      <div className="ct-side ct-side--r"><span><small>Defendant</small><Name p={c.defendant} /></span><Face who={c.defendant} size={size} /></div>
    </div>
  );
}

export function verdictLabel(c: Pick<CourtCard, 'verdict' | 'status' | 'role'>): { tone: 'win' | 'lose' | 'grey'; text: string } {
  if (c.status === 'dismissed') return { tone: 'grey', text: 'Dismissed' };
  if (c.verdict === 'guilty') return { tone: c.role === 'defendant' ? 'lose' : 'win', text: 'Guilty' };
  if (c.verdict === 'not_guilty') return { tone: c.role === 'defendant' ? 'win' : c.role === 'plaintiff' ? 'lose' : 'grey', text: 'Not guilty' };
  return { tone: 'grey', text: '' };
}

/** A case as a card: label, main line, meta line, divider, people row. */
export function CaseCard({ c, now, onOpen, cta }: { c: CourtCard; now: number; onOpen: () => void; cta?: string }) {
  const starts = Math.round((Date.parse(c.hearing_at) - now) / 1000);
  const v = verdictLabel(c);
  const meta = c.status === 'ruled' ? `Ruled ${dayTime(c.ruled_at)}${c.verdict_by === 'auto' ? ' · automatic' : c.verdict_by === 'admin' ? ' · by an admin' : ''}`
    : c.status === 'dismissed' ? 'Dismissed by the court'
      : c.live ? `Started ${hhmm(c.hearing_at)} · ruling due by ${hhmm(c.ruling_deadline)}`
        : `Starts ${hhmm(c.hearing_at)}${starts > 0 ? ` · in ${mmss(starts)}` : ''}`;
  return (
    <button type="button" className={`ct-card${c.live ? ' is-live' : ''}`} onClick={onOpen} data-testid={`court-case-${c.id}`}>
      <span className="ct-card__top">
        <span className="ct-label">{c.court} · {c.case_no}</span>
        {c.live ? <Badge tone="live"><i aria-hidden /> LIVE</Badge> : c.status === 'ruled' ? <Badge tone={v.tone}>{v.text}</Badge> : c.status === 'dismissed' ? <Badge tone="grey">Dismissed</Badge> : <Badge tone="soon">Soon</Badge>}
      </span>
      <span className="ct-main"><span aria-hidden>{KIND_ICON[c.kind]}</span> {c.title}</span>
      <span className="ct-meta">{naira(c.claim)} claimed · {meta}</span>
      <span className="ct-divider" />
      <Sides c={c} size={40} />
      <span className="ct-card__foot">
        <span className="ct-meta">{c.role !== 'visitor' ? roleLabel(c.role) : 'Open court'}{c.judge ? ` · Hon. Justice @${c.judge.username}` : c.status === 'scheduled' ? ' · judge not yet assigned' : ''}</span>
        {c.status === 'scheduled' && <span className="ct-gal" title="Gallery">👁 {c.gallery}/{c.gallery_size}</span>}
        {cta && <span className="ct-cta">{cta}</span>}
      </span>
    </button>
  );
}

export function LawyerCard({ l, action, selected, onPick, compact }: { l: CourtLawyer; action?: ReactNode; selected?: boolean; onPick?: () => void; compact?: boolean }) {
  const body = (
    <>
      <Face who={l} size={compact ? 40 : 48} />
      <span className="ct-lawyer__main">
        <span className="ct-lawyer__name">@{l.username} <RankBadge rank={l.rank} /></span>
        <span className="ct-meta">{l.wins} won · {l.losses} lost · {l.available_now ? <b className="ct-ok">available now</b> : l.available ? 'away' : 'not taking cases'}</span>
        {!compact && l.bio && <span className="ct-bio">{l.bio}</span>}
      </span>
      <span className="ct-lawyer__fee"><small>Fee</small><b>{naira(l.fee)}</b></span>
    </>
  );
  if (onPick) return <button type="button" className={`ct-lawyer${selected ? ' is-on' : ''}`} onClick={onPick} aria-pressed={selected}>{body}</button>;
  return <div className="ct-lawyer">{body}{action && <div className="ct-lawyer__act">{action}</div>}</div>;
}
