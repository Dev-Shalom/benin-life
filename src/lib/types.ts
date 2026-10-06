// Shared types — Phase 0 contract. Owners may append their own section at the bottom.

export type Gender = 'male' | 'female';

export type BodyType = 'slim' | 'average' | 'thick';
export type FabricId = 'plain' | 'ankara' | 'adire' | 'asooke' | 'lace';

/** One piece of clothing: style id, fabric and main colour (hex). */
export interface AvatarGarment {
  s: string;
  f: FabricId;
  c: string;
}

/**
 * 3D avatar look (R2). Stored by the server as opaque jsonb (< 4000 chars), so keep it flat and small.
 * Old saved looks (v1, the 2D SVG avatar) are upgraded on read by `migrateAvatar` in src/art/avatar3d.
 * `gender` stays a top-level key: the server's update_avatar() reads it.
 */
export interface AvatarConfigV2 {
  v: 2;
  gender: Gender;
  body: BodyType;
  skin: string; // skin tone id, e.g. 'tone4'
  face: string; // face shape: round | oval | square | long | heart | diamond
  eyes: string;
  brows: string;
  nose: string;
  lips: string;
  mouth: string; // expression
  facialHair: string; // 'none' allowed
  hair: string;
  hairColor: string; // hex
  hat: string; // headwear, 'none' allowed (gele, cap, coral cap...)
  top: AvatarGarment;
  bottom: AvatarGarment;
  shoes: { s: string; c: string };
  accent: string; // hex: headwear, embroidery, tie, prints
  accessories: string[]; // e.g. ['coral', 'chain', 'shades']
  preset: string | null; // last outfit preset applied (label only; every slot stays editable)
}

/** The current avatar format everywhere in the app. */
export type AvatarConfig = AvatarConfigV2;

/** Legacy 2D avatar (Phase 1). Only read by the migration. */
export interface AvatarConfigV1 {
  gender: Gender;
  skin: string;
  body: BodyType;
  hair: string;
  hairColor: string;
  eyes: string;
  brows: string;
  mouth: string;
  facialHair: string;
  outfit: string;
  outfitColor: string;
  accessories: string[];
}

export type SceneType =
  | 'market' | 'hospital' | 'campus' | 'palace' | 'museum' | 'club' | 'bank' | 'police'
  | 'motorpark' | 'street' | 'pos'
  | 'home_face_me' | 'home_flat' | 'home_duplex' | 'farm' | 'airport' | 'shrine'
  | 'workshop' | 'buka' | 'salon' | 'cyber' | 'office'
  // L2 landmarks (docs/PLACES.md)
  | 'mall' | 'cinema' | 'hotel' | 'zoo' | 'stadium' | 'monument' | 'car_dealer';

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
  /** L2: opening hours (Benin clock), null = always open. close_hour may be below open_hour (past midnight). */
  open_hour?: number | null;
  close_hour?: number | null;
  /** F1 soft launch: false = hidden (no pin, not in Ride/search, can't travel or act there). */
  active?: boolean;
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
  /** When the current busy activity started (set with busy_until; null for old rows). */
  busy_started_at?: string | null;
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
  mode?: 'real' | 'accelerated'; // L1: clock.mode
  date?: string; // L1: local date YYYY-MM-DD (Benin time in real mode)
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
  /** P1: own-vehicle option (mode car): the item id (bicycle, bajaj_boxer, g_wagon...). */
  vehicle?: string | null;
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

// ---- P1-ORIGIN: starting class roll (LAPO baby vs Nepo baby) ----
// Server: supabase/migrations/20261005000200_origin.sql. Interfaces below merge into Profile / GameState.

/** origin_tiers.id — 'lapo' (default) and 'nepo' today; more tiers can be added as data. */
export type OriginId = 'lapo' | 'nepo' | (string & {});

export interface Profile {
  origin: OriginId;
  /** Game day Dad's allowance was last claimed (null = never). */
  allowance_claimed_day: number | null;
}

export interface OriginItem {
  id: string;
  name: string;
  category: string;
}

