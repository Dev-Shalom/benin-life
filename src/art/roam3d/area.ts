// Free roam, phase 1: the walkable area. Everything is in MAP units (1 unit = 1 metre on the street scale) with
// x = east, y = south (north up on the city map), so the roam scene matches the 3D city map exactly.
// Pure numbers: the server has the same box in game_config (roam.area.*), see docs/ROAM.md.

/** The walkable box around Ring Road / King's Square (map units). */
export const AREA = { x0: 395, y0: 392, x1: 610, y1: 645 } as const;
/** Detail margin beyond the walkable box (buildings, windows, lamps are built here too). */
export const MARGIN = 26;
/** Low-detail backdrop beyond the detail margin so the edge of the area is not the edge of the world. */
export const BACKDROP = 150;

export const inArea = (x: number, y: number, pad = 0) => x >= AREA.x0 + pad && x <= AREA.x1 - pad && y >= AREA.y0 + pad && y <= AREA.y1 - pad;

/** Player and walking speeds (m/s). Walking is a little brisk so a block does not take forever. */
export const SPEED = { walk: 2.0, run: 4.9, accel: 12, turn: 11 } as const;
/** Player collision radius (m). */
export const PLAYER_R = 0.32;

export interface PlaceIn {
  id: string;
  name: string;
  scene: string;
  x: number;
  y: number;
}
