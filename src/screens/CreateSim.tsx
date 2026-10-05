// Character creator (R3b): Look -> Personality -> Dream -> Birth lottery -> Choose where to live.
// One live 3D turntable for the whole flow (never remounted between steps); the step content lives
// in a bottom sheet (phones) or a right-hand panel (desktop) with a sticky Continue.
//
// Server (docs/CREATOR.md): nothing is written until the end of Dream, where create_profile_v2
// rolls the origin. choose_start_home then moves the Sim in. A player who closes the app between
// the two comes back straight to the home step (GameState.creator.home_chosen === false).
import { useEffect, useRef, useState } from 'react';
import { Navigate, useNavigate } from 'react-router-dom';
import { AvatarStage, defaultAvatar, randomAvatar } from '../art/avatar3d';
import { chooseStartHome, createProfileV2, getCreatorCatalog, needsHome } from '../api/creator';
import { errorMessage, GameError } from '../lib/api';
import { CREATOR, P, WEEKDAYS, originCopy } from '../lib/pidgin';
import type { AvatarConfig, CreatorCatalog } from '../lib/types';
import { useGame } from '../state/game';
import { Button, Icon, LoadingScreen, toast } from '../ui';
import ErrorScreen from './ErrorScreen';
import OriginReveal from './OriginReveal';
import LookPanel, { USERNAME_RE } from './creator/LookPanel';
import { DreamPanel, HomePanel, TraitPanel } from './creator/Panels';

type Step = 0 | 1 | 2 | 3 | 4; // look, personality, dream, lottery, home
const LOOK = 0, TRAITS = 1, DREAM = 2, LOTTERY = 3, HOME = 4;

function isNameError(e: unknown): 'taken' | 'bad' | null {
  const msg = e instanceof Error ? e.message : String(e ?? '');
  if (/already carry|already (has|taken)|is taken/i.test(msg)) return 'taken';
  if (/username/i.test(msg)) return 'bad';
  return null;
}

