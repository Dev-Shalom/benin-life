// R5: road-following routes for the travel overlay. A graph is built once from the 2D map's roads
// (mapGeo ROADS + the Ring Road), then Dijkstra finds the way between the nearest road points.
// Pure maths in map space; no three.js.
import { RING, ROADS, spline, type Pt } from '../map/mapGeo';

interface Graph {
  xs: number[];
  ys: number[];
  adj: number[][];
}

let graph: Graph | null = null;

function build(): Graph {
  const xs: number[] = [];
  const ys: number[] = [];
  const adj: number[][] = [];
  const roadOf: number[] = [];
  const add = (x: number, y: number, road: number) => {
    xs.push(x);
    ys.push(y);
    adj.push([]);
    roadOf.push(road);
    return xs.length - 1;
  };
  const link = (a: number, b: number) => {
    if (a === b || adj[a].includes(b)) return;
    adj[a].push(b);
    adj[b].push(a);
  };
  const ringPts: Pt[] = [];
  for (let i = 0; i < 24; i++) {
    const a = (i / 24) * Math.PI * 2;
    ringPts.push([RING.x + Math.cos(a) * RING.r, RING.y + Math.sin(a) * RING.r]);
  }
  const lines: { pts: Pt[]; closed: boolean }[] = [{ pts: ringPts, closed: true }, ...ROADS.map((r) => ({ pts: r.pts, closed: false }))];
  lines.forEach((ln, ri) => {
    const sp = spline(ln.pts, ln.closed);
    const step = 9;
    const n = Math.max(2, Math.round(sp.length / step));
    let first = -1;
    let prev = -1;
    for (let k = 0; k <= n; k++) {
      if (ln.closed && k === n) break;
      const s = (k / n) * sp.length;
      // binary search the dense samples
      const S = sp.samples;
      let lo = 0;
      let hi = S.length - 1;
      while (hi - lo > 1) {
        const mid = (lo + hi) >> 1;
        if (S[mid].s < s) lo = mid;
        else hi = mid;
      }
      const id = add(S[hi].x, S[hi].y, ri);
      if (prev >= 0) link(prev, id);
      else first = id;
      prev = id;
    }
    if (ln.closed && first >= 0) link(prev, first);
  });
  // junctions: points of different roads close together
  const cell = 14;
  const grid = new Map<number, number[]>();
  const key = (cx: number, cy: number) => (cx + 100) * 1000 + (cy + 100);
  xs.forEach((x, i) => {
    const k = key(Math.floor(x / cell), Math.floor(ys[i] / cell));
    const arr = grid.get(k);
    if (arr) arr.push(i);
    else grid.set(k, [i]);
  });
  for (let i = 0; i < xs.length; i++) {
    const cx = Math.floor(xs[i] / cell);
    const cy = Math.floor(ys[i] / cell);
    for (let dx = -1; dx <= 1; dx++)
      for (let dy = -1; dy <= 1; dy++) {
        for (const j of grid.get(key(cx + dx, cy + dy)) ?? []) {
          if (j <= i || roadOf[j] === roadOf[i]) continue;
          if (Math.hypot(xs[i] - xs[j], ys[i] - ys[j]) < 9) link(i, j);
        }
      }
  }
  return { xs, ys, adj };
}

function nearest(g: Graph, x: number, y: number): number {
  let best = 0;
  let bd = Infinity;
  for (let i = 0; i < g.xs.length; i++) {
    const d = (g.xs[i] - x) ** 2 + (g.ys[i] - y) ** 2;
    if (d < bd) {
      bd = d;
      best = i;
    }
  }
  return best;
}

/** Polyline (map space) from one place to another along the roads. */
export function roadRoute(from: { x: number; y: number }, to: { x: number; y: number }): Pt[] {
  const g = (graph ??= build());
  const a = nearest(g, from.x, from.y);
  const b = nearest(g, to.x, to.y);
  const n = g.xs.length;
  const dist = new Float64Array(n).fill(Infinity);
  const prev = new Int32Array(n).fill(-1);
  const done = new Uint8Array(n);
  // small binary heap of [dist, node]
  const heap: [number, number][] = [[0, a]];
  dist[a] = 0;
  const push = (it: [number, number]) => {
    heap.push(it);
    let i = heap.length - 1;
    while (i > 0) {
      const p = (i - 1) >> 1;
      if (heap[p][0] <= heap[i][0]) break;
      [heap[p], heap[i]] = [heap[i], heap[p]];
      i = p;
    }
  };
  const pop = (): [number, number] => {
    const top = heap[0];
    const last = heap.pop()!;
    if (heap.length) {
      heap[0] = last;
      let i = 0;
      for (;;) {
        const l = 2 * i + 1;
        const r = l + 1;
        let m = i;
        if (l < heap.length && heap[l][0] < heap[m][0]) m = l;
        if (r < heap.length && heap[r][0] < heap[m][0]) m = r;
        if (m === i) break;
        [heap[m], heap[i]] = [heap[i], heap[m]];
        i = m;
      }
    }
    return top;
  };
  while (heap.length) {
    const [d, u] = pop();
    if (done[u]) continue;
    done[u] = 1;
    if (u === b) break;
    for (const v of g.adj[u]) {
      const nd = d + Math.hypot(g.xs[u] - g.xs[v], g.ys[u] - g.ys[v]);
      if (nd < dist[v]) {
        dist[v] = nd;
        prev[v] = u;
        push([nd, v]);
      }
    }
  }
  const out: Pt[] = [[to.x, to.y]];
  if (dist[b] < Infinity) {
    for (let u = b; u >= 0; u = prev[u]) out.push([g.xs[u], g.ys[u]]);
  }
  out.push([from.x, from.y]);
  out.reverse();
  return out;
}
