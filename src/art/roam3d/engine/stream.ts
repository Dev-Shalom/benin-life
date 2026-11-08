// Free roam: streams the city's 3D chunks around the player. Detailed chunks (windows, doors, signs, props) are built a little at a time
// (a generator, a few milliseconds a frame) nearest-first and biased towards where the player is heading; chunks that fall behind are
// disposed (geometry only: the materials and the sign atlas are shared). Beyond the detail radius a cheap merged-box backdrop shows the
// horizon. Trees, tree shadows and lamp pools are instanced meshes shared by all chunks and refilled when a chunk comes or goes.
import { DynamicDrawUsage, Group, IcosahedronGeometry, CylinderGeometry, InstancedMesh, Matrix4, MeshBasicMaterial, MeshLambertMaterial, Color, type BufferGeometry } from 'three';
import { STREAM } from '../area';
import type { ChunkData } from '../chunks';
import type { RoamWorld } from '../world';
import { buildChunkGen, buildFarChunk, flatDisc, softDisc, type ChunkMesh, type Kit } from './street';

interface Entry {
  detail?: ChunkMesh;
  far?: ChunkMesh;
}

interface Job {
  ck: ChunkData;
  gen: Generator<void, ChunkMesh>;
  ms: number;
}

export interface StreamStats {
  detail: number;
  far: number;
  building: boolean;
  queued: number;
  /** Longest single slice of work and the average slice (ms) since the last reset. */
  maxSliceMs: number;
  avgSliceMs: number;
  /** Total CPU time spent building the last finished detail chunks (ms). */
  lastChunkMs: number;
  avgChunkMs: number;
  built: number;
  disposed: number;
  tris: number;
  calls: number;
}

export class Streamer {
  readonly root = new Group();
  readonly entries = new Map<number, Entry>();
  readonly canopy: InstancedMesh;
  readonly trunks: InstancedMesh;
  readonly treeBlobs: InstancedMesh;
  readonly pools: InstancedMesh;
  readonly poolMat: MeshBasicMaterial;
  readonly blobMat: MeshBasicMaterial;
  readonly flat: BufferGeometry;
  private owned: { dispose(): void }[] = [];
  private W: RoamWorld;
  private kit: Kit;
  private job: Job | null = null;
  private treesDirty = false;
  private slotOf: Int32Array;
  private hidden: Uint8Array;
  private canopyMat: Float32Array;
  private zero = new Matrix4().makeScale(0, 0, 0);
  private tmpM = new Matrix4();
  private detailR: number;
  private farR: number;
  private sliceN = 0;
  private sliceSum = 0;
  private stat = { maxSlice: 0, lastChunk: 0, chunkSum: 0, built: 0, disposed: 0 };
  private lamps = new Map<number, Float32Array>();

  constructor(W: RoamWorld, kit: Kit, low: boolean) {
    this.W = W;
    this.kit = kit;
    this.detailR = low ? STREAM.detail.low : STREAM.detail.high;
    this.farR = low ? STREAM.far.low : STREAM.far.high;
    const nTrees = Math.max(1, W.trees.length);
    const canopyGeo = new IcosahedronGeometry(1, 0);
    const canopyMat = new MeshLambertMaterial({ flatShading: true });
    this.canopy = new InstancedMesh(canopyGeo, canopyMat, nTrees);
    const trunkGeo = new CylinderGeometry(0.5, 0.7, 1, 5);
    trunkGeo.translate(0, 0.5, 0);
    const trunkMat = new MeshLambertMaterial({ color: '#7a5a3c', flatShading: true });
    this.trunks = new InstancedMesh(trunkGeo, trunkMat, nTrees);
    this.canopy.instanceMatrix.setUsage(DynamicDrawUsage);
    this.trunks.instanceMatrix.setUsage(DynamicDrawUsage);
    this.canopy.setColorAt(0, new Color('#5f9a4b'));
    this.canopy.count = 0;
    this.trunks.count = 0;
    this.canopy.frustumCulled = false;
    this.trunks.frustumCulled = false;
    this.flat = flatDisc();
    this.poolMat = new MeshBasicMaterial({ map: softDisc('255,214,130', 0.95, 0.4), transparent: true, depthWrite: false, opacity: 0, blending: 2 /* additive */ });
    this.pools = new InstancedMesh(this.flat, this.poolMat, Math.max(1, W.lamps.length + 64));
    this.pools.count = 0;
    this.pools.frustumCulled = false;
    this.pools.renderOrder = 3;
    this.blobMat = new MeshBasicMaterial({ map: softDisc('18,20,30', 0.5, 0.2), transparent: true, depthWrite: false });
    this.treeBlobs = new InstancedMesh(this.flat, this.blobMat, nTrees);
    this.treeBlobs.count = 0;
    this.treeBlobs.frustumCulled = false;
    this.treeBlobs.renderOrder = 2;
    this.root.add(this.canopy, this.trunks, this.pools, this.treeBlobs);
    this.owned.push(canopyGeo, canopyMat, trunkGeo, trunkMat, this.flat, this.poolMat, this.poolMat.map!, this.blobMat, this.blobMat.map!);
    this.slotOf = new Int32Array(nTrees).fill(-1);
    this.hidden = new Uint8Array(nTrees);
    this.canopyMat = new Float32Array(nTrees * 16);
  }

