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
  // L1 lighting (docs/HUD_HOME.md "Lighting")
  | 'bulb_holder' | 'bulb_energy' | 'bulb_recharge' | 'ceiling_light' | 'tube_light' | 'led_strip' | 'table_lamp'
  | 'wall_light' | 'pendant_chandelier' | 'yard_lamp' | 'lamp_recharge' | 'lantern' | 'candle'
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
  /** L1: height of the surface on top (m): a table lamp, lantern or candle standing over this piece rests on it. */
  top?: number;
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
  stool: { w: 0.4, d: 0.4, solid: true, group: 'seat', spot: [0, 0.45, 0], seat: [0, 0.42, 0, 0], label: 'Stool', place: 'any', top: 0.42 },
  bench: { w: 1.4, d: 0.4, solid: true, group: 'seat', spot: [0, 0.5, 0], seat: [0, 0.45, 0, 0], label: 'Bench', place: 'any', top: 0.4 },
  table: { w: 0.9, d: 0.6, solid: true, label: 'Table', top: 0.75 },
  dining: { w: 1.4, d: 0.9, solid: true, label: 'Dining table', top: 0.76 },
  centre_table: { w: 1.0, d: 0.55, solid: true, label: 'Centre table', top: 0.44 },
  desk: { w: 1.0, d: 0.55, solid: true, label: 'Study desk', top: 0.76 },
  wardrobe: { w: 1.2, d: 0.6, solid: true, group: 'wardrobe', label: 'Wardrobe' },
  locker: { w: 0.6, d: 0.5, solid: true, group: 'wardrobe', label: 'Locker' },
  shelf: { w: 0.9, d: 0.35, solid: true, label: 'Shelf' },
  tv: { w: 1.2, d: 0.45, solid: true, group: 'media', label: 'TV' },
  tv_big: { w: 1.8, d: 0.45, solid: true, group: 'media', label: 'Big TV' },
  radio: { w: 0.45, d: 0.4, solid: true, group: 'media', label: 'Radio', place: 'any' },
  fan: { w: 0.45, d: 0.45, solid: true, label: 'Standing fan' },
  lamp: { w: 0.35, d: 0.35, solid: true, label: 'Standing lamp' },
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
  plastic_table: { w: 0.8, d: 0.8, solid: true, label: 'Plastic table', place: 'any', top: 0.72 },
  sofa_2: { w: 1.4, d: 0.85, solid: true, group: 'seat', spot: [0, 0.75, 0], seat: [0, 0.46, 0.06, 0], label: 'Loveseat' },
  sofa_lux: { w: 2.4, d: 0.95, solid: true, group: 'seat', spot: [0, 0.85, 0], seat: [0, 0.46, 0.08, 0], label: 'Luxury sofa' },
  recliner: { w: 0.95, d: 0.95, solid: true, group: 'seat', spot: [0, 0.8, 0], seat: [0, 0.46, 0.06, 0], label: 'Recliner' },
  centre_glass: { w: 1.2, d: 0.65, solid: true, label: 'Glass centre table', top: 0.45 },
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
  dressing: { w: 1.0, d: 0.45, solid: true, label: 'Dressing table', top: 0.75 },
  mirror_stand: { w: 0.5, d: 0.35, solid: true, label: 'Standing mirror' },
  bedside: { w: 0.45, d: 0.4, solid: true, label: 'Bedside table', top: 0.55 },
  lamp_small: { w: 0.3, d: 0.3, solid: false, label: 'Bedside lamp', place: 'any' },
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
  dining4: { w: 1.5, d: 1.6, solid: true, label: 'Dining set', top: 0.76 },
  dining6: { w: 2.1, d: 1.7, solid: true, label: 'Dining set', top: 0.76 },
  kitchen_cab: { w: 1.2, d: 0.55, solid: true, group: 'kitchen', spot: [0, 0.6, Math.PI], label: 'Kitchen cabinet', top: 0.91 },
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
  // L1 lighting. Sizes are copied into furniture.w/d by the lighting migration (20261105000100_lighting.sql).
  bulb_holder: { w: 0.3, d: 0.3, solid: false, label: 'Bulb holder' },
  bulb_energy: { w: 0.3, d: 0.3, solid: false, label: 'Energy-saving bulb' },
  bulb_recharge: { w: 0.3, d: 0.3, solid: false, label: 'Rechargeable bulb' },
  ceiling_light: { w: 0.6, d: 0.6, solid: false, label: 'Ceiling light' },
  tube_light: { w: 1.25, d: 0.16, solid: false, label: 'Tube light' },
  led_strip: { w: 2.0, d: 0.06, solid: false, label: 'LED strip', place: 'wall' },
  table_lamp: { w: 0.3, d: 0.3, solid: false, label: 'Table lamp', place: 'any' },
  wall_light: { w: 0.26, d: 0.14, solid: false, label: 'Wall light', place: 'wall' },
  pendant_chandelier: { w: 0.8, d: 0.8, solid: false, label: 'Pendant chandelier' },
  yard_lamp: { w: 0.3, d: 0.3, solid: true, label: 'Garden lamp', place: 'out' },
  lamp_recharge: { w: 0.22, d: 0.22, solid: false, label: 'Rechargeable lamp', place: 'any' },
  lantern: { w: 0.22, d: 0.22, solid: false, label: 'Lantern', place: 'any' },
  candle: { w: 0.12, d: 0.12, solid: false, label: 'Candle', place: 'any' },
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
  /** L1: the catalogue's brightness / warmth / works-without-power for this piece (furniture table, admin-editable);
   * absent = the defaults in LIGHTS. */
  light?: LightTune;
}

