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

export type HomePose = 'stand' | 'sit' | 'lie' | 'cook' | 'scrub' | 'dance' | 'greet';

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
  | 'drum_bucket' | 'gas_cooker'
  // B1 buy catalogue (docs/FURNITURE_CATALOGUE.md)
  | 'plastic_table' | 'sofa_2' | 'sofa_lux' | 'recliner' | 'centre_glass' | 'office_chair' | 'garden_set'
  | 'tv_small' | 'tv_43' | 'tv_55' | 'tv_75' | 'speaker_small' | 'home_theatre' | 'speaker_tower'
  | 'mat_raffia' | 'rug_big' | 'curtain' | 'curtain_lux' | 'fan_table' | 'fan_ceiling' | 'ac_big' | 'ac_standing'
  | 'bookshelf' | 'mattress_thick' | 'bed_6' | 'bed_lux' | 'clothes_rack' | 'wardrobe_big' | 'dressing'
  | 'mirror_stand' | 'bedside' | 'lamp_small' | 'chandelier'
  | 'gas_table' | 'cooker_big' | 'fridge_small' | 'fridge_sbs' | 'freezer' | 'microwave' | 'blender' | 'pots'
  | 'dispenser' | 'dining4' | 'dining6' | 'kitchen_cab'
  | 'bucket_bowl' | 'water_heater' | 'mirror_wall' | 'towel_rack' | 'washer'
  | 'gen_small' | 'gen_big' | 'inverter' | 'inverter_small' | 'solar' | 'water_tank' | 'gate_light' | 'car_shade'
  | 'plant_big' | 'wall_art' | 'plaque' | 'bronze_head' | 'wall_clock' | 'photo_frame' | 'aquarium' | 'vase'
  // H1: built into the duplex (architecture: never player furniture)
  | 'stairs';

/** Where a piece may stand (B1 arrange; the server checks the same rule from furniture.placement):
 * in = inside the house, out = in the yard, any = either (not across a wall), wall = inside, against
 * the north or west wall (hung on it). */
