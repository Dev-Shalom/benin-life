// Free roam: a small 2D collision world for the flat city (pure TypeScript, no three.js; shared by the scene and
// scripts/roam-collide-check.mjs). Units are metres on the ground plane (x, y = map x, map y).
//
// Static colliders: polygons (buildings, landmark footprints, compound walls, vehicles, stalls) stored as edge
// segments with an outward normal, and circles (trees, lamp poles). Both live in a dense spatial hash (CSR arrays).
// Dynamic colliders (NPC walkers = circles, moving cars = oriented boxes) are set every step and scanned linearly.
//
// The player is a circle. `move()` splits any displacement into sub-steps shorter than 0.4 x radius, so a circle can
// never jump across a wall whatever the speed (a swept test by construction), then pushes the circle out of whatever
// it overlaps (positional correction: the part of the motion along the wall survives, so you slide, never stick).
// Corners are resolved by iterating the deepest overlap first; if a step cannot be resolved at all (squeezed between
// two things) the circle returns to its last valid position. So a circle that starts valid never ends inside anything.

export type Pt = readonly [number, number];

export interface Vec2 {
  x: number;
  y: number;
}

export interface DynCircle {
  x: number;
  y: number;
  r: number;
  /** Owner id (the NPC) so it can skip itself. */
  id: number;
}

export interface DynBox {
  x: number;
  y: number;
  /** Half length (along heading) and half width. */
  hl: number;
  hw: number;
  /** Heading (rad): direction of the long axis in (x, y). */
  a: number;
  id: number;
  /** Speed along the heading (m/s), used only to give a gentle sideways shove. */
  v: number;
  /** Another real player's car (free roam live players): solid, but contact never counts as a hit (no damage from network lag). */
  remote?: boolean;
}

const EPS = 1e-9;
export const SKIN = 0.002;

export class CollisionWorld {
  /** Polygons as given (for exact inside tests and the stress script). */
  readonly polys: { pts: Pt[]; tall: boolean; id: string; h: number }[] = [];
  readonly circs: { x: number; y: number; r: number; tall: boolean; id: string; h: number }[] = [];
  // segments: ax, ay, bx, by, nx, ny (outward normal) ; tall flag separately
  private seg: number[] = [];
  private segTall: number[] = [];
  private segH: number[] = [];
  private SH = new Float32Array(0);
  private CH = new Float32Array(0);
  private segPoly: number[] = [];
  /** How far the polygon reaches behind each edge (its thickness there): a thin wall must never be treated as 'deep inside' from its far side. */
  private segThick: number[] = [];
  private SK = new Float32Array(0);
  private pendThick: number[] = [];
  private S = new Float64Array(0);
  private ST = new Uint8Array(0);
  private C = new Float64Array(0);
  private CT = new Uint8Array(0);
  private stampS = new Int32Array(0);
  private stampC = new Int32Array(0);
  private gen = 0;
  // hash
  private cell = 6;
  private gx0 = 0;
  private gy0 = 0;
  private gw = 1;
  private gh = 1;
  private sStart = new Int32Array(0);
  private sItems = new Int32Array(0);
  private cStart = new Int32Array(0);
  private cItems = new Int32Array(0);
  // dynamic bodies
  dynCircles: DynCircle[] = [];
  dynBoxes: DynBox[] = [];
  /** Optional walkable bounds (x0, y0, x1, y1): a rectangular wall around the play area. */
  bounds: [number, number, number, number] | null = null;
  built = false;
  private pendSeg: number[] = [];
  private circCountBuilt = 0;

