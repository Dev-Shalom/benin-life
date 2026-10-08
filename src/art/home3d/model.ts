// 3D home ("dollhouse") data — no three.js here, so the HUD and sheets can import it for free.
//
// Units are metres. A layout's house covers x 0..w, z 0..d. The camera looks from the south-east
// (+x, +z), so the north (z = 0) and west (x = 0) walls are full height and the south/east walls are
// a low cut-away kerb. Anything outside the house rectangle (inside `lot`) is the compound/yard.
//
// Furniture is data: a `kind` (geometry + footprint + where the Sim stands, see KINDS) placed at
// x/z with a rotation in quarter turns. Tapping a piece with a `group` lists the home activities of
// that group (ACTIVITY_GROUP); the Sim walks to that piece's spot when an activity of the group starts.

export type HomeLayoutId = 'hostel' | 'face_me' | 'self_contain' | 'flat' | 'duplex';

/** What tapping a piece of furniture is about. Home activities map to one group each. */
export type HomeGroup = 'bed' | 'kitchen' | 'bath' | 'toilet' | 'media' | 'seat' | 'wardrobe';

export type HomePose = 'stand' | 'sit' | 'lie' | 'cook' | 'scrub';

/** Activity id -> furniture group. Home activities not listed here use 'seat' (sofa, chair, mat). */
export const ACTIVITY_GROUP: Record<string, HomeGroup> = {
  sleep: 'bed',
  nap: 'bed',
  cook_home: 'kitchen',
  bathe: 'bath',
  use_toilet: 'toilet',
  watch_tv: 'media',
  listen_radio: 'media',
  cold_drink: 'kitchen',
  relax_sofa: 'seat',
  sit_rest: 'seat',
};

export function activityGroup(activityId: string): HomeGroup {
  return ACTIVITY_GROUP[activityId] ?? 'seat';
}

export const GROUP_META: Record<HomeGroup, { label: string; emoji: string; pose: HomePose; empty: string }> = {
  bed: { label: 'Bed', emoji: '🛏️', pose: 'lie', empty: 'Nothing to do here right now.' },
  kitchen: { label: 'Kitchen', emoji: '🍳', pose: 'cook', empty: 'Nothing to cook right now.' },
  bath: { label: 'Bath', emoji: '🛁', pose: 'scrub', empty: 'No bath options here.' },
  toilet: { label: 'Toilet', emoji: '🚽', pose: 'sit', empty: 'The toilet is free whenever you need it.' },
  media: { label: 'TV and radio', emoji: '📺', pose: 'sit', empty: 'Nothing on right now.' },
  seat: { label: 'Relax', emoji: '🛋️', pose: 'sit', empty: 'Sit down and catch your breath.' },
  wardrobe: { label: 'Wardrobe', emoji: '👔', pose: 'stand', empty: 'Change your look.' },
};

export type FurnitureKind =
  | 'bunk' | 'bed_single' | 'bed_double' | 'bed_king' | 'mattress'
  | 'sofa' | 'sofa_l' | 'armchair' | 'plastic_chair' | 'stool' | 'bench'
  | 'table' | 'dining' | 'centre_table' | 'desk'
  | 'wardrobe' | 'locker' | 'shelf'
  | 'tv' | 'tv_big' | 'radio'
  | 'fan' | 'lamp' | 'plant' | 'rug' | 'ac'
  | 'kerosene_stove' | 'hotplate' | 'kitchen' | 'island' | 'fridge' | 'gas'
  | 'bucket_bath' | 'shower' | 'bathtub' | 'toilet' | 'pit_toilet' | 'sink'
  | 'generator' | 'drum' | 'clothesline' | 'stall'
  | 'drum_bucket' | 'gas_cooker';

export interface KindMeta {
  /** Footprint in local space (before rotation). */
  w: number;
  d: number;
  /** Blocks walking (rugs, wall units and hanging things don't). */
  solid: boolean;
  group?: HomeGroup;
  /** Where the Sim goes for this piece, local [x, z, facing yaw]. Defaults to the front edge. */
  spot?: [number, number, number];
  /** Sit poses: where the hips go, local [x, y, z, yaw]. Lie poses: where the FEET go (head points to -z). */
  seat?: [number, number, number, number];
  label: string;
}