  private key(c: ChunkData) {
    return c.cy * 1000 + c.cx;
  }

  private dist(c: ChunkData, px: number, py: number) {
    const dx = Math.max(c.x0 - px, 0, px - c.x1), dy = Math.max(c.y0 - py, 0, py - c.y1);
    return Math.hypot(dx, dy);
  }

  /** All the chunks within `detail` of the player are built (so the street is whole round the player). */
  ready(px: number, py: number, within = 60): boolean {
    for (const c of this.W.chunks.list) {
      if (this.dist(c, px, py) > within) continue;
      if (!this.entries.get(this.key(c))?.detail) return false;
    }
    return true;
  }

  /**
   * Decide what is wanted and spend up to `budgetMs` building. (dirx, diry) = unit heading of the player / car (0, 0 when standing).
   * `burst` lets the first call build as much as it can.
   */
  update(px: number, py: number, dirx: number, diry: number, budgetMs: number) {
    const W = this.W;
    const list = W.chunks.list;
    const dR = this.detailR, fR = this.farR, hy = STREAM.hyst;
    // unload what fell behind
    for (const [k, e] of this.entries) {
      const c = list[(Math.floor(k / 1000)) * W.chunks.cols + (k % 1000)];
      const d = this.dist(c, px, py);
      if (e.detail && d > dR + hy) {
        this.removeDetail(c, e);
      }
      if (e.far && d > fR + hy) {
        this.root.remove(e.far.group);
        e.far.dispose();
        e.far = undefined;
      }
      if (!e.detail && !e.far) this.entries.delete(k);
    }
    // the backdrop: cheap, a couple a frame
    let farBudget = 2;
    for (const c of list) {
      if (farBudget <= 0) break;
      const d = this.dist(c, px, py);
      if (d > fR) continue;
      let e = this.entries.get(this.key(c));
      if (!e) this.entries.set(this.key(c), (e = {}));
      if (e.far) continue;
      e.far = buildFarChunk(this.kit, c);
      e.far.group.visible = !e.detail;
      this.root.add(e.far.group);
      farBudget--;
    }
    // the next detailed chunk: nearest first, a bias for where we are heading
    const t0 = performance.now();
    let guard = 0;
    while (performance.now() - t0 < budgetMs && guard++ < 400) {
      if (!this.job) {
        let best: ChunkData | null = null, bs = Infinity;
        for (const c of list) {
          const d = this.dist(c, px, py);
          if (d > dR) continue;
          if (this.entries.get(this.key(c))?.detail) continue;
          const cxm = (c.x0 + c.x1) / 2 - px, cym = (c.y0 + c.y1) / 2 - py;
          const cl = Math.hypot(cxm, cym) || 1;
          const ahead = (cxm * dirx + cym * diry) / cl;
          const sc = d - 55 * Math.max(0, ahead);
          if (sc < bs) { bs = sc; best = c; }
        }
        if (!best) break;
        this.job = { ck: best, gen: buildChunkGen(this.kit, best), ms: 0 };
      } else if (this.dist(this.job.ck, px, py) > dR + hy) {
        this.job = null; // fell out of range before it was done
        continue;
      }
      const s0 = performance.now();
      const r = this.job.gen.next();
      const dt = performance.now() - s0;
      this.job.ms += dt;
      this.sliceN++;
      this.sliceSum += dt;
      if (dt > this.stat.maxSlice) this.stat.maxSlice = dt;
      if (r.done) {
        const ck = this.job.ck;
        const mesh = r.value;
        let e = this.entries.get(this.key(ck));
        if (!e) this.entries.set(this.key(ck), (e = {}));
        e.detail = mesh;
        this.root.add(mesh.group);
        if (e.far) e.far.group.visible = false;
        this.stat.lastChunk = this.job.ms;
        this.stat.chunkSum += this.job.ms;
        this.stat.built++;
        this.lamps.set(this.key(ck), mesh.lamps);
        this.job = null;
        this.treesDirty = true;
      }
    }
    if (this.treesDirty) this.refill();
  }

  private removeDetail(c: ChunkData, e: Entry) {
    if (!e.detail) return;
    this.root.remove(e.detail.group);
    e.detail.dispose();
    e.detail = undefined;
    this.lamps.delete(this.key(c));
    if (e.far) e.far.group.visible = true;
    this.treesDirty = true;
    this.stat.disposed++;
  }

