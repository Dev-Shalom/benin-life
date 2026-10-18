// R12 Elections admin (docs/POLITICS.md): start / advance / cancel an election, see the candidates (with vote-buying reports) and disqualify
// them, remove a sitting officeholder, and read the tallies once an election has closed. Every action is audited. Ballot secrecy: until the
// close the page shows turnout only, never a count per candidate. Windows, fees and costs: Settings -> Politics. Offices and policies: Content.
import { useState } from 'react';
import {
  adminPolAdvance, adminPolCancel, adminPolDisqualify, adminPolDismissReports, adminPolOverview, adminPolRemoveHolder, adminPolStart, adminPolTallies,
  type AdminPolCandidate, type AdminPolTallies,
} from '../api/politics';
import { errorMessage } from '../lib/api';
import { naira } from '../lib/format';
import { toast } from '../ui';
import { Badge, Btn, ConfirmButton, LoadError, PageHead, Skeleton } from './parts';
import { timeShort, useLoad } from './util';

const when = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleString('en-GB', { weekday: 'short', day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' }) : '—');
const num = (v: string): number | null => (v.trim() === '' ? null : Number(v));

export default function Elections() {
  const { data, error, loading, reload } = useLoad(() => adminPolOverview(), []);
  const [reg, setReg] = useState('');
  const [camp, setCamp] = useState('');
  const [vote, setVote] = useState('');
  const [term, setTerm] = useState('');
  const [reason, setReason] = useState('');
  const [tallies, setTallies] = useState<AdminPolTallies | null>(null);
  if (error && !data) return <LoadError error={error} onRetry={() => void reload()} />;
  if (!data) return <Skeleton rows={6} />;
  const c = data.cycle;
  const run = async (fn: () => Promise<{ message: string }>) => {
    try { toast((await fn()).message, 'good'); setReason(''); } catch (e) { toast(errorMessage(e), 'bad'); }
    void reload();
  };
  const showTallies = async (id: number) => {
    try { setTallies(await adminPolTallies(id)); } catch (e) { toast(errorMessage(e), 'bad'); }
  };
  const cands = data.candidates;
  const statusTone = (s: AdminPolCandidate['status']) => (s === 'disqualified' ? 'red' : s === 'withdrawn' ? 'grey' : 'green');
  return (
    <div className="adm-page" data-testid="admin-elections">
      <PageHead title="Elections" sub="Benin Votes: start, advance or cancel an election; disqualify; tallies after the close"
        actions={<Btn small icon="refresh" onClick={() => void reload()} disabled={loading}>Refresh</Btn>} />
      {!data.enabled && <section className="adm-card"><p className="adm-sub">Benin Votes is switched off in Settings, Politics. Nothing moves until you switch it on.</p></section>}
      <section className="adm-card">
        <h3>{c ? `Election #${c.id}: ${c.status}` : 'No election running'}</h3>
        {c ? (
          <>
            <p className="adm-sub">
              Registration {when(c.reg_start)} · Campaign {when(c.camp_start)} · Voting {when(c.vote_start)} to {when(c.vote_end)} · term {c.term_days} days ·
              started {c.created_by ? `by @${c.created_by}` : 'by itself (auto cycle)'}
            </p>
            <p className="adm-sub">Turnout so far: {c.votes_cast} vote{c.votes_cast === 1 ? '' : 's'} from {c.voters} voter{c.voters === 1 ? '' : 's'}. Counts per candidate stay secret until the close.</p>
            <div className="adm-row">
              <ConfirmButton tone="primary" small confirmText={`Tap again: end ${c.status} now`} onConfirm={() => run(() => adminPolAdvance())}>Advance to the next phase</ConfirmButton>
              <input className="adm-input" value={reason} maxLength={200} onChange={(e) => setReason(e.target.value)} placeholder="Reason (for cancel, disqualify, remove)" aria-label="Reason" />
              <ConfirmButton tone="danger" small confirmText="Tap again: cancel and refund fees" onConfirm={() => { if (!reason.trim()) { toast('Write a reason first.', 'bad'); return; } return run(() => adminPolCancel(reason.trim())); }}>Cancel the election</ConfirmButton>
            </div>
          </>
        ) : (
          <>
            <p className="adm-sub">{data.auto_cycle ? 'The next election starts by itself when the current term is nearly over (Settings, Politics). ' : 'Auto cycle is off. '}Start one now (leave a box empty to use the Settings value). Whoever wins replaces the whole government.</p>
            <div className="adm-row">
              <input className="adm-input" value={reg} onChange={(e) => setReg(e.target.value)} placeholder="Registration hours" aria-label="Registration hours" inputMode="decimal" style={{ maxWidth: 150 }} />
              <input className="adm-input" value={camp} onChange={(e) => setCamp(e.target.value)} placeholder="Campaign hours" aria-label="Campaign hours" inputMode="decimal" style={{ maxWidth: 150 }} />
              <input className="adm-input" value={vote} onChange={(e) => setVote(e.target.value)} placeholder="Voting hours" aria-label="Voting hours" inputMode="decimal" style={{ maxWidth: 150 }} />
              <input className="adm-input" value={term} onChange={(e) => setTerm(e.target.value)} placeholder="Term days" aria-label="Term days" inputMode="decimal" style={{ maxWidth: 150 }} />
              <ConfirmButton tone="primary" small confirmText="Tap again: open registration" onConfirm={() => run(() => adminPolStart(num(reg), num(camp), num(vote), num(term)))}>Start an election</ConfirmButton>
            </div>
          </>
        )}
      </section>

      <section className="adm-card">
        <h3>Candidates{data.shown_cycle ? ` (election #${data.shown_cycle})` : ''}</h3>
        {cands.length === 0 ? <p className="adm-sub">Nobody has declared.</p> : (
          <div className="adm-scroll">
            <table className="adm-table">
              <thead><tr><th>Race</th><th>Candidate</th><th>Party</th><th>Promise</th><th>Rally pts</th><th>Backing</th><th>Reports</th><th>Status</th><th /></tr></thead>
              <tbody>
                {cands.map((k) => (
                  <tr key={k.id}>
                    <td>{k.office}{k.ward ? ` · ${k.ward}` : ''}</td>
                    <td><b>@{k.username}</b>{k.final_votes != null && <div className="adm-sub">{k.final_votes} votes{k.won ? ' · won' : ''}</div>}</td>
                    <td>{k.party ? `${k.party.abbr}` : 'Ind.'}</td>
                    <td style={{ maxWidth: 220 }}>{k.promise}</td>
                    <td>{k.rally_points} <span className="adm-sub">({k.rallies} rall{k.rallies === 1 ? 'y' : 'ies'}, {k.posters} poster{k.posters === 1 ? '' : 's'})</span></td>
                    <td>{k.supporters} supporter{k.supporters === 1 ? '' : 's'} · {k.endorsements} endorsement{k.endorsements === 1 ? '' : 's'}</td>
                    <td>
                      {k.reports > 0 ? <Badge tone={k.flagged ? 'red' : 'amber'}>{k.reports} open</Badge> : '–'}
                      {k.report_texts.map((t, i) => <div key={i} className="adm-sub">“{t}”</div>)}
                    </td>
                    <td><Badge tone={statusTone(k.status)}>{k.status}</Badge>{k.dq_reason && <div className="adm-sub">{k.dq_reason}</div>}</td>
                    <td>
                      {k.status === 'declared' && c && (
                        <div className="adm-row">
                          <ConfirmButton tone="danger" small confirmText="Tap again: disqualify" onConfirm={() => { if (!reason.trim()) { toast('Write a reason first.', 'bad'); return; } return run(() => adminPolDisqualify(k.id, reason.trim())); }}>Disqualify</ConfirmButton>
                          {k.reports > 0 && <Btn small onClick={() => void run(() => adminPolDismissReports(k.id))}>Reports reviewed</Btn>}
                        </div>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>

      <section className="adm-card">
        <h3>Sitting government</h3>
        {data.holders.length === 0 ? <p className="adm-sub">No seats are filled.</p> : (
          <div className="adm-scroll">
            <table className="adm-table">
              <thead><tr><th>Office</th><th>Holder</th><th>Party</th><th>Term ends</th><th>Policy</th><th>Salary paid</th><th /></tr></thead>
              <tbody>
                {data.holders.map((h) => (
                  <tr key={h.id}>
                    <td>{h.office}{h.ward ? ` · ${h.ward}` : ''}</td>
                    <td><b>{h.title} @{h.username}</b></td>
                    <td>{h.party?.abbr ?? 'Ind.'}</td>
                    <td>{when(h.term_end)}</td>
                    <td>{h.policy ? `${h.policy.icon} ${h.policy.name}` : '–'}</td>
                    <td>{naira(h.salary_paid)}</td>
                    <td><ConfirmButton tone="danger" small confirmText="Tap again: remove" onConfirm={() => { if (!reason.trim()) { toast('Write a reason first.', 'bad'); return; } return run(() => adminPolRemoveHolder(h.id, reason.trim())); }}>Remove</ConfirmButton></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>

      <section className="adm-card">
        <h3>History</h3>
        <div className="adm-scroll">
          <table className="adm-table">
            <thead><tr><th>#</th><th>Status</th><th>Registration opened</th><th>Voting ended</th><th>Candidates</th><th>Votes</th><th /></tr></thead>
            <tbody>
              {data.history.map((x) => (
                <tr key={x.id}>
                  <td>{x.id}</td>
                  <td><Badge tone={x.status === 'closed' ? 'green' : x.status === 'cancelled' ? 'grey' : 'blue'}>{x.status}</Badge>{x.cancel_reason && <div className="adm-sub">{x.cancel_reason}</div>}</td>
                  <td>{timeShort(x.reg_start)}</td>
                  <td>{when(x.vote_end)}</td>
                  <td>{x.candidates}</td>
                  <td>{x.votes ?? '–'}</td>
                  <td>{x.status === 'closed' && <Btn small onClick={() => void showTallies(x.id)}>Tallies</Btn>}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        {tallies && (
          <div data-testid="admin-tallies">
            <h4>Tallies for election #{tallies.cycle}</h4>
            {tallies.races.map((r, i) => (
              <p key={i} className="adm-sub"><b>{r.office}{r.ward ? ` · ${r.ward}` : ''}</b>{r.tie ? ` (${r.tie === 'rally' ? 'tie broken by rally points' : 'tie broken by a coin flip'})` : ''}: {r.candidates.map((x) => `${x.won ? '★ ' : ''}@${x.username} ${x.votes}`).join(' · ')}</p>
            ))}
            <Btn small onClick={() => setTallies(null)}>Close</Btn>
          </div>
        )}
      </section>
    </div>
  );
}
