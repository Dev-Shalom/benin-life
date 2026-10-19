// R11: the gang tag next to a name: [RNG] @x. Colour comes from the gang (server-validated hex). Renders nothing without a gang.
export function CrewTag({ tag, color, emblem }: { tag?: string | null; color?: string | null; emblem?: string | null }) {
  if (!tag) return null;
  const bg = /^#[0-9a-fA-F]{6}$/.test(color ?? '') ? (color as string) : '#7a8a99';
  return (
    <span className="cr-tag" data-testid="crew-tag" title={`Gang ${tag}`}
      style={{ display: 'inline-flex', alignItems: 'center', gap: 3, padding: '1px 6px', marginRight: 4, borderRadius: 8, font: '800 11.5px var(--font-display)', letterSpacing: '.04em', color: '#fff', background: bg, verticalAlign: 'middle' }}>
      {emblem ? <i aria-hidden style={{ fontStyle: 'normal', fontFamily: 'var(--font-emoji)' }}>{emblem}</i> : null}[{tag}]
    </span>
  );
}