/** L1: what the server's furniture row says about a light (brightness 0-10, warmth in kelvin, works in a power cut). */
export interface LightTune {
  b?: number;
  k?: number;
  np?: boolean;
}

/** L1: how a light is mounted: where its glow sits and what it needs to stand on. */
export type LightMount = 'ceiling' | 'wall' | 'table' | 'floor' | 'yard';

export interface LightDef {
  mount: LightMount;
  /** ceiling: how far below the ceiling the glow hangs; wall: height above the floor; table/floor/yard: above the piece's base. */
  y: number;
  /** Local z offset of the glow (out from the wall for wall pieces). */
  fwd?: number;
  /** Default brightness 0..10 (the furniture row overrides it). */
  b: number;
  /** Default colour temperature in kelvin. */
  k: number;
  /** Works in a power cut (rechargeable lamp, candle, lantern). */
  np?: boolean;
}

/** L1: every kind that is a light fixture, with its mount and defaults. See docs/HUD_HOME.md "Lighting". */
export const LIGHTS: Partial<Record<FurnitureKind, LightDef>> = {
  bulb_holder: { mount: 'ceiling', y: 0.42, b: 3, k: 2700 },
  bulb_energy: { mount: 'ceiling', y: 0.48, b: 4, k: 4000 },
  bulb_recharge: { mount: 'ceiling', y: 0.46, b: 3, k: 5000, np: true },
  ceiling_light: { mount: 'ceiling', y: 0.16, b: 6, k: 3500 },
  tube_light: { mount: 'ceiling', y: 0.18, b: 6, k: 6000 },
  led_strip: { mount: 'wall', y: 2.3, fwd: 0.08, b: 3, k: 3000 },
  table_lamp: { mount: 'table', y: 0.4, b: 3, k: 2700 },
  lamp: { mount: 'floor', y: 1.32, b: 4, k: 2700 },
  lamp_small: { mount: 'table', y: 0.47, b: 2, k: 2700 },
  wall_light: { mount: 'wall', y: 1.9, fwd: 0.12, b: 3, k: 2700 },
  chandelier: { mount: 'ceiling', y: 0.95, b: 9, k: 2700 },
  pendant_chandelier: { mount: 'ceiling', y: 0.95, b: 7, k: 3000 },
  gate_light: { mount: 'yard', y: 2.62, fwd: 0.2, b: 7, k: 5500 },
  yard_lamp: { mount: 'yard', y: 1.65, b: 4, k: 3000 },
  lamp_recharge: { mount: 'table', y: 0.17, b: 4, k: 5000, np: true },
  lantern: { mount: 'table', y: 0.14, b: 2, k: 2200, np: true },
  candle: { mount: 'table', y: 0.1, b: 1, k: 1900, np: true },
};

export const isLight = (kind: string): boolean => kind in LIGHTS;

/** The glow point of a light fixture in layout space (x, y, z), from where it stands. */
export function lightPoint(f: Pick<FurnitureItem, 'kind' | 'x' | 'z' | 'y' | 'rot'>, wallH: number): [number, number, number] {
  const d = LIGHTS[f.kind]!;
  const yaw = ((f.rot ?? 0) * Math.PI) / 2;
  const fwd = d.fwd ?? 0;
  const x = f.x + Math.sin(yaw) * fwd;
  const z = f.z + Math.cos(yaw) * fwd;
  const y = d.mount === 'ceiling' ? wallH - d.y : d.mount === 'wall' ? d.y : (f.y ?? 0) + d.y;
  return [x, y, z];
}

/** Brightness, warmth and power rule of one light, from the piece's row over the defaults. */
export function lightTuneOf(f: Pick<FurnitureItem, 'kind' | 'light'>): { b: number; k: number; np: boolean } {
  const d = LIGHTS[f.kind]!;
  return { b: f.light?.b ?? d.b, k: f.light?.k ?? d.k, np: f.light?.np ?? Boolean(d.np) };
}

