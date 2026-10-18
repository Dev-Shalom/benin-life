// R8 house upgrades: how finished (and in-progress) upgrades change a home's layout. Pure data, no three.js.
// Server: supabase/migrations/20261018000500_house_upgrades.sql (house_upgrades + player_house_upgrades),
// docs/HOUSE_UPGRADES.md.
//
// Geometry is CODE, not admin data: the same numbers are seeded into house_upgrades.effect.geom (per layout) so the
// server checks furniture against the same extended floor plan (bl_home_ext). scripts/home-upgrade-check.mjs
// verifies both agree and that nothing blocks the doors or the way to the new rooms.
//   room   = a rectangle added to the south wall (z starts at the house depth), door = the gap in the shared wall.
//   struct = a building in the yard.
import type { HomeLayout, HomeLayoutId, HomeRoom, HomeStruct, StructKind } from './model';

export type Rect4 = [number, number, number, number];

export interface UpgradeGeom {
  room?: { rect: Rect4; door: [number, number] };
  struct?: { kind: StructKind; rect: Rect4 };
}

/** upgrade id -> layout id -> geometry. Only layouts listed here draw the upgrade (others keep it as a bonus only). */
export const GEOM: Record<string, Partial<Record<HomeLayoutId, UpgradeGeom>>> = {
  ext_bedroom: {
    face_me: { room: { rect: [0, 3.8, 4.2, 6.6], door: [2.6, 3.4] } },
    self_contain: { room: { rect: [0, 4.8, 6, 7.6], door: [3.9, 4.9] } },
    flat: { room: { rect: [0, 7.2, 6, 10], door: [3, 4] } },
  },
  ext_guest_wing: {
    duplex: { room: { rect: [7.4, 10, 14.4, 13.4], door: [8, 9] } },
  },
  boys_quarters: {
    duplex: { struct: { kind: 'bq', rect: [15, 7, 18.2, 9.4] } },
  },
  gen_house: {
    face_me: { struct: { kind: 'genhouse', rect: [7.15, 0.4, 8.45, 1.4] } },
    self_contain: { struct: { kind: 'genhouse', rect: [7.4, 0.4, 8.7, 1.4] } },
    flat: { struct: { kind: 'genhouse', rect: [11.15, 0.4, 12.45, 1.4] } },
    duplex: { struct: { kind: 'genhouse', rect: [17.4, -0.1, 18.7, 0.9] } },
  },
  solar_system: {
    face_me: { struct: { kind: 'solar', rect: [7.15, 3.9, 9.15, 5] } },
    self_contain: { struct: { kind: 'solar', rect: [7.4, 4.65, 9.4, 5.75] } },
    flat: { struct: { kind: 'solar', rect: [9.9, 7.15, 11.9, 8.25] } },
    duplex: { struct: { kind: 'solar', rect: [18.65, 8.4, 20.65, 9.5] } },
  },
  borehole: {
    face_me: { struct: { kind: 'borehole', rect: [7.9, 1.9, 9.5, 3.1] } },
    self_contain: { struct: { kind: 'borehole', rect: [7.9, 2.15, 9.5, 3.35] } },
    flat: { struct: { kind: 'borehole', rect: [9.9, 2.15, 11.5, 3.35] } },
    duplex: { struct: { kind: 'borehole', rect: [15.65, 5.4, 17.25, 6.6] } },
  },
};

export interface UpgradeInfo {
  id: string;
  /** house_upgrades.effect (may carry `geom`, `finish`, `security`). */
  effect?: Record<string, unknown> | null;
}

export function geomOf(u: UpgradeInfo, layout: HomeLayoutId): UpgradeGeom | null {
  const fromEffect = (u.effect?.geom as Record<string, UpgradeGeom> | undefined)?.[layout];
  return fromEffect ?? GEOM[u.id]?.[layout] ?? null;
}

const mix = (a: string, b: string, t: number): string => {
  const pa = parseInt(a.slice(1), 16), pb = parseInt(b.slice(1), 16);
  const ch = (s: number) => Math.round(((pa >> s) & 255) * (1 - t) + ((pb >> s) & 255) * t);
  return `#${((1 << 24) | (ch(16) << 16) | (ch(8) << 8) | ch(0)).toString(16).slice(1)}`;
};

/** Finish level -> palette (walls get lighter and fresher, floors get tiled, then marble). */
function applyFinish(L: HomeLayout, level: number): HomeLayout {
  if (level <= 0) return L;
  const out: HomeLayout = { ...L, finish: level };
  out.wallInner = mix(L.wallInner, '#ffffff', level === 1 ? 0.45 : level === 2 ? 0.6 : 0.75);
  if (level >= 2) out.floor = { a: '#ece8e0', b: '#ddd8ce', tile: Math.max(0.8, L.floor.tile ?? 0.6) };
  if (level >= 3) {
    out.floor = { a: '#f2eee7', b: '#d6cfc1', tile: 1.0 };
    out.wallInner = '#faf6ee';
  }
  return out;
}

/** The rectangle a growing lot needs to hold a rect with a 0.6 m margin. */
const grow = (lot: Rect4, r: Rect4): Rect4 => [Math.min(lot[0], r[0]), Math.min(lot[1], r[1]), Math.max(lot[2], r[2] + 0.6), Math.max(lot[3], r[3] + 0.6)];

/**
 * The layout with finished upgrades built in and, for the ones still being built, scaffolding.
 * Furniture is untouched (it keeps its coordinates; the new rooms are simply more floor).
 */
export function applyUpgrades(base: HomeLayout, done: UpgradeInfo[], building: UpgradeInfo[] = []): HomeLayout {
  if (!done.length && !building.length) return base;
  let L: HomeLayout = { ...base };
  const rooms: HomeRoom[] = [];
  const structs: HomeStruct[] = [];
  const windows = [...base.windows];
  let lot = [...base.lot] as Rect4;
  let finish = 0;
  let security = 0;
  for (const u of done) {
    finish = Math.max(finish, Number(u.effect?.finish ?? 0) || 0);
    security = Math.max(security, Number(u.effect?.security ?? 0) || 0);
    const g = geomOf(u, base.id);
    if (g?.room && g.room.rect[1] === base.d) {
      rooms.push({ id: u.id, rect: g.room.rect, door: g.room.door });
      lot = grow(lot, g.room.rect);
      if (g.room.rect[0] === 0) windows.push(['w', g.room.rect[1] + 0.5, g.room.rect[3] - 0.5]);
    }
    if (g?.struct) { structs.push({ id: u.id, kind: g.struct.kind, rect: g.struct.rect }); lot = grow(lot, g.struct.rect); }
  }
  L = { ...L, lot, windows, rooms, structs, security };
  L = applyFinish(L, finish);
  // builders at work: scaffolding where the work is (a room or building spot, else round the house / the parking)
  const scaffold: NonNullable<HomeLayout['scaffold']> = [];
  for (const u of building) {
    const g = geomOf(u, base.id);
    if (g?.room) { scaffold.push({ rect: g.room.rect }); L = { ...L, lot: grow(L.lot, g.room.rect) }; }
    else if (g?.struct) scaffold.push({ rect: g.struct.rect });
    else if (String(u.effect?.garage_type ?? '') || u.effect?.garage_space) scaffold.push({ at: 'parking' });
    else scaffold.push({ at: 'house' });
  }
  if (scaffold.length) L = { ...L, scaffold };
  return L;
}

/** Finish level of the done upgrades (0..3), for UI labels. */
export const FINISH_NAMES = ['Bare walls', 'Fresh paint', 'POP ceiling and tiles', 'Premium finish'] as const;
