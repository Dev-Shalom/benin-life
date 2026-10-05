// Tiny inline icon set (24×24, stroke). Zero network cost.
import type { CSSProperties } from 'react';

const PATHS: Record<string, string> = {
  bag: 'M5 8h14l-1 12H6L5 8Z M9 8V6a3 3 0 0 1 6 0v2',
  chat: 'M4 5h16v11H9l-5 4V5Z M8 10h8 M8 13h5',
  file: 'M4 6a2 2 0 0 1 2-2h4l2 2h6a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V6Z M9 13h6',
  bell: 'M6 16V11a6 6 0 1 1 12 0v5l2 2H4l2-2Z M10 20a2 2 0 0 0 4 0',
  gear: 'M12 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6Z M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1Z',
  shield: 'M12 3 4 6v6c0 4.5 3.4 8.3 8 9 4.6-.7 8-4.5 8-9V6l-8-3Z M9 12l2 2 4-4',
  sun: 'M12 16a4 4 0 1 0 0-8 4 4 0 0 0 0 8Z M12 2v2 M12 20v2 M4.9 4.9l1.4 1.4 M17.7 17.7l1.4 1.4 M2 12h2 M20 12h2 M4.9 19.1l1.4-1.4 M17.7 6.3l1.4-1.4',
  moon: 'M20 14.5A8 8 0 1 1 9.5 4a6.5 6.5 0 0 0 10.5 10.5Z',
  cash: 'M3 7h18v10H3V7Z M12 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6Z M6 10v4 M18 10v4',
  bank: 'M3 10 12 4l9 6H3Z M5 10v8 M9.5 10v8 M14.5 10v8 M19 10v8 M3 20h18',
  close: 'M6 6l12 12 M18 6 6 18',
  back: 'M15 5l-7 7 7 7',
  chevronDown: 'M6 9l6 6 6-6',
  chevronUp: 'M6 15l6-6 6 6',
  chevronRight: 'M9 5l7 7-7 7',
  walk: 'M13 4.5a1.5 1.5 0 1 0 0-3 1.5 1.5 0 0 0 0 3Z M10 21l2-6 3 3v3 M7 12l2-4 4-1 2 4 3 1 M12 15l-1-5',
  keke: 'M4 17a2 2 0 1 0 4 0 2 2 0 0 0-4 0Z M16 17a2 2 0 1 0 4 0 2 2 0 0 0-4 0Z M8 17h8 M5 15V9a3 3 0 0 1 3-3h7l3 5v6 M12 6v5h6',
  bus: 'M5 4h14a1 1 0 0 1 1 1v12H4V5a1 1 0 0 1 1-1Z M4 11h16 M7 20v-3 M17 20v-3 M7.5 14.5h.01 M16.5 14.5h.01',
  car: 'M5 16H3v-4l2-5h14l2 5v4h-2 M7 18a2 2 0 1 0 0-4 2 2 0 0 0 0 4Z M17 18a2 2 0 1 0 0-4 2 2 0 0 0 0 4Z M9 16h6 M5 12h14',
  drop: 'M5 16H3v-4l2-5h14l2 5v4h-2 M7 18a2 2 0 1 0 0-4 2 2 0 0 0 0 4Z M17 18a2 2 0 1 0 0-4 2 2 0 0 0 0 4Z M9 16h6 M10 7V4h4v3',
  people: 'M9 11a3.5 3.5 0 1 0 0-7 3.5 3.5 0 0 0 0 7Z M2 20c.5-3.5 3.5-6 7-6s6.5 2.5 7 6 M16 4.5a3.5 3.5 0 0 1 0 6.5 M18 14c2 .7 3.5 2.8 4 6',
  pin: 'M12 21s7-6.2 7-12a7 7 0 1 0-14 0c0 5.8 7 12 7 12Z M12 11.5a2.5 2.5 0 1 0 0-5 2.5 2.5 0 0 0 0 5Z',
  dice: 'M5 3h14a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2Z M8 8h.01 M16 8h.01 M12 12h.01 M8 16h.01 M16 16h.01',
  crown: 'M3 8l4 4 5-7 5 7 4-4-2 11H5L3 8Z',
  clock: 'M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18Z M12 7v5l3 2',
  heart: 'M12 20s-7-4.4-7-10a4 4 0 0 1 7-2.6A4 4 0 0 1 19 10c0 5.6-7 10-7 10Z',
  food: 'M3 12h18 M4 12a8 8 0 0 0 16 0 M9 4c0 1.5 1 1.5 1 3 M13 4c0 1.5 1 1.5 1 3',
  bolt: 'M13 2 4 14h7l-1 8 9-12h-7l1-8Z',
  soap: 'M4 11h16v7a3 3 0 0 1-3 3H7a3 3 0 0 1-3-3v-7Z M8 7a2 2 0 1 0 0-4 2 2 0 0 0 0 4Z M15 8a1.5 1.5 0 1 0 0-3 1.5 1.5 0 0 0 0 3Z',
  party: 'M4 20 9 7l8 8-13 5Z M14 4l1 2 M19 9l2-1 M17 3l-1 3 M20 13l-3-1',
  stress: 'M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18Z M8 9l2 1 M16 9l-2 1 M8 16c1.5-1.5 6.5-1.5 8 0',
  user: 'M12 12a4 4 0 1 0 0-8 4 4 0 0 0 0 8Z M4 21c.8-4 4-6 8-6s7.2 2 8 6',
  mask: 'M3 9c3-2 15-2 18 0v3c0 4-4 6-9 6s-9-2-9-6V9Z M8 12h2 M14 12h2',
  plus: 'M12 5v14 M5 12h14',
  check: 'M5 12l5 5 9-10',
  logout: 'M15 4h3a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2h-3 M10 17l-5-5 5-5 M5 12h11',
  lock: 'M6 11h12v10H6V11Z M8 11V8a4 4 0 0 1 8 0v3 M12 15v2',
  cross: 'M9 3h6v6h6v6h-6v6H9v-6H3V9h6V3Z',
  info: 'M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18Z M12 11v5 M12 8h.01',
  warning: 'M12 3 2 20h20L12 3Z M12 10v4 M12 17h.01',
  star: 'M12 3l2.7 5.6 6.1.9-4.4 4.3 1 6.1L12 17l-5.4 2.9 1-6.1-4.4-4.3 6.1-.9L12 3Z',
  refresh: 'M20 11a8 8 0 1 0-2.3 5.7 M20 4v7h-7',
  map: 'M9 4 3 6v14l6-2 6 2 6-2V4l-6 2-6-2Z M9 4v14 M15 6v14',
  home: 'M3 11 12 4l9 7 M5 10v10h14V10 M10 20v-6h4v6',
  sparkle: 'M12 3l1.8 5.2L19 10l-5.2 1.8L12 17l-1.8-5.2L5 10l5.2-1.8L12 3Z M19 16l.7 1.8 1.8.7-1.8.7L19 21l-.7-1.8-1.8-.7 1.8-.7L19 16Z',
  camera: 'M4 8h3l2-3h6l2 3h3v11H4V8Z M12 16a3 3 0 1 0 0-6 3 3 0 0 0 0 6Z',
  road: 'M8 3 4 21 M16 3l4 18 M12 4v3 M12 10v3 M12 16v3',
  mail: 'M3 6h18v12H3V6Z M3 7l9 6 9-6',
  laptop: 'M5 5h14v10H5V5Z M2 19h20l-2-4H4l-2 4Z',
  eye: 'M2 12s3.6-7 10-7 10 7 10 7-3.6 7-10 7S2 12 2 12Z M12 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6Z',
  eyeOff: 'M3 3l18 18 M10.6 5.1C11 5 11.5 5 12 5c6.4 0 10 7 10 7a17 17 0 0 1-3.1 4.1 M6.6 6.6C3.9 8.3 2 12 2 12s3.6 7 10 7c1.8 0 3.4-.5 4.8-1.3 M9.9 9.9a3 3 0 0 0 4.2 4.2',
};

export type IconName = keyof typeof PATHS;

export function Icon({ name, size = 20, stroke = 2, className, style, title }: {
  name: IconName | string;
  size?: number;
  stroke?: number;
  className?: string;
  style?: CSSProperties;
  title?: string;
}) {
  const d = PATHS[name] ?? PATHS.info;
  return (
    <svg
      viewBox="0 0 24 24"
      width={size}
      height={size}
      fill="none"
      stroke="currentColor"
      strokeWidth={stroke}
      strokeLinecap="round"
      strokeLinejoin="round"
      className={className}
      style={{ flexShrink: 0, ...style }}
      aria-hidden={title ? undefined : true}
      role={title ? 'img' : undefined}
    >
      {title && <title>{title}</title>}
      <path d={d} />
    </svg>
  );
}
