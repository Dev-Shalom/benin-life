// P1: recognisable low-poly cars for the dealer showrooms, all procedural (no downloaded assets).
// Each model is built at real size (metres, front = +z, ground = y 0) and scaled by `s` into the
// HomeBuilder's current frame, so it merges into the place's few meshes like every other prop.
// Bodies are side profiles extruded across the car (ExtrudeGeometry with a small chamfer), plus a
// greenhouse (tinted glass + a body-colour roof band + pillars), wheels, lights (glow layer) and the
// details that make each one read: the AMG Panamericana grille, the G-Class spare wheel and round lamps,
// the Urus hexagons and Y lamps, the Cybertruck wedge and light bar, the Escalade's tall lamps and chrome.
import { ExtrudeGeometry, Shape, TorusGeometry, Vector2 } from 'three';
import type { HomeBuilder, BoxOpt } from '../../home3d/engine/build';

type B = HomeBuilder;
type P = [number, number]; // (z, y) in a side profile

export type LuxCar = 'gle63' | 'g63' | 'urus' | 'cybertruck' | 'escalade' | 'c300' | 'camry';

const TYRE = '#1b1c1f';
const GLASS = '#2e3d4e';
const CHROME = '#d9dde2';
const BLACKP = '#121316';
const HEAD = '#f4f7ff';
const TAIL = '#e0242c';
const AMBER = '#ffb030';

/** A semicircle (or polygon with n sides: 3 = hex-ish) cut out of the bottom edge for a wheel arch. */
function arch(zc: number, yb: number, r: number, n = 6): P[] {
  const pts: P[] = [];
  for (let i = 0; i <= n; i++) {
    const a = (i / n) * Math.PI;
    pts.push([zc + r * Math.cos(a), yb + r * Math.sin(a)]);
  }
  return pts;
}

/** Scaled drawing helpers in the builder's current frame. */
function kit(b: B, s: number) {
  const box = (w: number, h: number, d: number, x: number, y: number, z: number, c: string, o: BoxOpt = {}) =>
    b.box(w * s, h * s, d * s, x * s, y * s, z * s, c, { seg: 1, ...o });
  const cyl = (rt: number, rb: number, h: number, x: number, y: number, z: number, c: string, o: { seg?: number; rx?: number; ry?: number; rz?: number; layer?: 'solid' | 'glow' } = {}) =>
    b.cyl(rt * s, rb * s, h * s, x * s, y * s, z * s, c, { seg: o.seg ?? 12, rx: o.rx, ry: o.ry, rz: o.rz, layer: o.layer });
  /** Extrude a side profile (z, y) across the car: width w centred at x. */
  const slab = (prof: P[], w: number, x: number, c: string, o: BoxOpt & { bevel?: number } = {}) => {
    const sh = new Shape(prof.map(([z, y]) => new Vector2(z * s, y * s)));
    const bev = (o.bevel ?? 0.03) * s;
    const g = new ExtrudeGeometry(sh, { depth: Math.max(0.001, w * s - 2 * bev), bevelEnabled: bev > 0, bevelThickness: bev, bevelSize: bev, bevelSegments: 1, steps: 1, curveSegments: 3 });
    g.rotateY(-Math.PI / 2);
    g.translate((w * s) / 2 - bev, 0, 0);
    b.geo(g, x * s, 0, 0, c, { mat: 'plain', ...o });
  };
  /** A profile chain shifted down by t, as a closed band polygon (roof caps, pillars). */
  const band = (chain: P[], t: number): P[] => [...chain, ...chain.slice().reverse().map(([z, y]) => [z, y - t] as P)];
  /** Wheel on both sides: tyre + rim on the outer face. */
  const wheels = (zs: number[], tx: number, r: number, w: number, rim: string, spokes = 5) => {
    for (const zc of zs)
      for (const side of [-1, 1]) {
        const xo = side * tx;
        // cylinder bottom-centre, rotated about z: it runs from x towards -x by h
        cyl(r, r, w, xo + w / 2, r, zc, TYRE, { seg: 16, rz: Math.PI / 2 });
        const rx0 = side * (tx + w / 2 + 0.006);
        cyl(r * 0.64, r * 0.64, 0.02, rx0 + (side > 0 ? 0.02 : 0), r, zc, rim, { seg: 14, rz: Math.PI / 2 });
        for (let k = 0; k < spokes; k++) box(0.012, r * 0.58, 0.05, rx0 + side * 0.012, r, zc, rim, { rx: (k / spokes) * Math.PI * 2 });
        cyl(r * 0.16, r * 0.16, 0.03, rx0 + (side > 0 ? 0.035 : 0.005), r, zc, BLACKP, { seg: 8, rz: Math.PI / 2 });
      }
  };
  /** Greenhouse: tinted glass slab along `chain` (windscreen base .. rear base), a body roof band, pillars. */
  const cabin = (chain: P[], wg: number, body: string, o: { roof?: string; bz?: number[]; pillar?: number } = {}) => {
    slab(chain, wg, 0, GLASS, { bevel: 0.02 });
    const roof = chain.slice(1, -1);
    if (roof.length >= 2) slab(band(roof, 0.06), wg + 0.02, 0, o.roof ?? body, { bevel: 0.015 });
    const pw = o.pillar ?? 0.07;
    for (const side of [-1, 1]) {
      // A pillars + rear pillars follow the first / last segment
      slab(band([chain[0], chain[1]], 0.09), pw, side * (wg / 2 - pw / 2 + 0.012), o.roof ?? body, { bevel: 0.01 });
      slab(band([chain[chain.length - 2], chain[chain.length - 1]], 0.14), pw, side * (wg / 2 - pw / 2 + 0.012), o.roof ?? body, { bevel: 0.01 });
    }
    for (const bz of o.bz ?? []) {
      // B pillar: from the belt to the roof at bz
      const top = interp(chain, bz) - 0.05;
      const bot = Math.min(chain[0][1], chain[chain.length - 1][1]);
      for (const side of [-1, 1]) box(pw, top - bot, 0.09, side * (wg / 2 - pw / 2 + 0.012), bot, bz, o.roof ?? body);
    }
  };
  return { box, cyl, slab, band, wheels, cabin };
}