/**
 * Table lamps, lanterns and candles rest on whatever has a surface (KINDS[...].top) under them, else on the floor.
 * Returns the same array when nothing changes.
 */
export function liftLights(list: FurnitureItem[]): FurnitureItem[] {
  let out: FurnitureItem[] | null = null;
  list.forEach((f, i) => {
    const d = LIGHTS[f.kind];
    if (!d || d.mount !== 'table' || f.y !== undefined) return;
    let top = 0;
    for (const o of list) {
      const t = KINDS[o.kind]?.top;
      if (!t || o === f || t <= top) continue;
      const k = KINDS[o.kind];
      const q = (((o.rot ?? 0) % 4) + 4) % 4;
      const w = q % 2 ? k.d : k.w;
      const dd = q % 2 ? k.w : k.d;
      if (Math.abs(f.x - o.x) <= w / 2 && Math.abs(f.z - o.z) <= dd / 2) top = t;
    }
    if (top > 0) {
      out ??= list.slice();
      out[i] = { ...f, y: top };
    }
  });
  return out ?? list;
}

/**
 * Catalogue ids the lighting migration gives with a home (home_layouts.lights, `bl_house_lights_grant`), as opposed to
 * `included` (bl_house_items_grant). Every lighting id except the crystal chandelier, which was already a duplex built-in.
 */
export const LIGHT_BUILTIN_IDS: ReadonlySet<string> = new Set([
  'bulb_holder', 'bulb_energy', 'bulb_rechargeable', 'ceiling_light', 'tube_light', 'led_strip', 'table_lamp',
  'lamp_floor', 'lamp_bedside', 'wall_light', 'chandelier_modern', 'gate_light', 'yard_lamp',
  'lamp_rechargeable', 'lantern', 'candle',
]);

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

