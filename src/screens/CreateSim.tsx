import { useMemo, useState } from 'react';
import { Navigate, useNavigate } from 'react-router-dom';
import {
  AvatarPortrait,
  AvatarStage,
  applyPreset,
  defaultAvatar,
  optionsFor,
  presetsFor,
  randomAvatar,
  OUTFIT_PRESETS,
  type AvatarOption,
  type AvatarSlot,
} from '../art/avatar3d';
import { rpc, errorMessage } from '../lib/api';
import type { AvatarConfig, AvatarGarment, FabricId, GameState, Gender } from '../lib/types';
import { useGame } from '../state/game';
import { Button, Icon, Segmented, Tabs, toast } from '../ui';
import { Logo } from './Brand';
import OriginReveal from './OriginReveal';

type Step = 'gender' | 'name' | 'look';
type Group = 'outfit' | 'body' | 'face' | 'hair' | 'extras';

const USERNAME_RE = /^[A-Za-z0-9_]{3,16}$/;

const GROUPS: { id: Group; label: string }[] = [
  { id: 'outfit', label: 'Outfit' },
  { id: 'body', label: 'Body' },
  { id: 'face', label: 'Face' },
  { id: 'hair', label: 'Hair' },
  { id: 'extras', label: 'Extras' },
];

/** One editable row in the look editor. */
interface Row {
  label: string;
  hint?: string;
  slot: AvatarSlot;
  multi?: boolean;
  get: (a: AvatarConfig) => string | string[];
  set: (a: AvatarConfig, id: string) => AvatarConfig;
}

const garment = (k: 'top' | 'bottom', field: keyof AvatarGarment) => ({
  get: (a: AvatarConfig) => a[k][field] as string,
  set: (a: AvatarConfig, id: string) => ({ ...a, [k]: { ...a[k], [field]: field === 'f' ? (id as FabricId) : id } }),
});
const field = (k: 'body' | 'skin' | 'face' | 'eyes' | 'brows' | 'nose' | 'lips' | 'mouth' | 'facialHair' | 'hair' | 'hairColor' | 'hat' | 'accent') => ({
  get: (a: AvatarConfig) => a[k] as string,
  set: (a: AvatarConfig, id: string) => ({ ...a, [k]: id }) as AvatarConfig,
});

const ROWS: Record<Group, Row[]> = {
  outfit: [
    { label: 'Top', slot: 'top', ...garment('top', 's') },
    { label: 'Fabric', slot: 'fabric', ...garment('top', 'f') },
    { label: 'Outfit colour', slot: 'outfitColor', ...garment('top', 'c') },
    { label: 'Bottoms', slot: 'bottom', ...garment('bottom', 's') },
    { label: 'Bottoms fabric', slot: 'fabric', ...garment('bottom', 'f') },
    { label: 'Bottoms colour', slot: 'outfitColor', ...garment('bottom', 'c') },
    { label: 'Shoes', slot: 'shoes', get: (a) => a.shoes.s, set: (a, id) => ({ ...a, shoes: { ...a.shoes, s: id } }) },
    { label: 'Shoe colour', slot: 'outfitColor', get: (a) => a.shoes.c, set: (a, id) => ({ ...a, shoes: { ...a.shoes, c: id } }) },
    { label: 'Accent colour', hint: 'Headwear, tie, prints, embroidery and bags', slot: 'accent', ...field('accent') },
  ],
  body: [
    { label: 'Body type', slot: 'body', ...field('body') },
    { label: 'Skin tone', slot: 'skin', ...field('skin') },
  ],
  face: [
    { label: 'Face shape', slot: 'face', ...field('face') },
    { label: 'Eyes', slot: 'eyes', ...field('eyes') },
    { label: 'Brows', slot: 'brows', ...field('brows') },
    { label: 'Nose', slot: 'nose', ...field('nose') },
    { label: 'Lips', slot: 'lips', ...field('lips') },
    { label: 'Expression', slot: 'mouth', ...field('mouth') },
    { label: 'Facial hair', slot: 'facialHair', ...field('facialHair') },
  ],
  hair: [
    { label: 'Hairstyle', slot: 'hair', ...field('hair') },
    { label: 'Hair colour', slot: 'hairColor', ...field('hairColor') },
    { label: 'Headwear', slot: 'hat', ...field('hat') },
    { label: 'Headwear colour', slot: 'accent', ...field('accent') },
  ],
  extras: [
    {
      label: 'Accessories', hint: 'Pick as many as you like', slot: 'accessories', multi: true,
      get: (a) => a.accessories,
      set: (a, id) => ({ ...a, accessories: a.accessories.includes(id) ? a.accessories.filter((x) => x !== id) : [...a.accessories, id] }),
    },
    { label: 'Accent colour', hint: 'Headwear, tie, prints, embroidery and bags', slot: 'accent', ...field('accent') },
  ],
};