// Local frame: +z is the "front" of a piece (where you use it from).
export const KINDS: Record<FurnitureKind, KindMeta> = {
  bunk: { w: 1.0, d: 2.0, solid: true, group: 'bed', spot: [0.8, 0.2, -Math.PI / 2], seat: [0, 0.58, 0.88, 0], label: 'Bunk bed' },
  bed_single: { w: 1.0, d: 2.0, solid: true, group: 'bed', spot: [0.8, 0.2, -Math.PI / 2], seat: [0, 0.6, 0.88, 0], label: 'Bed' },
  bed_double: { w: 1.5, d: 2.0, solid: true, group: 'bed', spot: [1.05, 0.2, -Math.PI / 2], seat: [0.3, 0.65, 0.88, 0], label: 'Bed' },
  bed_king: { w: 1.9, d: 2.1, solid: true, group: 'bed', spot: [1.25, 0.2, -Math.PI / 2], seat: [0.4, 0.68, 0.95, 0], label: 'Bed' },
  mattress: { w: 1.3, d: 1.9, solid: true, group: 'bed', spot: [0.95, 0.2, -Math.PI / 2], seat: [0.15, 0.3, 0.85, 0], label: 'Foam mattress' },
  sofa: { w: 1.9, d: 0.85, solid: true, group: 'seat', spot: [0, 0.75, 0], seat: [0, 0.46, 0.06, 0], label: 'Sofa' },
  sofa_l: { w: 2.8, d: 0.9, solid: true, group: 'seat', spot: [0, 0.8, 0], seat: [0, 0.46, 0.06, 0], label: 'Sofa' },
  armchair: { w: 0.85, d: 0.85, solid: true, group: 'seat', spot: [0, 0.75, 0], seat: [0, 0.46, 0.06, 0], label: 'Armchair' },
  plastic_chair: { w: 0.5, d: 0.5, solid: true, group: 'seat', spot: [0, 0.5, 0], seat: [0, 0.45, 0.02, 0], label: 'Plastic chair' },
  stool: { w: 0.4, d: 0.4, solid: true, group: 'seat', spot: [0, 0.45, 0], seat: [0, 0.42, 0, 0], label: 'Stool' },
  bench: { w: 1.4, d: 0.4, solid: true, group: 'seat', spot: [0, 0.5, 0], seat: [0, 0.45, 0, 0], label: 'Bench' },
  table: { w: 0.9, d: 0.6, solid: true, label: 'Table' },
  dining: { w: 1.4, d: 0.9, solid: true, label: 'Dining table' },
  centre_table: { w: 1.0, d: 0.55, solid: true, label: 'Centre table' },
  desk: { w: 1.0, d: 0.55, solid: true, label: 'Study desk' },
  wardrobe: { w: 1.2, d: 0.6, solid: true, group: 'wardrobe', label: 'Wardrobe' },
  locker: { w: 0.6, d: 0.5, solid: true, group: 'wardrobe', label: 'Locker' },
  shelf: { w: 0.9, d: 0.35, solid: true, label: 'Shelf' },
  tv: { w: 1.2, d: 0.45, solid: true, group: 'media', label: 'TV' },
  tv_big: { w: 1.8, d: 0.45, solid: true, group: 'media', label: 'Big TV' },
  radio: { w: 0.45, d: 0.4, solid: true, group: 'media', label: 'Radio' },
  fan: { w: 0.45, d: 0.45, solid: true, label: 'Standing fan' },
  lamp: { w: 0.35, d: 0.35, solid: true, label: 'Lamp' },
  plant: { w: 0.45, d: 0.45, solid: true, label: 'Plant' },
  rug: { w: 2.0, d: 1.4, solid: false, label: 'Rug' },
  ac: { w: 0.9, d: 0.25, solid: false, label: 'Split AC' },
  kerosene_stove: { w: 0.6, d: 0.5, solid: true, group: 'kitchen', spot: [0, 0.6, Math.PI], label: 'Kerosene stove' },
  hotplate: { w: 0.55, d: 0.45, solid: true, group: 'kitchen', spot: [0, 0.55, Math.PI], label: 'Hot plate' },
  kitchen: { w: 2.2, d: 0.62, solid: true, group: 'kitchen', spot: [-0.6, 0.62, Math.PI], label: 'Kitchen' },
  island: { w: 1.6, d: 0.8, solid: true, group: 'kitchen', spot: [0, -0.75, 0], label: 'Kitchen island' },
  fridge: { w: 0.65, d: 0.62, solid: true, group: 'kitchen', spot: [0, 0.65, Math.PI], label: 'Fridge' },
  gas: { w: 0.32, d: 0.32, solid: true, label: 'Gas cylinder' },
  bucket_bath: { w: 1.1, d: 1.1, solid: false, group: 'bath', spot: [0, 0, 0], label: 'Bathroom (bucket)' },
  shower: { w: 0.95, d: 0.95, solid: false, group: 'bath', spot: [0, 0, 0], label: 'Shower' },
  bathtub: { w: 0.8, d: 1.7, solid: true, group: 'bath', spot: [-0.65, 0, Math.PI / 2], label: 'Bathtub' },
  toilet: { w: 0.45, d: 0.7, solid: true, group: 'toilet', spot: [0, 0.55, 0], seat: [0, 0.44, 0.02, 0], label: 'Toilet' },
  pit_toilet: { w: 1.1, d: 1.1, solid: false, group: 'toilet', spot: [0, 0, 0], label: 'Shared toilet' },
  sink: { w: 0.5, d: 0.42, solid: true, label: 'Sink' },
  generator: { w: 0.8, d: 0.55, solid: true, label: 'Generator' },
  drum: { w: 0.6, d: 0.6, solid: true, label: 'Water drum' },
  clothesline: { w: 2.4, d: 0.2, solid: false, label: 'Clothesline' },
  stall: { w: 1.2, d: 1.2, solid: false, label: 'Stall' },
  drum_bucket: { w: 1.0, d: 0.6, solid: true, group: 'bath', spot: [0.1, 0.65, Math.PI], label: 'Water drum and bucket' },
  gas_cooker: { w: 0.95, d: 0.6, solid: true, group: 'kitchen', spot: [-0.12, 0.62, Math.PI], label: 'Gas cooker' },
};