/** y of a (z-descending) chain at z. */
function interp(chain: P[], z: number): number {
  for (let i = 0; i < chain.length - 1; i++) {
    const [z0, y0] = chain[i];
    const [z1, y1] = chain[i + 1];
    if ((z <= z0 && z >= z1) || (z >= z0 && z <= z1)) return y0 + ((z - z0) / (z1 - z0 || 1)) * (y1 - y0);
  }
  return chain[0][1];
}

/** Lower body outline: bottom with two arches, then the given top chain (rear -> front). */
function lower(front: number, rear: number, yb: number, zf: number, zr: number, ra: number, top: P[], n = 6): P[] {
  return [
    [front, yb],
    ...arch(zf, yb, ra, n),
    ...arch(zr, yb, ra, n),
    [rear, yb],
    ...top,
  ];
}

// ---------------------------------------------------------------------------------------------------
// Models. Every function draws one car with its centre on the floor at the builder frame's origin.
// ---------------------------------------------------------------------------------------------------

/** Mercedes-AMG GLE 63 Coupe: sloping coupe roof, Panamericana grille (vertical slats), quad pipes. White. */
function gle63(b: B, s: number, paint = '#eef0f2') {
  const K = kit(b, s);
  const W = 2.0;
  K.slab(lower(2.47, -2.47, 0.36, 1.5, -1.43, 0.47, [
    [-2.47, 0.5], [-2.49, 0.95], [-2.3, 1.07], [-1.6, 1.11], [1.2, 1.06], [2.38, 0.9], [2.5, 0.64],
  ]), W, 0, paint, { bevel: 0.06 });
  K.cabin([[1.25, 1.04], [0.35, 1.62], [-0.5, 1.7], [-1.4, 1.55], [-2.15, 1.08]], W - 0.2, paint, { bz: [-0.25] });
  // Panamericana grille: black frame + vertical chrome slats, the star in the middle
  K.box(0.9, 0.42, 0.04, 0, 0.6, 2.49, BLACKP);
  for (let i = 0; i < 11; i++) K.box(0.025, 0.36, 0.03, -0.4 + i * 0.08, 0.63, 2.52, CHROME);
  K.cyl(0.07, 0.07, 0.02, 0, 0.81, 2.53, CHROME, { rx: Math.PI / 2, seg: 12 });
  // big lower intakes + splitter
  for (const sx of [-1, 1]) K.box(0.42, 0.22, 0.04, sx * 0.68, 0.4, 2.47, BLACKP, { rz: sx * 0.12 });
  K.box(1.7, 0.05, 0.12, 0, 0.36, 2.45, BLACKP);
  // slim angular headlights + DRL
  for (const sx of [-1, 1]) {
    K.box(0.5, 0.09, 0.05, sx * 0.7, 0.8, 2.42, HEAD, { layer: 'glow', rz: sx * -0.12 });
    K.box(0.42, 0.05, 0.03, sx * 0.74, 1.03, -2.45, TAIL, { layer: 'glow' });
  }
  K.box(1.2, 0.04, 0.03, 0, 1.03, -2.47, TAIL, { layer: 'glow' });
  // quad exhausts + diffuser
  K.box(1.5, 0.12, 0.06, 0, 0.38, -2.46, BLACKP);
  for (const sx of [-0.62, -0.46, 0.46, 0.62]) K.cyl(0.05, 0.05, 0.08, sx, 0.43, -2.54, CHROME, { rx: Math.PI / 2, seg: 8 });
  // mirrors, black side sills
  for (const sx of [-1, 1]) {
    K.box(0.18, 0.1, 0.12, sx * 1.05, 1.08, 0.95, paint);
    K.box(0.04, 0.12, 3.2, sx * 1.0, 0.36, 0.05, BLACKP);
  }
  K.wheels([1.5, -1.43], 0.86, 0.43, 0.26, '#2a2c30', 5);
}

