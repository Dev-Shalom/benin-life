// Free roam: the other real players in the 3D street (docs/ROAM.md "Live players"). One layer owned by the scene:
//   * a rig per player in view (the nearest N: 12 on High, `low_max` on Low), built lazily, one per frame; walkers use the crowd rig of
//     the player's own avatar (it comes from the server), drivers the drive scene's car look in the owner's car colour (no cockpit);
//   * smooth motion from RemoteTrack (interpolated 200 ms in the past, extrapolated, snapped on a teleport), walk / run / idle poses by
//     speed, emotes on top, scale-in / scale-out when a player arrives or leaves;
//   * name tags: the scene projects each head to the screen and writes `bridge.tags`; the HUD draws the tags and bubbles as HTML;
//   * collision: walkers are soft circles (the player and the car are blocked early, nobody is pushed), cars are solid boxes that never
//     count as a hit; a push that goes nowhere for 1.5 s makes players passable for a moment (StuckGuard).
import { Group, Vector3, type PerspectiveCamera } from 'three';
import type { AvatarConfig } from '../../../lib/types';
import { defaultAvatar } from '../../avatar3d/catalog';
import { applyPose, capturePose, gaitFor, mixPose, poseGait, poseIdle, POSE_SIZE, resetRig, stepLength } from '../../avatar3d/engine/anim';
import { buildCrowdRig, type CrowdRig } from '../../avatar3d/engine/crowd';
import { vehicleFor } from '../../drive3d/model';
import { makeCarState, type CarState } from '../carphys';
import type { CollisionWorld, DynBox, DynCircle } from '../collide';
import { SPEED } from '../area';
import type { LiveBridge, LiveTag } from '../live/bridge';
import type { Remote } from '../live/client';
import { poseEmote } from '../live/emotes';
import { StuckGuard } from '../live/soft';
import { CarRig, KIND_OF } from './carview';
import { CAR_SPECS } from '../carphys';

const clamp = (v: number, a: number, b: number) => Math.max(a, Math.min(b, v));
const ease = (x: number) => x * x * (3 - 2 * x);

interface Slot {
  id: string;
  g: Group;
  rig: CrowdRig | null;
  car: CarRig | null;
  carKind: string;
  carState: CarState;
  carItem: string | null;
  bufA: Float32Array;
  bufB: Float32Array;
  salt: number;
  phase: number;
  gait: number;
  odo: number;
  hdg: number;
  steer: number;
  strideScale: number;
  scale: number;
  failed: boolean;
  /** Reused per frame: where it is drawn (for the colliders and shadows). */
  rec: { x: number; y: number; car: boolean; hl: number; hw: number; h: number; v: number };
  tag: LiveTag;
}

export interface OthersOpts {
  root: Group;
  low: boolean;
  bridge: () => LiveBridge | null;
  cam: PerspectiveCamera;
  size: () => { w: number; h: number };
}

const REMOTE_CIRCLE_ID = 880000;
const REMOTE_BOX_ID = 890000;

export class OthersLayer {
  readonly slots = new Map<string, Slot>();
  readonly guard = new StuckGuard(1.5, 2.5);
  /** Walkers in view as soft circles (rebuilt every frame). */
  private circles: DynCircle[] = [];
  private merged: DynCircle[] = [];
  private boxes: DynBox[] = [];
  private lastBuild = 0;
  private v = new Vector3();
  private o: OthersOpts;
  /** Simulation seconds (set by the scene). */
  simT = 0;
  passable = false;
  /** Remote positions refreshed this frame (map metres). */
  private pos = new Map<string, { x: number; y: number; car: boolean; hl: number; hw: number; h: number; v: number }>();
  private lastFrame = 0;
  private listBuf: Remote[] = [];
  private seenBuf = new Set<string>();
  private myTag: LiveTag = { id: 'me', x: 0, y: 0, d: 0, a: 1, s: 1 };

  constructor(o: OthersOpts) {
    this.o = o;
  }

