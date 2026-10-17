// Phone "Ranks" app (PAY, docs/PAYMENTS.md): Rich list (cash + bank) and VIP list (real money spent on
// top-ups, tiers only unless leaderboard.vip_show_amounts). Top 3 on a podium, the rest in a list, your
// own row pinned at the bottom. Data: leaderboard_rich / leaderboard_vip RPCs (no emails ever).
import { useCallback, useEffect, useState } from 'react';
import { AvatarPortrait } from '../../../art/avatar3d';
import { errorMessage, rpc } from '../../../lib/api';
import { nairaShort } from '../../../lib/format';
import type { AvatarConfig } from '../../../lib/types';
import { Icon } from '../../../ui';
import '../../../styles/pay.css';

type Board = 'rich' | 'vip' | 'week';
interface RankRow {
  rank: number | null;
  id: string;
  username: string;
  avatar: unknown;
  origin: string;
  tier: string | null;
  total?: number;
  amount?: number | null;
  me?: boolean;
}
interface WeekExtra { week_start: string; ends_at: string; prizes: { rank: number; amount: number }[]; min_earned: number; last_week: { week_start: string; winners: { rank: number; username: string; total: number; prize: number }[] } | null; enabled: boolean }
interface BoardData extends Partial<WeekExtra> { rows: RankRow[]; me: RankRow | null; players: number; show_amounts?: boolean; tiers: { name: string; min: number }[] }

const MEDAL = ['🥇', '🥈', '🥉'];

function tierIndex(tiers: BoardData['tiers'], name: string | null) {
  const i = tiers.findIndex((t) => t.name === name);
  return i < 0 ? 0 : i;
}

function value(board: Board, r: RankRow, show: boolean): string | null {
  if (board === 'rich' || board === 'week') return r.total != null ? nairaShort(r.total) : null;
  return show && r.amount != null ? nairaShort(r.amount) : null;
}

function Portrait({ r, size }: { r: RankRow; size: number }) {
  return <AvatarPortrait config={(r.avatar ?? {}) as AvatarConfig} size={size} className="rk-face" alt="" />;
}

function TierBadge({ data, name }: { data: BoardData; name: string | null }) {
  if (!name) return null;
  return <span className={`rk-tier rk-tier--${Math.min(4, tierIndex(data.tiers, name))}`}>{name}</span>;
}

function Podium({ board, data }: { board: Board; data: BoardData }) {
  const top = data.rows.slice(0, 3);
  const order = [top[1], top[0], top[2]];
  return (
    <div className="rk-podium">
      {order.map((r, i) => {
        const place = i === 1 ? 1 : i === 0 ? 2 : 3;
        if (!r) return <div key={`empty-${place}`} className={`rk-pod rk-pod--${place} is-empty`}><span className="rk-pod__step">{place}</span></div>;
        const v = value(board, r, Boolean(data.show_amounts));
        return (
          <div key={r.id} className={`rk-pod rk-pod--${place}${r.me ? ' is-me' : ''}`}>
            {place === 1 && <span className="rk-pod__crown" aria-hidden>👑</span>}
            <span className="rk-pod__ring"><Portrait r={r} size={place === 1 ? 76 : 60} /></span>
            <span className="rk-pod__medal" aria-hidden>{MEDAL[place - 1]}</span>
            <span className="rk-pod__name">@{r.username}</span>
            <TierBadge data={data} name={r.tier} />
            {v && <span className="rk-pod__val">{v}</span>}
            <span className="rk-pod__step"><span>{place}</span></span>
          </div>
        );
      })}
    </div>
  );
}

function Row({ board, data, r, pinned }: { board: Board; data: BoardData; r: RankRow; pinned?: boolean }) {
  const v = value(board, r, Boolean(data.show_amounts) || Boolean(pinned && board === 'vip'));
  return (
    <li className={`rk-row${r.me ? ' is-me' : ''}${pinned ? ' is-pinned' : ''}`}>
      <span className="rk-row__rank">{r.rank ?? '–'}</span>
      <Portrait r={r} size={36} />
      <span className="rk-row__who">
        <span className="rk-row__name">@{r.username}{pinned ? <span className="rk-row__you">You</span> : null}</span>
        {r.tier ? <TierBadge data={data} name={r.tier} /> : board === 'week' && r.rank != null ? null : <span className="rk-row__sub">{board === 'vip' ? 'Top up to join the VIP list' : board === 'week' ? 'Earn something to rank' : 'Not ranked'}</span>}
      </span>
      {v && <span className="rk-row__val">{v}</span>}
    </li>
  );
}