/** Mercedes-AMG G 63 "G-Wagon": boxy, upright glass, round lamps, fender indicators, spare wheel. Matte grey. */
function g63(b: B, s: number, paint = '#5d6268') {
  const K = kit(b, s);
  const W = 1.95;
  K.slab(lower(2.36, -2.36, 0.42, 1.48, -1.41, 0.5, [
    [-2.36, 0.5], [-2.38, 1.16], [2.32, 1.16], [2.38, 0.96], [2.38, 0.5],
  ], 6), W, 0, paint, { bevel: 0.04 });
  K.cabin([[1.05, 1.15], [0.82, 1.86], [-2.24, 1.9], [-2.3, 1.15]], W - 0.1, paint, { bz: [-0.28, -1.38], pillar: 0.09 });
  // flat bonnet ridge + roof rails
  K.box(1.6, 0.04, 1.25, 0, 1.15, 1.7, paint);
  for (const sx of [-1, 1]) K.box(0.05, 0.05, 2.9, sx * 0.86, 1.95, -0.75, BLACKP);
  // grille with three horizontal louvres, the star
  K.box(1.0, 0.42, 0.05, 0, 0.66, 2.38, BLACKP);
  for (let i = 0; i < 3; i++) K.box(0.94, 0.04, 0.03, 0, 0.72 + i * 0.11, 2.42, CHROME);
  K.cyl(0.08, 0.08, 0.02, 0, 0.85, 2.44, CHROME, { rx: Math.PI / 2 });
  // round headlights in black rings, indicators on top of the fenders
  for (const sx of [-1, 1]) {
    K.cyl(0.17, 0.17, 0.04, sx * 0.7, 0.84, 2.36, BLACKP, { rx: Math.PI / 2, seg: 14 });
    K.cyl(0.13, 0.13, 0.03, sx * 0.7, 0.84, 2.39, HEAD, { rx: Math.PI / 2, seg: 14, layer: 'glow' });
    K.box(0.12, 0.07, 0.16, sx * 0.86, 1.16, 2.2, AMBER, { layer: 'glow' });
    // tall tail lamps
    K.box(0.14, 0.38, 0.04, sx * 0.86, 0.72, -2.39, TAIL, { layer: 'glow' });
    // fender flares + side steps + exposed door hinges
    K.box(0.06, 0.1, 1.2, sx * 0.99, 0.88, 1.48, BLACKP);
    K.box(0.06, 0.1, 1.2, sx * 0.99, 0.88, -1.41, BLACKP);
    K.box(0.22, 0.05, 1.6, sx * 1.02, 0.42, 0.04, BLACKP);
    for (const hz of [0.98, -0.32]) K.box(0.02, 0.08, 0.05, sx * 0.985, 1.0, hz, CHROME);
    // mirrors
    K.box(0.16, 0.14, 0.1, sx * 1.06, 1.24, 0.95, BLACKP);
  }
  // black bumpers
  K.box(2.0, 0.2, 0.14, 0, 0.42, 2.4, BLACKP);
  K.box(2.0, 0.2, 0.14, 0, 0.42, -2.42, BLACKP);
  // the spare wheel on the back door, in a matte cover with the star
  K.cyl(0.39, 0.39, 0.24, 0, 1.0, -2.36 - 0.24, TYRE, { rx: Math.PI / 2, seg: 16 });
  K.cyl(0.33, 0.33, 0.02, 0, 1.0, -2.62, paint, { rx: Math.PI / 2, seg: 16 });
  K.cyl(0.07, 0.07, 0.02, 0, 1.0, -2.64, CHROME, { rx: Math.PI / 2, seg: 10 });
  K.wheels([1.48, -1.41], 0.84, 0.44, 0.28, '#2e3034', 6);
}