  /* ---------------------------------------------------------------- per frame (rendering) */
  frame(dt: number, nowMs: number, me: { x: number; y: number }, meHead: { x: number; y: number; z: number } | null, dark: number) {
    const bridge = this.o.bridge();
    const client = bridge?.client ?? null;
    const o = this.o;
    this.pos.clear();
    if (!bridge) return;
    bridge.tags.length = 0;
    bridge.myTag = null;
    bridge.nearCount = 0;
    if (!client || client.status === 'idle' || client.status === 'off') {
      for (const s of this.slots.values()) { s.g.visible = false; if (s.car) s.car.group.visible = false; }
      bridge.drawn = 0;
      return;
    }
    client.prune(dt);
    const info = client.info;
    const buffer = info?.buffer_ms ?? 200;
    // the client already holds only the players it listens to (one cap for joining and drawing)
    const cap = client.maxShown();
    const list = this.listBuf;
    list.length = 0;
    for (const r of client.remotes.values()) {
      const t = r.track;
      if (t.has) t.sample(nowMs, buffer, dt);
      const x = t.has ? t.x : r.px, y = t.has ? t.y : r.py;
      r.dist = Math.hypot(x - me.x, y - me.y);
      list.push(r);
    }
    list.sort((a, b) => a.dist - b.dist);
    const { w, h } = o.size();
    const seen = this.seenBuf;
    seen.clear();
    let drawn = 0;
    for (let i = 0; i < list.length; i++) {
      const r = list[i];
      const show = i < cap && r.dist < 150;
      if (!show) continue;
      seen.add(r.id);
      const t = r.track;
      const car = t.has ? t.car : r.mode === 'car';
      let s: Slot | null | undefined = this.slots.get(r.id);
      if (!s) {
        // one new rig per frame at most (a crowd arriving must not stall a frame)
        if (nowMs - this.lastBuild < 30) continue;
        s = this.make(r);
        this.lastBuild = nowMs;
        if (!s) continue;
      }
      const x = t.has ? t.x : r.px, y = t.has ? t.y : r.py;
      const hd = t.has ? t.h : s.hdg;
      s.hdg = hd;
      // arrival / departure: scale in over 0.5 s, out over 0.8 s
      const k = r.leaving > 0 ? 1 - ease(clamp(r.leaving / 0.8, 0, 1)) : ease(clamp(r.born / 0.5, 0, 1));
      s.scale = clamp(k, 0, 1);
      const wantCar = car && Boolean(s.car || this.ensureCar(s, r));
      s.g.visible = s.scale > 0.02;
      if (s.car) s.car.group.visible = s.g.visible && wantCar;
      if (!s.g.visible) continue;
      s.g.scale.setScalar(Math.max(0.001, s.scale));
      s.g.position.set(x, 0, y);
      const near = r.dist < 28;
      const rec = s.rec;
      rec.x = x; rec.y = y; rec.car = wantCar; rec.hl = s.car?.half.l ?? 2.2; rec.hw = s.car?.half.w ?? 0.9; rec.h = hd; rec.v = t.speed * (t.reverse ? -1 : 1);
      this.pos.set(r.id, rec);
      if (wantCar && s.car) {
        if (s.rig) s.rig.ch.root.visible = false;
        // steering from the turn rate, the wheels roll with the distance drawn
        const dh = Math.atan2(Math.sin(hd - s.carState.h), Math.cos(hd - s.carState.h));
        const want = clamp(dt > 0 ? (dh / dt) * 0.16 : 0, -0.5, 0.5);
        s.steer += (want - s.steer) * Math.min(1, dt * 8);
        const cs = s.carState;
        cs.x = x; cs.y = y; cs.h = hd; cs.steer = s.steer; cs.spin += (t.odo - s.odo) / 0.34 * (t.reverse ? -1 : 1); cs.braking = t.brake;
        cs.roll = clamp(-s.steer * t.speed * 0.01, -0.06, 0.06);
        s.odo = t.odo;
        // the car group is positioned by setPose in world space, so the wrapper stays at the origin
        s.g.position.set(0, 0, 0);
        s.car.group.scale.setScalar(Math.max(0.001, s.scale));
        s.car.setPose(cs, dark, dark > 0.35);
      } else if (s.rig) {
        s.rig.ch.root.visible = true;
        s.g.rotation.y = Math.PI / 2 - hd;
        this.poseWalker(s, r, nowMs / 1000, dt, near);
      }
      // name tag
      const headY = wantCar ? 1.9 : 1.98;
      this.v.set(x, headY, y);
      this.v.project(o.cam);
      const d = r.dist;
      if (this.v.z < 1 && this.v.z > -1 && d < 75 && Math.abs(this.v.x) < 1.15 && Math.abs(this.v.y) < 1.15) {
        const tag = s.tag;
        tag.x = (this.v.x * 0.5 + 0.5) * w; tag.y = (-this.v.y * 0.5 + 0.5) * h; tag.d = d;
        tag.a = clamp((75 - d) / 25, 0, 1) * s.scale; tag.s = clamp(1.05 - d / 140, 0.72, 1);
        bridge.tags.push(tag);
      }
      drawn++;
      if (d < 12) bridge.nearCount++;
    }
    // slots of players no longer shown
    for (const [id, s] of this.slots) {
      if (!seen.has(id)) {
        const r = client.remotes.get(id);
        if (!r) this.free(id, s);
        else { s.g.visible = false; if (s.car) s.car.group.visible = false; }
      }
    }
    bridge.drawn = drawn;
    // my own bubble sits over my head
    if (meHead && client.myBubble) {
      this.v.set(meHead.x, meHead.y, meHead.z);
      this.v.project(o.cam);
      if (this.v.z < 1 && this.v.z > -1) {
        const m = this.myTag;
        m.x = (this.v.x * 0.5 + 0.5) * w; m.y = (-this.v.y * 0.5 + 0.5) * h;
        bridge.myTag = m;
      }
    }
    this.lastFrame = nowMs;
  }