export type Placement = 'in' | 'out' | 'any' | 'wall';

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
  /** Default 'in'. */
  place?: Placement;
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
  plastic_chair: { w: 0.5, d: 0.5, solid: true, group: 'seat', spot: [0, 0.5, 0], seat: [0, 0.45, 0.02, 0], label: 'Plastic chair', place: 'any' },
  stool: { w: 0.4, d: 0.4, solid: true, group: 'seat', spot: [0, 0.45, 0], seat: [0, 0.42, 0, 0], label: 'Stool', place: 'any' },
  bench: { w: 1.4, d: 0.4, solid: true, group: 'seat', spot: [0, 0.5, 0], seat: [0, 0.45, 0, 0], label: 'Bench', place: 'any' },
  table: { w: 0.9, d: 0.6, solid: true, label: 'Table' },
  dining: { w: 1.4, d: 0.9, solid: true, label: 'Dining table' },
  centre_table: { w: 1.0, d: 0.55, solid: true, label: 'Centre table' },
  desk: { w: 1.0, d: 0.55, solid: true, label: 'Study desk' },
  wardrobe: { w: 1.2, d: 0.6, solid: true, group: 'wardrobe', label: 'Wardrobe' },
  locker: { w: 0.6, d: 0.5, solid: true, group: 'wardrobe', label: 'Locker' },
  shelf: { w: 0.9, d: 0.35, solid: true, label: 'Shelf' },
  tv: { w: 1.2, d: 0.45, solid: true, group: 'media', label: 'TV' },
  tv_big: { w: 1.8, d: 0.45, solid: true, group: 'media', label: 'Big TV' },
  radio: { w: 0.45, d: 0.4, solid: true, group: 'media', label: 'Radio', place: 'any' },
  fan: { w: 0.45, d: 0.45, solid: true, label: 'Standing fan' },
  lamp: { w: 0.35, d: 0.35, solid: true, label: 'Lamp' },
  plant: { w: 0.45, d: 0.45, solid: true, label: 'Plant', place: 'any' },
  rug: { w: 2.0, d: 1.4, solid: false, label: 'Rug' },
  ac: { w: 0.9, d: 0.25, solid: false, label: 'Split AC', place: 'wall' },
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
  generator: { w: 0.8, d: 0.55, solid: true, label: 'Generator', place: 'out' },
  drum: { w: 0.6, d: 0.6, solid: true, label: 'Water drum', place: 'any' },
  clothesline: { w: 2.4, d: 0.2, solid: false, label: 'Clothesline', place: 'out' },
  stall: { w: 1.2, d: 1.2, solid: false, label: 'Stall' },
  drum_bucket: { w: 1.0, d: 0.6, solid: true, group: 'bath', spot: [0.1, 0.65, Math.PI], label: 'Water drum and bucket' },
  gas_cooker: { w: 0.95, d: 0.6, solid: true, group: 'kitchen', spot: [-0.12, 0.62, Math.PI], label: 'Gas cooker' },

  // ---- B1 buy catalogue. Sizes here are copied into furniture.w/d by the buy_catalogue migration.
  plastic_table: { w: 0.8, d: 0.8, solid: true, label: 'Plastic table', place: 'any' },
  sofa_2: { w: 1.4, d: 0.85, solid: true, group: 'seat', spot: [0, 0.75, 0], seat: [0, 0.46, 0.06, 0], label: 'Loveseat' },
  sofa_lux: { w: 2.4, d: 0.95, solid: true, group: 'seat', spot: [0, 0.85, 0], seat: [0, 0.46, 0.08, 0], label: 'Luxury sofa' },
  recliner: { w: 0.95, d: 0.95, solid: true, group: 'seat', spot: [0, 0.8, 0], seat: [0, 0.46, 0.06, 0], label: 'Recliner' },
  centre_glass: { w: 1.2, d: 0.65, solid: true, label: 'Glass centre table' },
  office_chair: { w: 0.6, d: 0.6, solid: true, group: 'seat', spot: [0, 0.55, 0], seat: [0, 0.48, 0.02, 0], label: 'Office chair' },
  garden_set: { w: 1.6, d: 1.6, solid: true, label: 'Garden chairs', place: 'out' },
  tv_small: { w: 0.8, d: 0.4, solid: true, group: 'media', label: 'Small TV' },
  tv_43: { w: 1.3, d: 0.45, solid: true, group: 'media', label: 'TV' },
  tv_55: { w: 1.5, d: 0.45, solid: true, group: 'media', label: 'TV' },
  tv_75: { w: 2.2, d: 0.5, solid: true, group: 'media', label: 'Big TV' },
  speaker_small: { w: 0.3, d: 0.3, solid: true, group: 'media', label: 'Speaker' },
  home_theatre: { w: 1.6, d: 0.45, solid: true, group: 'media', label: 'Home theatre' },
  speaker_tower: { w: 0.35, d: 0.35, solid: true, group: 'media', label: 'Tower speaker' },
  mat_raffia: { w: 1.6, d: 1.0, solid: false, label: 'Raffia mat' },
  rug_big: { w: 2.6, d: 1.8, solid: false, label: 'Big rug' },
  curtain: { w: 1.4, d: 0.15, solid: false, label: 'Curtains', place: 'wall' },
  curtain_lux: { w: 1.8, d: 0.18, solid: false, label: 'Curtains', place: 'wall' },
  fan_table: { w: 0.35, d: 0.3, solid: true, label: 'Rechargeable fan', place: 'any' },
  fan_ceiling: { w: 1.2, d: 1.2, solid: false, label: 'Ceiling fan' },
  ac_big: { w: 1.1, d: 0.28, solid: false, label: 'Inverter AC', place: 'wall' },
  ac_standing: { w: 0.5, d: 0.4, solid: true, label: 'Standing AC' },
  bookshelf: { w: 1.0, d: 0.38, solid: true, label: 'Bookshelf' },
  mattress_thick: { w: 1.4, d: 1.95, solid: true, group: 'bed', spot: [1.0, 0.2, -Math.PI / 2], seat: [0.15, 0.4, 0.85, 0], label: 'Foam mattress' },
  bed_6: { w: 1.8, d: 2.05, solid: true, group: 'bed', spot: [1.2, 0.2, -Math.PI / 2], seat: [0.35, 0.66, 0.9, 0], label: 'Bed' },
  bed_lux: { w: 2.1, d: 2.25, solid: true, group: 'bed', spot: [1.35, 0.2, -Math.PI / 2], seat: [0.45, 0.72, 1.0, 0], label: 'King bed' },
  clothes_rack: { w: 1.0, d: 0.45, solid: true, group: 'wardrobe', label: 'Hanger rack' },
  wardrobe_big: { w: 1.9, d: 0.62, solid: true, group: 'wardrobe', label: 'Wardrobe' },
  dressing: { w: 1.0, d: 0.45, solid: true, label: 'Dressing table' },
  mirror_stand: { w: 0.5, d: 0.35, solid: true, label: 'Standing mirror' },
  bedside: { w: 0.45, d: 0.4, solid: true, label: 'Bedside table' },
  lamp_small: { w: 0.3, d: 0.3, solid: true, label: 'Lamp' },
  chandelier: { w: 0.9, d: 0.9, solid: false, label: 'Chandelier' },
  gas_table: { w: 0.7, d: 0.5, solid: true, group: 'kitchen', spot: [0, 0.6, Math.PI], label: 'Gas burner' },
  cooker_big: { w: 0.95, d: 0.62, solid: true, group: 'kitchen', spot: [0, 0.65, Math.PI], label: 'Gas cooker' },
  fridge_small: { w: 0.5, d: 0.5, solid: true, group: 'kitchen', spot: [0, 0.55, Math.PI], label: 'Bar fridge' },
  fridge_sbs: { w: 0.95, d: 0.75, solid: true, group: 'kitchen', spot: [0, 0.75, Math.PI], label: 'Fridge' },
  freezer: { w: 1.0, d: 0.62, solid: true, group: 'kitchen', spot: [0, 0.65, Math.PI], label: 'Freezer' },
  microwave: { w: 0.55, d: 0.45, solid: true, group: 'kitchen', spot: [0, 0.55, Math.PI], label: 'Microwave' },
  blender: { w: 0.4, d: 0.4, solid: true, group: 'kitchen', spot: [0, 0.5, Math.PI], label: 'Blender' },
  pots: { w: 0.7, d: 0.4, solid: true, group: 'kitchen', spot: [0, 0.5, Math.PI], label: 'Pots' },
  dispenser: { w: 0.38, d: 0.38, solid: true, group: 'kitchen', spot: [0, 0.45, Math.PI], label: 'Water dispenser' },
  dining4: { w: 1.5, d: 1.6, solid: true, label: 'Dining set' },
  dining6: { w: 2.1, d: 1.7, solid: true, label: 'Dining set' },
  kitchen_cab: { w: 1.2, d: 0.55, solid: true, group: 'kitchen', spot: [0, 0.6, Math.PI], label: 'Kitchen cabinet' },
  bucket_bowl: { w: 0.6, d: 0.45, solid: true, group: 'bath', spot: [0, 0.55, Math.PI], label: 'Bucket and bowl' },
  water_heater: { w: 0.45, d: 0.3, solid: false, label: 'Water heater', place: 'wall' },
  mirror_wall: { w: 0.6, d: 0.08, solid: false, label: 'Mirror', place: 'wall' },
  towel_rack: { w: 0.6, d: 0.3, solid: true, label: 'Towel rack' },
  washer: { w: 0.62, d: 0.62, solid: true, label: 'Washing machine' },
  gen_small: { w: 0.55, d: 0.4, solid: true, label: 'Small generator', place: 'out' },
  gen_big: { w: 1.8, d: 0.9, solid: true, label: 'Soundproof generator', place: 'out' },
  inverter: { w: 0.8, d: 0.5, solid: true, label: 'Inverter' },
  inverter_small: { w: 0.5, d: 0.4, solid: true, label: 'Inverter' },
  solar: { w: 2.0, d: 1.1, solid: true, label: 'Solar panels', place: 'out' },
  water_tank: { w: 1.2, d: 1.2, solid: true, label: 'Water tank', place: 'out' },
  gate_light: { w: 0.4, d: 0.4, solid: true, label: 'Floodlight', place: 'out' },
  car_shade: { w: 2.8, d: 4.2, solid: false, label: 'Car shade', place: 'out' },
  plant_big: { w: 0.6, d: 0.6, solid: true, label: 'Palm', place: 'any' },
  wall_art: { w: 0.9, d: 0.08, solid: false, label: 'Wall art', place: 'wall' },
  plaque: { w: 0.5, d: 0.1, solid: false, label: 'Bronze plaque', place: 'wall' },
  bronze_head: { w: 0.45, d: 0.45, solid: true, label: 'Bronze head' },
  wall_clock: { w: 0.4, d: 0.08, solid: false, label: 'Wall clock', place: 'wall' },
  photo_frame: { w: 0.5, d: 0.08, solid: false, label: 'Photo frame', place: 'wall' },
  aquarium: { w: 1.0, d: 0.42, solid: true, label: 'Aquarium' },
  vase: { w: 0.3, d: 0.3, solid: true, label: 'Flower vase' },
  // H1: the duplex staircase (built in; climbs along local -z to the upstairs that the cut-away hides)
  stairs: { w: 1.0, d: 2.6, solid: true, label: 'Staircase' },
};