export default function CreateSim() {
  const session = useGame((s) => s.session);
  const status = useGame((s) => s.status);
  const gameError = useGame((s) => s.error);
  const state = useGame((s) => s.state);
  const applyState = useGame((s) => s.applyState);
  const signOut = useGame((s) => s.signOut);
  const nav = useNavigate();

  const [step, setStep] = useState<Step>(LOOK);
  const [username, setUsername] = useState('');
  const [avatar, setAvatar] = useState<AvatarConfig>(() => defaultAvatar('female'));
  const [nameError, setNameError] = useState<string | null>(null);
  const [catalog, setCatalog] = useState<CreatorCatalog | null>(null);
  const [catalogFailed, setCatalogFailed] = useState(false);
  const [traits, setTraits] = useState<string[]>([]);
  const [swapNote, setSwapNote] = useState<string | null>(null);
  const [dream, setDream] = useState<string | null>(null);
  const [home, setHome] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  // The coin toss plays once, right after the roll. Coming back to the step shows the result.
  const [freshRoll, setFreshRoll] = useState(false);
  const nameRef = useRef<HTMLInputElement>(null);
  const sheetRef = useRef<HTMLDivElement>(null);

  const committed = needsHome(state);
  // A Sim that exists but has no home can only be on the lottery or home step.
  const cur: Step = committed && step < LOTTERY ? HOME : step;

  useEffect(() => {
    if (catalog || committed) return;
    let live = true;
    getCreatorCatalog()
      .then((c) => live && setCatalog(c))
      .catch(() => live && setCatalogFailed(true));
    return () => {
      live = false;
    };
  }, [catalog, committed, catalogFailed]);

  // New step: start the sheet at the top.
  useEffect(() => {
    sheetRef.current?.scrollTo({ top: 0 });
  }, [cur]);

  // Warm the game chunk once the Sim exists.
  useEffect(() => {
    if (committed) void import('./Game');
  }, [committed]);

  if (status === 'ready' && state && !committed) return <Navigate to="/play" replace />;
  if (session && (status === 'loading' || status === 'idle')) return <LoadingScreen text={P.loading} />;
  if (session && status === 'error') return <ErrorScreen message={gameError ?? P.somethingWrong} />;

  const needTraits = catalog?.trait_count ?? 2;
  const shownName = (committed ? state?.profile.username : username) || 'your Sim';
  const stageAvatar = committed && state ? state.profile.avatar : avatar;

  const toggleTrait = (id: string) => {
    setSwapNote(null);
    setTraits((cur) => {
      if (cur.includes(id)) return cur.filter((x) => x !== id);
      if (cur.length < needTraits) return [...cur, id];
      // Full: the oldest pick makes way, and we say so.
      const out = catalog?.traits.find((t) => t.id === cur[0])?.name ?? '';
      setSwapNote(CREATOR.traitsSwap(out));
      return [...cur.slice(1), id];
    });
  };

  const create = async () => {
    if (!dream) return;
    setErr(null);
    setBusy(true);
    try {
      const st = await createProfileV2({ username, gender: avatar.gender, avatar, traits, dream });
      setFreshRoll(true);
      setStep(LOTTERY);
      applyState(st);
    } catch (e) {
      const kind = isNameError(e);
      if (kind) {
        setNameError(kind === 'taken' ? CREATOR.nameTaken(username) : errorMessage(e));
        setStep(LOOK);
        window.setTimeout(() => nameRef.current?.focus(), 60);
      } else if (e instanceof GameError && e.hint === 'profile_exists') {
        await useGame.getState().refresh();
        setStep(HOME);
      } else {
        setErr(errorMessage(e));
      }
    } finally {
      setBusy(false);
    }
  };

  const moveIn = async () => {
    if (!home) return;
    setErr(null);
    setBusy(true);
    try {
      const res = await chooseStartHome(home);
      applyState(res);
      void useGame.getState().refresh();
      nav('/play', { replace: true });
    } catch (e) {
      const msg = errorMessage(e);
      setErr(msg);
      toast(msg, 'bad');
      if (e instanceof GameError && e.hint === 'home_already_chosen') {
        await useGame.getState().refresh();
      }
    } finally {
      setBusy(false);
    }
  };

  // ---- primary action per step ----
  const left = needTraits - traits.length;
  const primary: { label: string; disabled: boolean } =
    cur === LOOK ? { label: CREATOR.continue, disabled: false }
    : cur === TRAITS ? { label: left > 0 ? CREATOR.traitsMore(left) : CREATOR.continue, disabled: left > 0 }
    : cur === DREAM ? { label: dream ? CREATOR.continue : CREATOR.dreamPick, disabled: !dream }
    : cur === LOTTERY ? { label: CREATOR.chooseHome, disabled: !state }
    : { label: home ? CREATOR.moveIn : CREATOR.pickHome, disabled: !home };

  const runPrimary = () => {
    if (cur === LOOK) {
      if (!USERNAME_RE.test(username)) {
        setNameError(CREATOR.nameBad);
        nameRef.current?.focus();
        return;
      }
      setStep(TRAITS);
    } else if (cur === TRAITS) setStep(DREAM);
    else if (cur === DREAM) void create();
    else if (cur === LOTTERY) setStep(HOME);
    else void moveIn();
  };

  const back = () => {
    setErr(null);
    if (cur === LOOK) {
      if (!session) return nav('/');
      if (window.confirm(CREATOR.logoutConfirm)) void signOut().then(() => nav('/', { replace: true }));
      return;
    }
    if (cur === HOME) return setStep(LOTTERY);
    if (cur === LOTTERY) return; // the Sim exists now; there is no going back past the roll
    setStep((cur - 1) as Step);
  };

  const tier = state?.origin?.id ?? state?.profile.origin ?? 'lapo';
  const tierCopy = originCopy(tier, state?.origin?.name ?? '', state?.origin?.tagline ?? '');
  const rentDay = WEEKDAYS[catalog?.rent_weekday ?? 5] ?? 'Saturday';

  return (
    <div className={`creator creator--s${cur}`}>
      <header className="creator__bar">
        <button
          type="button"
          className="creator__round"
          onClick={back}
          disabled={cur === LOTTERY}
          aria-label={cur === LOOK ? CREATOR.logout : P.back}
          title={cur === LOOK ? CREATOR.logout : P.back}
        >
          <Icon name={cur === LOOK ? 'logout' : 'back'} size={20} stroke={2.4} />
        </button>
        <div className="creator__title">
          <h1>{CREATOR.steps[cur]}</h1>
          <div className="creator__progress" role="progressbar" aria-label="Creator progress" aria-valuemin={1} aria-valuemax={5} aria-valuenow={cur + 1}>
            {CREATOR.steps.map((s, i) => (
              <span key={s} className={i <= cur ? 'is-on' : undefined} />
            ))}
          </div>
        </div>
        <div className="creator__actions">
          {cur === LOOK && (
            <button type="button" className="creator__round" aria-label={CREATOR.shuffle} title={CREATOR.shuffle}
              onClick={() => setAvatar(randomAvatar(avatar.gender))}>
              <Icon name="dice" size={20} stroke={2.2} />
            </button>
          )}
          <Button size="sm" variant="green" className="creator__next" disabled={primary.disabled || busy} onClick={runPrimary}>
            {cur === HOME ? CREATOR.moveIn : CREATOR.next}
          </Button>
        </div>
      </header>

      <div className="creator__body">
        <div className="creator__stage">
          <AvatarStage config={stageAvatar} className="creator__canvas" />
        </div>

        <div className="creator__sheet">
          <div className="creator__scroll" ref={sheetRef}>
            <div className="creator__step" key={cur}>
              {cur === LOOK && (
                <LookPanel avatar={avatar} onAvatar={setAvatar} username={username}
                  onUsername={(v) => { setUsername(v); setNameError(null); }} nameError={nameError} nameRef={nameRef} />
              )}
              {cur === TRAITS && (
                <TraitPanel name={shownName} traits={catalog?.traits ?? null} picked={traits} need={needTraits}
                  onToggle={toggleTrait} />
              )}
              {cur === DREAM && (
                <DreamPanel name={shownName} dreams={catalog?.dreams ?? null} picked={dream} onPick={setDream} />
              )}
              {cur === LOTTERY && state && <OriginReveal state={state} replay={freshRoll} />}
              {cur === HOME && state && (
                <HomePanel
                  name={shownName}
                  homes={state.creator?.homes ?? []}
                  picked={home}
                  onPick={setHome}
                  rentDay={rentDay}
                  originChip={
                    <button type="button" className={`lottery-chip lottery-chip--${tier === 'nepo' ? 'gold' : 'warm'}`}
                      onClick={() => { setFreshRoll(false); setStep(LOTTERY); }}>
                      <span aria-hidden>{tierCopy.emoji}</span>
                      {tierCopy.title.replace(/!$/, '')}
                      <span className="lottery-chip__more">{CREATOR.seeLottery}</span>
                      <Icon name="chevronRight" size={14} stroke={2.6} />
                    </button>
                  }
                />
              )}
              {catalogFailed && !catalog && cur < LOTTERY && cur > LOOK && (
                <div className="creator__fail">
                  <p className="error-text">{CREATOR.catalogFailed}</p>
                  <Button size="sm" variant="ghost" onClick={() => setCatalogFailed(false)}>{P.retry}</Button>
                </div>
              )}
            </div>
          </div>
          <div className="creator__cta">
            {err && <p className="error-text creator__err" role="alert">{err}</p>}
            {cur === TRAITS && (
              <p className={`creator__note${swapNote ? ' is-on' : ''}`} aria-live="polite">{swapNote ?? ''}</p>
            )}
            <Button size="lg" variant="green" block loading={busy} disabled={primary.disabled} onClick={runPrimary}>
              {busy && cur === DREAM ? CREATOR.creating : primary.label}
            </Button>
          </div>
        </div>
      </div>
    </div>
  );
}