/** Lamborghini Urus: low, wide, wedge nose, hexagon arches + grille, Y lamps. Giallo yellow, black roof. */
function urus(b: B, s: number, paint = '#f2c200') {
  const K = kit(b, s);
  const W = 2.02;
  K.slab(lower(2.55, -2.53, 0.34, 1.55, -1.45, 0.52, [
    [-2.53, 0.5], [-2.56, 0.88], [-2.4, 1.03], [-1.7, 1.09], [1.15, 1.02], [2.36, 0.86], [2.6, 0.6],
  ], 3), W, 0, paint, { bevel: 0.05 });
  K.cabin([[1.2, 1.0], [0.25, 1.5], [-0.62, 1.6], [-1.6, 1.42], [-2.25, 1.05]], W - 0.24, paint, { roof: BLACKP, bz: [-0.3] });
  // black cladding along the sills and arches
  for (const sx of [-1, 1]) {
    K.box(0.05, 0.16, 3.0, sx * 1.01, 0.34, 0.05, BLACKP);
    // Y headlights: two slim strokes each
    K.box(0.42, 0.05, 0.04, sx * 0.72, 0.82, 2.42, HEAD, { layer: 'glow', rz: sx * 0.22 });
    K.box(0.2, 0.05, 0.04, sx * 0.62, 0.74, 2.46, HEAD, { layer: 'glow', rz: sx * -0.55 });
    // triangle side intakes
    K.box(0.34, 0.2, 0.05, sx * 0.72, 0.45, 2.55, BLACKP, { rz: sx * 0.4 });
    // Y tail lamps
    K.box(0.4, 0.05, 0.04, sx * 0.7, 0.92, -2.55, TAIL, { layer: 'glow', rz: sx * -0.2 });
    K.box(0.18, 0.05, 0.04, sx * 0.58, 0.84, -2.56, TAIL, { layer: 'glow', rz: sx * 0.6 });
    K.box(0.16, 0.09, 0.12, sx * 1.08, 1.03, 0.95, BLACKP);
  }
  // hexagonal lower grille (6-sided cylinder) + the bull badge
  K.cyl(0.36, 0.36, 0.05, 0, 0.5, 2.55, BLACKP, { rx: Math.PI / 2, seg: 6 });
  K.cyl(0.05, 0.05, 0.02, 0, 0.82, 2.5, '#d9a441', { rx: Math.PI / 2, seg: 6 });
  K.box(1.3, 0.03, 0.03, 0, 0.98, -2.5, TAIL, { layer: 'glow' });
  // hex exhausts
  for (const sx of [-0.55, 0.55]) K.cyl(0.08, 0.08, 0.08, sx, 0.42, -2.6, CHROME, { rx: Math.PI / 2, seg: 6 });
  K.wheels([1.55, -1.45], 0.86, 0.46, 0.3, '#1d1f22', 6);
}