/** Kinds that are part of the house (bathroom, shared compound things, wall units), unless an item is marked
 * `included` (H4: then the player owns it). Everything else is
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
  /** H1: built into this house (fitted kitchen counter, island, staircase): architecture. Stays when the
   * player's own furniture replaces the default set, can't be moved, and blocks solid pieces like FIXED_KINDS. */
  fixed?: boolean;
  /** H4: came with the house (ACs, ceiling fan, dining set, guest room ...): the catalogue furniture id the
   * player is given a real copy of when they move in (server: home_layouts.included, bl_house_items_grant).
   * Drawn here only until the player's own furniture loads; then the owned copy stands in its place and can be
   * moved, stored and sold like bought furniture. Never a fixture, even for FIXED_KINDS kinds (ac, generator). */
  included?: string;
}

/** H1: part of the house itself (FIXED_KINDS or a built-in piece), not the player's furniture. H4: pieces that
 * came with the house (`included`) are the player's furniture, not fixtures. */
export function isFixture(f: Pick<FurnitureItem, 'kind' | 'fixed' | 'included'>): boolean {
  if (f.included) return false;
  return Boolean(f.fixed) || FIXED_KINDS.has(f.kind);
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
  // ---- R8 house upgrades (see upgrades.ts applyUpgrades; absent on a plain layout)
  /** Extension rooms built onto the south wall (docs/HOUSE_UPGRADES.md). */
  rooms?: HomeRoom[];
  /** Yard buildings: boys' quarters, generator house, solar rack, borehole tank. */
  structs?: HomeStruct[];
  /** Finish level 0..3 (bare, fresh paint, POP + tiles, premium). */
  finish?: number;
  /** Security level 0..2 (compound wall, gate + CCTV). */
  security?: number;
  /** Builders at work: scaffolding drawn here. `at` = a spot with no fixed rect. */
  scaffold?: { rect?: [number, number, number, number]; at?: 'house' | 'parking' }[];
}

