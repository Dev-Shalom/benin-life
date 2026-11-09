// Dev page for the shared vehicle library (dev server only, no session):
//   /dev/vehicles?m=sedan&cam=3q|side|front|rear|top|chase&night=1&c=c3c7cd      one vehicle close up
//   /dev/vehicles?view=lineup&cam=3q|top                                            every vehicle in a row
//   /dev/vehicles?view=showroom                                                     the dealer / garage cars (place3d builder)
//   /dev/vehicles?view=traffic&n=60                                                 instanced traffic, prints the frame time
// Optional: lod=0|1|2 (detail), kit=1 (wheels drawn separately like the player's own vehicle), tris=1 (print triangle counts).
import { useEffect, useRef } from 'react';
import {
  AmbientLight,
  Box3,
  Color,
  DirectionalLight,
  Fog,
  HemisphereLight,
  InstancedMesh,
  Matrix4,
  Mesh,
  MeshBasicMaterial,
  MeshLambertMaterial,
  PerspectiveCamera,
  PlaneGeometry,
  Scene,
  Vector3,
  WebGLRenderer,
  type BufferGeometry,
  DoubleSide,
} from 'three';
import { HomeBuilder } from '../../home3d/engine/build';
import { bicycle, drawCar, motorcycle, type LuxCar } from '../../place3d/engine/cars';
import { LAB_MODELS, labGeometry, labKit, labMaterial, labWheelGeometry, labTris, setVehicleRenderer } from './labApi';

