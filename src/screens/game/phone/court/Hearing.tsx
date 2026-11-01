// A hearing, live: both sides (or their lawyers) post short statements, the judge rules, a bounded gallery watches.
// Realtime: ONE channel for THIS case (court_statements, RLS lets only people in the case or the gallery see rows), a slow check-in poll
// that also keeps the gallery seat and lets the lazy court clock settle the case, and a faster poll when Realtime is in fallback mode.
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import type { RealtimeChannel } from '@supabase/supabase-js';
import {
  courtAfter, courtCase, courtGalleryJoin, courtGalleryLeave, courtHire, courtJudgeTake, courtPost, courtRule, KIND_HELP, KIND_ICON, KIND_LABEL, roleLabel,
  type CourtCase, type CourtStatement,
} from '../../../../api/court';
import { errorMessage } from '../../../../lib/api';
import { naira } from '../../../../lib/format';
import { startPoller, trackSubscribe, usePollMode } from '../../../../lib/realtime';
import { supabase } from '../../../../lib/supabase';
import { Button, toast } from '../../../../ui';
import { LawyerList } from './LawyerPanel';
import { Badge, Face, hhmm, mmss, Name, RankBadge, Sides, useNow, verdictLabel } from './courtKit';

const FACTS: [string, string, 'naira' | 'text' | 'days'][] = [
  ['place', 'Place', 'text'], ['amount', 'Taken', 'naira'], ['property', 'Property', 'text'], ['owed', 'Rent owed', 'naira'], ['caution_kept', 'Caution kept', 'naira'],
  ['unpaid', 'Still unpaid', 'naira'], ['stay_days', 'Stay before notice', 'days'], ['item', 'Item', 'text'], ['price', 'Price paid', 'naira'], ['value', 'Value', 'naira'],
];

function Bubble({ m, me }: { m: CourtStatement; me: string }) {
  if (m.kind === 'ruling') return <div className="ct-ruling"><span className="ct-label">The ruling</span><p>{m.body}</p></div>;
  const mine = m.author === me;
  return (
    <div className={`ct-msg ct-msg--${m.side}${mine ? ' is-mine' : ''}`}>
      <span className="ct-msg__who">
        {m.side === 'bench' ? 'Hon. Justice' : m.side === 'plaintiff' ? 'Plaintiff' : 'Defendant'}{m.as_lawyer ? ' (lawyer)' : ''} · @{m.author ?? 'court'}
      </span>
      <p>{m.body}</p>
    </div>
  );
}