  /* ---------------------------------------------------------------- building */
  private make(r: Remote): Slot | null {
    let rig: CrowdRig | null = null;
    let av: AvatarConfig;
    try {
      av = (r.avatar && typeof r.avatar === 'object' && (r.avatar as AvatarConfig).gender ? (r.avatar as AvatarConfig) : defaultAvatar('male')) as AvatarConfig;
      rig = buildCrowdRig(av, this.o.low ? 0.25 : 0.4);
    } catch {
      try {
        rig = buildCrowdRig(defaultAvatar('male'), 0.25);
      } catch {
        rig = null;
      }
    }
    const g = new Group();
    if (rig) g.add(rig.ch.root);
    g.visible = false;
    this.o.root.add(g);
    const tune = rig ? gaitFor(rig.ch, { speed: SPEED.walk, robeMult: 0.7 }) : { cruise: 1.9, strideScale: 1 };
    const s: Slot = {
      id: r.id, g, rig, car: null, carKind: '', carState: makeCarState(0, 0, 0), carItem: null, bufA: new Float32Array(POSE_SIZE), bufB: new Float32Array(POSE_SIZE),
      salt: Math.random() * 10, phase: Math.random(), gait: 0, odo: r.track.odo, hdg: 0, steer: 0, strideScale: tune.strideScale, scale: 0, failed: !rig,
      rec: { x: 0, y: 0, car: false, hl: 2.2, hw: 0.9, h: 0, v: 0 }, tag: { id: r.id, x: 0, y: 0, a: 0, d: 0, s: 1 },
    };
    this.slots.set(r.id, s);
    return s;
  }

  private ensureCar(s: Slot, r: Remote): boolean {
    if (s.car && s.carItem === (r.veh ?? '')) return true;
    if (s.car) { s.g.remove(s.car.group); s.car.dispose(); s.car = null; }
    try {
      const look = vehicleFor('car', r.veh);
      s.car = new CarRig(look.kind, look.color, true);
      s.carKind = KIND_OF[look.kind];
      s.carItem = r.veh ?? '';
      // the car lives in world space under the root (setPose positions it), not inside the walker's group
      this.o.root.add(s.car.group);
      s.carState = makeCarState(0, 0, 0);
      s.odo = r.track.odo;
      void CAR_SPECS;
      return true;
    } catch {
      return false;
    }
  }

  private free(id: string, s: Slot) {
    this.o.root.remove(s.g);
    s.rig?.dispose();
    if (s.car) { this.o.root.remove(s.car.group); s.car.dispose(); }
    this.slots.delete(id);
  }

  dispose() {
    for (const [id, s] of this.slots) this.free(id, s);
  }

