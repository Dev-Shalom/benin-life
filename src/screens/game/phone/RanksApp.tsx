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

type Board = 'rich' | 'vip';
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
interface BoardData { rows: RankRow[]; me: RankRow | null; players: number; show_amounts?: boolean; tiers: { name: string; min: number }[] }

const MEDAL = ['🥇', '🥈', '🥉'];

function tierIndex(tiers: BoardData['tiers'], name: string | null) {
  const i = tiers.findIndex((t) => t.name === name);
  return i < 0 ? 0 : i;
}

function value(board: Board, r: RankRow, show: boolean): string | null {
  if (board === 'rich') return r.total != null ? nairaShort(r.total) : null;
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
        {r.tier ? <TierBadge data={data} name={r.tier} /> : <span className="rk-row__sub">{board === 'vip' ? 'Top up to join the VIP list' : 'Not ranked'}</span>}
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
      const d = await rpc<BoardData>(b === 'rich' ? 'leaderboard_rich' : 'leaderboard_vip', { p_limit: 50 });
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
          <button type="button" role="tab" aria-selected={board === 'rich'} className={`rk-tab${board === 'rich' ? ' is-on' : ''}`} onClick={() => setBoard('rich')}>💰 Rich list</button>
          <button type="button" role="tab" aria-selected={board === 'vip'} className={`rk-tab${board === 'vip' ? ' is-on' : ''}`} onClick={() => setBoard('vip')}>👑 VIP</button>
        </div>
        <button type="button" className={`rk-refresh${loading ? ' is-spinning' : ''}`} onClick={() => void load(board)} aria-label="Refresh" disabled={loading}>
          <Icon name="refresh" size={16} stroke={2.4} />
        </button>
      </div>
      <p className="rk-blurb">
        {board === 'rich' ? 'The richest Sims in Benin City, cash + bank.' : 'Top supporters of Benin Life. Top 3 VIPs get announced when they walk in anywhere.'}
      </p>
      {err && !d && <p className="phone-app__lead">{err}</p>}
      {!d && !err && <div className="panel-skel"><span /><span /><span /></div>}
      {d && (
        <>
          {d.rows.length === 0
            ? <div className="rk-empty"><span aria-hidden>{board === 'vip' ? '👑' : '💰'}</span><p>{board === 'vip' ? 'No VIPs yet. The first top-up takes the crown.' : 'Nobody on the list yet.'}</p></div>
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
          {d.me && meInList === false && d.me.rank == null && board === 'rich' && <p className="rk-foot">Admins and banned players are hidden from the ranks.</p>}
        </>
      )}
    </div>
  );
}