  addPoly(pts: Pt[], opt: { tall?: boolean; id?: string; h?: number } = {}) {
    if (pts.length < 3) return;
    let area = 0;
    for (let i = 0; i < pts.length; i++) {
      const a = pts[i];
      const b = pts[(i + 1) % pts.length];
      area += a[0] * b[1] - b[0] * a[1];
    }
    if (Math.abs(area) < 1e-6) return;
    const pi = this.polys.push({ pts, tall: opt.tall !== false, id: opt.id ?? 'poly', h: opt.h ?? 6 }) - 1;
    // outward normal of an edge a->b: for a counter-clockwise polygon (area > 0 in x-right, y-up maths) it is (dy, -dx)
    const sgn = area > 0 ? 1 : -1;
    for (let i = 0; i < pts.length; i++) {
      const a = pts[i];
      const b = pts[(i + 1) % pts.length];
      const dx = b[0] - a[0];
      const dy = b[1] - a[1];
      const l = Math.hypot(dx, dy);
      if (l < 1e-6) continue;
      const row = [a[0], a[1], b[0], b[1], (sgn * dy) / l, (-sgn * dx) / l];
      this.seg.push(...row);
      if (this.built) this.pendSeg.push(...row);
      // inward extent of the polygon behind this edge (distance to its farthest vertex along -normal)
      let thick = 0;
      for (const q of pts) thick = Math.max(thick, (a[0] - q[0]) * row[4] + (a[1] - q[1]) * row[5]);
      this.segThick.push(thick);
      if (this.built) this.pendThick.push(thick);
      this.segTall.push(opt.tall !== false ? 1 : 0);
      this.segH.push(opt.h ?? 6);
      this.segPoly.push(pi);
    }
  }

  addCircle(x: number, y: number, r: number, opt: { tall?: boolean; id?: string; h?: number } = {}) {
    this.circs.push({ x, y, r, tall: opt.tall !== false, id: opt.id ?? 'circle', h: opt.h ?? 4 });
  }

  /** An oriented box (centre, size along / across the heading a) as a polygon. */
  addObb(x: number, y: number, w: number, d: number, a: number, opt: { tall?: boolean; id?: string; h?: number } = {}) {
    this.addPoly(obbCorners(x, y, w, d, a), opt);
  }

  /** Build the hash. Call once after adding statics (and again after adding more). */
  build(cell = 6) {
    this.cell = cell;
    const n = this.seg.length / 6;
    this.S = Float64Array.from(this.seg);
    this.ST = Uint8Array.from(this.segTall);
    this.SH = Float32Array.from(this.segH);
    this.SK = Float32Array.from(this.segThick);
    const m = this.circs.length;
    this.C = new Float64Array(m * 3);
    this.CT = new Uint8Array(m);
    this.CH = new Float32Array(m);
    this.circs.forEach((c, i) => {
      this.C[i * 3] = c.x;
      this.C[i * 3 + 1] = c.y;
      this.C[i * 3 + 2] = c.r;
      this.CT[i] = c.tall ? 1 : 0;
      this.CH[i] = c.h;
    });
    let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
    for (let i = 0; i < n; i++) {
      x0 = Math.min(x0, this.S[i * 6], this.S[i * 6 + 2]);
      y0 = Math.min(y0, this.S[i * 6 + 1], this.S[i * 6 + 3]);
      x1 = Math.max(x1, this.S[i * 6], this.S[i * 6 + 2]);
      y1 = Math.max(y1, this.S[i * 6 + 1], this.S[i * 6 + 3]);
    }
    for (const c of this.circs) {
      x0 = Math.min(x0, c.x - c.r);
      y0 = Math.min(y0, c.y - c.r);
      x1 = Math.max(x1, c.x + c.r);
      y1 = Math.max(y1, c.y + c.r);
    }
    if (!isFinite(x0)) {
      x0 = y0 = 0;
      x1 = y1 = 1;
    }
    this.gx0 = Math.floor(x0 / cell) - 1;
    this.gy0 = Math.floor(y0 / cell) - 1;
    this.gw = Math.floor(x1 / cell) + 2 - this.gx0;
    this.gh = Math.floor(y1 / cell) + 2 - this.gy0;
    const cells = this.gw * this.gh;
    const sCount = new Int32Array(cells + 1);
    const cCount = new Int32Array(cells + 1);
    const eachCell = (ax: number, ay: number, bx: number, by: number, pad: number, f: (ci: number) => void) => {
      const i0 = Math.floor((Math.min(ax, bx) - pad) / cell) - this.gx0;
      const i1 = Math.floor((Math.max(ax, bx) + pad) / cell) - this.gx0;
      const j0 = Math.floor((Math.min(ay, by) - pad) / cell) - this.gy0;
      const j1 = Math.floor((Math.max(ay, by) + pad) / cell) - this.gy0;
      for (let j = j0; j <= j1; j++) for (let i = i0; i <= i1; i++) if (i >= 0 && j >= 0 && i < this.gw && j < this.gh) f(j * this.gw + i);
    };
    for (let i = 0; i < n; i++) eachCell(this.S[i * 6], this.S[i * 6 + 1], this.S[i * 6 + 2], this.S[i * 6 + 3], 0, (ci) => sCount[ci + 1]++);
    for (let i = 0; i < m; i++) eachCell(this.C[i * 3], this.C[i * 3 + 1], this.C[i * 3], this.C[i * 3 + 1], this.C[i * 3 + 2], (ci) => cCount[ci + 1]++);
    for (let i = 0; i < cells; i++) {
      sCount[i + 1] += sCount[i];
      cCount[i + 1] += cCount[i];
    }
    this.sStart = sCount;
    this.cStart = cCount;
    this.sItems = new Int32Array(sCount[cells]);
    this.cItems = new Int32Array(cCount[cells]);
    const sFill = sCount.slice(0, cells);
    const cFill = cCount.slice(0, cells);
    for (let i = 0; i < n; i++) eachCell(this.S[i * 6], this.S[i * 6 + 1], this.S[i * 6 + 2], this.S[i * 6 + 3], 0, (ci) => (this.sItems[sFill[ci]++] = i));
    for (let i = 0; i < m; i++) eachCell(this.C[i * 3], this.C[i * 3 + 1], this.C[i * 3], this.C[i * 3 + 1], this.C[i * 3 + 2], (ci) => (this.cItems[cFill[ci]++] = i));
    this.stampS = new Int32Array(n);
    this.stampC = new Int32Array(m);
    this.pendSeg = [];
    this.pendThick = [];
    this.circCountBuilt = m;
    this.built = true;
  }

