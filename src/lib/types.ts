// Shared types — Phase 0 contract. Owners may append their own section at the bottom.

export type Gender = 'male' | 'female';

export interface AvatarConfig {
  gender: Gender;
  skin: string; // skin tone id from AVATAR_OPTIONS.skin
  body: 'slim' | 'average' | 'thick';
  hair: string;
  hairColor: string; // hex
  eyes: string;
  brows: string;
  mouth: string;
  facialHair: string; // 'none' allowed
  outfit: string;
  outfitColor: string; // hex — primary fabric colour
  accessories: string[]; // e.g. ['coral_beads', 'gold_chain']
}

export type SceneType =
  | 'market' | 'hospital' | 'campus' | 'palace' | 'museum' | 'club' | 'bank' | 'police'
  | 'motorpark' | 'street' | 'pos'
  | 'home_face_me' | 'home_flat' | 'home_duplex' | 'farm' | 'airport' | 'shrine'
  | 'workshop' | 'buka' | 'salon' | 'cyber' | 'office';

export type PanelId =
  | 'activities' | 'jobs' | 'shop' | 'market_p2p' | 'housing' | 'inventory'
  | 'bank' | 'pos' | 'loans' | 'esusu' | 'farm' | 'hospital' | 'babalawo'
  | 'police' | 'rob' | 'crimes'
  | 'chat' | 'messages' | 'profile'
  | 'wallet' | 'airport';

export interface Location {
  id: string;
  name: string;
  district: string;
  scene: SceneType;
  blurb: string;
  risk: number;
  night_risk_mult: number;
  cctv: boolean;
  keke_ok: boolean;
  congestion: number;
  remote_km: number;
  x: number;
  y: number;
  actions: PanelId[];
  sort: number;
}

export interface Profile {
  id: string;
  username: string;
  gender: Gender;
  avatar: AvatarConfig;
  is_admin: boolean;
  cash: number;
  bank: number;
  hunger: number;
  energy: number;
  hygiene: number;
  fun: number;
  social: number;
  health: number;
  stress: number;
  location_id: string;
  home_location_id: string;
  housing_id: string;
  job_id: string | null;
  job_level: number;
  job_xp: number;
  street_cred: number;
  wanted: number;
  busy_until: string | null;
  busy_label: string | null;
  jailed_until: string | null;
  jail_reason: string | null;
  hospitalized_until: string | null;
  protected_until: string | null;
  charm_strength: number;
  charm_until: string | null;
  created_at: string;
}

export interface GameClock {
  game_minutes: number; // total game minutes since epoch
  day: number; // game day number (1-based)
  hour: number; // 0-23
  minute: number; // 0-59
  is_night: boolean;
}

export interface TravelState {
  to: string;
  mode: TravelMode;
  started_at: string;
  arrives_at: string;
}

export type TravelMode = 'walk' | 'keke' | 'bus' | 'drop' | 'car';

export interface GameState {
  profile: Profile;
  clock: GameClock;
  location: Location;
  travel: TravelState | null;
  server_time: string; // ISO; use to correct client clock skew
}

export interface TravelOption {
  mode: TravelMode;
  label: string;
  allowed: boolean;
  reason?: string;
  cost: number;
  game_minutes: number;
  real_seconds: number;
  risk_pct: number;
}

export interface TravelQuote {
  dest: string;
  km: number;
  options: TravelOption[];
}

export interface PublicPlayer {
  id: string;
  username: string;
  avatar: AvatarConfig;
  street_cred: number;
  last_seen: string;
}

export interface GameEvent {
  id: number;
  user_id: string;
  kind: string;
  title: string;
  body: string;
  data: Record<string, unknown>;
  read: boolean;
  created_at: string;
}

export type ConfigKind = 'percent' | 'number' | 'naira' | 'minutes' | 'bool' | 'text';

export interface ConfigRow {
  key: string;
  value: unknown;
  category: string;
  label: string;
  description: string;
  kind: ConfigKind;
  min: number | null;
  max: number | null;
  updated_at: string;
}

export interface PanelProps {
  state: GameState;
  location: Location;
  refresh: () => Promise<void>;
  close: () => void;
  params?: Record<string, unknown>;
}

// ---- Owner sections below (append only) ----
