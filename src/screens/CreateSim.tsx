import { useMemo, useState } from 'react';
import { Navigate, useNavigate } from 'react-router-dom';
import { Avatar } from '../art/avatar/Avatar';
import { AVATAR_OPTIONS, defaultAvatar, randomAvatar, type AvatarOption } from '../art/avatar/catalog';
import { rpc, errorMessage } from '../lib/api';
import type { AvatarConfig, GameState, Gender } from '../lib/types';
import { useGame } from '../state/game';
import { Button, Icon, Tabs, toast } from '../ui';
import { Logo } from './Brand';

type Slot = keyof typeof AVATAR_OPTIONS;
type Step = 'gender' | 'name' | 'look';

const SLOT_LABELS: Record<Slot, string> = {
  skin: 'Skin',
  body: 'Body',
  hair: 'Hair',
  hairColor: 'Hair colour',
  eyes: 'Eyes',
  brows: 'Brows',
  mouth: 'Mouth',
  facialHair: 'Beard',
  outfit: 'Outfit',
  outfitColor: 'Cloth colour',
  accessories: 'Jewelry & extras',
};
const SLOT_ORDER: Slot[] = ['skin', 'body', 'hair', 'hairColor', 'outfit', 'outfitColor', 'accessories', 'eyes', 'brows', 'mouth', 'facialHair'];

const USERNAME_RE = /^[A-Za-z0-9_]{3,16}$/;

function optionsFor(slot: Slot, gender: Gender): AvatarOption[] {
  return (AVATAR_OPTIONS[slot] ?? []).filter((o) => !o.gender || o.gender === gender);
}