/** Tesla Cybertruck: one flat stainless wedge, trapezoid arches, a full-width light bar. Brushed steel. */
function cybertruck(b: B, s: number, paint = '#b9bec4') {
  const K = kit(b, s);
  const W = 2.03;
  const yb = 0.42;
  const trap = (zc: number): P[] => [[zc + 0.62, yb], [zc + 0.42, yb + 0.56], [zc - 0.42, yb + 0.56], [zc - 0.62, yb]];
  const body: P[] = [[2.84, yb], ...trap(1.83), ...trap(-1.8), [-2.84, yb], [-2.84, 1.22], [0.05, 1.79], [2.84, 1.02], [2.86, 0.72]];
  K.slab(body, W, 0, paint, { bevel: 0.015, mat: 'metal' });
  // tinted glass: windscreen panel on the front slope, side windows, rear glass strip
  const nose = (z: number) => 1.79 - (z - 0.05) * ((1.79 - 1.02) / 2.79);
  const roofY = (z: number) => 1.79 + (z - 0.05) * ((1.79 - 1.22) / 2.89);
  K.slab([[1.5, nose(1.5) + 0.02], [0.08, nose(0.08) + 0.02], [0.08, nose(0.08) - 0.015], [1.5, nose(1.5) - 0.015]], W - 0.18, 0, GLASS, { bevel: 0 });
  K.slab([[1.15, 1.2], [0.12, 1.7], [-1.3, roofY(-1.3) - 0.06], [-1.3, 1.2]], W + 0.012, 0, GLASS, { bevel: 0 });
  for (const sx of [-1, 1]) K.box(0.04, 0.48, 0.07, sx * (W / 2 + 0.01), 1.2, -0.35, paint, { mat: 'metal' });
  // the light bars
  K.box(W - 0.04, 0.035, 0.03, 0, 1.0, 2.84, HEAD, { layer: 'glow', rx: -0.27 });
  K.box(W - 0.04, 0.04, 0.03, 0, 1.18, -2.86, TAIL, { layer: 'glow' });
  // black cladding: sills, around the arches
  for (const sx of [-1, 1]) {
    K.box(0.05, 0.14, 2.4, sx * (W / 2 + 0.01), yb, 0, BLACKP);
    for (const zc of [1.83, -1.8]) K.box(0.05, 0.08, 0.86, sx * (W / 2 + 0.01), yb + 0.54, zc, BLACKP);
  }
  K.box(W, 0.16, 0.08, 0, yb, 2.84, BLACKP);
  // aero wheel covers
  K.wheels([1.83, -1.8], 0.86, 0.44, 0.28, '#5a5f66', 0);
}

/** Cadillac Escalade: tall, square shoulders, huge chrome grille, vertical lamps. Black. */
function escalade(b: B, s: number, paint = '#0f1012') {
  const K = kit(b, s);
  const W = 2.06;
  K.slab(lower(2.69, -2.68, 0.42, 1.62, -1.5, 0.52, [
    [-2.68, 0.5], [-2.7, 1.22], [-2.6, 1.3], [1.3, 1.27], [2.55, 1.2], [2.72, 1.04], [2.72, 0.5],
  ]), W, 0, paint, { bevel: 0.05 });
  K.cabin([[1.3, 1.25], [0.55, 1.88], [-2.5, 1.92], [-2.62, 1.28]], W - 0.12, paint, { bz: [-0.35, -1.45] });
  // big chrome-framed grille with a dark mesh, the crest
  K.box(1.24, 0.6, 0.05, 0, 0.6, 2.71, CHROME);
  K.box(1.12, 0.5, 0.05, 0, 0.65, 2.73, '#1e2024');
  for (let i = 0; i < 4; i++) K.box(1.1, 0.02, 0.03, 0, 0.72 + i * 0.1, 2.76, '#55595f');
  K.box(0.14, 0.12, 0.02, 0, 0.9, 2.78, '#c8a24a');
  for (const sx of [-1, 1]) {
    // vertical LED lamps + the horizontal lamp
    K.box(0.06, 0.5, 0.04, sx * 0.88, 0.55, 2.69, HEAD, { layer: 'glow' });
    K.box(0.28, 0.07, 0.04, sx * 0.78, 1.0, 2.66, HEAD, { layer: 'glow' });
    // tall tail lamps
    K.box(0.08, 0.7, 0.04, sx * 0.96, 0.62, -2.7, TAIL, { layer: 'glow' });
    // chrome side trim + running boards
    K.box(0.02, 0.04, 3.6, sx * 1.04, 0.84, 0.05, CHROME);
    K.box(0.22, 0.05, 2.0, sx * 1.1, 0.4, 0.05, '#1b1c1f');
    K.box(0.18, 0.14, 0.12, sx * 1.1, 1.3, 1.1, paint);
  }
  K.box(2.06, 0.18, 0.14, 0, 0.42, 2.72, '#1b1c1f');
  K.box(2.06, 0.18, 0.14, 0, 0.42, -2.72, '#1b1c1f');
  K.box(1.3, 0.04, 0.03, 0, 1.12, -2.71, CHROME);
  K.wheels([1.62, -1.5], 0.88, 0.46, 0.29, '#c9cdd2', 6);
}

