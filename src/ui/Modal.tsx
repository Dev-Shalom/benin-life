import type { ReactNode } from 'react';
import { createPortal } from 'react-dom';
import { usePresence, useEscape } from './presence';

export function Modal({ open, onClose, title, children, actions, art, tone = 'default', dismissable = true }: {
  open: boolean;
  onClose: () => void;
  title?: ReactNode;
  children?: ReactNode;
  actions?: ReactNode;
  /** Illustration slot above the title. */
  art?: ReactNode;
  tone?: 'default' | 'bad' | 'good';
  dismissable?: boolean;
}) {
  const { mounted, closing } = usePresence(open, 220);
  useEscape(open && dismissable, onClose);
  if (!mounted) return null;
  return createPortal(
    <div className={`bl-modal-root${closing ? ' is-closing' : ''}`}>
      <div className="bl-modal-backdrop" onClick={dismissable ? onClose : undefined} />
      <div className={`bl-modal bl-modal--${tone}`} role="alertdialog" aria-modal="true">
        {art && <div className="bl-modal__art">{art}</div>}
        {title && <h3 className="bl-modal__title">{title}</h3>}
        {children && <div className="bl-modal__body">{children}</div>}
        {actions && <div className="bl-modal__actions">{actions}</div>}
      </div>
    </div>,
    document.body,
  );
}
