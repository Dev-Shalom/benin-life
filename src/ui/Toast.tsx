// Toasts — call `toast('Omo!', 'bad')` from anywhere; render <Toaster /> once at the app root.
import { useSyncExternalStore } from 'react';
import { Icon } from './Icon';

export type ToastKind = 'info' | 'good' | 'bad';

interface ToastItem {
  id: number;
  msg: string;
  kind: ToastKind;
  leaving?: boolean;
}

let items: ToastItem[] = [];
let nextId = 1;
const listeners = new Set<() => void>();
const MAX = 4;

function emit() {
  for (const l of listeners) l();
}

function dismiss(id: number) {
  items = items.map((t) => (t.id === id ? { ...t, leaving: true } : t));
  emit();
  window.setTimeout(() => {
    items = items.filter((t) => t.id !== id);
    emit();
  }, 220);
}

/** Show a toast. Duration scales with message length. Returns an id. */
export function toast(msg: string, kind: ToastKind = 'info'): number {
  if (!msg) return 0;
  const id = nextId++;
  // de-dupe identical messages already on screen
  if (items.some((t) => t.msg === msg && !t.leaving)) return id;
  items = [...items, { id, msg, kind }].slice(-MAX);
  emit();
  const ms = Math.min(7000, 2600 + msg.length * 45);
  window.setTimeout(() => dismiss(id), ms);
  return id;
}

function subscribe(cb: () => void) {
  listeners.add(cb);
  return () => listeners.delete(cb);
}

const ICON: Record<ToastKind, string> = { info: 'info', good: 'check', bad: 'warning' };

export function Toaster() {
  const list = useSyncExternalStore(subscribe, () => items, () => items);
  return (
    <div className="bl-toaster" aria-live="polite" aria-atomic="false">
      {list.map((t) => (
        <button key={t.id} type="button" className={`bl-toast bl-toast--${t.kind}${t.leaving ? ' is-leaving' : ''}`}
          onClick={() => dismiss(t.id)}>
          <span className="bl-toast__icon"><Icon name={ICON[t.kind]} size={16} stroke={2.5} /></span>
          <span className="bl-toast__msg">{t.msg}</span>
        </button>
      ))}
    </div>
  );
}