// Home sizes (docs/HUD_HOME.md "Home sizes"): every tier is roomy and each is clearly bigger than the one below.
//   hostel 6.2 x 5.0, face-me 6.8 x 5.6 (LAPO start), self-contain 9.0 x 6.8, mini-flat 13.0 x 9.4, duplex 19.0 x 13.4.
// Rules the plans follow: 0.8 m or more between big pieces, 1.1+ m doorways, the north / west walls stay free for
// wall pieces, the compound (lot) keeps the same margins as before, and every default slot is valid for the starter
// sets (scripts/home-space-check.mjs checks all of it, and home_layouts in SQL is generated from this file).
export const LAYOUTS: Record<HomeLayoutId, HomeLayout> = {
  // UNIBEN hostel: a shared room with bunks, desks and lockers; bathroom stalls down the corridor.
  hostel: {
    id: 'hostel',
    label: 'UNIBEN hostel room',
    w: 6.2,
    d: 5.0,
    lot: [0, 0, 9.0, 6.6],
    floor: { a: '#a9b4ad', b: '#9da9a2', tile: 0.6 },
    wall: '#5a6b7a',
    wallInner: '#d9e4ec',
    wallH: 2.5,
    partitions: [],
    doors: [['e', 3.5, 4.6]],
    windows: [['n', 1.4, 3.2], ['n', 4.3, 5.5], ['w', 1.4, 3.2], ['w', 3.8, 4.8]],
    yard: { colour: '#c98a5e' },
    home: [4.2, 3.4, -Math.PI / 4],
    slots: { bed: [0.75, 1.2, 0], seat: [4.3, 4.1, 0], sofa: [2.9, 3.5, 3], tv: [0.3, 3.5, 1], rug: [1.7, 3.5, 0], ctable: [1.55, 3.5, 1], stove: [4.2, 0.4, 0], fridge: [5.5, 0.45, 0], wardrobe: [2.7, 0.35, 0], bath: [7.6, 3.8, 3] },
    furniture: [
      { id: 'bunk1', kind: 'bunk', x: 0.65, z: 1.2, color: '#2f6fb3' },
      { id: 'bunk2', kind: 'bunk', x: 2.5, z: 1.2, color: '#b33f3f' },
      { id: 'locker1', kind: 'locker', x: 4.1, z: 0.35 },
      { id: 'locker2', kind: 'locker', x: 4.75, z: 0.35 },
      { id: 'desk1', kind: 'desk', x: 0.65, z: 4.4, rot: 2 * Q },
      { id: 'chair1', kind: 'plastic_chair', x: 0.65, z: 3.65, color: '#e8e4dc' },
      { id: 'radio', kind: 'radio', x: 1.0, z: 4.42, y: 0.75, rot: 2 * Q },
      { id: 'desk2', kind: 'desk', x: 5.75, z: 2.0, rot: 3 * Q },
      { id: 'chair2', kind: 'plastic_chair', x: 5.05, z: 2.0, rot: 1 * Q, color: '#3e8f5a', actorFor: ['media', 'seat'] },
      { id: 'hotplate', kind: 'hotplate', x: 5.6, z: 0.4 },
      { id: 'fan', kind: 'fan', x: 3.3, z: 2.9 },
      { id: 'bucket', kind: 'bucket_bath', x: 7.6, z: 1.1, rot: 3 * Q },
      { id: 'toilet', kind: 'pit_toilet', x: 7.6, z: 2.45, rot: 3 * Q },
      { id: 'drum', kind: 'drum', x: 7.6, z: 5.4 },
      // L1 built-in light (bl_house_lights_grant): a bulb in the room
      { id: 'lt_room', kind: 'bulb_holder', x: 3.1, z: 2.1, included: 'bulb_holder' },
    ],
  },

  // Face-me-I-face-you single room (the LAPO start home): a medium, roomy room; the bathroom, toilet and
  // generator are shared in the compound.
  face_me: {
    id: 'face_me',
    label: 'Face-me-I-face-you room',
    w: 6.8,
    d: 5.6,
    lot: [0, 0, 9.8, 7.2],
    floor: { a: '#9e9a92', b: '#97938b', tile: 1.2 },
    wall: '#6b5e4e',
    wallInner: '#cfe3cf',
    wallH: 2.5,
    partitions: [],
    doors: [['e', 3.9, 5.0]],
    windows: [['n', 1.5, 3.1], ['n', 4.4, 5.8], ['w', 4.3, 5.2]],
    yard: { colour: '#bf7a4c', fence: true },
    home: [4.3, 3.0, -Math.PI / 4],
    slots: { bed: [0.85, 1.2, 0], seat: [4.6, 4.45, 0], sofa: [2.9, 3.6, 3], tv: [0.3, 3.6, 1], rug: [1.9, 3.6, 0], ctable: [1.6, 3.6, 1], stove: [5.25, 0.4, 0], fridge: [6.4, 0.45, 0], wardrobe: [3.0, 0.35, 0], bath: [8.5, 3.6, 3] },
    furniture: [
      { id: 'rug', kind: 'rug', x: 1.9, z: 3.6, color: '#9c3b33' },
      { id: 'bed', kind: 'bed_double', x: 0.85, z: 1.2, color: '#6d4aa0' },
      { id: 'wardrobe', kind: 'wardrobe', x: 3.0, z: 0.35, color: '#8a5a33' },
      { id: 'fan', kind: 'fan', x: 4.3, z: 0.55 },
      { id: 'table', kind: 'table', x: 4.6, z: 5.15 },
      { id: 'radio', kind: 'radio', x: 4.6, z: 5.15, y: 0.75 },
      { id: 'chair', kind: 'plastic_chair', x: 4.6, z: 4.45, color: '#e8e4dc', actorFor: ['media', 'seat'] },
      { id: 'stove', kind: 'kerosene_stove', x: 5.25, z: 0.45 },
      { id: 'bucket', kind: 'bucket_bath', x: 8.4, z: 0.95, rot: 3 * Q },
      { id: 'toilet', kind: 'pit_toilet', x: 8.4, z: 2.2, rot: 3 * Q },
      { id: 'gen', kind: 'generator', x: 8.0, z: 6.5 },
      { id: 'drum', kind: 'drum', x: 9.2, z: 6.4 },
      { id: 'line', kind: 'clothesline', x: 7.2, z: 0.9, rot: 1 * Q },
      // L1 built-in light
      { id: 'lt_room', kind: 'bulb_holder', x: 3.4, z: 2.6, included: 'bulb_holder' },
    ],
  },

  // Self-contain in Uselu: a bathroom corner, kitchen row, sleeping corner and a proper sitting area.
  self_contain: {
    id: 'self_contain',
    label: 'Self-contain',
    w: 9.0,
    d: 6.8,
    lot: [0, 0, 11.4, 8.4],
    floor: { a: '#e9e1d2', b: '#ddd3c1', tile: 0.6 },
    patches: [[0, 0, 2.6, 2.6, '#cfe0e6', '#bdd2d9', 0.3]],
    wall: '#4f5d6b',
    wallInner: '#f1ead9',
    wallH: 2.6,
    partitions: [[2.6, 0, 2.6, 1.7], [0, 2.6, 1.4, 2.6]],
    doors: [['e', 4.9, 6.0]],
    windows: [['n', 0.7, 1.9], ['n', 3.4, 5.6], ['n', 6.8, 8.4], ['w', 2.9, 4.1], ['w', 5.9, 6.5]],
    yard: { colour: '#c4875a' },
    home: [4.4, 3.2, -Math.PI / 4],
    slots: { bed: [7.95, 1.6, 3], seat: [4.8, 3.55, 0], sofa: [3.0, 4.9, 3], tv: [0.3, 4.9, 1], ctable: [1.65, 4.9, 1], rug: [1.8, 4.9, 0], stove: [3.7, 0.4, 0], fridge: [5.0, 0.45, 0], wardrobe: [8.7, 3.7, 3], bath: [10.2, 2.4, 0] },
    furniture: [
      { id: 'toilet', kind: 'toilet', x: 0.5, z: 0.55 },
      { id: 'shower', kind: 'shower', x: 1.9, z: 0.75 },
      { id: 'sink', kind: 'sink', x: 0.3, z: 1.8, rot: 1 * Q },
      { id: 'kitchen', kind: 'kitchen', x: 4.7, z: 0.35, color: '#f4f1ea' },
      { id: 'gas', kind: 'gas', x: 3.3, z: 0.3 },
      { id: 'bed', kind: 'bed_double', x: 7.95, z: 1.6, rot: 3 * Q, color: '#2e7d6b' },
      { id: 'wardrobe', kind: 'wardrobe', x: 8.7, z: 3.7, rot: 3 * Q, color: '#7b4f2e' },
      { id: 'tv', kind: 'tv', x: 0.3, z: 4.9, rot: 1 * Q },
      { id: 'rug', kind: 'rug', x: 1.8, z: 4.9, color: '#9c3b33' },
      { id: 'sofa', kind: 'sofa', x: 3.0, z: 4.9, rot: 3 * Q, color: '#b0473c', actorFor: ['media', 'seat'] },
      { id: 'ctable', kind: 'centre_table', x: 1.65, z: 4.9, rot: 1 * Q },
      { id: 'fan', kind: 'fan', x: 6.0, z: 3.4 },
      { id: 'gen', kind: 'generator', x: 10.2, z: 0.9, rot: 1 * Q },
      { id: 'plant', kind: 'plant', x: 10.6, z: 7.4 },
      // L1 built-in lights: a bulb in each room, a brighter bulb over the sitting area
      { id: 'lt_bath', kind: 'bulb_holder', x: 1.3, z: 1.3, included: 'bulb_holder' },
      { id: 'lt_kitchen', kind: 'bulb_holder', x: 4.8, z: 1.4, included: 'bulb_holder' },
      { id: 'lt_bed', kind: 'bulb_holder', x: 7.0, z: 2.6, included: 'bulb_holder' },
      { id: 'lt_sit', kind: 'bulb_energy', x: 3.0, z: 5.0, included: 'bulb_energy' },
    ],
  },

  // H1 mid tier: mini-flat on Mission Road, 13 x 9.4 m. Bedroom (NW), kitchen (N), bathroom (NE),
  // parlour (SW) and a dining corner by the side door. Comes with a kitchen cabinet, a bedroom AC, a
  // ceiling fan and a dining set.
  flat: {
    id: 'flat',
    label: 'Mini-flat',
    w: 13.0,
    d: 9.4,
    lot: [0, 0, 15.2, 11.0],
    floor: { a: '#f2f0ec', b: '#e4e0d8', tile: 0.8 },
    patches: [
      [0, 0, 5.0, 4.2, '#efe6d6', '#e1d5c0', 0.5], // bedroom
      [5.0, 0, 9.2, 3.6, '#e9ece9', '#d9dedb', 0.4], // kitchen
      [9.2, 0, 13.0, 3.2, '#d4e4ea', '#c2d6de', 0.3], // bathroom
    ],
    wall: '#3b4350',
    wallInner: '#eef0f3',
    wallH: 2.7,
    partitions: [
      [5.0, 0, 5.0, 4.2], [0, 4.2, 3.6, 4.2], // bedroom (door to the parlour 3.6-5.0)
      [9.2, 0, 9.2, 3.2], [9.2, 3.2, 10.3, 3.2], [11.5, 3.2, 13.0, 3.2], // bathroom (door 10.3-11.5)
      [5.0, 4.2, 5.9, 4.2], // kitchen stub
    ],
    doors: [['e', 5.0, 6.2]],
    windows: [['n', 2.4, 4.2], ['n', 6.0, 8.4], ['w', 1.4, 3.0], ['w', 5.4, 8.2]],
    yard: { colour: '#7aa35a' },
    home: [7.0, 7.2, -Math.PI / 4],
    slots: { bed: [1.35, 1.35, 0], seat: [2.3, 8.5, 2], sofa: [3.6, 6.6, 3], tv: [0.3, 6.6, 1], ctable: [1.8, 6.6, 1], rug: [2.0, 6.6, 0], stove: [5.9, 0.4, 0], fridge: [5.45, 1.9, 1], wardrobe: [4.62, 1.8, 3], bath: [9.8, 2.2, 1] },
    furniture: [
      { id: 'toilet', kind: 'toilet', x: 9.85, z: 0.55 },
      { id: 'sink', kind: 'sink', x: 10.95, z: 0.3 },
      { id: 'shower', kind: 'shower', x: 12.0, z: 0.65 },
      { id: 'cab', kind: 'kitchen_cab', x: 7.4, z: 0.33, color: '#f4f1ea', included: 'kitchen_cabinet' },
      { id: 'ac', kind: 'ac', x: 1.4, z: 0.15, included: 'ac_split' },
      { id: 'cfan', kind: 'fan_ceiling', x: 2.0, z: 6.6, included: 'fan_ceiling' },
      { id: 'dining', kind: 'dining4', x: 9.9, z: 6.4, color: '#8a5a33', included: 'dining_4' },
      { id: 'gen', kind: 'generator', x: 14.2, z: 1.4, rot: 1 * Q, included: 'gen_firman' },
      // L1 built-in lights: ceiling lights, a tube in the kitchen, a chandelier in the parlour, wall lights, a yard floodlight
      { id: 'lt_bed', kind: 'ceiling_light', x: 2.5, z: 2.2, included: 'ceiling_light' },
      { id: 'lt_kitchen', kind: 'tube_light', x: 7.1, z: 1.7, included: 'tube_light' },
      { id: 'lt_bath', kind: 'bulb_holder', x: 11.1, z: 1.6, included: 'bulb_holder' },
      { id: 'lt_parlour', kind: 'pendant_chandelier', x: 4.9, z: 6.9, included: 'chandelier_modern' },
      { id: 'lt_dining', kind: 'ceiling_light', x: 10.4, z: 6.8, included: 'ceiling_light' },
      { id: 'lt_wall1', kind: 'wall_light', x: 0.1, z: 5.0, rot: 1 * Q, included: 'wall_light' },
      { id: 'lt_wall2', kind: 'wall_light', x: 0.1, z: 8.8, rot: 1 * Q, included: 'wall_light' },
      { id: 'lt_gate', kind: 'gate_light', x: 14.6, z: 10.3, included: 'gate_light' },
      // default set (replaced by the player's own furniture)
      { id: 'bed', kind: 'bed_double', x: 1.35, z: 1.35, color: '#5b3fa0' },
      { id: 'wardrobe', kind: 'wardrobe', x: 4.62, z: 1.8, rot: 3 * Q, color: '#8a5a33' },
      { id: 'stove', kind: 'gas_cooker', x: 5.9, z: 0.4 },
      { id: 'fridge', kind: 'fridge', x: 5.45, z: 1.9, rot: 1 * Q },
      { id: 'rug', kind: 'rug', x: 2.0, z: 6.6, color: '#b3332c' },
      { id: 'tv', kind: 'tv', x: 0.3, z: 6.6, rot: 1 * Q },
      { id: 'sofa', kind: 'sofa', x: 3.6, z: 6.6, rot: 3 * Q, color: '#7a1f2b', actorFor: ['media', 'seat'] },
      { id: 'arm', kind: 'armchair', x: 2.3, z: 8.5, rot: 2 * Q, color: '#7a1f2b' },
      { id: 'ctable', kind: 'centre_table', x: 1.8, z: 6.6, rot: 1 * Q },
      { id: 'plant', kind: 'plant', x: 7.2, z: 8.7 },
    ],
  },

  // H1 top tier: GRA duplex (ground floor), 19 x 13.4 m, by far the widest. Master bedroom (NW), fitted
  // kitchen with an island (N), bathroom with a tub, laundry + staircase (NE), a wide hall and entrance lobby,
  // a study, a furnished guest bedroom (SE), dining and a big parlour (S). Comes with the fitted kitchen, ACs,
  // chandelier, ceiling fan, water heater, the dining set and the guest room.
  duplex: {
    id: 'duplex',
    label: 'GRA duplex',
    w: 19.0,
    d: 13.4,
    // GRA compound: a pool deck in front, the paved parking bay by the gate (east), lawn round the house.
    lot: [-1, -0.5, 23.2, 18.0],
    floor: { a: '#f4f1ec', b: '#e8e3da', tile: 1.0 },
    patches: [
      [0, 0, 6.0, 5.0, '#c9a27a', '#bf976e', 0.4], // master bedroom (wood)
      [6.0, 0, 12.2, 4.2, '#e7e3dc', '#d8d2c8', 0.5], // kitchen
      [12.2, 0, 15.4, 3.6, '#dfe9ee', '#cfdde4', 0.4], // bathroom
      [15.4, 0, 19.0, 3.6, '#d9d6cf', '#cbc7bf', 0.4], // laundry
      [15.2, 6.6, 19.0, 9.8, '#d3b48c', '#c9a97f', 0.4], // study (wood)
      [13.6, 9.8, 19.0, 13.4, '#c9a27a', '#bf976e', 0.4], // guest bedroom (wood)
    ],
    wall: '#2f3640',
    wallInner: '#f6f3ee',
    wallH: 2.9,
    partitions: [
      [6.0, 0, 6.0, 5.0], [0, 5.0, 4.4, 5.0], // master bedroom (door 4.4-6.0)
      [12.2, 0, 12.2, 3.6], [12.2, 3.6, 13.4, 3.6], [14.6, 3.6, 15.4, 3.6], // bathroom (door 13.4-14.6)
      [15.4, 0, 15.4, 3.6], [15.4, 3.6, 16.0, 3.6], // laundry + stairs (open 16.0-19.0)
      [15.2, 6.6, 19.0, 6.6], [15.2, 6.6, 15.2, 7.4], [15.2, 8.6, 15.2, 9.8], // study (door 7.4-8.6)
      [13.6, 9.8, 19.0, 9.8], [13.6, 9.8, 13.6, 10.8], [13.6, 12.0, 13.6, 13.4], // guest bedroom (door 10.8-12.0)
      [9.6, 10.8, 9.6, 13.4], // parlour / dining divider
    ],
    doors: [['s', 7.0, 8.4], ['e', 4.6, 5.9]],
    windows: [['n', 1.0, 4.2], ['n', 7.8, 10.4], ['n', 13.0, 14.6], ['n', 16.2, 18.0], ['w', 6.6, 11.4], ['w', 1.2, 3.8]],
    yard: { colour: '#6fa052' },
    home: [7.2, 6.6, -Math.PI / 4],
    slots: { bed: [1.6, 1.5, 0], seat: [2.4, 11.9, 2], sofa: [4.2, 9.4, 3], tv: [0.3, 9.4, 1], ctable: [2.1, 9.4, 1], rug: [2.3, 9.4, 0], stove: [6.9, 0.4, 0], fridge: [6.4, 2.0, 1], wardrobe: [4.0, 0.35, 0], bath: [13.2, 2.4, 1] },
    furniture: [
      // bathroom
      { id: 'toilet', kind: 'toilet', x: 12.75, z: 0.55 },
      { id: 'sink', kind: 'sink', x: 13.75, z: 0.3 },
      { id: 'tub', kind: 'bathtub', x: 14.85, z: 1.3 },
      { id: 'heater', kind: 'water_heater', x: 14.5, z: 0.15, included: 'water_heater' },
      // fitted kitchen
      { id: 'kitchen', kind: 'kitchen', x: 9.0, z: 0.35, color: '#2f3640', fixed: true },
      { id: 'cab', kind: 'kitchen_cab', x: 11.2, z: 0.33, color: '#2f3640', included: 'kitchen_cabinet' },
      { id: 'island', kind: 'island', x: 9.0, z: 2.5, color: '#e9e4dc', fixed: true },
      // laundry + staircase
      { id: 'washer', kind: 'washer', x: 16.0, z: 0.45, included: 'washing_machine' },
      { id: 'stairs', kind: 'stairs', x: 18.45, z: 1.6, fixed: true },
      // master bedroom + parlour comfort
      { id: 'ac1', kind: 'ac', x: 1.6, z: 0.15, included: 'ac_split' },
      { id: 'ac2', kind: 'ac', x: 0.15, z: 7.6, rot: 1 * Q, included: 'ac_split' },
      { id: 'chand', kind: 'chandelier', x: 2.3, z: 9.4, included: 'chandelier' },
      { id: 'cfan', kind: 'fan_ceiling', x: 11.4, z: 8.8, included: 'fan_ceiling' },
      // dining (kept clear of the study and guest bedroom doors)
      { id: 'dining', kind: 'dining6', x: 11.4, z: 8.8, color: '#5b3a24', included: 'dining_6' },
      // guest bedroom (furnished)
      { id: 'gbed', kind: 'bed_double', x: 18.0, z: 11.6, rot: 3 * Q, color: '#e8dccb', included: 'bed_double' },
      { id: 'gside', kind: 'bedside', x: 18.5, z: 10.4, included: 'bedside' },
      { id: 'gward', kind: 'wardrobe_big', x: 15.1, z: 13.05, rot: 2 * Q, color: '#5b3a24', included: 'wardrobe_big' },
      // compound
      { id: 'gen', kind: 'generator', x: 21.2, z: 1.2, rot: 1 * Q, included: 'gen_firman' },
      { id: 'palm1', kind: 'plant_big', x: -0.5, z: 17.2, included: 'plant_palm' },
      { id: 'palm2', kind: 'plant_big', x: 22.6, z: 5.2, included: 'plant_palm' },
      // L1 built-in lights: a light in every room, wall lights, an LED strip, garden lamps and a gate floodlight
      { id: 'lt_master', kind: 'ceiling_light', x: 3.0, z: 2.5, included: 'ceiling_light' },
      { id: 'lt_mwall', kind: 'wall_light', x: 0.1, z: 3.3, rot: 1 * Q, included: 'wall_light' },
      { id: 'lt_mstrip', kind: 'led_strip', x: 3.2, z: 0.05, included: 'led_strip' },
      { id: 'lt_kit1', kind: 'tube_light', x: 8.0, z: 2.2, included: 'tube_light' },
      { id: 'lt_kit2', kind: 'tube_light', x: 10.4, z: 2.2, included: 'tube_light' },
      { id: 'lt_bath', kind: 'bulb_energy', x: 13.8, z: 1.8, included: 'bulb_energy' },
      { id: 'lt_laundry', kind: 'bulb_holder', x: 17.2, z: 1.8, included: 'bulb_holder' },
      { id: 'lt_study', kind: 'ceiling_light', x: 17.1, z: 8.2, included: 'ceiling_light' },
      { id: 'lt_parlour', kind: 'ceiling_light', x: 6.6, z: 8.0, included: 'ceiling_light' },
      { id: 'lt_pwall1', kind: 'wall_light', x: 0.1, z: 8.6, rot: 1 * Q, included: 'wall_light' },
      { id: 'lt_pwall2', kind: 'wall_light', x: 0.1, z: 11.4, rot: 1 * Q, included: 'wall_light' },
      { id: 'lt_standing', kind: 'lamp', x: 0.45, z: 12.9, included: 'lamp_floor' },
      { id: 'lt_hall', kind: 'pendant_chandelier', x: 8.0, z: 6.4, included: 'chandelier_modern' },
      { id: 'lt_lobby', kind: 'ceiling_light', x: 7.7, z: 12.0, included: 'ceiling_light' },
      { id: 'lt_dining', kind: 'ceiling_light', x: 11.4, z: 11.4, included: 'ceiling_light' },
      { id: 'lt_guest', kind: 'ceiling_light', x: 16.3, z: 11.6, included: 'ceiling_light' },
      { id: 'lt_gbed', kind: 'lamp_small', x: 18.5, z: 10.4, included: 'lamp_bedside' },
      { id: 'lt_gate', kind: 'gate_light', x: 20.8, z: 4.2, included: 'gate_light' },
      { id: 'lt_yard1', kind: 'yard_lamp', x: -0.6, z: 14.8, included: 'yard_lamp' },
      { id: 'lt_yard2', kind: 'yard_lamp', x: 12.0, z: 15.2, included: 'yard_lamp' },
      // default set (replaced by the player's own furniture)
      { id: 'bed', kind: 'bed_king', x: 1.6, z: 1.5, color: '#efe9df' },
      { id: 'wardrobe', kind: 'wardrobe', x: 4.0, z: 0.35, color: '#5b3a24' },
      { id: 'stove', kind: 'gas_cooker', x: 6.9, z: 0.4 },
      { id: 'fridge', kind: 'fridge', x: 6.4, z: 2.0, rot: 1 * Q },
      { id: 'rug', kind: 'rug', x: 2.3, z: 9.4, color: '#d4b26a' },
      { id: 'tv', kind: 'tv_big', x: 0.3, z: 9.4, rot: 1 * Q },
      { id: 'sofa', kind: 'sofa_l', x: 4.2, z: 9.4, rot: 3 * Q, color: '#e6e0d6', actorFor: ['media', 'seat'] },
      { id: 'arm', kind: 'armchair', x: 2.4, z: 11.9, rot: 2 * Q, color: '#a0703c' },
      { id: 'ctable', kind: 'centre_table', x: 2.1, z: 9.4, rot: 1 * Q },
      { id: 'lamp2', kind: 'lamp', x: 0.35, z: 12.9 },
      { id: 'plant1', kind: 'plant', x: 8.9, z: 12.8 },
      { id: 'desk', kind: 'desk', x: 18.45, z: 7.0, rot: 2 * Q },
      { id: 'deskchair', kind: 'plastic_chair', x: 18.45, z: 7.6, rot: 2 * Q, color: '#e8e4dc' },
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
  /** L1: the catalogue row's light values (brightness / warmth / works without power); lights only. */
  light?: LightTune;
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
        light: p.light,
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
