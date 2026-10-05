// The live 3D turntable (react-three-fiber). Lazy-loaded: only screens that show it pull in three.js.
// Drag (mouse or touch) spins the character with inertia. Renders on demand at ~30 fps while idle,
// every frame while spinning, and not at all when hidden or scrolled away.
import { Canvas, useFrame, useThree } from '@react-three/fiber';
import { useEffect, useMemo, useRef, useState, type CSSProperties } from 'react';
import type { AvatarConfig } from '../../../lib/types';
import { avatarKey } from '../catalog';
import { buildCharacter, type Character } from './character';
import { poseIdle } from './anim';
import { makeLights, makePlatform } from './scene';

export interface StageProps {
  config: AvatarConfig;
  interactive?: boolean;
  autoRotate?: boolean;
  /** Start angle (radians). */
  yaw?: number;
  className?: string;
  style?: CSSProperties;
  /** Hide the "Drag to spin" hint. */
  hideHint?: boolean;
  onStats?: (s: Character['stats']) => void;
}

interface Spin {
  angle: number;
  vel: number;
  dragging: boolean;
  lastInput: number;
  visible: boolean;
}

function Driver({ spin }: { spin: React.MutableRefObject<Spin> }) {
  const invalidate = useThree((s) => s.invalidate);
  useEffect(() => {
    let raf = 0;
    let last = 0;
    const loop = (now: number) => {
      raf = requestAnimationFrame(loop);
      const sp = spin.current;
      if (document.hidden || !sp.visible) return;
      const busy = sp.dragging || Math.abs(sp.vel) > 0.02;
      if (!busy && now - last < 1000 / 30) return;
      last = now;
      invalidate();
    };
    raf = requestAnimationFrame(loop);
    return () => cancelAnimationFrame(raf);
  }, [invalidate, spin]);
  return null;
}

function Rig({ config, spin, autoRotate, onStats }: { config: AvatarConfig; spin: React.MutableRefObject<Spin>; autoRotate: boolean; onStats?: StageProps['onStats'] }) {
  const key = avatarKey(config);
  // eslint-disable-next-line react-hooks/exhaustive-deps
  const ch = useMemo(() => buildCharacter(config), [key]);
  const lights = useMemo(() => makeLights(), []);
  const platform = useMemo(() => makePlatform(), []);
  const { camera, size, invalidate } = useThree();
  const salt = useMemo(() => Math.random() * 10, []);

  useEffect(() => {
    onStats?.(ch.stats);
    invalidate();
    return () => ch.dispose();
  }, [ch, onStats, invalidate]);

  // frame the whole body (and tall headwear) for this canvas shape
  useEffect(() => {
    const cam = camera as import('three').PerspectiveCamera;
    const top = Math.max(ch.topY, 1.6) + 0.06;
    const bottom = -0.3;
    const H = top - bottom;
    const W = 1.25;
    const aspect = size.width / Math.max(1, size.height);
    const tanH = Math.tan((cam.fov * Math.PI) / 360);
    const dist = Math.max(H / 2 / tanH, W / 2 / (tanH * aspect));
    const cy = (top + bottom) / 2;
    cam.position.set(0, cy + 0.42, dist);
    cam.lookAt(0, cy, 0);
    cam.updateProjectionMatrix();
    invalidate();
  }, [camera, size.width, size.height, ch, invalidate]);

  useFrame((state, dt) => {
    const sp = spin.current;
    const step = Math.min(dt, 0.05);
    if (!sp.dragging) {
      sp.angle += sp.vel * step;
      sp.vel *= Math.exp(-step * 2.6);
      if (Math.abs(sp.vel) < 0.02) sp.vel = 0;
      if (autoRotate && performance.now() - sp.lastInput > 4000) sp.angle += 0.3 * step;
    }
    ch.root.rotation.y = sp.angle;
    poseIdle(ch, state.clock.elapsedTime, salt);
  });

  return (
    <>
      <primitive object={lights} />
      <primitive object={platform} />
      <primitive object={ch.root} />
    </>
  );
}

export default function Stage({ config, interactive = true, autoRotate = false, yaw = 0, className, style, hideHint, onStats }: StageProps) {
  const spin = useRef<Spin>({ angle: yaw, vel: 0, dragging: false, lastInput: 0, visible: true });
  const wrap = useRef<HTMLDivElement>(null);
  const [touched, setTouched] = useState(false);
  const drag = useRef<{ x: number; t: number; id: number } | null>(null);

  useEffect(() => {
    const el = wrap.current;
    if (!el || typeof IntersectionObserver === 'undefined') return;
    const io = new IntersectionObserver((e) => {
      spin.current.visible = e.some((x) => x.isIntersecting);
    });
    io.observe(el);
    return () => io.disconnect();
  }, []);

  const handlers = interactive
    ? {
        onPointerDown: (e: React.PointerEvent) => {
          if (e.button !== 0 && e.pointerType === 'mouse') return;
          drag.current = { x: e.clientX, t: performance.now(), id: e.pointerId };
          spin.current.dragging = true;
          spin.current.vel = 0;
          spin.current.lastInput = performance.now();
          try {
            (e.currentTarget as HTMLElement).setPointerCapture(e.pointerId);
          } catch {
            /* synthetic or already-released pointer */
          }
          if (!touched) setTouched(true);
        },
        onPointerMove: (e: React.PointerEvent) => {
          const d = drag.current;
          if (!d || d.id !== e.pointerId) return;
          const now = performance.now();
          const dx = e.clientX - d.x;
          const dt = Math.max(1, now - d.t) / 1000;
          const width = wrap.current?.clientWidth || 300;
          const dAng = (dx / width) * Math.PI * 1.6;
          spin.current.angle += dAng;
          spin.current.vel = spin.current.vel * 0.4 + (dAng / dt) * 0.6;
          spin.current.lastInput = now;
          d.x = e.clientX;
          d.t = now;
        },
        onPointerUp: (e: React.PointerEvent) => {
          if (drag.current?.id !== e.pointerId) return;
          drag.current = null;
          spin.current.dragging = false;
          if (performance.now() - spin.current.lastInput > 80) spin.current.vel = 0;
          spin.current.vel = Math.max(-9, Math.min(9, spin.current.vel));
        },
        onPointerCancel: () => {
          drag.current = null;
          spin.current.dragging = false;
        },
      }
    : {};

  return (
    <div ref={wrap} className={`avatar-stage${interactive ? ' is-interactive' : ''}${className ? ' ' + className : ''}`} style={style} {...handlers}>
      <Canvas
        dpr={[1, 1.5]}
        frameloop="demand"
        flat
        gl={{ antialias: true, alpha: true, powerPreference: 'low-power' }}
        camera={{ fov: 24, near: 0.1, far: 40, position: [0, 1.2, 5] }}
        style={{ touchAction: interactive ? 'pan-y' : 'auto' }}
      >
        <Driver spin={spin} />
        <Rig config={config} spin={spin} autoRotate={autoRotate} onStats={onStats} />
      </Canvas>
      {interactive && !hideHint && <span className={`avatar-stage__hint${touched ? ' is-gone' : ''}`}>Drag to spin</span>}
    </div>
  );
}
