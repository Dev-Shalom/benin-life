// Free roam: the look of the player's own vehicle. The body, wheels that steer and spin, a blob shadow, tail / brake lights and headlight
// cones come from the drive scene's own kit (drive3d/engine/vehicles.ts, props.ts), so the car looks exactly like it does on a trip.
import {
  AdditiveBlending,
  CanvasTexture,
  DoubleSide,
  Group,
  InstancedMesh,
  Matrix4,
  Mesh,
  MeshBasicMaterial,
  MeshLambertMaterial,
  PlaneGeometry,
  Quaternion,
  Vector3,
} from 'three';
import type { VehicleKind } from '../../drive3d/model';
import { buildCockpit, type Cockpit } from '../../drive3d/engine/props';
import { unitWheelGeometry, vehicleKit } from '../../drive3d/engine/vehicles';
import type { CarKind, CarState } from '../carphys';

export const KIND_OF: Record<VehicleKind, CarKind> = { sedan: 'sedan', suv: 'suv', pickup: 'pickup', moto: 'moto', bike: 'bike', keke: 'sedan', bus: 'suv' };

function radial(): CanvasTexture {
  const cv = document.createElement('canvas');
  cv.width = cv.height = 64;
  const g = cv.getContext('2d')!;
  const r = g.createRadialGradient(32, 32, 2, 32, 32, 31);
  r.addColorStop(0, 'rgba(0,0,0,0.55)');
  r.addColorStop(1, 'rgba(0,0,0,0)');
  g.fillStyle = r;
  g.fillRect(0, 0, 64, 64);
  return new CanvasTexture(cv);
}

function beam(): CanvasTexture {
  const cv = document.createElement('canvas');
  cv.width = 32;
  cv.height = 128;
  const g = cv.getContext('2d')!;
  const gr = g.createLinearGradient(0, 128, 0, 0);
  gr.addColorStop(0, 'rgba(255,240,200,0.85)');
  gr.addColorStop(1, 'rgba(255,240,200,0)');
  g.fillStyle = gr;
  g.fillRect(0, 0, 32, 128);
  const gx = g.createLinearGradient(0, 0, 32, 0);
  gx.addColorStop(0, 'rgba(0,0,0,1)');
  gx.addColorStop(0.5, 'rgba(0,0,0,0)');
  gx.addColorStop(1, 'rgba(0,0,0,1)');
  g.globalCompositeOperation = 'destination-out';
  g.fillStyle = gx;
  g.fillRect(0, 0, 32, 128);
  return new CanvasTexture(cv);
}

export class CarRig {
  /** Positioned and yawed every frame; children are in the model's own frame (nose = -z). */
  readonly group = new Group();
  private rig = new Group();
  readonly body: Mesh;
  private wheels: InstancedMesh;
  private wheelSpec: { x: number; z: number; r: number; wid: number; front: boolean }[];
  private shadow: Mesh;
  private beamMat: MeshBasicMaterial;
  private beams: Mesh[] = [];
  private tailMat: MeshBasicMaterial;
  private tails: Mesh[] = [];
  readonly cockpit: Cockpit;
  readonly kind: VehicleKind;
  private owned: { dispose(): void }[] = [];
  private m4 = new Matrix4();
  private q = new Quaternion();
  private qs = new Quaternion();
  private v3 = new Vector3();
  private s3 = new Vector3();
  private ax = new Vector3(1, 0, 0);
  private ay = new Vector3(0, 1, 0);
  readonly bodyMat: MeshLambertMaterial;
  /** Half-length / width of the model (m). */
  readonly half: { l: number; w: number };

