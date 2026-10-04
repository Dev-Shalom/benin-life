import { NEED_META, needMood, type NeedKey } from '../lib/pidgin';
import { Icon } from './Icon';

/** One need meter. Stress is inverted (high = bad). `compact` = icon + thin bar only. */
export function NeedBar({ need, value, compact }: { need: NeedKey; value: number; compact?: boolean }) {
  const meta = NEED_META[need];
  const v = Math.max(0, Math.min(100, Number(value) || 0));
  const mood = needMood(need, v);
  return (
    <div className={`bl-need bl-need--${mood}${compact ? ' bl-need--compact' : ''}`} title={`${meta.label}: ${Math.round(v)}`}>
      <span className="bl-need__icon"><Icon name={meta.icon} size={compact ? 13 : 16} /></span>
      {!compact && <span className="bl-need__label">{meta.label}</span>}
      <span className="bl-need__track" role="meter" aria-label={meta.label} aria-valuemin={0} aria-valuemax={100} aria-valuenow={Math.round(v)}>
        <span className="bl-need__fill" style={{ width: `${v}%` }} />
      </span>
      {!compact && <span className="bl-need__val">{Math.round(v)}</span>}
    </div>
  );
}