/** Kinds that come with the house (bathroom, shared compound things, wall units). Everything else is
 * the player's own furniture and is replaced by their furniture set (furnishLayout). */
export const FIXED_KINDS: ReadonlySet<FurnitureKind> = new Set<FurnitureKind>([
  'toilet', 'pit_toilet', 'shower', 'bathtub', 'sink', 'bucket_bath', 'generator', 'drum', 'clothesline', 'ac', 'stall',
]);

export interface FurnitureItem {
  id: string;
  kind: FurnitureKind;
  x: number;
  z: number;
  /** Quarter turns (0 = front faces +z / south). */
  rot?: number;
  /** Height it stands at (e.g. a radio on a table). */
  y?: number;
  /** Colour override for the main material. */
  color?: string;
  /** Taps on this piece act for this group (e.g. a TV or radio decoration that opens 'media'). */
  group?: HomeGroup;
  /** This piece is where the Sim goes for the group (e.g. the sofa for 'media'). */
  actorFor?: HomeGroup[];
  /** Home activities this piece hosts (a player's own furniture, from the server's furniture table). */
  activities?: string[];
}

/** Wall segment [x1, z1, x2, z2] (axis-aligned). */
export type Seg = [number, number, number, number];

export interface HomeLayout {
  id: HomeLayoutId;
  label: string;
  w: number;
  d: number;
  /** Walkable area including the yard [x0, z0, x1, z1]. */
  lot: [number, number, number, number];
  floor: { a: string; b?: string; tile?: number };
  /** Floor patches (bathroom tiles, kitchen) [x0, z0, x1, z1, colourA, colourB?, tile?]. */
  patches?: [number, number, number, number, string, string?, number?][];
  wall: string;
  /** Inside face colour of the back walls. */
  wallInner: string;
  wallH: number;
  /** Interior partitions (half height so you can see in). Leave gaps for doorways. */
  partitions: Seg[];
  /** Gaps in the low front walls [side, from, to]. */
  doors: ['s' | 'e', number, number][];
  /** Windows on the back walls [side, from, to]. */
  windows: ['n' | 'w', number, number][];
  yard?: { colour: string; fence?: boolean };
  /** Spot the Sim idles at when nothing is going on [x, z, yaw]. */
  home: [number, number, number];
  furniture: FurnitureItem[];
  /** Where each furniture-set slot goes [x, z, rot quarter turns] (see furnishLayout). */
  slots: Record<string, [number, number, number]>;
}