export function Hearing({ id, myName, isJudge, onBack, onChanged }: { id: number; myName: string; isJudge: boolean; onBack: () => void; onChanged: () => void }) {
  const [c, setC] = useState<CourtCase | null>(null);
  const [msgs, setMsgs] = useState<CourtStatement[]>([]);
  const [err, setErr] = useState('');
  const [text, setText] = useState('');
  const [note, setNote] = useState('');
  const [busy, setBusy] = useState(false);
  const [hiring, setHiring] = useState(false);
  const pollMode = usePollMode();
  const now = useNow(1000);
  const lastId = useRef(0);
  const endRef = useRef<HTMLDivElement>(null);
  const cRef = useRef<CourtCase | null>(null);
  cRef.current = c;

  const load = useCallback(async () => {
    try {
      const r = await courtCase(id);
      setC(r);
      setMsgs(r.statements);
      lastId.current = r.statements.reduce((m, s) => Math.max(m, s.id), 0);
      setErr('');
    } catch (e) { setErr(errorMessage(e)); }
  }, [id]);
  useEffect(() => { void load(); }, [load]);

  const take = useCallback((rows: CourtStatement[]) => {
    if (!rows.length) return;
    setMsgs((cur) => {
      const have = new Set(cur.map((x) => x.id));
      const add = rows.filter((x) => !have.has(x.id));
      return add.length ? [...cur, ...add].sort((a, b) => a.id - b.id) : cur;
    });
    lastId.current = Math.max(lastId.current, ...rows.map((x) => x.id));
    if (rows.some((x) => x.kind === 'ruling')) { void load(); onChanged(); }
  }, [load, onChanged]);

  const watching = Boolean(c && c.status === 'scheduled' && (c.me.participant || c.me.in_gallery));
  // live: one channel for this case, plus a slow check-in; fallback: a faster poll
  useEffect(() => {
    if (!watching) return;
    const checkin = async () => {
      const r = await courtAfter(id, lastId.current);
      take(r.statements);
      setC((cur) => (cur ? { ...cur, gallery: r.gallery } : cur));
      if (r.status !== 'scheduled') { void load(); onChanged(); }
    };
    if (pollMode) {
      const p = startPoller(checkin, () => 6000, { immediate: true });
      return () => p.stop();
    }
    const channel: RealtimeChannel = supabase.channel(`court-${id}`)
      .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'court_statements', filter: `case_id=eq.${id}` }, (payload) => {
        const r = payload.new as Record<string, unknown>;
        take([{ id: Number(r.id), side: r.side as CourtStatement['side'], kind: r.kind as CourtStatement['kind'], as_lawyer: Boolean(r.as_lawyer), body: String(r.body), at: String(r.created_at), author: null }]);
        void checkin(); // fills in the author name
      });
    trackSubscribe(channel, 'court', (s) => { if (s === 'SUBSCRIBED') void checkin(); });
    const p = startPoller(checkin, () => 45_000);
    return () => { p.stop(); void supabase.removeChannel(channel); };
  }, [watching, pollMode, id, take, load, onChanged]);

  // the hearing starts: refresh once so the composer and the LIVE badge appear
  const startMs = c ? Date.parse(c.hearing_at) : 0;
  const started = c ? now >= startMs : false;
  useEffect(() => { if (c && c.status === 'scheduled' && started && !c.live) void load(); }, [c, started, load]);
  useEffect(() => { endRef.current?.scrollIntoView({ block: 'end' }); }, [msgs.length]);
  useEffect(() => () => { void courtGalleryLeave(id).catch(() => undefined); }, [id]);

  const act = async (fn: () => Promise<{ message?: string; closed?: boolean } | unknown>, ok?: string) => {
    setBusy(true);
    try {
      const r = (await fn()) as { message?: string; closed?: boolean } | undefined;
      if (r && 'closed' in r && r.closed) toast(r.message ?? 'This hearing is over.');
      else if (ok || r?.message) toast(ok ?? r?.message ?? '', 'good');
      await load(); onChanged();
    } catch (e) { toast(errorMessage(e), 'bad'); } finally { setBusy(false); }
  };

  const facts = useMemo(() => (c ? FACTS.filter(([k]) => c.evidence[k] !== undefined && c.evidence[k] !== null) : []), [c]);
  if (err && !c) return <div className="ct-stack"><button type="button" className="ct-back" onClick={onBack}>← Back</button><p className="error-text">{err}</p></div>;
  if (!c) return <div className="ct-stack"><div className="ct-skel"><span /><span /><span /></div></div>;

  const max = c.settings.statement_max_len;
  const left = c.settings.statement_max_len - text.length;
  const startsIn = Math.max(0, Math.round((startMs - now) / 1000));
  const v = verdictLabel(c);
  const canSeat = c.status === 'scheduled' && c.me.role === 'visitor';
  const unassignedJudge = isJudge && c.status === 'scheduled' && !c.judge && c.me.role === 'visitor';
  const lawyerOf = (side: 'plaintiff' | 'defendant') => c.hires.find((h) => h.side === side && (h.status === 'accepted' || h.status === 'paid' || h.status === 'pending'));
  return (
    <div className="ct-stack ct-hearing">
      <button type="button" className="ct-back" onClick={onBack}>← Back</button>
      <section className="ct-panel">
        <span className="ct-card__top"><span className="ct-label">{c.court} · {c.case_no}</span>
          {c.live ? <Badge tone="live"><i aria-hidden /> LIVE</Badge> : c.status === 'ruled' ? <Badge tone={v.tone}>{v.text}</Badge> : c.status === 'dismissed' ? <Badge tone="grey">Dismissed</Badge> : <Badge tone="soon">Soon</Badge>}</span>
        <h2 className="ct-title ct-title--sm"><span aria-hidden>{KIND_ICON[c.kind]}</span> {c.title}</h2>
        <span className="ct-meta">{KIND_LABEL[c.kind]} · {naira(c.claim)} claimed · {roleLabel(c.me.role)}</span>
        <span className="ct-divider" />
        <Sides c={c} size={46} />
        <div className="ct-people">
          {(['plaintiff', 'defendant'] as const).map((side) => { const h = lawyerOf(side); return h ? (
            <span key={side} className="ct-chip"><Face who={h.lawyer} size={22} /> @{h.lawyer.username} <RankBadge rank={h.lawyer.rank} />{h.status === 'pending' ? ' · waiting' : ''}</span>
          ) : null; })}
          <span className="ct-chip">⚖️ {c.judge ? <>Hon. Justice <Name p={c.judge} /></> : 'No judge yet'}</span>
          {c.status === 'scheduled' && <span className="ct-chip">👁 {c.gallery}/{c.gallery_size} in the gallery</span>}
        </div>
        {c.status === 'scheduled' && (
          <p className="ct-clock">{started ? <>The hearing is on. The judge must rule by <b>{hhmm(c.ruling_deadline)}</b>, or the automatic ruling decides from the record.</>
            : <>Starts at <b>{hhmm(c.hearing_at)}</b> · in <b>{mmss(startsIn)}</b></>}</p>
        )}
      </section>

      {facts.length > 0 && (
        <section className="ct-panel">
          <span className="ct-label">What the game recorded</span>
          <dl className="ct-dl">
            {facts.map(([k, label, kind]) => { const val = c.evidence[k]; return <div key={k}><dt>{label}</dt><dd>{kind === 'naira' ? naira(Number(val)) : kind === 'days' ? `${val} days` : String(val)}</dd></div>; })}
          </dl>
          <span className="ct-meta">{KIND_HELP[c.kind]}</span>
        </section>
      )}

      {c.status === 'ruled' && (
        <section className={`ct-verdict ct-verdict--${v.tone}`}>
          <span className="ct-label">Verdict{c.verdict_by === 'auto' ? ' · automatic' : c.verdict_by === 'admin' ? ' · by an admin' : ''}{c.overridden ? ' · overruled' : ''}</span>
          <span className="ct-verdict__word">{c.verdict === 'guilty' ? 'GUILTY' : 'NOT GUILTY'}</span>
          {c.verdict === 'guilty' ? (
            <dl className="ct-dl">
              <div><dt>Paid back to the plaintiff</dt><dd>{naira(c.restitution_paid)}</dd></div>
              {c.restitution_debt > 0 && <div><dt>Court debt (from future income)</dt><dd>{naira(c.restitution_debt)}</dd></div>}
              <div><dt>Fine</dt><dd>{naira(c.fine)}</dd></div>
              {c.cred_hit > 0 && <div><dt>Street cred lost</dt><dd>{c.cred_hit}</dd></div>}
              {c.jail_seconds > 0 && <div><dt>Repeat offender: jail</dt><dd>{c.jail_seconds} s</dd></div>}
            </dl>
          ) : <span className="ct-meta">The case is dismissed. The plaintiff loses the filing fee.</span>}
          {c.verdict_note && <span className="ct-meta">{c.verdict_note}</span>}
        </section>
      )}

      {/* lawyers */}
      {c.me.can_hire && !hiring && <Button variant="gold" block onClick={() => setHiring(true)}>Hire a lawyer</Button>}
      {hiring && c.me.can_hire && (
        <section className="ct-panel">
          <span className="ct-label">Hire a lawyer</span>
          <span className="ct-meta">The fee is held until the verdict. If the lawyer says no, or does not answer before the hearing, it comes back.</span>
          <LawyerList skipMe action={(l) => <Button size="sm" variant="green" loading={busy} onClick={() => void act(async () => { const r = await courtHire(c.id, l.user_id); setHiring(false); return r; })}>Hire for {naira(l.fee)}</Button>} />
        </section>
      )}

      {/* judge */}
      {unassignedJudge && <Button variant="green" block loading={busy} onClick={() => void act(() => courtJudgeTake(c.id))}>Take this case as the judge</Button>}
      {c.me.role === 'judge' && c.status === 'scheduled' && (
        <section className="ct-panel ct-bench">
          <span className="ct-label">The bench</span>
          {c.me.can_rule ? (
            <>
              <span className="ct-meta">Read both sides, then rule. The money moves at once.</span>
              <textarea className="ct-input" rows={2} maxLength={300} value={note} onChange={(e) => setNote(e.target.value)} placeholder="A short reason for the record (optional)" aria-label="Reason for the ruling" />
              <div className="ct-row">
                <Button variant="green" loading={busy} onClick={() => void act(() => courtRule(c.id, 'guilty', note))}>Guilty</Button>
                <Button variant="danger" loading={busy} onClick={() => void act(() => courtRule(c.id, 'not_guilty', note))}>Not guilty</Button>
              </div>
            </>
          ) : <span className="ct-meta">{started ? `You can rule from ${hhmm(c.me.rule_from)}, so both sides can speak.` : `The hearing starts at ${hhmm(c.hearing_at)}.`}</span>}
        </section>
      )}

      {/* the record */}
      <section className="ct-panel ct-thread">
        <span className="ct-label">{c.status === 'scheduled' ? (c.live ? 'Live statements' : 'Statements') : 'Case record'}</span>
        {!c.can_see && <p className="ct-meta">{canSeat ? 'Take a seat in the gallery to watch the hearing live.' : 'Statements are shown to the people in the hearing.'}</p>}
        {c.can_see && !msgs.length && <p className="ct-meta">{c.live ? 'No statements yet.' : 'Nobody has spoken yet. Statements open when the hearing starts.'}</p>}
        {msgs.map((m) => <Bubble key={m.id} m={m} me={myName} />)}
        <div ref={endRef} />
      </section>

      {canSeat && (
        <Button variant="green" block loading={busy} onClick={() => void act(() => courtGalleryJoin(c.id), 'You have a seat in the gallery.')}>
          Take a seat in the gallery ({c.gallery}/{c.gallery_size})
        </Button>
      )}

      {c.me.can_post && c.status === 'scheduled' && (
        <form className="ct-compose" onSubmit={(e) => { e.preventDefault(); if (!text.trim()) return; const body = text; setText(''); void act(() => courtPost(c.id, body)); }}>
          <textarea className="ct-input" rows={2} maxLength={max} value={text} onChange={(e) => setText(e.target.value)} placeholder={c.me.role === 'judge' ? 'A remark from the bench' : 'Your statement, short and clear'} aria-label="Statement" />
          <div className="ct-compose__row">
            <span className="ct-meta">{left} left · {c.me.statements_left} statement{c.me.statements_left === 1 ? '' : 's'} left for your side</span>
            <Button type="submit" variant="green" size="sm" loading={busy} disabled={!text.trim() || c.me.statements_left < 1}>Send</Button>
          </div>
        </form>
      )}
    </div>
  );
}