/** `get_my_state().origin` — the player's tier and what it gives. */
export interface OriginInfo {
  id: OriginId;
  name: string; // "Nepo baby"
  tagline: string; // Pidgin
  perks: Record<string, unknown>; // future hooks, e.g. { micro_loan_access: 'easy' }
  career_head_start: number; // levels added at first job (Phase 2)
  allowance_daily: number; // naira per game day, 0 = none
  allowance_claimable: boolean; // allowance > 0 and not yet claimed this game day
  start_cash: number;
  start_bank: number;
  items: OriginItem[]; // starter items from config
}

export interface GameState {
  /** Missing only on a server without the origin migration. */
  origin?: OriginInfo | null;
}

/** `claim_allowance()` result. */
export interface ClaimAllowanceResult {
  message: string;
  amount: number;
  account: 'bank';
  bank: number; // new bank balance
  day: number;
}

// ---- R3a: creator data (traits, dreams, start homes, rent) ----
// Server: supabase/migrations/20261005000400_creator.sql, docs/CREATOR.md. Wrappers: src/api/creator.ts.

/** Need keys a trait's `effects.decay` may scale. */
export type DecayNeed = 'hunger' | 'energy' | 'hygiene' | 'fun' | 'social' | 'stress' | 'bladder';

/** Data-driven trait effects. `decay` multipliers apply now; the rest are stored for Phase 2. */
export interface TraitEffects {
  decay?: Partial<Record<DecayNeed, number>>;
  skill_xp?: Record<string, number>;
  [key: string]: unknown;
}

export interface Trait {
  id: string;
  name: string;
  emoji: string;
  description: string;
  effects: TraitEffects;
}

export type DreamGoal =
  | { type: 'career_top'; track?: string }
  | { type: 'net_worth'; amount: number }
  | { type: 'skill'; skill: string; level: number }
  | { type: 'friends'; count: number; level?: string }
  | { type: 'startup_funded' }
  | { type: string; [key: string]: unknown };

export interface Dream {
  id: string;
  name: string;
  emoji: string;
  description: string;
  goal: DreamGoal;
}

export type StartHomeTag = 'Student life' | 'Hard start' | 'Balanced' | 'Big spender' | (string & {});

/** A start home as the catalog lists it (all origins). */
export interface StartHomeCatalogItem {
  id: string;
  name: string;
  emoji: string;
  district: string;
  tag: StartHomeTag;
  description: string;
  location_id: string;
  weekly_rent: number;
  /** Cash in hand per origin id; a missing origin falls back to origin.<tier>.start_cash. */
  start_cash: Record<string, number>;
  /** Empty = every origin may pick it. */
  allowed_origins: string[];
  locked_quip: string;
}

/** A start home as offered to one player (GameState.creator.homes): amounts for their origin. */
export interface StartHomeOption {
  id: string;
  name: string;
  emoji: string;
  district: string;
  tag: StartHomeTag;
  description: string;
  location_id: string;
  location_name: string;
  scene: SceneType;
  housing_id: string;
  weekly_rent: number;
  start_cash: number;
  start_bank: number;
  allowed: boolean;
  /** Joke shown on a greyed-out card; null when allowed. */
  locked_quip: string | null;
}

/** `creator_catalog()` — readable before sign-up. */
export interface CreatorCatalog {
  trait_count: number;
  traits: Trait[];
  dreams: Dream[];
  homes: StartHomeCatalogItem[];
  /** Rent weekday, 0 = Monday … 6 = Sunday (game day 1 is a Monday). */
  rent_weekday: number;
}

/** `get_my_state().creator` — route back to the home step while `home_chosen` is false. */
export interface CreatorState {
  home_chosen: boolean;
  traits: string[];
  dream: string | null;
  start_home: string | null;
  /** Homes for the player's origin while no home is chosen; null afterwards. */
  homes: StartHomeOption[] | null;
}

export interface RentState {
  weekly: number;
  due_at: string | null;
  owed: number;
  /** False while rent.enabled is off: the due date rolls forward without charging. */
  enabled: boolean;
}

export interface Profile {
  traits: string[];
  dream: string | null;
  start_home: string | null;
  home_chosen: boolean;
  weekly_rent: number;
  rent_due_at: string | null;
  rent_owed: number;
}

export interface GameClock {
  /** 0 = Monday … 6 = Sunday (game day 1 is a Monday). Missing on servers before R3a. */
  weekday?: number;
}

export interface GameState {
  creator?: CreatorState;
  rent?: RentState;
}

