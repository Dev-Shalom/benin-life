import { useEffect, useRef, useState } from 'react';

/** Keeps something mounted for `ms` after `open` turns false so exit animations can play. */
export function usePresence(open: boolean, ms = 240): { mounted: boolean; closing: boolean } {
  const [mounted, setMounted] = useState(open);
  const [closing, setClosing] = useState(false);
  const [prevOpen, setPrevOpen] = useState(open);
  if (open !== prevOpen) {
    setPrevOpen(open);
    if (open) {
      setMounted(true);
      setClosing(false);
    } else if (mounted) {
      setClosing(true);
    }
  }
  useEffect(() => {
    if (!closing) return;
    const id = window.setTimeout(() => {
      setMounted(false);
      setClosing(false);
    }, ms);
    return () => window.clearTimeout(id);
  }, [closing, ms]);
  return { mounted, closing };
}

// Escape-key stack so only the top-most overlay closes.
const stack: { current: () => void }[] = [];
let bound = false;
function onKey(e: KeyboardEvent) {
  if (e.key === 'Escape' && stack.length) {
    e.preventDefault();
    stack[stack.length - 1].current();
  }
}

export function useEscape(active: boolean, onEscape: () => void) {
  const ref = useRef(onEscape);
  useEffect(() => {
    ref.current = onEscape;
  });
  useEffect(() => {
    if (!active) return;
    if (!bound) {
      window.addEventListener('keydown', onKey);
      bound = true;
    }
    const entry = { current: () => ref.current() };
    stack.push(entry);
    return () => {
      const i = stack.indexOf(entry);
      if (i >= 0) stack.splice(i, 1);
    };
  }, [active]);
}