  get segmentCount() {
    return this.seg.length / 6;
  }

  /* ------------------------------------------------------------ resolve */

  /**
   * Push the circle (pos, r) out of everything it overlaps. Returns true when it ends clear (within SKIN) of all
   * statics and dynamics. `self` skips one dynamic body (an NPC resolving itself). `dyn` = false: statics only.
   */
  resolve(p: Vec2, r: number, self = -1, dyn = true): boolean {
    for (let it = 0; it < 10; it++) {
      let px = 0, py = 0, depth = 0;
      // deepest static overlap this pass
      const res = this.deepest(p.x, p.y, r, self, dyn);
      depth = res;
      px = _out.x;
      py = _out.y;
      if (depth <= SKIN * 0.5) return true;
      p.x += px;
      p.y += py;
    }
    return this.deepest(p.x, p.y, r, self, dyn) <= SKIN * 0.5 + 1e-6;
  }

  /** Overlap of a circle with the STATIC colliders and the city edge: the depth (0 = clear); the push-out vector is left in `push`. */
  readonly push = { x: 0, y: 0 };
  probe(x: number, y: number, r: number): number {
    const d = this.deepest(x, y, r, -1, false);
    this.push.x = _out.x;
    this.push.y = _out.y;
    return d;
  }

  /** Is the circle clear of every collider? */
  clear(x: number, y: number, r: number, self = -1, dyn = true): boolean {
    return this.deepest(x, y, r, self, dyn) <= SKIN * 0.5;
  }