/** `choose_start_home()` result: the new GameState plus a message. */
export type ChooseStartHomeResult = GameState & { message: string };

/** `admin_set_origin()` result. */
export interface AdminSetOriginResult {
  message: string;
  old: OriginId;
  new: OriginId;
  cash: number;
  bank: number;
  items: string[];
}

// ---- R4: bladder need, players online ----
// Server: supabase/migrations/20261005000500_bladder.sql. Bladder: 100 = comfortable, drops every game
// hour (needs.bladder_per_hour, trait effects.decay.bladder); toilet activities refill it.

export interface Profile {
  /** 0-100. Missing only on a server without the R4 migration. */
  bladder?: number;
}

/** `players_online()` — Sims seen in the last time.presence_real_minutes. */
export interface PlayersOnline {
  count: number;
  minutes: number;
}

// ---- V1-3: careers (docs/CAREERS.md) ----
// Server: supabase/migrations/20261005000700_careers.sql.

export interface CareerRequirement {
  key: 'min_shifts_in_level' | 'item' | 'degree' | 'min_level_track' | 'min_street_cred' | string;
  label: string;
  met: boolean;
  item?: string;
  track?: string;
}

export interface CareerJob {
  track: string;
  track_name: string;
  emoji: string;
  skill: string | null;
  level: number;
  title: string;
  top_level: number;
  pay_per_shift: number;
  shift_game_minutes: number;
  energy_cost: number;
  xp: number;
  /** null at the top of the ladder */
  xp_to_next: number | null;
  shifts_in_level: number;
  total_shifts: number;
  shifts_today: number;
  max_shifts_per_day: number;
  /** performance % if a shift started now (from current needs) */
  perf_now: number;
  /** pay a shift started now would earn (performance, traits, career.pay_mult) */
  pay_now: number;
  started_at: string | null;
  locations: { id: string; name: string }[];
  next: { level: number; title: string; pay_per_shift: number; requirements: CareerRequirement[] } | null;
  pending: { ends_at: string; pay: number; xp: number; perf: number } | null;
}

export interface CareerState {
  job: CareerJob | null;
  degree: boolean;
  best: Record<string, number>;
}

export interface GameState {
  /** Missing only on a server without the careers migration. */
  career?: CareerState;
}

export interface Profile {
  job_shift_ends_at?: string | null;
}

export interface JobLevelInfo {
  level: number;
  title: string;
  pay_per_shift: number;
  shift_game_minutes: number;
  xp_to_next: number | null;
  requirements: CareerRequirement[];
}

export interface JobTrack {
  id: string;
  name: string;
  emoji: string;
  category: 'official' | 'hustle';
  description: string;
  skill: string | null;
  locations: { id: string; name: string }[];
  entry_level: number;
  levels: JobLevelInfo[];
}

/** `jobs_catalog()` */
export interface JobsCatalog {
  current: string | null;
  degree: boolean;
  tracks: JobTrack[];
}

/** `work_finish()` */
export interface WorkFinishResult {
  message: string | null;
  pay?: number;
  xp?: number;
  perf?: number;
  promoted?: { level: number; title: string; pay: number };
  blocked?: { title: string; missing: string[] };
}

// ---- V1-4: shops, Bag, Chowdeck, rent on (docs/SHOPS.md) ----
// Server: supabase/migrations/20261005000800_shops.sql.

/** 'use' = eat/drink/use from the Bag; 'boost' = used up by an activity (soap + bath); 'keep' = owned (laptop). */
export type ItemKind = 'use' | 'boost' | 'keep';

/** Need deltas, or `{ boost: { <activity id>: needs } }`. */
export type ItemEffects = Record<string, number> & { boost?: Record<string, Record<string, number>> };

export interface ItemBase {
  id: string;
  name: string;
  category: 'food' | 'drink' | 'hygiene' | 'health' | 'phone' | 'gadget' | 'vehicle' | 'souvenir' | (string & {});
  icon: string | null;
  description: string;
  effects: ItemEffects;
}

/** `get_my_state().inventory` entry (only qty > 0). */
export interface InventoryItem extends ItemBase {
  qty: number;
  price: number;
  kind: ItemKind;
  sellable: boolean;
  /** what a market pays for one (0 when not sellable) */
  resale_price: number;
}

