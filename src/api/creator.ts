// R3a: typed wrappers for the creator RPCs (server: supabase/migrations/20261005000400_creator.sql).
// Flow (R3b UI): Look -> Personality -> Dream -> createProfileV2 (birth lottery reveal) -> chooseStartHome.
import { rpc, GameError } from '../lib/api';
import type {
  AdminSetOriginResult,
  AvatarConfig,
  ChooseStartHomeResult,
  CreatorCatalog,
  GameState,
  Gender,
  OriginId,
} from '../lib/types';

/** Traits, dreams and start homes (works before sign-up too). */
export function getCreatorCatalog(): Promise<CreatorCatalog> {
  return rpc<CreatorCatalog>('creator_catalog');
}

/**
 * Create the Sim (no home yet). Rolls the origin (or applies origin.force_next).
 * The result's `creator.homes` lists the start homes for that origin.
 */
export function createProfileV2(args: {
  username: string;
  gender: Gender;
  avatar: AvatarConfig;
  traits: string[];
  dream: string;
}): Promise<GameState> {
  return rpc<GameState>('create_profile_v2', {
    p_username: args.username,
    p_gender: args.gender,
    p_avatar: { ...args.avatar, gender: args.gender },
    p_traits: args.traits,
    p_dream: args.dream,
  });
}

/** Move into a start home (once). Pays the starter pack and sets the weekly rent. */
export function chooseStartHome(homeId: string): Promise<ChooseStartHomeResult> {
  return rpc<ChooseStartHomeResult>('choose_start_home', { p_home: homeId });
}

/** Admin only: change a player's origin; with applyPerks, top up the difference (never takes away). */
export function adminSetOrigin(userId: string, origin: OriginId, applyPerks = false): Promise<AdminSetOriginResult> {
  return rpc<AdminSetOriginResult>('admin_set_origin', { p_user: userId, p_origin: origin, p_apply_perks: applyPerks });
}

/** True when the Sim exists but still has to pick a home (route to the creator's home step). */
export function needsHome(state: GameState | null | undefined): boolean {
  return !!state && state.creator?.home_chosen === false;
}

/** True when a gameplay RPC was refused because no home is chosen yet. */
export function isNoHomeError(e: unknown): boolean {
  return e instanceof GameError && e.hint === 'no_home';
}