  /** Deepest overlap; the push-out vector that cures it is left in `_out`. 0 when clear. */
  private deepest(x: number, y: number, r: number, self: number, dyn: boolean): number {
    _best = 0;
    _out.x = 0;
    _out.y = 0;
    const S = this.S;
    const gen = ++this.gen;
    const cell = this.cell;
    if (this.built) {
      const i0 = Math.floor((x - r) / cell) - this.gx0;
      const i1 = Math.floor((x + r) / cell) - this.gx0;
      const j0 = Math.floor((y - r) / cell) - this.gy0;
      const j1 = Math.floor((y + r) / cell) - this.gy0;
      for (let j = j0; j <= j1; j++) {
        if (j < 0 || j >= this.gh) continue;
        for (let i = i0; i <= i1; i++) {
          if (i < 0 || i >= this.gw) continue;
          const ci = j * this.gw + i;
          for (let k = this.sStart[ci], e = this.sStart[ci + 1]; k < e; k++) {
            const s = this.sItems[k];
            if (this.stampS[s] === gen) continue;
            this.stampS[s] = gen;
            testSeg(S, s * 6, x, y, r, this.SK[s]);
          }
          for (let k = this.cStart[ci], e = this.cStart[ci + 1]; k < e; k++) {
            const c = this.cItems[k];
            if (this.stampC[c] === gen) continue;
            this.stampC[c] = gen;
            testCirc(this.C[c * 3], this.C[c * 3 + 1], this.C[c * 3 + 2], x, y, r);
          }
        }
      }
    }
    // colliders added after build() (door posts, stalls while the world is being made): scanned linearly
    {
      const P = this.built ? this.pendSeg : this.seg;
      const PT = this.built ? this.pendThick : this.segThick;
      for (let o = 0; o < P.length; o += 6) testSeg(P, o, x, y, r, PT[o / 6]);
    }
    for (let c = this.built ? this.circCountBuilt : 0; c < this.circs.length; c++) {
      const q = this.circs[c];
      testCirc(q.x, q.y, q.r, x, y, r);
    }
    let best = _best;
    if (this.bounds) {
      const [bx0, by0, bx1, by1] = this.bounds;
      let d = bx0 + r - x;
      if (d > best) { best = d; _out.x = d + SKIN; _out.y = 0; }
      d = x + r - bx1;
      if (d > best) { best = d; _out.x = -(d + SKIN); _out.y = 0; }
      d = by0 + r - y;
      if (d > best) { best = d; _out.x = 0; _out.y = d + SKIN; }
      d = y + r - by1;
      if (d > best) { best = d; _out.x = 0; _out.y = -(d + SKIN); }
    }
    if (dyn) {
      for (let k = 0; k < this.dynCircles.length; k++) {
        const c = this.dynCircles[k];
        if (c.id === self) continue;
        const vx = x - c.x, vy = y - c.y;
        const rr = r + c.r;
        if (vx > rr || vx < -rr || vy > rr || vy < -rr) continue;
        const dd = Math.hypot(vx, vy);
        const d = rr - dd;
        if (d > best) {
          best = d;
          if (dd > EPS) {
            _out.x = (vx / dd) * (d + SKIN);
            _out.y = (vy / dd) * (d + SKIN);
          } else {
            _out.x = d + SKIN;
            _out.y = 0;
          }
        }
      }
      for (let k = 0; k < this.dynBoxes.length; k++) {
        const b = this.dynBoxes[k];
        if (b.id === self) continue;
        const reach = b.hl + b.hw + r;
        if (x - b.x > reach || b.x - x > reach || y - b.y > reach || b.y - y > reach) continue;
        const c = Math.cos(b.a), s = Math.sin(b.a);
        const wx = x - b.x, wy = y - b.y;
        const lx = wx * c + wy * s; // along heading
        const ly = -wx * s + wy * c; // across
        const qx = Math.max(-b.hl, Math.min(b.hl, lx));
        const qy = Math.max(-b.hw, Math.min(b.hw, ly));
        const vx = lx - qx, vy = ly - qy;
        const dd = Math.hypot(vx, vy);
        if (dd >= r) continue;
        let d: number;
        let ux: number, uy: number; // in the box frame
        if (dd > EPS) {
          d = r - dd;
          ux = vx / dd;
          uy = vy / dd;
        } else {
          // centre inside the box: leave by the nearest side
          const ex = b.hl - Math.abs(lx), ey = b.hw - Math.abs(ly);
          if (ey <= ex) { ux = 0; uy = ly >= 0 ? 1 : -1; d = r + ey; } else { ux = lx >= 0 ? 1 : -1; uy = 0; d = r + ex; }
        }
        // a moving car shoves you gently SIDEWAYS, not along its path (no carrying you down the road)
        if (Math.abs(ux) > Math.abs(uy) && Math.abs(b.v) > 0.5 && Math.abs(ly) < b.hw + r) {
          const sg = ly >= 0 ? 1 : -1;
          const need = b.hw + r - Math.abs(ly);
          ux = 0;
          uy = sg;
          d = Math.min(Math.max(need, 0), 0.1);
        }
        if (d > best) {
          best = d;
          _out.x = (ux * c - uy * s) * (d + SKIN);
          _out.y = (ux * s + uy * c) * (d + SKIN);
        }
      }
    }
    return best;
  }