export default function CreateSim() {
  const status = useGame((s) => s.status);
  const applyState = useGame((s) => s.applyState);
  const signOut = useGame((s) => s.signOut);
  const nav = useNavigate();

  const [step, setStep] = useState<Step>('gender');
  const [gender, setGender] = useState<Gender>('male');
  const [username, setUsername] = useState('');
  const [avatar, setAvatar] = useState<AvatarConfig>(() => defaultAvatar('male'));
  const [slot, setSlot] = useState<Slot>('skin');
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  const slots = useMemo(() => SLOT_ORDER.filter((s) => optionsFor(s, gender).length > 0), [gender]);
  const previews = useMemo(() => ({ male: defaultAvatar('male'), female: defaultAvatar('female') }), []);

  if (status === 'ready') return <Navigate to="/play" replace />;

  const chooseGender = (g: Gender) => {
    setGender(g);
    setAvatar(defaultAvatar(g));
  };

  const setSlotValue = (s: Slot, id: string) => {
    setAvatar((a) => {
      if (s === 'accessories') {
        const has = a.accessories.includes(id);
        return { ...a, accessories: has ? a.accessories.filter((x) => x !== id) : [...a.accessories, id] };
      }
      return { ...a, [s]: id } as AvatarConfig;
    });
  };

  const isSelected = (s: Slot, id: string) =>
    s === 'accessories' ? avatar.accessories.includes(id) : (avatar as unknown as Record<string, unknown>)[s] === id;

  const nameOk = USERNAME_RE.test(username);

  const create = async () => {
    setErr(null);
    if (!nameOk) {
      setStep('name');
      return setErr('Name must be 3–16 letters, numbers or _ only.');
    }
    setBusy(true);
    try {
      const st = await rpc<GameState>('create_profile', { p_username: username, p_gender: gender, p_avatar: { ...avatar, gender } });
      toast(`Welcome to Benin, ${username}! Your face-me-I-face-you for Ekenwan dey wait you.`, 'good');
      if (st && st.profile) applyState(st);
      else await useGame.getState().refresh();
      nav('/play', { replace: true });
    } catch (e) {
      const msg = errorMessage(e);
      setErr(msg);
      toast(msg, 'bad');
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="create">
      <header className="create__top">
        <div className="row">
          <Logo size={34} />
          <div>
            <h1 className="create__title">Create your Sim</h1>
            <p className="create__step">
              Step {step === 'gender' ? 1 : step === 'name' ? 2 : 3} of 3 ·{' '}
              {step === 'gender' ? 'Who you be?' : step === 'name' ? 'Wetin dem dey call you?' : 'Fine-tune your look'}
            </p>
          </div>
        </div>
        <button type="button" className="create__logout" onClick={() => void signOut()}>Log out</button>
      </header>

      {step === 'gender' && (
        <section className="create__panel create__gender">
          <div className="gender-grid">
            {(['male', 'female'] as Gender[]).map((g) => (
              <button key={g} type="button" className={`gender-card${gender === g ? ' is-active' : ''}`} onClick={() => chooseGender(g)}>
                <div className="gender-card__art">
                  <Avatar config={previews[g]} view="full" className="gender-card__avatar" />
                </div>
                <span className="gender-card__label">{g === 'male' ? 'Guy man' : 'Babe'}</span>
                {gender === g && <span className="gender-card__tick"><Icon name="check" size={16} stroke={3} /></span>}
              </button>
            ))}
          </div>
          <div className="create__actions">
            <Button size="lg" block onClick={() => setStep('name')}>Next <Icon name="chevronRight" size={18} /></Button>
          </div>
        </section>
      )}

      {step === 'name' && (
        <section className="create__panel create__name">
          <div className="name-card">
            <div className="name-card__avatar">
              <Avatar config={avatar} view="portrait" className="name-card__portrait" />
            </div>
            <div className="field">
              <label htmlFor="sim-name">Your street name</label>
              <input id="sim-name" className="input" autoFocus autoComplete="off" autoCapitalize="off" spellCheck={false}
                maxLength={16} placeholder="e.g. Osas_Gold" value={username}
                onChange={(e) => { setUsername(e.target.value.replace(/\s/g, '_')); setErr(null); }}
                onKeyDown={(e) => { if (e.key === 'Enter' && nameOk) setStep('look'); }} />
              <p className="hint">3–16 letters, numbers or _ . Everybody for Benin go see am — keep am clean.</p>
              {err && <p className="error-text">{err}</p>}
            </div>
          </div>
          <div className="create__actions row">
            <Button variant="ghost" size="lg" onClick={() => setStep('gender')}>Back</Button>
            <Button size="lg" className="grow" disabled={!nameOk} onClick={() => setStep('look')}>
              Next <Icon name="chevronRight" size={18} />
            </Button>
          </div>
        </section>
      )}

      {step === 'look' && (
        <section className="create__look">
          <div className="look-stage">
            <div className="look-stage__glow" />
            <Avatar config={avatar} view="full" className="look-stage__avatar" />
            <div className="look-stage__plinth" />
            <div className="look-stage__name">{username || 'Your Sim'}</div>
            <Button variant="gold" size="sm" icon="dice" className="look-stage__random" onClick={() => setAvatar({ ...randomAvatar(gender), gender })}>
              Shuffle
            </Button>
          </div>
          <div className="look-editor">
            <Tabs value={slot} onChange={(s) => setSlot(s as Slot)} tabs={slots.map((s) => ({ id: s, label: SLOT_LABELS[s] }))} />
            <div className={`opt-grid${optionsFor(slot, gender).some((o) => o.swatch) ? ' opt-grid--swatch' : ''}`}>
              {optionsFor(slot, gender).map((o) =>
                o.swatch ? (
                  <button key={o.id} type="button" className={`swatch${isSelected(slot, o.id) ? ' is-active' : ''}`}
                    onClick={() => setSlotValue(slot, o.id)} title={o.label} aria-label={o.label} aria-pressed={isSelected(slot, o.id)}>
                    <span style={{ background: o.swatch }} />
                    <small>{o.label}</small>
                  </button>
                ) : (
                  <button key={o.id} type="button" className={`opt${isSelected(slot, o.id) ? ' is-active' : ''}`}
                    onClick={() => setSlotValue(slot, o.id)} aria-pressed={isSelected(slot, o.id)}>
                    {slot === 'accessories' && <span className="opt__check">{isSelected(slot, o.id) ? <Icon name="check" size={12} stroke={3} /> : null}</span>}
                    {o.label}
                  </button>
                ),
              )}
            </div>
            {err && <p className="error-text">{err}</p>}
            <div className="create__actions row">
              <Button variant="ghost" size="lg" onClick={() => setStep('name')}>Back</Button>
              <Button size="lg" variant="green" className="grow" loading={busy} onClick={() => void create()}>
                Enter Benin
              </Button>
            </div>
          </div>
        </section>
      )}
    </div>
  );
}