const Q = 1; // quarter turn

export const LAYOUTS: Record<HomeLayoutId, HomeLayout> = {
  // UNIBEN hostel: a shared room with bunks, desks and lockers; bathroom stalls down the corridor.
  hostel: {
    id: 'hostel',
    label: 'UNIBEN hostel room',
    w: 5.2,
    d: 4.4,
    lot: [0, 0, 7.6, 5.6],
    floor: { a: '#a9b4ad', b: '#9da9a2', tile: 0.6 },
    wall: '#5a6b7a',
    wallInner: '#d9e4ec',
    wallH: 2.5,
    partitions: [],
    doors: [['e', 3.1, 4.1]],
    windows: [['n', 1.4, 3.0], ['w', 1.2, 2.6]],
    yard: { colour: '#c98a5e' },
    home: [3.6, 3.4, -Math.PI / 4],
    slots: { bed: [0.75, 1.1, 0], seat: [3.2, 2.9, 0], sofa: [2.0, 3.4, 3], tv: [0.3, 3.4, 1], stove: [4.7, 0.4, 0], fridge: [4.85, 1.45, 3], wardrobe: [3.4, 0.35, 0], bath: [6.8, 3.55, 3] },
    furniture: [
      { id: 'bunk1', kind: 'bunk', x: 0.6, z: 1.1, color: '#2f6fb3' },
      { id: 'bunk2', kind: 'bunk', x: 2.0, z: 1.1, color: '#b33f3f' },
      { id: 'locker1', kind: 'locker', x: 3.3, z: 0.35 },
      { id: 'locker2', kind: 'locker', x: 3.95, z: 0.35 },
      { id: 'desk1', kind: 'desk', x: 0.6, z: 3.6, rot: 2 * Q },
      { id: 'chair1', kind: 'plastic_chair', x: 0.6, z: 3.0, color: '#e8e4dc' },
      { id: 'radio', kind: 'radio', x: 0.95, z: 3.62, y: 0.75, rot: 2 * Q },
      { id: 'desk2', kind: 'desk', x: 4.6, z: 1.6, rot: 3 * Q },
      { id: 'chair2', kind: 'plastic_chair', x: 4.0, z: 1.6, rot: 1 * Q, color: '#3e8f5a', actorFor: ['media', 'seat'] },
      { id: 'hotplate', kind: 'hotplate', x: 4.7, z: 0.4 },
      { id: 'fan', kind: 'fan', x: 2.9, z: 2.6 },
      { id: 'bucket', kind: 'bucket_bath', x: 6.6, z: 1.0, rot: 3 * Q },
      { id: 'toilet', kind: 'pit_toilet', x: 6.6, z: 2.4, rot: 3 * Q },
      { id: 'drum', kind: 'drum', x: 6.6, z: 4.6 },
    ],
  },

  // Face-me-I-face-you single room; the bathroom, toilet and generator are shared in the compound.
  face_me: {
    id: 'face_me',
    label: 'Face-me-I-face-you room',
    w: 4.2,
    d: 3.8,
    lot: [0, 0, 7.2, 5.4],
    floor: { a: '#9e9a92', b: '#97938b', tile: 1.2 },
    wall: '#6b5e4e',
    wallInner: '#cfe3cf',
    wallH: 2.5,
    partitions: [],
    doors: [['e', 2.4, 3.3]],
    windows: [['n', 2.3, 3.4]],
    yard: { colour: '#bf7a4c', fence: true },
    home: [2.6, 2.6, -Math.PI / 4],
    slots: { bed: [0.85, 1.1, 0], seat: [1.3, 3.2, 3], sofa: [1.7, 3.3, 2], tv: [2.75, 0.3, 0], rug: [2.2, 2.4, 0], stove: [3.6, 2.0, 3], fridge: [3.75, 0.4, 0], wardrobe: [0.35, 3.0, 1], bath: [5.7, 3.5, 3] },
    furniture: [
      { id: 'rug', kind: 'rug', x: 2.1, z: 2.7, color: '#9c3b33' },
      { id: 'bed', kind: 'bed_double', x: 0.85, z: 1.1, color: '#6d4aa0' },
      { id: 'wardrobe', kind: 'wardrobe', x: 2.2, z: 0.35, color: '#8a5a33' },
      { id: 'fan', kind: 'fan', x: 3.6, z: 0.5 },
      { id: 'table', kind: 'table', x: 0.6, z: 3.25, rot: 1 * Q },
      { id: 'radio', kind: 'radio', x: 0.6, z: 3.45, y: 0.75, rot: 1 * Q },
      { id: 'chair', kind: 'plastic_chair', x: 1.25, z: 3.2, rot: 3 * Q, color: '#e8e4dc', actorFor: ['media', 'seat'] },
      { id: 'stove', kind: 'kerosene_stove', x: 3.6, z: 1.6, rot: 3 * Q },
      { id: 'bucket', kind: 'bucket_bath', x: 6.2, z: 0.9, rot: 3 * Q },
      { id: 'toilet', kind: 'pit_toilet', x: 6.2, z: 2.25, rot: 3 * Q },
      { id: 'gen', kind: 'generator', x: 5.0, z: 4.7 },
      { id: 'drum', kind: 'drum', x: 6.4, z: 4.6 },
      { id: 'line', kind: 'clothesline', x: 4.9, z: 0.5, rot: 1 * Q },
    ],
  },

  // Self-contain in Uselu: one room with its own kitchenette and bathroom.
  self_contain: {
    id: 'self_contain',
    label: 'Self-contain',
    w: 6.0,
    d: 4.8,
    lot: [0, 0, 7.4, 6.0],
    floor: { a: '#e9e1d2', b: '#ddd3c1', tile: 0.6 },
    patches: [[0, 0, 1.9, 2.0, '#cfe0e6', '#bdd2d9', 0.3]],
    wall: '#4f5d6b',
    wallInner: '#f1ead9',
    wallH: 2.6,
    partitions: [[1.9, 0, 1.9, 1.1], [0, 2.0, 1.2, 2.0]],
    doors: [['e', 2.55, 3.45]],
    windows: [['n', 2.6, 4.0], ['w', 2.8, 4.0]],
    yard: { colour: '#c4875a' },
    home: [3.8, 3.2, -Math.PI / 4],
    slots: { bed: [4.95, 1.5, 3], seat: [2.6, 3.5, 3], sofa: [2.6, 3.5, 3], tv: [0.3, 3.5, 1], ctable: [1.45, 3.5, 1], rug: [1.6, 3.5, 1], stove: [2.7, 0.35, 0], fridge: [3.55, 0.4, 0], wardrobe: [5.3, 0.35, 0], bath: [6.7, 2.0, 0] },
    furniture: [
      { id: 'toilet', kind: 'toilet', x: 0.45, z: 0.5 },
      { id: 'shower', kind: 'shower', x: 1.3, z: 0.65 },
      { id: 'sink', kind: 'sink', x: 0.35, z: 1.5, rot: 1 * Q },
      { id: 'kitchen', kind: 'kitchen', x: 3.4, z: 0.35, color: '#f4f1ea' },
      { id: 'gas', kind: 'gas', x: 2.1, z: 0.3 },
      { id: 'bed', kind: 'bed_double', x: 4.95, z: 1.5, rot: 3 * Q, color: '#2e7d6b' },
      { id: 'wardrobe', kind: 'wardrobe', x: 5.3, z: 0.35, color: '#7b4f2e' },
      { id: 'tv', kind: 'tv', x: 0.3, z: 3.5, rot: 1 * Q },
      { id: 'sofa', kind: 'sofa', x: 2.6, z: 3.5, rot: 3 * Q, color: '#b0473c', actorFor: ['media', 'seat'] },
      { id: 'ctable', kind: 'centre_table', x: 1.45, z: 3.5, rot: 1 * Q },
      { id: 'fan', kind: 'fan', x: 3.2, z: 2.0 },
      { id: 'gen', kind: 'generator', x: 6.8, z: 1.0, rot: 1 * Q },
      { id: 'plant', kind: 'plant', x: 6.8, z: 5.4 },
    ],
  },

  // Mini-flat on Mission Road: parlour, bedroom, kitchen and bathroom.
  flat: {
    id: 'flat',
    label: 'Mini-flat',
    w: 8.0,
    d: 6.2,
    lot: [0, 0, 9.4, 7.4],
    floor: { a: '#f2f0ec', b: '#2b2f36', tile: 0.6 },
    patches: [[0, 0, 3.2, 2.8, '#efe6d6', '#e1d5c0', 0.5], [5.6, 0, 8.0, 2.4, '#d4e4ea', '#c2d6de', 0.3]],
    wall: '#3b4350',
    wallInner: '#eef0f3',
    wallH: 2.7,
    partitions: [
      [3.2, 0, 3.2, 1.6], [3.2, 2.4, 3.2, 2.8], [0, 2.8, 2.4, 2.8], // bedroom
      [5.6, 0, 5.6, 1.4], [5.6, 2.4, 6.6, 2.4], [7.4, 2.4, 8.0, 2.4], // bathroom
    ],
    doors: [['e', 4.4, 5.4]],
    windows: [['n', 0.8, 2.4], ['n', 3.8, 5.0], ['w', 3.6, 5.4]],
    yard: { colour: '#7aa35a' },
    home: [5.4, 4.4, -Math.PI / 4],
    slots: { bed: [0.95, 1.15, 0], seat: [3.2, 4.7, 3], sofa: [3.2, 4.7, 3], tv: [0.3, 4.7, 1], ctable: [1.9, 4.7, 1], rug: [2.0, 4.7, 0], stove: [4.2, 0.35, 0], fridge: [5.1, 0.4, 0], wardrobe: [2.4, 0.35, 0], bath: [8.7, 2.6, 0] },
    furniture: [
      { id: 'bed', kind: 'bed_double', x: 0.95, z: 1.15, color: '#5b3fa0' },
      { id: 'wardrobe', kind: 'wardrobe', x: 2.4, z: 0.35, color: '#8a5a33' },
      { id: 'ac', kind: 'ac', x: 1.6, z: 0.15 },
      { id: 'kitchen', kind: 'kitchen', x: 4.45, z: 0.35, color: '#f4f1ea' },
      { id: 'fridge', kind: 'fridge', x: 3.65, z: 1.9, rot: 1 * Q },
      { id: 'gas', kind: 'gas', x: 5.3, z: 0.95 },
      { id: 'toilet', kind: 'toilet', x: 6.1, z: 0.5 },
      { id: 'shower', kind: 'shower', x: 7.45, z: 0.6 },
      { id: 'sink', kind: 'sink', x: 6.8, z: 0.3 },
      { id: 'rug', kind: 'rug', x: 2.0, z: 4.7, color: '#b3332c' },
      { id: 'tv', kind: 'tv', x: 0.3, z: 4.7, rot: 1 * Q },
      { id: 'sofa', kind: 'sofa', x: 3.2, z: 4.7, rot: 3 * Q, color: '#7a1f2b', actorFor: ['media', 'seat'] },
      { id: 'arm', kind: 'armchair', x: 2.0, z: 5.75, rot: 2 * Q, color: '#7a1f2b' },
      { id: 'ctable', kind: 'centre_table', x: 1.9, z: 4.7, rot: 1 * Q },
      { id: 'dining', kind: 'dining', x: 6.4, z: 3.35 },
      { id: 'dchair1', kind: 'plastic_chair', x: 5.9, z: 4.1, rot: 2 * Q, color: '#c79a5a' },
      { id: 'dchair2', kind: 'plastic_chair', x: 6.9, z: 4.1, rot: 2 * Q, color: '#c79a5a' },
      { id: 'lamp', kind: 'lamp', x: 0.35, z: 5.85 },
      { id: 'plant', kind: 'plant', x: 7.6, z: 5.8 },
      { id: 'gen', kind: 'generator', x: 8.8, z: 1.2, rot: 1 * Q },
    ],
  },

  // GRA duplex (ground floor): open-plan living, big kitchen, master bedroom, bath with a tub.
  duplex: {
    id: 'duplex',
    label: 'GRA duplex',
    w: 10.0,
    d: 7.6,
    // Wider GRA compound: leave room for a small pool, driveway and carport around the cut-away home.
    lot: [-1, -0.4, 14.5, 10.6],
    floor: { a: '#f4f1ec', b: '#e8e3da', tile: 0.8 },
    patches: [[0, 0, 3.8, 3.2, '#c9a27a', '#bf976e', 0.4], [7.2, 0, 10.0, 2.8, '#dfe9ee', '#cfdde4', 0.4]],
    wall: '#2f3640',
    wallInner: '#f6f3ee',
    wallH: 2.9,
    partitions: [
      [3.8, 0, 3.8, 2.0], [0, 3.2, 2.8, 3.2],
      [7.2, 0, 7.2, 1.6], [7.2, 2.8, 8.0, 2.8], [8.9, 2.8, 10.0, 2.8],
    ],
    doors: [['e', 5.0, 6.2], ['s', 4.4, 5.6]],
    windows: [['n', 0.8, 2.8], ['n', 4.4, 6.6], ['w', 4.2, 6.8]],
    yard: { colour: '#6fa052' },
    home: [6.2, 5.6, -Math.PI / 4],
    slots: { bed: [1.3, 1.25, 0], seat: [3.2, 5.6, 3], sofa: [3.2, 5.6, 3], tv: [0.3, 5.6, 1], ctable: [1.9, 5.6, 1], rug: [2.2, 5.6, 0], stove: [5.7, 0.35, 0], fridge: [4.4, 0.35, 0], wardrobe: [3.0, 0.35, 0], bath: [11.0, 3.0, 0] },
    furniture: [
      { id: 'bed', kind: 'bed_king', x: 1.3, z: 1.25, color: '#efe9df' },
      { id: 'wardrobe', kind: 'wardrobe', x: 3.0, z: 0.35, color: '#5b3a24' },
      { id: 'ac1', kind: 'ac', x: 1.4, z: 0.15 },
      { id: 'lamp1', kind: 'lamp', x: 2.6, z: 2.8 },
      { id: 'island', kind: 'island', x: 5.5, z: 2.0, color: '#e9e4dc' },
      { id: 'kitchen', kind: 'kitchen', x: 5.7, z: 0.35, color: '#2f3640' },
      { id: 'fridge', kind: 'fridge', x: 4.25, z: 0.35 },
      { id: 'toilet', kind: 'toilet', x: 7.7, z: 0.5 },
      { id: 'tub', kind: 'bathtub', x: 9.5, z: 1.2 },
      { id: 'sink', kind: 'sink', x: 8.5, z: 0.3 },
      { id: 'rug', kind: 'rug', x: 2.2, z: 5.6, color: '#d4b26a' },
      { id: 'tv', kind: 'tv_big', x: 0.3, z: 5.6, rot: 1 * Q },
      { id: 'sofa', kind: 'sofa_l', x: 3.6, z: 5.6, rot: 3 * Q, color: '#e6e0d6', actorFor: ['media', 'seat'] },
      { id: 'arm', kind: 'armchair', x: 2.2, z: 7.0, rot: 2 * Q, color: '#a0703c' },
      { id: 'ctable', kind: 'centre_table', x: 2.0, z: 5.6, rot: 1 * Q },
      { id: 'dining', kind: 'dining', x: 8.0, z: 4.6 },
      { id: 'dchair1', kind: 'plastic_chair', x: 7.5, z: 5.35, rot: 2 * Q, color: '#5b3a24' },
      { id: 'dchair2', kind: 'plastic_chair', x: 8.5, z: 5.35, rot: 2 * Q, color: '#5b3a24' },
      { id: 'dchair3', kind: 'plastic_chair', x: 7.5, z: 3.85, color: '#5b3a24' },
      { id: 'dchair4', kind: 'plastic_chair', x: 8.5, z: 3.85, color: '#5b3a24' },
      { id: 'ac2', kind: 'ac', x: 0.15, z: 5.0, rot: 1 * Q },
      { id: 'lamp2', kind: 'lamp', x: 0.35, z: 7.2 },
      { id: 'plant1', kind: 'plant', x: 9.6, z: 7.2 },
      { id: 'plant2', kind: 'plant', x: 4.6, z: 7.2 },
      { id: 'gen', kind: 'generator', x: 11.0, z: 1.4, rot: 1 * Q },
      { id: 'plant3', kind: 'plant', x: 11.0, z: 8.4 },
    ],
  },
};

