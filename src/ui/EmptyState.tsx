import type { ReactNode } from 'react';
import { Icon } from './Icon';

export function EmptyState({ icon = 'sparkle', title, body, action }: {
  icon?: string; title: string; body?: ReactNode; action?: ReactNode;
}) {
  return (
    <div className="bl-empty">
      <span className="bl-empty__icon"><Icon name={icon} size={28} /></span>
      <h4>{title}</h4>
      {body && <p className="muted">{body}</p>}
      {action}
    </div>
  );
}