/** A saloon (Mercedes C300 or Toyota Camry): long bonnet, short boot. */
function saloon(b: B, s: number, kind: 'c300' | 'camry', paint: string) {
  const K = kit(b, s);
  const W = 1.83;
  K.slab(lower(2.37, -2.36, 0.36, 1.43, -1.4, 0.42, [
    [-2.36, 0.46], [-2.38, 0.82], [-2.28, 0.97], [-1.55, 0.99], [1.05, 0.93], [2.26, 0.79], [2.4, 0.58],
  ]), W, 0, paint, { bevel: 0.06 });
  K.cabin([[1.05, 0.92], [0.22, 1.38], [-0.75, 1.43], [-1.55, 0.98]], W - 0.22, paint, { bz: [-0.25] });
  for (const sx of [-1, 1]) {
    K.box(0.4, 0.08, 0.04, sx * 0.62, 0.75, 2.33, HEAD, { layer: 'glow', rz: sx * -0.18 });
    K.box(0.34, 0.07, 0.04, sx * 0.66, 0.88, -2.38, TAIL, { layer: 'glow' });
    K.box(0.15, 0.08, 0.1, sx * 0.97, 0.95, 0.85, paint);
    K.box(0.03, 0.1, 2.8, sx * 0.92, 0.36, 0.05, kind === 'c300' ? CHROME : '#2a2c30');
  }
  if (kind === 'c300') {
    // the Mercedes grille: one chrome bar across, the big star in the middle
    K.box(0.74, 0.3, 0.04, 0, 0.5, 2.38, BLACKP, { rx: 0.1 });
    K.box(0.74, 0.04, 0.03, 0, 0.64, 2.41, CHROME);
    K.cyl(0.11, 0.11, 0.025, 0, 0.64, 2.42, CHROME, { rx: Math.PI / 2, seg: 14 });
    K.cyl(0.07, 0.07, 0.02, 0, 0.64, 2.44, BLACKP, { rx: Math.PI / 2, seg: 3 });
    K.wheels([1.43, -1.4], 0.8, 0.36, 0.23, '#c9cdd2', 5);
  } else {
    // Camry: slim upper grille, a wide black lower grille
    K.box(0.6, 0.06, 0.03, 0, 0.72, 2.37, CHROME);
    K.box(1.3, 0.28, 0.04, 0, 0.42, 2.4, BLACKP);
    K.cyl(0.07, 0.07, 0.02, 0, 0.72, 2.39, CHROME, { rx: Math.PI / 2, seg: 10 });
    K.wheels([1.43, -1.4], 0.8, 0.36, 0.23, '#9aa1a8', 5);
  }
}