/** R8: a room added to the south side of the house (rect starts at z = house depth; door = gap in the shared wall). */
export interface HomeRoom {
  id: string;
  rect: [number, number, number, number];
  door: [number, number];
}

export type StructKind = 'bq' | 'genhouse' | 'solar' | 'borehole';

/** R8: a building in the yard (blocks walking and solid furniture). */
export interface HomeStruct {
  id: string;
  kind: StructKind;
  rect: [number, number, number, number];
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

  // H1 mid tier: mini-flat on Mission Road, 9.6 x 7.2 m. Bedroom (NW), kitchen (N), bathroom (NE),
  // parlour (SW) and a dining corner by the side door. Comes with a kitchen cabinet, a bedroom AC, a
  // ceiling fan and a dining set.
  flat: {
    id: 'flat',
    label: 'Mini-flat',
    w: 9.6,
    d: 7.2,
    lot: [0, 0, 11.4, 8.6],
    floor: { a: '#f2f0ec', b: '#e4e0d8', tile: 0.8 },
    patches: [
      [0, 0, 3.8, 3.2, '#efe6d6', '#e1d5c0', 0.5], // bedroom
      [3.8, 0, 6.8, 3.2, '#e9ece9', '#d9dedb', 0.4], // kitchen
      [6.8, 0, 9.6, 2.6, '#d4e4ea', '#c2d6de', 0.3], // bathroom
    ],
    wall: '#3b4350',
    wallInner: '#eef0f3',
    wallH: 2.7,
    partitions: [
      [3.8, 0, 3.8, 3.2], [0, 3.2, 2.8, 3.2], // bedroom (door to the parlour 2.8-3.8)
      [6.8, 0, 6.8, 2.6], [6.8, 2.6, 7.6, 2.6], [8.6, 2.6, 9.6, 2.6], // bathroom (door 7.6-8.6)
      [3.8, 3.2, 4.4, 3.2], // kitchen stub
    ],
    doors: [['e', 4.0, 5.2]],
    windows: [['n', 0.8, 2.6], ['n', 4.4, 5.6], ['w', 4.0, 6.4]],
    yard: { colour: '#7aa35a' },
    home: [6.2, 6.2, -Math.PI / 4],
    slots: { bed: [1.15, 1.25, 0], seat: [2.0, 6.7, 2], sofa: [3.4, 5.2, 3], tv: [0.3, 5.2, 1], ctable: [1.9, 5.2, 1], rug: [2.0, 5.2, 0], stove: [4.4, 0.35, 0], fridge: [4.25, 1.75, 1], wardrobe: [3.42, 1.6, 3], bath: [7.25, 1.9, 1] },
    furniture: [
      { id: 'toilet', kind: 'toilet', x: 7.25, z: 0.5 },
      { id: 'sink', kind: 'sink', x: 8.0, z: 0.3 },
      { id: 'shower', kind: 'shower', x: 9.05, z: 0.6 },
      { id: 'cab', kind: 'kitchen_cab', x: 6.12, z: 0.33, color: '#f4f1ea', included: 'kitchen_cabinet' },
      { id: 'ac', kind: 'ac', x: 1.2, z: 0.15, included: 'ac_split' },
      { id: 'cfan', kind: 'fan_ceiling', x: 2.2, z: 5.2, included: 'fan_ceiling' },
      { id: 'dining', kind: 'dining4', x: 7.6, z: 4.7, color: '#8a5a33', included: 'dining_4' },
      { id: 'gen', kind: 'generator', x: 10.6, z: 1.2, rot: 1 * Q, included: 'gen_firman' },
      // default set (replaced by the player's own furniture)
      { id: 'bed', kind: 'bed_double', x: 1.15, z: 1.25, color: '#5b3fa0' },
      { id: 'wardrobe', kind: 'wardrobe', x: 3.42, z: 1.6, rot: 3 * Q, color: '#8a5a33' },
      { id: 'stove', kind: 'gas_cooker', x: 4.4, z: 0.35 },
      { id: 'fridge', kind: 'fridge', x: 4.25, z: 1.75, rot: 1 * Q },
      { id: 'rug', kind: 'rug', x: 2.0, z: 5.2, color: '#b3332c' },
      { id: 'tv', kind: 'tv', x: 0.3, z: 5.2, rot: 1 * Q },
      { id: 'sofa', kind: 'sofa', x: 3.4, z: 5.2, rot: 3 * Q, color: '#7a1f2b', actorFor: ['media', 'seat'] },
      { id: 'arm', kind: 'armchair', x: 2.0, z: 6.7, rot: 2 * Q, color: '#7a1f2b' },
      { id: 'ctable', kind: 'centre_table', x: 1.9, z: 5.2, rot: 1 * Q },
      { id: 'plant', kind: 'plant', x: 5.6, z: 6.8 },
    ],
  },

