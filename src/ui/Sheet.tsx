// Bottom sheet on phones, right-side panel on desktop (>= 900px).
import { useRef, useState, type ReactNode, type PointerEvent as RPointerEvent } from 'react';
import { createPortal } from 'react-dom';
import { usePresence, useEscape } from './presence';
import { IconButton } from './Button';

export interface SheetProps {
  open: boolean;
  onClose: () => void;
  title?: ReactNode;
  subtitle?: ReactNode;
  /** Custom header (e.g. scene art). Replaces the title/subtitle block. */
  header?: ReactNode;
  footer?: ReactNode;
  children?: ReactNode;
  /** 'tall' pins the sheet to ~92% height on phones. */
  size?: 'auto' | 'tall';
  className?: string;
}

export function Sheet({ open, onClose, title, subtitle, header, footer, children, size = 'auto', className = '' }: SheetProps) {
  const { mounted, closing } = usePresence(open, 260);
  useEscape(open, onClose);
  const [drag, setDrag] = useState(0);
  const start = useRef<number | null>(null);

  if (!mounted) return null;

  const onDown = (e: RPointerEvent) => {
    if (window.matchMedia('(min-width: 900px)').matches) return;
    if ((e.target as HTMLElement).closest('button')) return;
    start.current = e.clientY;
    (e.currentTarget as HTMLElement).setPointerCapture(e.pointerId);
  };
  const onMove = (e: RPointerEvent) => {
    if (start.current == null) return;
    setDrag(Math.max(0, e.clientY - start.current));
  };
  const onUp = () => {
    if (start.current == null) return;
    start.current = null;
    if (drag > 90) onClose();
    setDrag(0);
  };
  const dragHandlers = { onPointerDown: onDown, onPointerMove: onMove, onPointerUp: onUp, onPointerCancel: onUp };

  return createPortal(
    <div className={`bl-sheet-root${closing ? ' is-closing' : ''}`}>
      <div className="bl-sheet-backdrop" onClick={onClose} />
      <section
        className={`bl-sheet bl-sheet--${size} ${className}`}
        role="dialog"
        aria-modal="true"
        style={drag ? { transform: `translateY(${drag}px)`, transition: 'none' } : undefined}
      >
        <div className="bl-sheet__grab" {...dragHandlers}>
          <span />
        </div>
        <IconButton icon="close" label="Close" variant="plain" size={38} className="bl-sheet__close" onClick={onClose} />
        {header ? (
          <div className="bl-sheet__custom-head" {...dragHandlers}>{header}</div>
        ) : title || subtitle ? (
          <header className="bl-sheet__head" {...dragHandlers}>
            {title && <h3 className="bl-sheet__title">{title}</h3>}
            {subtitle && <p className="bl-sheet__sub">{subtitle}</p>}
          </header>
        ) : null}
        <div className="bl-sheet__body">{children}</div>
        {footer && <footer className="bl-sheet__foot">{footer}</footer>}
      </section>
    </div>,
    document.body,
  );
}
