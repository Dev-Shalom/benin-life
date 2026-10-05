// Shared lighting and the turntable platform (used by the live stage and the portrait renderer alike).
import {
  CanvasTexture,
  CylinderGeometry,
  DirectionalLight,
  Group,
  HemisphereLight,
  Mesh,
  MeshBasicMaterial,
  MeshLambertMaterial,
  PlaneGeometry,
  SRGBColorSpace,
} from 'three';

/** Soft daylight: sky/ground fill, a warm key from the front-left, a cool fill and a rim from behind. */
export function makeLights(): Group {
  const g = new Group();
  g.name = 'lights';
  const hemi = new HemisphereLight('#f4f8ff', '#a39282', 1.75);
  const key = new DirectionalLight('#fff4e6', 2.45);
  key.position.set(1.6, 3.2, 3.4);
  const fill = new DirectionalLight('#dce8ff', 0.75);
  fill.position.set(-3, 1.6, 1.6);
  const rim = new DirectionalLight('#ffffff', 1.25);
  rim.position.set(-0.6, 2.6, -3.5);
  g.add(hemi, key, fill, rim);
  return g;
}

let shadowTex: CanvasTexture | null = null;
function blobTexture() {
  if (shadowTex) return shadowTex;
  const c = document.createElement('canvas');
  c.width = c.height = 128;
  const x = c.getContext('2d')!;
  const gr = x.createRadialGradient(64, 64, 4, 64, 64, 62);
  gr.addColorStop(0, 'rgba(40,55,80,0.34)');
  gr.addColorStop(0.55, 'rgba(40,55,80,0.14)');
  gr.addColorStop(1, 'rgba(40,55,80,0)');
  x.fillStyle = gr;
  x.fillRect(0, 0, 128, 128);
  shadowTex = new CanvasTexture(c);
  shadowTex.colorSpace = SRGBColorSpace;
  return shadowTex;
}

/** Soft blob shadow under the feet (no shadow maps: cheap on phones). */
export function makeShadow(radius = 0.42): Mesh {
  const m = new Mesh(new PlaneGeometry(radius * 2, radius * 2), new MeshBasicMaterial({ map: blobTexture(), transparent: true, depthWrite: false }));
  m.rotation.x = -Math.PI / 2;
  m.position.y = 0.002;
  m.renderOrder = 1;
  return m;
}

/** The round turntable base. */
export function makePlatform(): Group {
  const g = new Group();
  const disc = new Mesh(new CylinderGeometry(0.56, 0.58, 0.035, 56), new MeshLambertMaterial({ color: '#e4e8ee' }));
  disc.position.y = -0.0175;
  const top = new Mesh(new CylinderGeometry(0.545, 0.545, 0.002, 56), new MeshLambertMaterial({ color: '#eef1f5' }));
  top.position.y = 0.0005;
  g.add(disc, top, makeShadow());
  return g;
}