  /** Rewrite the shared instanced meshes from the loaded chunks. */
  private refill() {
    this.treesDirty = false;
    const cm = this.canopy.instanceMatrix.array as Float32Array;
    const tm = this.trunks.instanceMatrix.array as Float32Array;
    const bm = this.treeBlobs.instanceMatrix.array as Float32Array;
    const col = this.canopy.instanceColor!.array as Float32Array;
    this.slotOf.fill(-1);
    let n = 0;
    const m4 = this.tmpM;
    for (const e of this.entries.values()) {
      const d = e.detail;
      if (!d) continue;
      for (let k = 0; k < d.treeIdx.length; k++) {
        const g = d.treeIdx[k];
        this.slotOf[g] = n;
        for (let j = 0; j < 16; j++) this.canopyMat[g * 16 + j] = d.treeMat[k * 32 + j];
        if (this.hidden[g]) this.zero.toArray(cm, n * 16);
        else for (let j = 0; j < 16; j++) cm[n * 16 + j] = d.treeMat[k * 32 + j];
        for (let j = 0; j < 16; j++) tm[n * 16 + j] = d.treeMat[k * 32 + 16 + j];
        col[n * 3] = d.treeCol[k * 3]; col[n * 3 + 1] = d.treeCol[k * 3 + 1]; col[n * 3 + 2] = d.treeCol[k * 3 + 2];
        const r = d.treeInfo[k * 3 + 2] * 2.25;
        m4.makeScale(r, 1, r);
        m4.setPosition(d.treeInfo[k * 3], 0.09, d.treeInfo[k * 3 + 1]);
        m4.toArray(bm, n * 16);
        n++;
      }
    }
    this.canopy.count = this.trunks.count = this.treeBlobs.count = n;
    this.canopy.instanceMatrix.needsUpdate = true;
    this.trunks.instanceMatrix.needsUpdate = true;
    this.treeBlobs.instanceMatrix.needsUpdate = true;
    this.canopy.instanceColor!.needsUpdate = true;
    // lamp pools
    const pm = this.pools.instanceMatrix.array as Float32Array;
    let pn = 0;
    for (const arr of this.lamps.values()) {
      for (let k = 0; k < arr.length; k += 2) {
        if (pn >= this.pools.instanceMatrix.count) break;
        m4.makeScale(11, 1, 11);
        m4.setPosition(arr[k], 0.1, arr[k + 1]);
        m4.toArray(pm, pn * 16);
        pn++;
      }
    }
    this.pools.count = pn;
    this.pools.instanceMatrix.needsUpdate = true;
  }

  /** Hide / show one tree canopy (the camera fades trees that would fill the screen). */
  treeFade(g: number, hide: boolean) {
    if ((this.hidden[g] === 1) === hide) return;
    this.hidden[g] = hide ? 1 : 0;
    const slot = this.slotOf[g];
    if (slot < 0) return;
    const arr = this.canopy.instanceMatrix.array as Float32Array;
    if (hide) this.zero.toArray(arr, slot * 16);
    else for (let j = 0; j < 16; j++) arr[slot * 16 + j] = this.canopyMat[g * 16 + j];
    this.canopy.instanceMatrix.needsUpdate = true;
  }

  /** Visit the trees of the loaded chunks that lie within r of the point (global index, x, y, canopy radius). */
  eachTreeNear(px: number, py: number, r: number, f: (g: number, x: number, y: number, rad: number) => void) {
    const list = this.W.chunks.list;
    for (const [k, e] of this.entries) {
      const d = e.detail;
      if (!d || d.treeIdx.length === 0) continue;
      const c = list[(Math.floor(k / 1000)) * this.W.chunks.cols + (k % 1000)];
      if (this.dist(c, px, py) > r) continue;
      for (let i = 0; i < d.treeIdx.length; i++) {
        const x = d.treeInfo[i * 3], y = d.treeInfo[i * 3 + 1];
        if (Math.abs(x - px) > r || Math.abs(y - py) > r) continue;
        f(d.treeIdx[i], x, y, d.treeInfo[i * 3 + 2]);
      }
    }
  }

  stats(): StreamStats {
    let detail = 0, far = 0, tris = 0, calls = 0;
    for (const e of this.entries.values()) {
      if (e.detail) { detail++; tris += e.detail.tris; calls += e.detail.calls; }
      if (e.far) far++;
    }
    return {
      detail, far, building: Boolean(this.job), queued: 0,
      maxSliceMs: this.stat.maxSlice, avgSliceMs: this.sliceN ? this.sliceSum / this.sliceN : 0,
      lastChunkMs: this.stat.lastChunk, avgChunkMs: this.stat.built ? this.stat.chunkSum / this.stat.built : 0,
      built: this.stat.built, disposed: this.stat.disposed, tris, calls,
    };
  }

  resetSliceStats() {
    this.stat.maxSlice = 0;
    this.sliceN = 0;
    this.sliceSum = 0;
  }

  /** Drop everything that is built (for a teleport far away): the next update rebuilds round the new spot. */
  flush() {
    this.job = null;
    for (const [k, e] of this.entries) {
      const c = this.W.chunks.list[(Math.floor(k / 1000)) * this.W.chunks.cols + (k % 1000)];
      this.removeDetail(c, e);
    }
    this.refill();
  }

  dispose() {
    this.job = null;
    for (const e of this.entries.values()) {
      e.detail?.dispose();
      e.far?.dispose();
    }
    this.entries.clear();
    for (const o of this.owned) o.dispose();
    this.canopy.dispose();
    this.trunks.dispose();
    this.pools.dispose();
    this.treeBlobs.dispose();
    this.kit.dispose();
  }
}