  /**
   * Move the circle by (dx, dy), sliding along whatever is in the way. Returns the distance really moved.
   * Sub-steps of at most 0.4 x radius: no tunnelling at any speed. `p` must start clear (else it is first pushed out).
   */
  move(p: Vec2, dx: number, dy: number, r: number, self = -1): number {
    const dist = Math.hypot(dx, dy);
    if (dist < 1e-9) {
      if (!this.clear(p.x, p.y, r, self)) this.resolve(p, r, self);
      return 0;
    }
    const n = Math.max(1, Math.ceil(dist / (r * 0.4)));
    const sx = dx / n;
    const sy = dy / n;
    const sx0 = p.x, sy0 = p.y;
    for (let i = 0; i < n; i++) {
      const lx = p.x, ly = p.y;
      p.x += sx;
      p.y += sy;
      if (!this.clear(p.x, p.y, r, self)) {
        if (!this.resolve(p, r, self)) {
          // squeezed: try each axis alone, else stay
          p.x = lx + sx;
          p.y = ly;
          if (!this.clear(p.x, p.y, r, self)) {
            p.x = lx;
            p.y = ly + sy;
            if (!this.clear(p.x, p.y, r, self)) {
              p.x = lx;
              p.y = ly;
            }
          }
        }
      }
    }
    return Math.hypot(p.x - sx0, p.y - sy0);
  }

  /* ------------------------------------------------------------ queries */

  /** Is the point inside any solid polygon or circle? (exact; independent of the hash) */
  solidAt(x: number, y: number): boolean {
    for (const c of this.circs) if ((x - c.x) ** 2 + (y - c.y) ** 2 < c.r * c.r) return true;
    for (const pl of this.polys) if (inPoly(x, y, pl.pts)) return true;
    return false;
  }

  /**
   * Camera collision: how far along (ox, oy) -> (tx, ty) a circle of radius `rad` gets before touching a TALL collider
   * (building, wall, trunk). Returns a fraction 0..1.
   */
  rayTall(ox: number, oy: number, tx: number, ty: number, rad: number, y0 = 1.5, y1 = 1.5): number {
    const len = Math.hypot(tx - ox, ty - oy);
    if (len < 1e-6) return 1;
    const n = Math.max(2, Math.ceil(len / 0.2));
    for (let i = 1; i <= n; i++) {
      const t = i / n;
      if (this.tallNear(ox + (tx - ox) * t, oy + (ty - oy) * t, rad, y0 + (y1 - y0) * t)) return Math.max(0, (i - 1) / n);
    }
    return 1;
  }

  private tallNear(x: number, y: number, rad: number, cy: number): boolean {
    const cell = this.cell;
    const i0 = Math.floor((x - rad) / cell) - this.gx0;
    const i1 = Math.floor((x + rad) / cell) - this.gx0;
    const j0 = Math.floor((y - rad) / cell) - this.gy0;
    const j1 = Math.floor((y + rad) / cell) - this.gy0;
    const S = this.S;
    for (let j = j0; j <= j1; j++) {
      if (j < 0 || j >= this.gh) continue;
      for (let i = i0; i <= i1; i++) {
        if (i < 0 || i >= this.gw) continue;
        const ci = j * this.gw + i;
        for (let k = this.sStart[ci], e = this.sStart[ci + 1]; k < e; k++) {
          const s = this.sItems[k];
          if (!this.ST[s] || this.SH[s] < cy - 0.4) continue;
          const o = s * 6;
          if (segDistSq(x, y, S[o], S[o + 1], S[o + 2], S[o + 3]) < rad * rad) return true;
          // inside the polygon (camera far inside a building)
        }
        for (let k = this.cStart[ci], e = this.cStart[ci + 1]; k < e; k++) {
          const c = this.cItems[k];
          if (!this.CT[c] || this.CH[c] < cy - 0.4) continue;
          if ((x - this.C[c * 3]) ** 2 + (y - this.C[c * 3 + 1]) ** 2 < (rad + this.C[c * 3 + 2]) ** 2) return true;
        }
      }
    }
    return false;
  }

  /** True when the point is inside a tall polygon (used so the camera never sits inside a building). */
  insideTall(x: number, y: number): boolean {
    for (const pl of this.polys) if (pl.tall && inPoly(x, y, pl.pts)) return true;
    return false;
  }
}

const _out = { x: 0, y: 0 };