/** Bajaj Boxer style motorcycle: red tank, long black seat, chrome exhaust, round headlamp. */
export function motorcycle(b: B, s: number, tank = '#b0202d') {
  const K = kit(b, s);
  for (const zc of [0.66, -0.66]) {
    const tg = new TorusGeometry(0.29 * s, 0.05 * s, 6, 16);
    b.geo(tg, 0, 0.3 * s, zc * s, TYRE, { ry: Math.PI / 2, mat: 'plain' });
    K.cyl(0.08, 0.08, 0.1, 0.05, 0.3, zc, '#8a9097', { rz: Math.PI / 2, seg: 8 });
    for (let k = 0; k < 6; k++) K.box(0.01, 0.25, 0.02, 0, 0.3, zc, '#8a9097', { rx: (k / 6) * Math.PI * 2 });
  }
  K.box(0.2, 0.26, 0.42, 0, 0.32, 0.02, '#4a4e54'); // engine
  K.box(0.26, 0.2, 0.42, 0, 0.72, 0.22, tank); // tank
  K.box(0.24, 0.08, 0.66, 0, 0.76, -0.3, BLACKP); // seat
  K.box(0.24, 0.12, 0.3, 0, 0.62, -0.62, tank); // tail
  K.box(0.06, 0.06, 0.9, 0, 0.55, 0.0, '#2a2c30', { rx: -0.25 }); // frame
  for (const sx of [-1, 1]) K.box(0.03, 0.56, 0.04, sx * 0.08, 0.32, 0.62, CHROME, { rx: -0.42 }); // fork
  K.cyl(0.015, 0.015, 0.7, 0.35, 1.0, 0.48, BLACKP, { rz: Math.PI / 2, seg: 6 }); // handlebar
  K.cyl(0.08, 0.08, 0.05, 0, 0.86, 0.66, HEAD, { rx: Math.PI / 2, seg: 10, layer: 'glow' });
  K.cyl(0.03, 0.04, 0.7, 0.14, 0.32, -0.62, CHROME, { rx: Math.PI / 2, seg: 8 }); // exhaust
  K.box(0.2, 0.03, 0.26, 0, 0.7, -0.82, '#2a2c30'); // rack
}

/** A roadster bicycle: thin wheels, diamond frame, saddle, bars. */
export function bicycle(b: B, s: number, frame = '#1f5a3a') {
  const K = kit(b, s);
  for (const zc of [0.52, -0.52]) {
    const tg = new TorusGeometry(0.33 * s, 0.022 * s, 5, 18);
    b.geo(tg, 0, 0.35 * s, zc * s, TYRE, { ry: Math.PI / 2, mat: 'plain' });
    for (let k = 0; k < 8; k++) K.box(0.006, 0.31, 0.012, 0, 0.35, zc, '#9aa1a8', { rx: (k / 8) * Math.PI * 2 });
  }
  K.box(0.035, 0.035, 0.62, 0, 0.72, 0.02, frame); // top tube
  K.box(0.035, 0.035, 0.72, 0, 0.36, 0.14, frame, { rx: -0.62 }); // down tube
  K.box(0.035, 0.5, 0.035, 0, 0.32, -0.22, frame, { rx: 0.25 }); // seat tube
  K.box(0.035, 0.035, 0.52, 0, 0.35, -0.3, frame); // chain stay
  K.box(0.035, 0.45, 0.035, 0, 0.36, 0.45, frame, { rx: -0.3 }); // fork
  K.box(0.12, 0.04, 0.22, 0, 0.84, -0.3, BLACKP); // saddle
  K.cyl(0.012, 0.012, 0.5, 0.25, 0.95, 0.4, BLACKP, { rz: Math.PI / 2, seg: 6 }); // bars
  K.cyl(0.05, 0.05, 0.03, 0, 0.32, -0.02, '#9aa1a8', { rz: Math.PI / 2, seg: 10 }); // chainring
}

/** Draw a luxury car at (x, z) with yaw `ry`, scale s, in absolute layout space (resets the builder frame). */
export function drawCar(b: B, kind: LuxCar, x: number, z: number, ry: number, s: number, paint?: string) {
  b.setFrame(x, 0, z, ry);
  switch (kind) {
    case 'gle63': return gle63(b, s, paint);
    case 'g63': return g63(b, s, paint);
    case 'urus': return urus(b, s, paint);
    case 'cybertruck': return cybertruck(b, s, paint);
    case 'escalade': return escalade(b, s, paint);
    case 'c300': return saloon(b, s, 'c300', paint ?? '#1f3a5f');
    case 'camry': return saloon(b, s, 'camry', paint ?? '#8e1b1b');
  }
}

/** Real names for the showroom tags / tests. */
export const CAR_NAMES: Record<LuxCar, string> = {
  gle63: 'Mercedes-AMG GLE 63 Coupe',
  g63: 'Mercedes-AMG G 63',
  urus: 'Lamborghini Urus',
  cybertruck: 'Tesla Cybertruck',
  escalade: 'Cadillac Escalade',
  c300: 'Mercedes-Benz C300',
  camry: 'Toyota Camry',
};