  // H1 top tier: GRA duplex (ground floor), 14.4 x 10 m, by far the widest. Master bedroom (NW), fitted
  // kitchen with an island (N), bathroom with a tub, laundry + staircase (NE), a furnished guest bedroom
  // (SE), dining and a big parlour (S). Comes with the fitted kitchen, ACs, chandelier, ceiling fan,
  // water heater, the dining set and the guest room.
  duplex: {
    id: 'duplex',
    label: 'GRA duplex',
    w: 14.4,
    d: 10.0,
    // GRA compound: a pool deck in front, the paved parking bay by the gate (east), lawn round the house.
    lot: [-1, -0.5, 18.6, 14.6],
    floor: { a: '#f4f1ec', b: '#e8e3da', tile: 1.0 },
    patches: [
      [0, 0, 4.4, 3.8, '#c9a27a', '#bf976e', 0.4], // master bedroom (wood)
      [4.4, 0, 9.2, 3.6, '#e7e3dc', '#d8d2c8', 0.5], // kitchen
      [9.2, 0, 11.8, 3.0, '#dfe9ee', '#cfdde4', 0.4], // bathroom
      [11.8, 0, 14.4, 3.0, '#d9d6cf', '#cbc7bf', 0.4], // laundry
      [10.4, 5.4, 14.4, 10.0, '#c9a27a', '#bf976e', 0.4], // guest bedroom (wood)
    ],
    wall: '#2f3640',
    wallInner: '#f6f3ee',
    wallH: 2.9,
    partitions: [
      [4.4, 0, 4.4, 3.8], [0, 3.8, 3.2, 3.8], // master bedroom (door 3.2-4.4)
      [9.2, 0, 9.2, 3.0], [9.2, 3.0, 9.9, 3.0], [10.9, 3.0, 11.8, 3.0], // bathroom (door 9.9-10.9)
      [11.8, 0, 11.8, 3.0], [11.8, 3.0, 12.2, 3.0], // laundry + stairs (open 12.2-14.4)
      [10.4, 5.4, 14.4, 5.4], [10.4, 5.4, 10.4, 6.2], [10.4, 7.2, 10.4, 10.0], // guest bedroom (door 6.2-7.2)
      [7.2, 8.6, 7.2, 10.0], // parlour / dining divider
    ],
    doors: [['s', 5.4, 6.6], ['e', 3.6, 4.8]],
    windows: [['n', 0.8, 3.0], ['n', 5.6, 8.0], ['n', 10.0, 11.0], ['w', 5.0, 8.4], ['w', 1.0, 3.0]],
    yard: { colour: '#6fa052' },
    home: [6.0, 8.6, -Math.PI / 4],
    slots: { bed: [1.4, 1.35, 0], seat: [2.2, 9.2, 2], sofa: [3.7, 6.9, 3], tv: [0.3, 6.9, 1], ctable: [1.9, 6.9, 1], rug: [2.1, 6.9, 0], stove: [5.1, 0.35, 0], fridge: [4.85, 1.75, 1], wardrobe: [3.4, 0.35, 0], bath: [9.75, 2.2, 1] },
    furniture: [
      // bathroom
      { id: 'toilet', kind: 'toilet', x: 9.7, z: 0.5 },
      { id: 'sink', kind: 'sink', x: 10.6, z: 0.3 },
      { id: 'tub', kind: 'bathtub', x: 11.3, z: 1.2 },
      { id: 'heater', kind: 'water_heater', x: 10.3, z: 0.15, included: 'water_heater' },
      // fitted kitchen
      { id: 'kitchen', kind: 'kitchen', x: 6.75, z: 0.35, color: '#2f3640', fixed: true },
      { id: 'cab', kind: 'kitchen_cab', x: 8.5, z: 0.33, color: '#2f3640', included: 'kitchen_cabinet' },
      { id: 'island', kind: 'island', x: 6.9, z: 2.3, color: '#e9e4dc', fixed: true },
      // laundry + staircase
      { id: 'washer', kind: 'washer', x: 12.3, z: 0.4, included: 'washing_machine' },
      { id: 'stairs', kind: 'stairs', x: 13.8, z: 1.5, fixed: true },
      // master bedroom + parlour comfort
      { id: 'ac1', kind: 'ac', x: 1.4, z: 0.15, included: 'ac_split' },
      { id: 'ac2', kind: 'ac', x: 0.15, z: 5.2, rot: 1 * Q, included: 'ac_split' },
      { id: 'chand', kind: 'chandelier', x: 2.2, z: 6.9, included: 'chandelier' },
      { id: 'cfan', kind: 'fan_ceiling', x: 8.2, z: 6.4, included: 'fan_ceiling' },
      // dining (kept clear of the guest bedroom door at x 10.4, z 6.2-7.2: at x 8.8 it left a 0.27 m squeeze)
      { id: 'dining', kind: 'dining6', x: 8.2, z: 6.4, color: '#5b3a24', included: 'dining_6' },
      // guest bedroom (furnished)
      { id: 'gbed', kind: 'bed_double', x: 13.4, z: 7.6, rot: 3 * Q, color: '#e8dccb', included: 'bed_double' },
      { id: 'gside', kind: 'bedside', x: 13.9, z: 6.2, included: 'bedside' },
      { id: 'gward', kind: 'wardrobe_big', x: 11.5, z: 9.65, rot: 2 * Q, color: '#5b3a24', included: 'wardrobe_big' },
      // compound
      { id: 'gen', kind: 'generator', x: 16.6, z: 1.2, rot: 1 * Q, included: 'gen_firman' },
      { id: 'palm1', kind: 'plant_big', x: -0.5, z: 13.8, included: 'plant_palm' },
      { id: 'palm2', kind: 'plant_big', x: 17.9, z: 6.2, included: 'plant_palm' },
      // default set (replaced by the player's own furniture)
      { id: 'bed', kind: 'bed_king', x: 1.4, z: 1.35, color: '#efe9df' },
      { id: 'wardrobe', kind: 'wardrobe', x: 3.4, z: 0.35, color: '#5b3a24' },
      { id: 'stove', kind: 'gas_cooker', x: 5.1, z: 0.35 },
      { id: 'fridge', kind: 'fridge', x: 4.85, z: 1.75, rot: 1 * Q },
      { id: 'rug', kind: 'rug', x: 2.1, z: 6.9, color: '#d4b26a' },
      { id: 'tv', kind: 'tv_big', x: 0.3, z: 6.9, rot: 1 * Q },
      { id: 'sofa', kind: 'sofa_l', x: 3.7, z: 6.9, rot: 3 * Q, color: '#e6e0d6', actorFor: ['media', 'seat'] },
      { id: 'arm', kind: 'armchair', x: 2.2, z: 9.2, rot: 2 * Q, color: '#a0703c' },
      { id: 'ctable', kind: 'centre_table', x: 1.9, z: 6.9, rot: 1 * Q },
      { id: 'lamp2', kind: 'lamp', x: 0.35, z: 9.6 },
      { id: 'plant1', kind: 'plant', x: 6.9, z: 9.6 },
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
  /** B1: copies owned (plastic chairs, fans ...). Default 1. */
  qty?: number;
  /** B1: catalogue name (for the arrange list). */
  name?: string;
  /** H2: 'starter', 'buy' or (H4) 'came_with_house'. */
  source?: string;
  /** H4: how many copies came with a house (starter piece, a home's built-ins). They are the highest-numbered
   * copies (qty - houseQty + 1 .. qty) and sell for furniture.included_resale_pct. */
  houseQty?: number;
}

/** H4: copy n of a piece came with the house (the highest houseQty copies; see OwnedPiece.houseQty). */
export function cameWithHouse(p: Pick<OwnedPiece, 'qty' | 'houseQty'>, copy: number): boolean {
  const qty = Math.max(1, p.qty ?? 1);
  return copy > qty - Math.max(0, Math.min(qty, p.houseQty ?? 0));
}

export interface SavedHomePosition {
  x: number;
  z: number;
  rotation: number;
  /** B1: in the inventory (bought or stored), not in the room. */
  stored?: boolean;
  /** B1: the layout the position belongs to (null = legacy row, current home). */
  layout?: string | null;
}

/** B1: the placement key of copy n (1-based) of a furniture id: own_<id>, own_<id>-2, own_<id>-3 ... */
export function furnitureKey(id: string, copy = 1): string {
  return copy <= 1 ? `own_${id}` : `own_${id}-${copy}`;
}

/** B1: furniture id of a placement key (own_plastic_chair-3 -> plastic_chair). */
export function furnitureIdOfKey(key: string): string {
  return key.replace(/^own_/, '').replace(/-\d+$/, '');
}

const SEATS = new Set<string>(['sofa', 'sofa_l', 'armchair', 'sofa_2', 'sofa_lux', 'recliner']);

/**
 * The layout with the player's own furniture: the house's fixtures (FIXED_KINDS, `fixed`) stay, every other
 * piece (including H4 `included` pieces, which the player owns as real copies) is replaced by the owned pieces. `null` = the full default furnishing (dev page, before the
 * furniture loads). Same rule as the server's bl_furniture_materialize (B1):
 * - a copy with a saved row stands at the row, or is in the inventory when the row is `stored`;
 * - a copy without a row (starter furniture never moved) takes its slot's default spot when this
 *   layout has that slot and no earlier row-less piece took it; otherwise it waits in the inventory.
 * Rows saved for another layout (the player moved house) count as no row.
 */
export function furnishHome(base: HomeLayout, pieces: OwnedPiece[] | null, rows: Record<string, SavedHomePosition> = {}): HomeLayout {
  if (!pieces) return base;
  const fixtures = base.furniture.filter(isFixture);
  const used = new Set<string>();
  const own: FurnitureItem[] = [];
  // H4: pieces that came with the house go after the player's own, so a bought bed hosts sleep before the guest bed
  const later: FurnitureItem[] = [];
  for (const p of pieces) {
    if (!(p.kind in KINDS)) continue;
    const qty = Math.max(1, p.qty ?? 1);
    for (let copy = 1; copy <= qty; copy++) {
      const id = furnitureKey(p.id, copy);
      const row = rows[id] && (rows[id].layout == null || rows[id].layout === base.id) ? rows[id] : null;
      let at: [number, number, number] | null = null;
      if (row) {
        if (row.stored) continue;
        at = [row.x, row.z, ((row.rotation % 4) + 4) % 4];
      } else {
        const slot = base.slots[p.slot];
        if (copy > 1 || !slot || used.has(p.slot)) continue;
        used.add(p.slot);
        at = slot;
      }
      (copy > 1 && cameWithHouse(p, copy) ? later : own).push({
        id,
        kind: p.kind as FurnitureKind,
        x: at[0],
        z: at[1],
        rot: at[2],
        color: p.color ?? undefined,
        activities: p.activities,
        actorFor: SEATS.has(p.kind) ? ['media', 'seat'] : undefined,
      });
    }
  }
  return { ...base, furniture: [...fixtures, ...own, ...later] };
}

/** The layout with the player's own furniture at their default slots (no saved positions). */
export function furnishLayout(base: HomeLayout, pieces: OwnedPiece[] | null): HomeLayout {
  return furnishHome(base, pieces, {});
}

/** Apply the homeowner's saved furniture positions to the shared house layout. */
export function applyHomePositions(base: HomeLayout, positions: Record<string, SavedHomePosition>): HomeLayout {
  if (!Object.keys(positions).length) return base;
  let changed = false;
  const furniture = base.furniture.map((item) => {
    if (!item.id.startsWith('own_')) return item;
    const position = positions[item.id];
    if (!position || position.stored) return item;
    changed = true;
    return { ...item, x: position.x, z: position.z, rot: ((position.rotation % 4) + 4) % 4 };
  });
  return changed ? { ...base, furniture } : base;
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