export default function RanksApp() {
  const [board, setBoard] = useState<Board>('rich');
  const [data, setData] = useState<Partial<Record<Board, BoardData>>>({});
  const [err, setErr] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  const load = useCallback(async (b: Board) => {
    setLoading(true);
    try {
      const d0 = await rpc<BoardData>(b === 'rich' ? 'leaderboard_rich' : b === 'vip' ? 'leaderboard_vip' : 'weekly_leaderboard', { p_limit: 50 });
      const d = { ...d0, tiers: d0.tiers ?? [] };
      setData((x) => ({ ...x, [b]: d }));
      setErr(null);
    } catch (e) {
      setErr(errorMessage(e));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { void load(board); }, [board, load]);

  const d = data[board];
  const rest = d ? d.rows.slice(3) : [];
  const meInList = d?.rows.some((r) => r.me);

  return (
    <div className="phone-app__body rk">
      <div className="rk-head">
        <div className="rk-tabs" role="tablist" aria-label="Leaderboards">
          <button type="button" role="tab" aria-selected={board === 'rich'} className={`rk-tab${board === 'rich' ? ' is-on' : ''}`} onClick={() => setBoard('rich')}>💰 Rich</button>
          <button type="button" role="tab" aria-selected={board === 'week'} className={`rk-tab${board === 'week' ? ' is-on' : ''}`} onClick={() => setBoard('week')} data-testid="ranks-week-tab">🔥 Week</button>
          <button type="button" role="tab" aria-selected={board === 'vip'} className={`rk-tab${board === 'vip' ? ' is-on' : ''}`} onClick={() => setBoard('vip')}>👑 VIP</button>
        </div>
        <button type="button" className={`rk-refresh${loading ? ' is-spinning' : ''}`} onClick={() => void load(board)} aria-label="Refresh" disabled={loading}>
          <Icon name="refresh" size={16} stroke={2.4} />
        </button>
      </div>
      <p className="rk-blurb">
        {board === 'week' ? "This week's top earners: money from jobs, hustles and investments only. Resets Monday 12 AM." : board === 'rich' ? 'The richest Sims in Benin City, cash + bank.' : 'Top supporters of Benin Life. Top 3 VIPs get announced when they walk in anywhere.'}
      </p>
      {err && !d && <p className="phone-app__lead">{err}</p>}
      {!d && !err && <div className="panel-skel"><span /><span /><span /></div>}
      {d && (
        <>
          {board === 'week' && d.prizes && (
            <div className="rk-week" data-testid="week-prizes">
              <span>🥇 {nairaShort(d.prizes[0]?.amount ?? 0)}</span><span>🥈 {nairaShort(d.prizes[1]?.amount ?? 0)}</span><span>🥉 {nairaShort(d.prizes[2]?.amount ?? 0)}</span>
              <small>Paid to the top 3 when the week closes (earn at least {nairaShort(d.min_earned ?? 0)}).</small>
            </div>
          )}
          {d.rows.length === 0
            ? <div className="rk-empty"><span aria-hidden>{board === 'vip' ? '👑' : board === 'week' ? '🔥' : '💰'}</span><p>{board === 'vip' ? 'No VIPs yet. The first top-up takes the crown.' : board === 'week' ? 'Nobody has earned anything yet this week. Do a shift or a hustle!' : 'Nobody on the list yet.'}</p></div>
            : <Podium board={board} data={d} />}
          {rest.length > 0 && (
            <ol className="rk-list">
              {rest.map((r) => <Row key={r.id} board={board} data={d} r={r} />)}
            </ol>
          )}
          {d.me && (
            <ol className="rk-list rk-list--me">
              <Row board={board} data={d} r={{ ...d.me, me: true }} pinned />
            </ol>
          )}
          {board === 'week' && d.last_week && d.last_week.winners.length > 0 && (
            <div className="rk-week rk-week--last">
              <b>Last week's winners</b>
              {d.last_week.winners.map((w) => <small key={w.rank}>{MEDAL[w.rank - 1]} @{w.username} · {nairaShort(w.total)} earned · prize {nairaShort(w.prize)}</small>)}
            </div>
          )}
          {d.me && meInList === false && d.me.rank == null && board === 'rich' && <p className="rk-foot">Admins and banned players are hidden from the ranks.</p>}
        </>
      )}
    </div>
  );
}