  /** `lite` = another player's car: no cockpit / dashboard. */
  constructor(kind: VehicleKind, color: number, lite = false) {
    this.kind = kind;
    const kit = vehicleKit(kind);
    const own = <T extends { dispose(): void }>(o: T) => (this.owned.push(o), o);
    this.bodyMat = own(new MeshLambertMaterial({ vertexColors: true, color }));
    this.body = new Mesh(kit.body, this.bodyMat);
    this.rig.add(this.body);
    this.group.add(this.rig);
    const wheelGeo = own(unitWheelGeometry());
    const wheelMat = own(new MeshLambertMaterial({ vertexColors: true }));
    this.wheelSpec = kit.wheels;
    this.wheels = new InstancedMesh(wheelGeo, wheelMat, Math.max(1, kit.wheels.length));
    this.wheels.frustumCulled = false;
    this.rig.add(this.wheels);
    kit.body.computeBoundingBox();
    const bb = kit.body.boundingBox!;
    this.half = { l: (bb.max.z - bb.min.z) / 2, w: (bb.max.x - bb.min.x) / 2 };
    const wide = kind === 'moto' || kind === 'bike';
    this.shadow = new Mesh(own(new PlaneGeometry(this.half.w * 2 + 1.2, this.half.l * 2 + 1.6)), own(new MeshBasicMaterial({ map: own(radial()), transparent: true, depthWrite: false })));
    this.shadow.rotation.x = -Math.PI / 2;
    this.shadow.position.y = 0.07;
    this.group.add(this.shadow);
    // headlight cones on the road (only at night)
    this.beamMat = own(new MeshBasicMaterial({ map: own(beam()), transparent: true, depthWrite: false, blending: AdditiveBlending, opacity: 0 }));
    const bg = own(new PlaneGeometry(2.6, 16));
    for (const x of wide ? [0] : [-0.62, 0.62]) {
      const b = new Mesh(bg, this.beamMat);
      b.rotation.x = -Math.PI / 2;
      b.position.set(x * 1.4, 0.09, bb.min.z - 8);
      this.group.add(b);
      this.beams.push(b);
    }
    // brake / tail lights
    this.tailMat = own(new MeshBasicMaterial({ color: '#e0352b', transparent: true, opacity: 0, depthWrite: false, side: DoubleSide }));
    const lamp = own(new PlaneGeometry(0.34, 0.15));
    const lampY = bb.min.y + (bb.max.y - bb.min.y) * 0.52;
    for (const sx of wide ? [0] : [-1, 1]) {
      const t = new Mesh(lamp, this.tailMat);
      t.position.set(sx * Math.max(0.3, this.half.w) * 0.72, lampY, bb.max.z + 0.02);
      this.rig.add(t);
      this.tails.push(t);
    }
    this.cockpit = lite ? (null as unknown as Cockpit) : buildCockpit(kind);
    this.cockpit?.setLook(color, 0);
  }

  /** Put the car at its pose. dark = 0..1 night, headlights = lamps on. */
  setPose(c: CarState, dark: number, headlights: boolean) {
    this.group.position.set(c.x, 0, c.y);
    this.group.rotation.y = -c.h - Math.PI / 2;
    this.rig.rotation.z = c.roll;
    this.rig.rotation.x = -c.pitch;
    this.rig.position.y = 0.02 + Math.abs(c.roll) * 0.4;
    const spec = this.wheelSpec;
    for (let i = 0; i < spec.length; i++) {
      const w = spec[i];
      this.q.setFromAxisAngle(this.ay, w.front ? -c.steer : 0);
      this.qs.setFromAxisAngle(this.ax, c.spin);
      this.q.multiply(this.qs);
      this.m4.compose(this.v3.set(w.x, w.r, w.z), this.q, this.s3.set(w.wid, w.r, w.r));
      this.wheels.setMatrixAt(i, this.m4);
    }
    this.wheels.instanceMatrix.needsUpdate = true;
    this.beamMat.opacity = headlights ? Math.min(1, dark * 1.3) * 0.7 : 0;
    this.tailMat.opacity = c.braking ? 0.95 : headlights && dark > 0.3 ? 0.55 : 0;
    this.cockpit?.setLook(this.bodyMat.color.getHex(), dark);
  }

  dispose() {
    this.cockpit?.dispose();
    for (const o of this.owned) o.dispose();
    this.wheels.dispose();
  }
}
