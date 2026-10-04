// Phase 0 — do not edit. Lazy-loads src/art/scenes/<type>.tsx; falls back to a gradient.
import { lazy, Suspense, type ComponentType, type LazyExoticComponent } from 'react';
import type { SceneType } from '../lib/types';

type SceneComp = ComponentType<{ night: boolean }>;
const modules = import.meta.glob<{ default: SceneComp }>('./scenes/*.tsx');
const cache = new Map<string, LazyExoticComponent<SceneComp>>();

function Fallback({ night }: { night: boolean }) {
  return (
    <svg viewBox="0 0 800 450" preserveAspectRatio="xMidYMid slice" width="100%" height="100%" aria-hidden>
      <defs>
        <linearGradient id="scene-fallback-sky" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stopColor={night ? '#0b1430' : '#f6c27a'} />
          <stop offset="60%" stopColor={night ? '#2a2350' : '#e98a4f'} />
          <stop offset="100%" stopColor={night ? '#3b1f2b' : '#b5552b'} />
        </linearGradient>
      </defs>
      <rect width="800" height="450" fill="url(#scene-fallback-sky)" />
    </svg>
  );
}

export function Scene({ type, night }: { type: SceneType; night: boolean }) {
  const loader = modules[`./scenes/${type}.tsx`];
  if (!loader) return <Fallback night={night} />;
  let Comp = cache.get(type);
  if (!Comp) {
    Comp = lazy(loader);
    cache.set(type, Comp);
  }
  return (
    <Suspense fallback={<Fallback night={night} />}>
      <Comp night={night} />
    </Suspense>
  );
}