let _best = 0;
function testSeg(S: ArrayLike<number>, o: number, x: number, y: number, r: number, thick: number) {
  const ax = S[o], ay = S[o + 1];
  const dx = S[o + 2] - ax, dy = S[o + 3] - ay;
  const l2 = dx * dx + dy * dy;
  let t = ((x - ax) * dx + (y - ay) * dy) / l2;
  const nx = S[o + 4], ny = S[o + 5];
  let d: number;
  let ux: number, uy: number;
  if (t > 0 && t < 1) {
    // beside the edge: signed distance along the outward normal (negative = inside the polygon)
    const sd = (x - ax) * nx + (y - ay) * ny;
    if (sd >= r || sd < -Math.min(r + 0.6, thick * 0.5 + 0.02)) return;
    d = r - sd;
    ux = nx;
    uy = ny;
  } else {
    t = t <= 0 ? 0 : 1;
    const qx = ax + dx * t, qy = ay + dy * t;
    const vx = x - qx, vy = y - qy;
    const dd = Math.hypot(vx, vy);
    if (dd >= r) return;
    if (dd > EPS) {
      const side = vx * nx + vy * ny;
      if (side < -1e-9 && dd < 1e-3) {
        ux = nx; uy = ny; d = r + dd;
      } else {
        ux = vx / dd; uy = vy / dd; d = r - dd;
      }
    } else {
      ux = nx; uy = ny; d = r;
    }
  }
  if (d > _best) {
    _best = d;
    _out.x = ux * (d + SKIN);
    _out.y = uy * (d + SKIN);
  }
}
function testCirc(cx: number, cy: number, cr: number, x: number, y: number, r: number) {
  const vx = x - cx, vy = y - cy;
  const dd = Math.hypot(vx, vy);
  const d = r + cr - dd;
  if (d > _best) {
    _best = d;
    if (dd > EPS) {
      _out.x = (vx / dd) * (d + SKIN);
      _out.y = (vy / dd) * (d + SKIN);
    } else {
      _out.x = d + SKIN;
      _out.y = 0;
    }
  }
}

function segDistSq(px: number, py: number, ax: number, ay: number, bx: number, by: number): number {
  const dx = bx - ax;
  const dy = by - ay;
  const l2 = dx * dx + dy * dy;
  const t = l2 > 0 ? Math.max(0, Math.min(1, ((px - ax) * dx + (py - ay) * dy) / l2)) : 0;
  const qx = ax + t * dx - px;
  const qy = ay + t * dy - py;
  return qx * qx + qy * qy;
}

export function inPoly(x: number, y: number, poly: readonly Pt[]): boolean {
  let inside = false;
  for (let i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    const xi = poly[i][0], yi = poly[i][1], xj = poly[j][0], yj = poly[j][1];
    if (yi > y !== yj > y && x < ((xj - xi) * (y - yi)) / (yj - yi) + xi) inside = !inside;
  }
  return inside;
}

/** Corners of an oriented box: centre, length w along the heading a, width d across. */
export function obbCorners(x: number, y: number, w: number, d: number, a: number): Pt[] {
  const c = Math.cos(a);
  const s = Math.sin(a);
  const hw = w / 2;
  const hd = d / 2;
  return [
    [x - hw * c + hd * s, y - hw * s - hd * c],
    [x + hw * c + hd * s, y + hw * s - hd * c],
    [x + hw * c - hd * s, y + hw * s + hd * c],
    [x - hw * c - hd * s, y - hw * s + hd * c],
  ];
}

/**
 * Exact (brute force, no hash) check used by the stress test: is a circle clear of every static collider?
 * Returns the smallest clearance (negative = overlapping). Polygons: distance to the boundary, or minus the depth when inside.
 */
export function clearance(world: CollisionWorld, x: number, y: number): { min: number; who: string } {
  let min = Infinity;
  let who = '';
  for (const c of world.circs) {
    const d = Math.hypot(x - c.x, y - c.y) - c.r;
    if (d < min) { min = d; who = c.id; }
  }
  for (const pl of world.polys) {
    let d = Infinity;
    for (let i = 0; i < pl.pts.length; i++) {
      const a = pl.pts[i];
      const b = pl.pts[(i + 1) % pl.pts.length];
      d = Math.min(d, Math.sqrt(segDistSq(x, y, a[0], a[1], b[0], b[1])));
    }
    if (inPoly(x, y, pl.pts)) d = -d;
    if (d < min) { min = d; who = pl.id; }
  }
  return { min, who };
}