  /* ---------------------------------------------------------------- poses */
  private poseWalker(s: Slot, r: Remote, t: number, dt: number, near: boolean) {
    const rig = s.rig;
    if (!rig) return;
    const ch = rig.ch;
    const tr = r.track;
    const moving = tr.speed > 0.3;
    s.gait = clamp(s.gait + (moving ? 1 : -1) * dt * 6, 0, 1);
    const moved = tr.odo - s.odo;
    s.odo = tr.odo;
    if (!near && ((Math.floor(t * 60) + s.salt * 7) | 0) % 2 !== 0) return; // far rigs animate every other frame
    const runK = clamp((tr.speed - 2.6) / (SPEED.run - 2.6), 0, 1);
    if (s.gait > 0.02) {
      const ss = s.strideScale * (1 + 0.7 * runK);
      s.phase += moved / (2 * stepLength(ch, Math.max(0.3, s.gait), ss));
      resetRig(ch);
      poseGait(ch, s.phase, s.gait, { strideScale: ss });
      if (runK > 0.05) {
        const rg = ch.rig;
        rg.chest.rotation.x += 0.2 * runK;
        rg.armL.rotation.x *= 1 + 0.9 * runK;
        rg.armR.rotation.x *= 1 + 0.9 * runK;
        rg.foreL.rotation.x -= 0.8 * runK;
        rg.foreR.rotation.x -= 0.8 * runK;
        rg.body.rotation.x = 0.08 * runK;
      }
      if (s.gait < 0.98) {
        capturePose(ch, s.bufB);
        poseIdle(ch, t, s.salt);
        capturePose(ch, s.bufA);
        applyPose(ch, mixPose(s.bufB, s.bufB, s.bufA, 1 - ease(s.gait)));
      }
    } else {
      poseIdle(ch, t, s.salt);
      if (tr.emote !== 0) poseEmote(ch, tr.emote, (performance.now() - tr.emoteAt) / 1000);
    }
  }

  /* ---------------------------------------------------------------- collision (called from the fixed step) */
  /** Walkers as soft circles for the car and the traffic (they brake early, nothing touches). */
  addPeople(out: { x: number; y: number; r: number }[], me: { x: number; y: number }) {
    for (const p of this.pos.values()) {
      if (p.car) continue;
      if (Math.abs(p.x - me.x) > 40 || Math.abs(p.y - me.y) > 40) continue;
      out.push({ x: p.x, y: p.y, r: 0.32 });
    }
  }

  /** Walkers as circles the walking player cannot enter; cars as boxes that block but never hurt. */
  addColliders(col: CollisionWorld, me: { x: number; y: number }, walking: boolean) {
    if (this.passable) return;
    let nc = 0, nb = 0;
    this.merged.length = 0;
    for (const c of col.dynCircles) this.merged.push(c);
    for (const [id, p] of this.pos) {
      if (Math.abs(p.x - me.x) > 25 || Math.abs(p.y - me.y) > 25) continue;
      if (p.car) {
        let b = this.boxes[nb];
        if (!b) b = this.boxes[nb] = { x: 0, y: 0, hl: 0, hw: 0, a: 0, id: 0, v: 0, remote: true };
        b.x = p.x; b.y = p.y; b.hl = p.hl; b.hw = p.hw; b.a = p.h; b.id = REMOTE_BOX_ID + nb; b.v = p.v; b.remote = true;
        col.dynBoxes.push(b);
        nb++;
      } else if (walking) {
        let c = this.circles[nc];
        if (!c) c = this.circles[nc] = { x: 0, y: 0, r: 0.34, id: 0 };
        c.x = p.x; c.y = p.y; c.r = 0.34; c.id = REMOTE_CIRCLE_ID + nc;
        this.merged.push(c);
        nc++;
      }
      void id;
    }
    this.circles.length = nc;
    if (nc > 0) col.dynCircles = this.merged;
  }

  /** The player asked for `wanted` m/s and got `real`: decide whether players are passable. Returns true while they are. */
  stuck(dt: number, me: { x: number; y: number }, wanted: number, real: number): boolean {
    let touching = false, overlapping = false;
    for (const p of this.pos.values()) {
      const d = Math.hypot(p.x - me.x, p.y - me.y);
      const reach = p.car ? Math.max(p.hl, p.hw) + 1.4 : 1.0;
      if (d < reach) touching = true;
      if (d < (p.car ? Math.min(p.hl, p.hw) + 0.3 : 0.7)) overlapping = true;
    }
    this.passable = this.guard.step(this.simT, dt, wanted, real, touching, overlapping);
    return this.passable;
  }

  /** Blob shadows for the players drawn (x, y, size). */
  eachBlob(cb: (x: number, y: number, sx: number, sz: number, a: number) => void) {
    for (const [id, p] of this.pos) {
      const s = this.slots.get(id);
      if (!s || !s.g.visible) continue;
      if (p.car) continue; // the car brings its own shadow
      cb(p.x, p.y, 1.0 * s.scale, 1.0 * s.scale, 0);
    }
  }

  count(): number {
    return this.pos.size;
  }
  debug() {
    const first = [...this.slots.values()][0];
    return { slots: this.slots.size, drawn: this.pos.size, passable: this.passable, last: this.lastFrame, armRz: first?.rig ? +first.rig.ch.rig.armR.rotation.z.toFixed(2) : null, gait: first?.gait ?? null, vis: first?.g.visible ?? null };
  }
}
