// R12: the title of an officeholder next to a name: Hon. @x, Gov. @x. Renders nothing without a title.
export function OfficeTag({ title }: { title?: string | null }) {
  if (!title) return null;
  return (
    <span className="office-tag" data-testid="office-tag" title={`Holds office: ${title}`}
      style={{ display: 'inline-flex', alignItems: 'center', padding: '1px 6px', marginRight: 4, borderRadius: 8, font: '800 11.5px var(--font-display)', letterSpacing: '.02em', color: '#3b2a00', background: 'linear-gradient(180deg,#ffe08a,#e8b431)', verticalAlign: 'middle' }}>
      {title}
    </span>
  );
}
