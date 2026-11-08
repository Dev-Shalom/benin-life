// Free roam: the walkable world. Everything is in MAP units (1 unit = 1 metre on the street scale) with
// x = east, y = south (north up on the city map), so the roam scene matches the 3D city map exactly.
// Phase 2: the whole city. Pure numbers; the server has the matching switches in game_config (roam.area.*, roam.chunk.*).

/** The whole city map (map units). A fence and road-closed barriers stand on this edge. */
export const AREA = { x0: 0, y0: 0, x1: 1000, y1: 1000 } as const;

export const inArea = (x: number, y: number, pad = 0) => x >= AREA.x0 + pad && x <= AREA.x1 - pad && y >= AREA.y0 + pad && y <= AREA.y1 - pad;

/** Player and walking speeds (m/s). Walking is a little brisk so a block does not take forever. */
export const SPEED = { walk: 2.0, run: 4.9, accel: 12, turn: 11 } as const;
/** Player collision radius (m). */
export const PLAYER_R = 0.32;

/** Streaming defaults (the server sends hints in roam_start: roam.chunk.m / roam.chunk.load_m). */
export const CHUNK_M = 120;
export const STREAM = {
  /** Detailed chunks within this distance (nearest edge) of the player. */
  detail: { high: 200, low: 150 },
  /** Low-detail backdrop chunks (merged boxes) up to this distance. */
  far: { high: 360, low: 270 },
  /** Hysteresis before a chunk is dropped (m). */
  hyst: 40,
} as const;

export interface PlaceIn {
  id: string;
  name: string;
  scene: string;
  x: number;
  y: number;
  /** false = inactive (closed): the place stands in the street with a shut gate and an "Under construction" board. */
  active?: boolean;
  keke_ok?: boolean;
}
