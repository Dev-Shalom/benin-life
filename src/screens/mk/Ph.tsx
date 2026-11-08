// A Phosphor icon (regular weight) as inline SVG. The path data lives in icons.ts and is copied from @phosphor-icons/core.
import type { SVGProps } from 'react';
import { PH, type PhName } from './icons';

export function Ph({ name, className, ...rest }: { name: PhName } & Omit<SVGProps<SVGSVGElement>, 'name'>) {
  return (
    <svg className={className} viewBox="0 0 256 256" aria-hidden="true" focusable="false" {...rest}>
      <path d={PH[name]} />
    </svg>
  );
}