/** housing_id (server) -> layout. Unknown ids fall back on the location's scene. */
const HOUSING_LAYOUT: Record<string, HomeLayoutId> = {
  hostel_uniben: 'hostel',
  face_me_ekenwan: 'face_me',
  face_me_aduwawa: 'face_me',
  self_contain_uselu: 'self_contain',
  mini_flat_mission: 'flat',
  duplex_gra: 'duplex',
};

export function homeLayoutFor(housingId: string | null | undefined, scene?: string | null): HomeLayoutId {
  const id = housingId ?? '';
  if (HOUSING_LAYOUT[id]) return HOUSING_LAYOUT[id];
  if (id.startsWith('hostel')) return 'hostel';
  if (id.startsWith('face_me')) return 'face_me';
  if (id.startsWith('self_con')) return 'self_contain';
  if (id.includes('flat')) return 'flat';
  if (id.includes('duplex')) return 'duplex';
  if (scene === 'home_duplex') return 'duplex';
  if (scene === 'home_flat') return 'self_contain';
  return 'face_me';
}

/** The furniture piece a group's activities happen at (actorFor wins, then the first of that group). */
export function actorFor(layout: HomeLayout, group: HomeGroup): FurnitureItem | null {
  const explicit = layout.furniture.find((f) => f.actorFor?.includes(group));
  if (explicit) return explicit;
  const own = layout.furniture.find((f) => (f.group ?? KINDS[f.kind].group) === group && !f.actorFor);
  if (own) return own;
  if (group === 'seat' || group === 'media') return actorFor(layout, 'bed');
  return null;
}