export default function VehicleLab() {
  const ref = useRef<HTMLCanvasElement>(null);
  useEffect(() => {
    const q = new URLSearchParams(window.location.search);
    const cv = ref.current!;
    const renderer = new WebGLRenderer({ canvas: cv, antialias: true, preserveDrawingBuffer: true });
    renderer.setPixelRatio(Math.min(2, window.devicePixelRatio));
    setVehicleRenderer(renderer);
    const view = q.get('view') ?? 'one';
    const night = q.get('night') === '1';
    const lod = Number(q.get('lod') ?? 0) as 0 | 1 | 2;
    const sky = night ? new Color('#0c1424') : new Color('#bcd8ee');
    const scene = new Scene();
    scene.background = sky;
    scene.fog = new Fog(sky, 40, 140);
    scene.add(new HemisphereLight(night ? 0x4a5a7a : 0xe6f0fa, night ? 0x20242c : 0x8a8272, night ? 0.9 : 1.15));
    const sun = new DirectionalLight(night ? 0x8fa6d0 : 0xfff1d8, night ? 0.5 : 1.35);
    sun.position.set(-6, 10, 5);
    scene.add(sun);
    scene.add(new AmbientLight(0xffffff, 0.08));
    const ground = new Mesh(new PlaneGeometry(400, 400), new MeshLambertMaterial({ color: night ? '#2a2e36' : '#6b7280' }));
    ground.rotation.x = -Math.PI / 2;
    scene.add(ground);
    const cam = new PerspectiveCamera(32, 1, 0.1, 400);
    const disposers: (() => void)[] = [];
    const mats: ReturnType<typeof labMaterial>[] = [];
    const tint = new Color(`#${q.get('c') ?? 'b9bfc8'}`);
    const log: string[] = [];

    const addModel = (name: string, x: number, z: number, ry = 0, color = tint) => {
      const geo: BufferGeometry = labGeometry(name, lod);
      const mat = labMaterial(color);
      mat.glow.value = night ? 1.6 : 0.5;
      mats.push(mat);
      const m = new Mesh(geo, mat);
      m.position.set(x, 0, z);
      m.rotation.y = ry;
      scene.add(m);
      log.push(`${name}: ${labTris(geo)} tris`);
      return m;
    };

    const frame = (box: Box3, dir: Vector3, fit = 1.0) => {
      const c = box.getCenter(new Vector3());
      const s = box.getSize(new Vector3());
      const r = Math.max(s.x, s.y * 1.4, s.z) * 0.5 * fit;
      const aspect = cv.clientWidth / cv.clientHeight;
      const vf = (cam.fov * Math.PI) / 180;
      const d = Math.max(r / Math.sin(vf / 2) / Math.min(1, aspect) * 0.75, 3);
      cam.position.copy(c).addScaledVector(dir.normalize(), d);
      cam.lookAt(c);
    };

    const resize = () => {
      const w = cv.clientWidth;
      const h = cv.clientHeight;
      renderer.setSize(w, h, false);
      cam.aspect = w / h;
      cam.updateProjectionMatrix();
    };
    resize();

    const camDirs: Record<string, [number, number, number]> = {
      '3q': [0.62, 0.34, -0.72],
      '3qr': [0.62, 0.34, 0.72],
      side: [1, 0.12, 0],
      front: [0, 0.18, -1],
      rear: [0, 0.2, 1],
      top: [0.001, 1, 0.12],
      chase: [0, 0.38, 1],
    };
    const camKey = q.get('cam') ?? '3q';
    let tick: (() => void) | null = null;

    if (view === 'lineup') {
      const names = LAB_MODELS;
      const cols = 4;
      names.forEach((n, i) => {
        const cx = (i % cols - (cols - 1) / 2) * 7.2;
        const cz = Math.floor(i / cols) * 7.2;
        addModel(n, cx, cz, 0.62 + (n === 'bus' ? 0.25 : 0));
      });
      const rows = Math.ceil(names.length / cols);
      cam.fov = 32;
      cam.updateProjectionMatrix();
      if (camKey === 'top') cam.position.set(0, 34, 3);
      else cam.position.set(0, 15, -22);
      cam.lookAt(0, 0.3, ((rows - 1) * 7.2) / 2);
    } else if (view === 'showroom') {
      // the place3d builder: dealer cars on a floor, as the showroom draws them
      const b = new HomeBuilder();
      b.ao = false;
      const only = q.get('k');
      const kinds: LuxCar[] = only ? [only as LuxCar] : ['g63', 'gle63', 'urus', 'cybertruck', 'escalade', 'c300', 'camry'];
      kinds.forEach((k, i) => drawCar(b, k, only ? 0 : (i - 3) * 5.4, 0, only ? 0.5 : 0.5 - i * 0.07, 1));
      if (!only) {
        b.setFrame(-18, 0, 5, 0.5);
        motorcycle(b, 1.1);
        b.setFrame(-16.4, 0, 5, 0.3);
        bicycle(b, 1.1);
      }
      b.resetFrame();
      const L = b.finish();
      const grp: Mesh[] = [];
      if (L.solid) grp.push(new Mesh(L.solid, new MeshLambertMaterial({ vertexColors: true })));
      if (L.glass) grp.push(new Mesh(L.glass, new MeshLambertMaterial({ vertexColors: true, transparent: true, opacity: 0.85 })));
      if (L.glow) grp.push(new Mesh(L.glow, new MeshBasicMaterial({ vertexColors: true })));
      grp.forEach((m) => scene.add(m));
      for (const k of ['solid', 'glass', 'glow'] as const) if (L[k]) log.push(`${k}: ${labTris(L[k]!)} tris`);
      if (only) {
        const box = new Box3().setFromObject(grp[0]);
        cam.fov = 28;
        cam.updateProjectionMatrix();
        frame(box, new Vector3(...(camDirs[camKey] ?? camDirs['3q'])), 1.0);
      } else {
        cam.fov = 30;
        cam.updateProjectionMatrix();
        cam.position.set(-1, 13, -38);
        cam.lookAt(-1, 0.3, 0);
      }
    } else if (view === 'traffic') {
      const n = Number(q.get('n') ?? 60);
      const names = ['sedan', 'suv', 'pickup', 'keke', 'moto', 'bus'];
      const ims: InstancedMesh[] = [];
      const per = Math.ceil(n / names.length);
      const m4 = new Matrix4();
      names.forEach((name, ki) => {
        const geo = labGeometry(name, lod);
        const mat = labMaterial(0xffffff);
        mat.glow.value = night ? 1.6 : 0.5;
        mats.push(mat);
        const im = new InstancedMesh(geo, mat, per);
        for (let i = 0; i < per; i++) {
          const lane = (i % 3) - 1;
          const z = ki * 8 + Math.floor(i / 3) * 7 - 40;
          m4.makeRotationY(lane < 0 ? Math.PI : 0).setPosition(lane * 3.6, 0, z);
          im.setMatrixAt(i, m4);
          im.setColorAt(i, new Color().setHSL(((i * 0.13 + ki * 0.21) % 1), 0.25, 0.55));
        }
        scene.add(im);
        ims.push(im);
        log.push(`${name}: ${labTris(geo)} tris x ${per}`);
      });
      cam.position.set(7, 3.2, -60);
      cam.lookAt(0, 1, 0);
      let frames = 0;
      let t0 = performance.now();
      tick = () => {
        frames++;
        const t = performance.now();
        if (t - t0 > 2000) {
          (window as unknown as { __fps: number }).__fps = (frames * 1000) / (t - t0);
          frames = 0;
          t0 = t;
        }
      };
    } else {
      const name = q.get('m') ?? 'sedan';
      let m: Mesh;
      if (q.get('kit') === '1') {
        const kit = labKit(name, lod);
        const mat = labMaterial(tint);
        mat.glow.value = night ? 1.6 : 0.5;
        mats.push(mat);
        m = new Mesh(kit.body, mat);
        scene.add(m);
        const wg = labWheelGeometry(kit.wheels[0]?.style ?? 'car', lod);
        const wm = labMaterial(0xffffff);
        wm.glow.value = 0;
        mats.push(wm);
        const im = new InstancedMesh(wg, wm, kit.wheels.length);
        const m4 = new Matrix4();
        kit.wheels.forEach((w, i) => {
          m4.makeScale(w.wid, w.r, w.r).setPosition(w.x, w.r, w.z);
          im.setMatrixAt(i, m4);
        });
        scene.add(im);
        log.push(`${name} kit: body ${labTris(kit.body)} + ${kit.wheels.length} x ${labTris(wg)} tris`);
      } else {
        m = addModel(name, 0, 0, 0);
      }
      const box = new Box3().setFromObject(m);
      const dir = new Vector3(...(camDirs[camKey] ?? camDirs['3q']));
      cam.fov = camKey === 'chase' ? 40 : 28;
      cam.updateProjectionMatrix();
      frame(box, dir, camKey === 'chase' ? 1.2 : 1.0);
    }
    (window as unknown as { __labLog: string[] }).__labLog = log;
    if (q.get('tris') === '1') {
      const d = document.createElement('pre');
      d.style.cssText = 'position:fixed;left:8px;top:8px;color:#fff;background:#0008;padding:6px;font:11px monospace;margin:0';
      d.textContent = log.join('\n');
      document.body.appendChild(d);
      disposers.push(() => d.remove());
    }
    let raf = 0;
    let drawn = 0;
    const loop = () => {
      renderer.render(scene, cam);
      tick?.();
      drawn++;
      // ?still=1: a few frames for a screenshot, then stop (software GL is slow)
      if (q.get('still') === '1' && drawn > 3) return;
      raf = requestAnimationFrame(loop);
    };
    loop();
    window.addEventListener('resize', resize);
    return () => {
      cancelAnimationFrame(raf);
      window.removeEventListener('resize', resize);
      disposers.forEach((f) => f());
      renderer.dispose();
    };
  }, []);
  return <canvas ref={ref} style={{ position: 'fixed', inset: 0, width: '100vw', height: '100vh', display: 'block' }} />;
}

void DoubleSide;
