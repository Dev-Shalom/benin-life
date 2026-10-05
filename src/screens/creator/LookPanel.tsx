// Creator step 1: Look. Name, body, outfit presets, and every piece editable afterwards.
import { useState } from 'react';
import {
  applyPreset,
  defaultAvatar,
  optionsFor,
  presetsFor,
  OUTFIT_PRESETS,
  type AvatarOption,
  type AvatarSlot,
} from '../../art/avatar3d';
import { CREATOR } from '../../lib/pidgin';
import type { AvatarConfig, AvatarGarment, FabricId, Gender } from '../../lib/types';
import { Icon, Segmented, Tabs } from '../../ui';

export const USERNAME_RE = /^[A-Za-z0-9_]{3,20}$/;

type Group = 'outfit' | 'hair' | 'face' | 'body' | 'extras';

const GROUPS: { id: Group; label: string }[] = [
  { id: 'outfit', label: 'Outfit' },
  { id: 'hair', label: 'Hair' },
  { id: 'face', label: 'Face' },
  { id: 'body', label: 'Skin & body' },
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

const garment = (k: 'top' | 'bottom', f: keyof AvatarGarment) => ({
  get: (a: AvatarConfig) => a[k][f] as string,
  set: (a: AvatarConfig, id: string) => ({ ...a, [k]: { ...a[k], [f]: f === 'f' ? (id as FabricId) : id } }),
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
  hair: [
    { label: 'Hairstyle', slot: 'hair', ...field('hair') },
    { label: 'Hair colour', slot: 'hairColor', ...field('hairColor') },
    { label: 'Headwear', slot: 'hat', ...field('hat') },
    { label: 'Headwear colour', slot: 'accent', ...field('accent') },
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
  body: [
    { label: 'Skin tone', slot: 'skin', ...field('skin') },
    { label: 'Body type', slot: 'body', ...field('body') },
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

/** True when the current outfit still matches the preset exactly (compared after the same normalising applyPreset does). */
function matchesPreset(a: AvatarConfig, id: string | null | undefined): boolean {
  if (!id || !OUTFIT_PRESETS.some((x) => x.id === id)) return false;
  const p = applyPreset(a, id);
  const same = (x: unknown, y: unknown) => JSON.stringify(x) === JSON.stringify(y);
  return same(a.top, p.top) && same(a.bottom, p.bottom) && same(a.shoes, p.shoes) && a.hat === p.hat
    && a.accent === p.accent && same([...a.accessories].sort(), [...p.accessories].sort());
}

function OptionRow({ row, avatar, onPick }: { row: Row; avatar: AvatarConfig; onPick: (a: AvatarConfig) => void }) {
  const opts: AvatarOption[] = optionsFor(row.slot, avatar.gender);
  if (!opts.length) return null;
  const value = row.get(avatar);
  const isOn = (id: string) => (Array.isArray(value) ? value.includes(id) : value === id);
  const swatches = opts.some((o) => o.swatch);
  return (
    <div className="look-row" role="group" aria-label={row.label}>
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

export interface LookPanelProps {
  avatar: AvatarConfig;
  onAvatar: (a: AvatarConfig) => void;
  username: string;
  onUsername: (v: string) => void;
  /** Server or validation error for the name, shown under the field. */
  nameError: string | null;
  nameRef: React.RefObject<HTMLInputElement | null>;
}

export default function LookPanel({ avatar, onAvatar, username, onUsername, nameError, nameRef }: LookPanelProps) {
  const [group, setGroup] = useState<Group>('outfit');
  const [touched, setTouched] = useState(false);
  const gender = avatar.gender;
  const presetEdited = !!avatar.preset && !matchesPreset(avatar, avatar.preset);
  const localBad = touched && username.length > 0 && !USERNAME_RE.test(username);
  const error = nameError ?? (localBad ? CREATOR.nameBad : null);

  const chooseGender = (g: Gender) => {
    if (g === gender) return;
    // keep the face and skin; reset gender-specific hair and clothes
    const a = avatar;
    onAvatar({ ...defaultAvatar(g), skin: a.skin, face: a.face, eyes: a.eyes, nose: a.nose, body: a.body });
  };

  return (
    <div className="look">
      <div className="field look__name">
        <label htmlFor="sim-name" className="look-row__label">{CREATOR.nameLabel}</label>
        <div className={`name-input${error ? ' is-bad' : ''}`}>
          <span className="name-input__at" aria-hidden>@</span>
          <input
            id="sim-name"
            ref={nameRef}
            className="name-input__field"
            autoComplete="off"
            autoCapitalize="off"
            autoCorrect="off"
            spellCheck={false}
            maxLength={20}
            placeholder={CREATOR.namePlaceholder}
            value={username}
            aria-invalid={!!error}
            aria-describedby="sim-name-help"
            onChange={(e) => onUsername(e.target.value.replace(/\s/g, '_'))}
            onBlur={() => setTouched(true)}
          />
          <span className="name-input__count" aria-hidden>{username.length}/20</span>
        </div>
        <p id="sim-name-help" className={error ? 'error-text' : 'hint'} role={error ? 'alert' : undefined}>
          {error ?? CREATOR.nameHelp}
        </p>
      </div>

      <div className="look-row">
        <span className="look-row__label">{CREATOR.body}</span>
        <Segmented label={CREATOR.body} value={gender} onChange={chooseGender}
          options={[{ id: 'female', label: 'Woman' }, { id: 'male', label: 'Man' }]} />
      </div>

      <Tabs value={group} onChange={(g) => setGroup(g as Group)} tabs={GROUPS} />
      <div className="look__body" key={group}>
        {group === 'outfit' && (
          <div className="look-row">
            <div className="look-row__head">
              <span className="look-row__label">{CREATOR.presets}</span>
              <span className={`look-row__hint${presetEdited ? ' is-edited' : ''}`}>{presetEdited ? CREATOR.presetsEdited : CREATOR.presetsHint}</span>
            </div>
            <div className="preset-grid">
              {presetsFor(gender).map((p) => {
                const on = avatar.preset === p.id;
                return (
                  <button key={p.id} type="button" className={`preset${on ? ' is-active' : ''}`} aria-pressed={on}
                    onClick={() => onAvatar(applyPreset(avatar, p.id))}>
                    <span className="preset__emoji" aria-hidden>{p.emoji}</span>
                    <span className="preset__label">{p.label}</span>
                    {on && presetEdited && <span className="preset__edited">{CREATOR.edited}</span>}
                  </button>
                );
              })}
            </div>
          </div>
        )}
        {ROWS[group].map((row) => (
          <OptionRow key={row.label} row={row} avatar={avatar} onPick={onAvatar} />
        ))}
      </div>
    </div>
  );
}
