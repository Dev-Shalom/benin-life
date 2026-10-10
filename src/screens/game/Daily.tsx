// D1: daily reward + daily gem hunt on the HUD (docs/DAILY.md).
//   DailySync   loads both statuses (on mount, every 5 min while visible, on arrival at a new place)
//   DailyChips  the two left-rail chips ("Daily reward ready · day N", "Daily gem hunt · X found")
//   DailySheets the 7-day reward sheet (Claim) and the gem-hunt hints sheet
//   PlaceGem    the glowing gem button inside a place that hides one of today's gems
import { useEffect, useState } from 'react';
import { useConfig } from '../../lib/config';
import { districtName, naira, nairaShort } from '../../lib/format';
import { errorMessage } from '../../lib/api';
import { playCue } from '../../lib/sound';
import { useDaily, type RewardStep } from '../../state/daily';
import { useGame } from '../../state/game';
import { Button, Sheet, toast } from '../../ui';
import './Daily.css';

/** Keeps the daily statuses fresh. `here` = the place you stand in (null while travelling). */
export function DailySync({ here }: { here: string | null }) {
  const load = useDaily((s) => s.load);
  const loadGems = useDaily((s) => s.loadGems);
  useEffect(() => {
    void load();
    const id = window.setInterval(() => { if (document.visibilityState === 'visible') void load(); }, 5 * 60_000);
    const vis = () => { if (document.visibilityState === 'visible') void load(); };
    document.addEventListener('visibilitychange', vis);
    return () => { window.clearInterval(id); document.removeEventListener('visibilitychange', vis); };
  }, [load]);
  useEffect(() => { if (here) void loadGems(); }, [here, loadGems]);
  return null;
}

function useDailyFlags() {
  const { cfg } = useConfig();
  const reward = useDaily((s) => s.reward);
  const gems = useDaily((s) => s.gems);
  const rewardOn = Boolean(reward?.enabled) && cfg('daily.reward_enabled', true);
  const gemsOn = Boolean(gems?.enabled) && cfg('daily.gems_enabled', true) && (gems?.total ?? 0) > 0;
  return { reward, gems, rewardOn, gemsOn };
}

/** Icons for the folded rail summary + how many chips are showing. */
export function useDailyChipIcons(): string[] {
  const { reward, gems, rewardOn, gemsOn } = useDailyFlags();
  return [...(rewardOn && reward?.ready ? ['🎁'] : []), ...(gemsOn && gems && gems.found < gems.total ? ['💎'] : [])];
}

export function DailyChips({ onPick }: { onPick?: () => void }) {
  const { reward, gems, rewardOn, gemsOn } = useDailyFlags();
  const setSheet = useDaily((s) => s.setSheet);
  const showReward = rewardOn && reward?.ready;
  const showGems = gemsOn && gems && gems.found < gems.total;
  if (!showReward && !showGems) return null;
  return (
    <div className="daily-row">
      {showReward && reward && (
        <button type="button" className="wish-chip wish-chip--daily" onClick={() => { onPick?.(); setSheet('reward'); }}
          aria-label={`Daily reward ready, day ${reward.day}. Open the 7-day rewards`}>
          <span className="wish-chip__icon" aria-hidden>🎁</span>
          <span className="wish-chip__text">
            <span className="wish-chip__title"><span className="daily-long">Daily reward ready</span><span className="daily-short">Daily reward · day {reward.day}</span></span>
            <span className="wish-chip__sub">Day {reward.day} · {reward.next ? nairaShort(reward.next.cash) : ''}</span>
          </span>
          <span className="daily-dot" aria-hidden />
        </button>
      )}
      {showGems && gems && (
        <button type="button" className="wish-chip wish-chip--gem" onClick={() => { onPick?.(); setSheet('gems'); }}
          aria-label={`Daily gem hunt: ${gems.found} of ${gems.total} found, next prize ${naira(gems.next_prize)}. Show hints`}>
          <span className="wish-chip__icon" aria-hidden>💎</span>
          <span className="wish-chip__text">
            <span className="wish-chip__title"><span className="daily-long">Daily gem hunt · {gems.found}/{gems.total}</span><span className="daily-short">Gem hunt · {gems.found}/{gems.total}{gems.next_prize > 0 ? ` · next ${nairaShort(gems.next_prize)}` : ' · all found'}</span></span>
            <span className="wish-chip__sub">{gems.found_all_players.toLocaleString('en-NG')} found · next prize {nairaShort(gems.next_prize)}</span>
          </span>
        </button>
      )}
    </div>
  );
}