export function itemGroup(f: FurnitureItem): HomeGroup | undefined {
  return f.group ?? KINDS[f.kind].group;
}

/** A piece of furniture the player owns (server: player_furniture + furniture). */
export interface OwnedPiece {
  id: string;
  kind: string;
  slot: string;
  activities: string[];
  color?: string | null;
}

const SEATS = new Set<string>(['sofa', 'sofa_l', 'armchair']);

/**
 * The layout with the player's own furniture: the house's fixtures (FIXED_KINDS) stay, every other
 * piece is replaced by the owned pieces, each placed at its slot. Pieces with an unknown kind or a
 * slot this layout doesn't have are skipped; the first piece in a slot wins. `null` = the full
 * default furnishing (dev page, before the furniture loads).
 */
export function furnishLayout(base: HomeLayout, pieces: OwnedPiece[] | null): HomeLayout {
  if (!pieces) return base;
  const fixtures = base.furniture.filter((f) => FIXED_KINDS.has(f.kind));
  const used = new Set<string>();
  const own: FurnitureItem[] = [];
  for (const p of pieces) {
    const at = base.slots[p.slot];
    if (!at || used.has(p.slot) || !(p.kind in KINDS)) continue;
    used.add(p.slot);
    own.push({
      id: `own_${p.id}`,
      kind: p.kind as FurnitureKind,
      x: at[0],
      z: at[1],
      rot: at[2],
      color: p.color ?? undefined,
      activities: p.activities,
      actorFor: SEATS.has(p.kind) ? ['media', 'seat'] : undefined,
    });
  }
  return { ...base, furniture: [...fixtures, ...own] };
}

/** Where an activity happens: the group's explicit actor (sofa for TV), then a piece that hosts the
 * activity (the drum for a bucket bath), then the group's usual piece. */
export function pieceFor(layout: HomeLayout, activityId: string | null | undefined, group: HomeGroup): FurnitureItem | null {
  const explicit = layout.furniture.find((f) => f.actorFor?.includes(group));
  if (explicit) return explicit;
  if (activityId) {
    const host = layout.furniture.find((f) => f.activities?.includes(activityId));
    if (host) return host;
  }
  return actorFor(layout, group);
}