export interface ShopItem extends ItemBase {
  price: number;
  kind: ItemKind;
  sellable: boolean;
  resale_price: number;
  owned: number;
  affordable: boolean;
}

/** `shop_list(p_location)` */
export interface ShopList {
  location: { id: string; name: string; scene: SceneType };
  here: boolean;
  sell_here: boolean;
  cash: number;
  items: ShopItem[];
}

export interface FoodMenuItem extends ItemBase {
  shop_price: number;
  /** delivery price of one */
  price: number;
  owned: number;
}

/** `food_menu()` */
export interface FoodMenu {
  markup_pct: number;
  min_fee: number;
  cash: number;
  bank: number;
  items: FoodMenuItem[];
}

export interface RentState {
  /** Percent of sleep/nap energy kept while rent is owed (rent.owed_sleep_energy_pct). */
  owed_sleep_pct?: number;
}

export interface GameState {
  /** Missing only on a server without the shops migration. */
  inventory?: InventoryItem[];
}

// ---- V1-5: bank, PoS, phone transfers (docs/BANK.md) ----
// Server: supabase/migrations/20261005000900_bank.sql.

/** A place where money moves: the bank counter (banking hours) or a PoS stand (any hour, fee). */
export interface BankPlace {
  id: string;
  name: string;
  district: string;
  kind: 'bank' | 'pos';
}

/** `bank_info()` (read-only). */
export interface BankInfo {
  cash: number;
  bank: number;
  min_amount: number;
  bank_hours: { open_hour: number; close_hour: number; open: boolean; opens_in_game_minutes: number; opens_in_real_seconds: number };
  pos: { fee_pct: number; fee_min: number; max_amount: number; max_cashout: number; max_deposit: number };
  transfer: {
    fee: number;
    min_amount: number;
    daily_limit: number;
    sent_today: number;
    left_today: number;
    count_today: number;
    daily_count: number;
    cooldown_real_seconds: number;
    new_account_wait_real_seconds: number;
  };
  tip_cash_threshold: number;
  places: BankPlace[];
}

/** One `bank_history()` row (both accounts, newest first). */
export interface LedgerRow {
  id: number;
  account: 'cash' | 'bank';
  delta: number;
  balance_after: number;
  reason: string;
  label: string;
  note: string | null;
  created_at: string;
}

/** `bank_recipient(p_username)` */
export interface BankRecipient {
  id: string;
  username: string;
  avatar: unknown;
}

/** Result of bank_deposit / bank_withdraw / pos_cashout / pos_deposit. */
export interface MoneyMoveResult {
  message: string;
  amount: number;
  fee?: number;
  cash: number;
  bank: number;
}

/** `bank_transfer(...)` */
export interface TransferResult {
  message: string;
  amount: number;
  fee: number;
  bank: number;
  to: { id: string; username: string };
  sent_today: number;
  left_today: number;
}

// ---- V1-6: location chat (docs/CHAT.md) ----
// Server: supabase/migrations/20261005001000_chat.sql. Wrappers: src/api/chat.ts, live state: src/state/chat.ts.

/** A chat message (chat_recent / chat_send rows; realtime INSERT rows lack `avatar` and `mine`). */
export interface ChatMessage {
  id: number;
  location_id: string;
  user_id: string;
  username: string;
  body: string;
  created_at: string;
  avatar?: AvatarConfig | null;
  mine?: boolean;
}

/** `chat_send()` result. */
export type ChatSendResult = ChatMessage & { message: string; masked: boolean };

/** A row of `chat_blocked()`. */
export interface BlockedPlayer {
  id: string;
  username: string;
  avatar: AvatarConfig | null;
  created_at: string;
}

// ---- L1: real Benin time + short actions (docs/REAL_LIFE_PLAN.md, 20261006000100_real_time.sql) ----
export interface Profile {
  /** Need values just before the running action's effects (live-filling bars); null when none. */
  busy_needs_from?: Partial<Record<'hunger' | 'energy' | 'hygiene' | 'fun' | 'social' | 'stress' | 'health' | 'bladder', number>> | null;
  /** The running shift's pay / XP (paid when it ends; the busy banner counts them up). */
  job_shift_pay?: number | null;
  job_shift_xp?: number | null;
}