function StepCard({ s, i }: { s: RewardStep; i: number }) {
  return (
    <li className={`daily-step is-${s.state}${s.day === 7 ? ' is-big' : ''}`} style={{ animationDelay: `${i * 35}ms` }}>
      <span className="daily-step__day">Day {s.day}</span>
      <span className="daily-step__icon" aria-hidden>{s.state === 'claimed' ? '✓' : s.item_icon ?? (s.day === 7 ? '🏆' : '💵')}</span>
      <span className="daily-step__cash">{nairaShort(s.cash)}</span>
      {s.item_name && <span className="daily-step__item">+ {s.item_name}</span>}
      <span className="sr-only">{s.state === 'claimed' ? 'claimed' : s.state === 'today' ? 'today' : 'upcoming'}</span>
    </li>
  );
}

export function DailySheets() {
  const { reward, gems } = useDailyFlags();
  const sheet = useDaily((s) => s.sheet);
  const setSheet = useDaily((s) => s.setSheet);
  const claim = useDaily((s) => s.claim);
  const refresh = useGame((s) => s.refresh);
  const [busy, setBusy] = useState(false);
  const [burst, setBurst] = useState(0);
  const close = () => setSheet(null);

  const doClaim = async () => {
    if (busy) return;
    setBusy(true);
    try {
      const r = await claim();
      setBurst((n) => n + 1);
      toast(`🎉 ${r.message}`, 'good');
      playCue('money');
      await refresh();
      window.setTimeout(close, 900);
    } catch (e) {
      toast(errorMessage(e), 'bad');
    } finally {
      setBusy(false);
    }
  };

  const left = gems ? gems.total - gems.found : 0;
  return (
    <>
      <Sheet open={sheet === 'reward' && Boolean(reward)} onClose={close} className="daily-sheet"
        title="Daily reward" subtitle="Claim once a day. Miss a day and you start again at day 1.">
        {reward && (
          <div className="daily-reward">
            <ol className="daily-steps" key={burst}>
              {reward.steps.map((s, i) => <StepCard key={s.day} s={s} i={i} />)}
            </ol>
            {burst > 0 && <div className="daily-confetti" key={`c${burst}`} aria-hidden>{Array.from({ length: 14 }, (_, i) => <i key={i} style={{ ['--i' as string]: i }} />)}</div>}
            <Button variant="gold" block size="lg" onClick={() => void doClaim()} disabled={!reward.ready || busy} loading={busy}>
              {reward.ready
                ? `Claim day ${reward.day} · ${naira(reward.next?.cash ?? 0)}${reward.next?.item_name ? ` + ${reward.next.item_name}` : ''}`
                : `Claimed today · back tomorrow for day ${(reward.day % 7) + 1}`}
            </Button>
          </div>
        )}
      </Sheet>
      <Sheet open={sheet === 'gems' && Boolean(gems)} onClose={close} className="daily-sheet"
        title="Daily gem hunt" subtitle="Gems hide inside real places today. Same hunt for everyone in Benin.">
        {gems && (
          <div className="gem-hunt">
            <div className="gem-hunt__stats">
              <span><b>{gems.found}/{gems.total}</b> found by you</span>
              <span><b>{gems.found_all_players.toLocaleString('en-NG')}</b> found today by everyone</span>
            </div>
            <ul className="gem-hints">
              {gems.gems.map((g) => (
                <li key={g.idx} className={`gem-hint${g.found ? ' is-found' : ''}`}>
                  <span className="gem-hint__gem" aria-hidden>💎</span>
                  <span className="gem-hint__text">
                    <b>{g.found ? g.place_name ?? 'Found' : `Somewhere in ${districtName(g.district)}`}</b>
                    <small>{g.found ? 'Found ✓' : g.here ? 'It is right here: look around the room!' : 'An always-open public place'}</small>
                  </span>
                </li>
              ))}
            </ul>
            <p className="gem-hunt__prize">
              {left > 0
                ? <>Next prize <b>{naira(gems.next_prize)}</b>{left > 1 ? <> · find all {gems.total} for a <b>{naira(gems.all_bonus)}</b> bonus</> : ' (includes the all-found bonus)'}</>
                : <>All found today. New gems tomorrow (Benin time).</>}
            </p>
          </div>
        )}
      </Sheet>
    </>
  );
}

/** Inside a place with one of today's gems: the tap target (positioned by the 3D scene, see PlaceScene `gem`). */
export function usePlaceGem(placeId: string | null): { onFind: () => void } | null {
  const { gems, gemsOn } = useDailyFlags();
  const find = useDaily((s) => s.find);
  const refresh = useGame((s) => s.refresh);
  const [busy, setBusy] = useState(false);
  if (!placeId || !gemsOn || !gems || gems.here !== placeId) return null;
  return {
    onFind: () => {
      if (busy) return;
      setBusy(true);
      find(placeId)
        .then(async (r) => {
          toast(`💎 ${r.message}`, 'good');
          playCue('money');
          await refresh();
        })
        .catch((e) => toast(errorMessage(e), 'bad'))
        .finally(() => setBusy(false));
    },
  };
}