/** True when the current outfit still matches the preset exactly. */
function matchesPreset(a: AvatarConfig, id: string | null): boolean {
  if (!id) return false;
  const p = OUTFIT_PRESETS.find((x) => x.id === id);
  if (!p) return false;
  const patch = p.build(a.gender);
  const same = (x: unknown, y: unknown) => JSON.stringify(x) === JSON.stringify(y);
  return same(a.top, patch.top) && same(a.bottom, patch.bottom) && same(a.shoes, patch.shoes) && a.hat === patch.hat
    && a.accent === patch.accent && same([...a.accessories].sort(), [...patch.accessories].sort());
}

function OptionRow({ row, avatar, onPick }: { row: Row; avatar: AvatarConfig; onPick: (a: AvatarConfig) => void }) {
  const opts: AvatarOption[] = optionsFor(row.slot, avatar.gender);
  if (!opts.length) return null;
  const value = row.get(avatar);
  const isOn = (id: string) => (Array.isArray(value) ? value.includes(id) : value === id);
  const swatches = opts.some((o) => o.swatch);
  return (
    <div className="look-row">
      <div className="look-row__head">
        <span className="look-row__label">{row.label}</span>
        {row.hint && <span className="look-row__hint">{row.hint}</span>}
      </div>
      <div className={swatches ? 'swatch-row' : 'chip-row'}>
        {opts.map((o) =>
          swatches ? (
            <button key={o.id} type="button" className={`swatch-dot${isOn(o.id) ? ' is-active' : ''}`} title={o.label} aria-label={o.label}
              aria-pressed={isOn(o.id)} onClick={() => onPick(row.set(avatar, o.id))}>
              <span style={{ background: o.swatch }} />
            </button>
          ) : (
            <button key={o.id} type="button" className={`opt${isOn(o.id) ? ' is-active' : ''}`} aria-pressed={isOn(o.id)}
              onClick={() => onPick(row.set(avatar, o.id))}>
              {row.multi && <span className="opt__check">{isOn(o.id) ? <Icon name="check" size={12} stroke={3} /> : null}</span>}
              {o.label}
            </button>
          ),
        )}
      </div>
    </div>
  );
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
  const [group, setGroup] = useState<Group>('outfit');
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  // Fresh GameState from create_profile, held back from the store until the origin reveal is done
  // (applying it flips status to 'ready', which redirects to /play).
  const [revealed, setRevealed] = useState<GameState | null>(null);

  const previews = useMemo(() => ({ male: defaultAvatar('male'), female: defaultAvatar('female') }), []);

  if (status === 'ready') return <Navigate to="/play" replace />;

  if (revealed) {
    return (
      <OriginReveal
        state={revealed}
        onDone={() => {
          applyState(revealed);
          void useGame.getState().refresh();
          nav('/play', { replace: true });
        }}
      />
    );
  }

  const chooseGender = (g: Gender) => {
    setGender(g);
    // keep the face and skin; reset gender-specific hair and clothes
    setAvatar((a) => ({ ...defaultAvatar(g), skin: a.skin, face: a.face, eyes: a.eyes, nose: a.nose, body: a.body }));
  };

  const nameOk = USERNAME_RE.test(username);
  const presetEdited = avatar.preset && !matchesPreset(avatar, avatar.preset);

  const create = async () => {
    setErr(null);
    if (!nameOk) {
      setStep('name');
      return setErr('Your name must be 3 to 16 letters, numbers or _.');
    }
    setBusy(true);
    try {
      const st = await rpc<GameState>('create_profile', { p_username: username, p_gender: gender, p_avatar: { ...avatar, gender } });
      if (st && st.profile) {
        setRevealed(st); // OriginReveal is the welcome; it enters the game when the player taps
      } else {
        await useGame.getState().refresh();
        nav('/play', { replace: true });
      }
    } catch (e) {
      const msg = errorMessage(e);
      setErr(msg);
      toast(msg, 'bad');
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className={`create${step === 'look' ? ' create--look' : ''}`}>
      <header className="create__top">
        <div className="row">
          <Logo size={34} />
          <div>
            <h1 className="create__title">Create your Sim</h1>
            <p className="create__step">
              Step {step === 'gender' ? 1 : step === 'name' ? 2 : 3} of 3:{' '}
              {step === 'gender' ? 'Choose a body' : step === 'name' ? 'Name your Sim' : 'Style your look'}
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
                  <AvatarPortrait config={previews[g]} view="full" size={150} className="gender-card__avatar" />
                </div>
                <span className="gender-card__label">{g === 'male' ? 'Man' : 'Woman'}</span>
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
              <AvatarPortrait config={avatar} size={120} className="name-card__portrait" />
            </div>
            <div className="field">
              <label htmlFor="sim-name">Sim name</label>
              <input id="sim-name" className="input" autoFocus autoComplete="off" autoCapitalize="off" spellCheck={false}
                maxLength={16} placeholder="e.g. Osas_Gold" value={username}
                onChange={(e) => { setUsername(e.target.value.replace(/\s/g, '_')); setErr(null); }}
                onKeyDown={(e) => { if (e.key === 'Enter' && nameOk) setStep('look'); }} />
              <p className="hint">3 to 16 letters, numbers or _. Everyone in Benin City will see it, so keep it clean.</p>
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
            <AvatarStage config={avatar} className="look-stage__canvas" />
            <div className="look-stage__name">@{username || 'your_sim'}</div>
            <Button variant="ghost" size="sm" icon="dice" className="look-stage__random" onClick={() => setAvatar({ ...randomAvatar(gender), gender })}>
              Shuffle
            </Button>
          </div>
          <div className="look-editor">
            <Tabs value={group} onChange={(g) => setGroup(g as Group)} tabs={GROUPS} />
            <div className="look-editor__body" key={group}>
              {group === 'outfit' && (
                <div className="look-row">
                  <div className="look-row__head">
                    <span className="look-row__label">Outfit presets</span>
                    <span className="look-row__hint">{presetEdited ? 'Edited. Tap a preset to reset it.' : 'A whole look in one tap. Change any piece after.'}</span>
                  </div>
                  <div className="preset-grid">
                    {presetsFor(gender).map((p) => {
                      const on = avatar.preset === p.id;
                      return (
                        <button key={p.id} type="button" className={`preset${on ? ' is-active' : ''}`} aria-pressed={on}
                          onClick={() => setAvatar((a) => applyPreset(a, p.id))}>
                          <span className="preset__emoji" aria-hidden>{p.emoji}</span>
                          <span className="preset__label">{p.label}</span>
                          {on && presetEdited && <span className="preset__edited">Edited</span>}
                        </button>
                      );
                    })}
                  </div>
                </div>
              )}
              {group === 'body' && (
                <div className="look-row">
                  <div className="look-row__head"><span className="look-row__label">Body</span></div>
                  <Segmented label="Body" value={gender} onChange={chooseGender}
                    options={[{ id: 'female', label: 'Woman' }, { id: 'male', label: 'Man' }]} />
                </div>
              )}
              {ROWS[group].map((row) => (
                <OptionRow key={row.label} row={row} avatar={avatar} onPick={setAvatar} />
              ))}
            </div>
            {err && <p className="error-text">{err}</p>}
            <div className="create__actions look-editor__actions row">
              <Button variant="ghost" size="lg" onClick={() => setStep('name')}>Back</Button>
              <Button size="lg" variant="green" className="grow" loading={busy} onClick={() => void create()}>
                Enter Benin City
              </Button>
            </div>
          </div>
        </section>
      )}
    </div>
  );
}
