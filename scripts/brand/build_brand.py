"""Benin Life brand build: writes the logo SVGs (public/brand/), the favicon, the inline
logo markup used by src/ui/Logo.tsx (src/ui/logoArt.ts) and a PNG job list for render.mjs.

  pip install fonttools
  (cd scripts/brand && mkdir -p .fonts && cd .fonts && npm pack @fontsource/outfit@5 && tar xzf fontsource-outfit-*.tgz)
  python3 scripts/brand/build_brand.py && node scripts/brand/render.mjs

The swords and wordmark geometry live in geom.py / textpath.py. See docs/BRAND.md.
"""
import json, math, os
from geom import *
from textpath import text_path

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
PUB = os.path.join(ROOT, 'public')
BRAND = os.path.join(PUB, 'brand')
os.makedirs(BRAND, exist_ok=True)

INK_LIGHT, ACCENT_LIGHT = INK, CORAL          # wordmark on light backgrounds
INK_DARK, ACCENT_DARK = IVORY, '#E8664F'      # wordmark on dark backgrounds


def bead(x, y, r, p=''):
    return (f'<circle cx="{x}" cy="{y}" r="{r}" fill="url(#{p}cr)"/>'
            f'<circle cx="{x - r * 0.32:.2f}" cy="{y - r * 0.34:.2f}" r="{r * 0.28:.2f}" fill="#fff" fill-opacity="0.38"/>')


def garland(p, x0, x1, y, sag, n, r, mono=None):
    """A strand of coral beads hung between two points (the Oba's coral regalia)."""
    out = []
    for i in range(n):
        t = i / (n - 1)
        x = x0 + (x1 - x0) * t
        yy = y + sag * math.sin(math.pi * t)
        out.append(f'<circle cx="{x:.2f}" cy="{yy:.2f}" r="{r}" fill="{mono or f"url(#{p}cr)"}"/>')
    return ''.join(out)


def emblem(p='', detail=True, mono=None):
    """Ada (left) and Eben (right) standing, a coral bead between them, a coral strand below.
    Drawn in a 128 x 128 box."""
    a = ada(p, detail=detail, mono=mono)
    e = eben(p, detail=detail, mono=mono)
    s = '0.95' if detail else '1.22 1.04'
    gy = 80 if detail else 80
    ax, ex, rot = (37, 91, 7) if detail else (33, 95, 4)
    body = (f'<g transform="translate({ax} {gy}) rotate(-{rot}) scale({s})">{a}</g>'
            f'<g transform="translate({ex} {gy}) rotate({rot}) scale({s})">{e}</g>')
    if mono:
        body += f'<circle cx="64" cy="52" r="12" fill="{mono}"/>'
    else:
        body += bead(64, 52 if detail else 54, 12 if detail else 14, p)
    if detail:
        body += garland(p, 45, 83, 80, 12, 7, 2.7, mono)
    return body


def tile(p='', rx=28, ring=True):
    t = f'<rect width="128" height="128" rx="{rx}" fill="{INK}"/>'
    if ring:
        t += f'<rect x="4" y="4" width="120" height="120" rx="{rx - 3.5}" fill="none" stroke="{BRONZE}" stroke-opacity="0.38" stroke-width="1.5"/>'
    return t


def svg(vb, body, p='', title='Benin Life'):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{vb}" role="img" aria-label="{title}">'
            f'<title>{title}</title><defs>{defs(p)}</defs>{body}</svg>\n')


def fill(v):
    # CSS variables only work reliably through style, not presentation attributes.
    return f'style="fill:{v}"' if 'var(' in v else f'fill="{v}"'


def bead_rule(p, x0, x1, y, mono=None):
    """Bronze rule with three coral beads, used under/around the wordmark."""
    mid = (x0 + x1) / 2
    beads = ''.join(f'<circle cx="{mid + dx}" cy="{y}" r="{r}" fill="{mono or f"url(#{p}cr)"}"/>'
                    for dx, r in ((-9, 2.1), (0, 2.8), (9, 2.1)))
    rule = (f'<path d="M{x0} {y} H{mid - 14} M{mid + 14} {y} H{x1}" stroke="{mono or BRONZE}" '
            f'stroke-width="2" stroke-linecap="round"/>')
    return rule + beads


# ---------- full (horizontal): Ada | Benin Life | Eben ----------
def full(p='', ink='var(--logo-ink, currentColor)', accent='var(--logo-accent, #C0392B)', mono=None):
    size = 50
    d1, w1 = text_path('Benin', size, 0, 0, 800)
    gap = size * 0.22
    d2, w2 = text_path('Life', size, 0, 0, 800)
    tw = w1 + gap + w2
    x0 = 54
    base = 78
    d1, _ = text_path('Benin', size, x0, base, 800)
    d2, _ = text_path('Life', size, x0 + w1 + gap, base, 800)
    W = x0 + tw + 54
    body = (f'<g transform="translate(28 84) rotate(-5) scale(0.95)">{ada(p, mono=mono)}</g>'
            f'<g transform="translate({W - 28:.1f} 84) rotate(5) scale(0.95)">{eben(p, mono=mono)}</g>'
            f'<path d="{d1}" {fill(mono or ink)}/><path d="{d2}" {fill(mono or accent)}/>'
            + bead_rule(p, x0 + 3, x0 + tw - 3, 98, mono))
    return f'0 0 {W:.1f} 128', body


# ---------- stacked: emblem over BENIN / LIFE ----------
def stacked(p='', ink='var(--logo-ink, currentColor)', accent='var(--logo-accent, #C0392B)', mono=None):
    W = 200
    d1, w1 = text_path('Benin', 54, W / 2, 196, 800, anchor='middle')
    d2, w2 = text_path('LIFE', 20, W / 2 + 0.24 * 20, 226, 700, tracking=0.48, anchor='middle')
    rule_y = 219
    half = w2 / 2 + 14
    body = (f'<g transform="translate(20 0) scale(1.25)">{emblem(p, mono=mono)}</g>'
            f'<path d="{d1}" {fill(mono or ink)}/><path d="{d2}" {fill(mono or accent)}/>'
            f'<path d="M{W/2 - half - 30} {rule_y} H{W/2 - half} M{W/2 + half} {rule_y} H{W/2 + half + 30}" '
            f'stroke="{mono or BRONZE}" stroke-width="2" stroke-linecap="round"/>'
            f'<circle cx="{W/2 - half - 36}" cy="{rule_y}" r="2.4" fill="{mono or f"url(#{p}cr)"}"/>'
            f'<circle cx="{W/2 + half + 36}" cy="{rule_y}" r="2.4" fill="{mono or f"url(#{p}cr)"}"/>')
    return f'0 0 {W} 238', body


def write(name, content):
    with open(os.path.join(BRAND, name), 'w') as f:
        f.write(content)


# ---------- static files ----------
write('logo-mark.svg', svg('0 0 128 128', tile() + emblem(), title='Benin Life'))
write('logo-mark-plain.svg', svg('0 0 128 128', emblem(), title='Benin Life'))
write('logo-mark-small.svg', svg('0 0 128 128', tile(rx=26, ring=False) + emblem(detail=False), title='Benin Life'))
write('logo-mark-mono.svg', svg('0 0 128 128', emblem(mono='#1E1410'), title='Benin Life'))
write('logo-mark-mono-white.svg', svg('0 0 128 128', emblem(detail=False, mono='#FFFFFF'), title='Benin Life'))
vb, body = full(ink=INK_LIGHT, accent=ACCENT_LIGHT); write('logo-full.svg', svg(vb, body))
vb, body = full(ink=INK_DARK, accent=ACCENT_DARK); write('logo-full-on-dark.svg', svg(vb, body))
vb, body = stacked(ink=INK_LIGHT, accent=ACCENT_LIGHT); write('logo-stacked.svg', svg(vb, body))
vb, body = stacked(ink=INK_DARK, accent=ACCENT_DARK); write('logo-stacked-on-dark.svg', svg(vb, body))
vb, body = full(mono='#1E1410'); write('logo-full-mono.svg', svg(vb, body))

# Favicon: simplified mark (bigger bead, two perforations, no strand) so it reads at 16 px.
with open(os.path.join(PUB, 'favicon.svg'), 'w') as f:
    f.write(svg('0 0 128 128', tile(rx=26, ring=False) + emblem(detail=False)))

# Maskable icon: full-bleed tile, emblem inside the 80% safe circle.
write('icon-maskable.svg', svg('0 0 128 128', f'<rect width="128" height="128" fill="{INK}"/>'
                               f'<g transform="translate(64 64) scale(0.72) translate(-64 -64)">{emblem()}</g>'))
# Apple touch icon: full-bleed square (iOS rounds the corners itself).
write('icon-apple.svg', svg('0 0 128 128', f'<rect width="128" height="128" fill="{INK}"/>'
                            f'<rect x="5" y="5" width="118" height="118" rx="22" fill="none" stroke="{BRONZE}" stroke-opacity="0.35" stroke-width="1.5"/>'
                            f'<g transform="translate(64 64) scale(0.9) translate(-64 -64)">{emblem()}</g>'))

# ---------- inline markup for src/ui/Logo.tsx ----------
P = '__ID__'
art = {}
art['mark'] = ('0 0 128 128', tile(P) + emblem(P))
art['markSmall'] = ('0 0 128 128', tile(P, rx=26, ring=False) + emblem(P, detail=False))
art['markPlain'] = ('0 0 128 128', emblem(P))
art['full'] = full(P)
art['stacked'] = stacked(P)
lines = ['// GENERATED by scripts/brand/build_brand.py. Do not edit by hand; edit the generator and re-run it.',
         '// Inline SVG bodies for the Benin Life logo. "__ID__" is replaced with a per-instance id prefix.',
         '// Wordmark colours read --logo-ink (default currentColor) and --logo-accent (default coral).',
         '',
         f"export const LOGO_DEFS = {json.dumps(defs(P))};", '']
for k, (vb, body) in art.items():
    lines.append(f"export const LOGO_{k.upper()} = {{ viewBox: {json.dumps(vb)}, body: {json.dumps(body)} }};")
with open(os.path.join(ROOT, 'src', 'ui', 'logoArt.ts'), 'w') as f:
    f.write('\n'.join(lines) + '\n')

print('wrote brand files')

# ---------- Open Graph / Twitter share image (1200 x 630) ----------
def og():
    vb, body = full('og', ink=INK_DARK, accent=ACCENT_DARK)
    fw = float(vb.split()[2])
    scale = 940 / fw
    lx = (1200 - fw * scale) / 2
    tag, _ = text_path('Live a whole new life in Benin City', 34, 600, 488, 500, anchor='middle')
    sub, _ = text_path('FREE TO PLAY IN YOUR BROWSER', 20, 600 + 0.3 * 10, 536, 700, tracking=0.3, anchor='middle')
    beads_top = ''.join(f'<circle cx="{x}" cy="34" r="5" fill="url(#ogcr)"/>' for x in range(600 - 26 * 22, 1200 - 27, 26))
    beads_bot = ''.join(f'<circle cx="{x}" cy="596" r="5" fill="url(#ogcr)"/>' for x in range(600 - 26 * 22, 1200 - 27, 26))
    pattern = f'''<pattern id="ogpat" width="60" height="60" patternUnits="userSpaceOnUse">
 <g fill="none" stroke="{BRONZE}" stroke-width="1.6">
  <path d="M30 14 C36 22 36 26 30 30 C24 26 24 22 30 14Z M30 46 C36 38 36 34 30 30 C24 34 24 38 30 46Z M14 30 C22 24 26 24 30 30 C26 36 22 36 14 30Z M46 30 C38 24 34 24 30 30 C34 36 38 36 46 30Z"/>
 </g><circle cx="30" cy="30" r="2.2" fill="{BRONZE}"/><circle cx="0" cy="0" r="1.8" fill="{BRONZE}"/><circle cx="60" cy="0" r="1.8" fill="{BRONZE}"/><circle cx="0" cy="60" r="1.8" fill="{BRONZE}"/><circle cx="60" cy="60" r="1.8" fill="{BRONZE}"/></pattern>
<radialGradient id="ogbg" cx="0.5" cy="0.42" r="0.75"><stop offset="0" stop-color="#4A2C17"/><stop offset="0.55" stop-color="#2A1B12"/><stop offset="1" stop-color="#140D09"/></radialGradient>
<radialGradient id="ogfade" cx="0.5" cy="0.45" r="0.6"><stop offset="0" stop-color="#2A1B12" stop-opacity="0.95"/><stop offset="0.7" stop-color="#2A1B12" stop-opacity="0.4"/><stop offset="1" stop-color="#2A1B12" stop-opacity="0"/></radialGradient>'''
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1200 630" width="1200" height="630">'
            f'<defs>{defs("og")}{pattern}</defs>'
            f'<rect width="1200" height="630" fill="url(#ogbg)"/>'
            f'<rect width="1200" height="630" fill="url(#ogpat)" opacity="0.13"/>'
            f'<rect width="1200" height="630" fill="url(#ogfade)"/>'
            f'<rect x="18" y="56" width="1164" height="518" rx="18" fill="none" stroke="{BRONZE}" stroke-opacity="0.55" stroke-width="2"/>'
            f'{beads_top}{beads_bot}'
            f'<g transform="translate({lx:.1f} 120) scale({scale:.4f})">{body}</g>'
            f'<path d="{tag}" fill="{IVORY}"/><path d="{sub}" fill="{BRONZE_HI}" fill-opacity="0.85"/></svg>\n')

write('og-image.svg', og())

# ---------- PNG jobs for render.mjs ----------
jobs = [
    {'svg': 'public/brand/logo-mark.svg', 'out': 'public/icon-192.png', 'w': 192},
    {'svg': 'public/brand/logo-mark.svg', 'out': 'public/icon-512.png', 'w': 512},
    {'svg': 'public/brand/icon-maskable.svg', 'out': 'public/icon-maskable-512.png', 'w': 512},
    {'svg': 'public/brand/icon-apple.svg', 'out': 'public/apple-touch-icon.png', 'w': 180},
    {'svg': 'public/brand/logo-mark-mono-white.svg', 'out': 'public/badge-96.png', 'w': 96},
    {'svg': 'public/brand/og-image.svg', 'out': 'public/og-image.png', 'w': 1200, 'h': 630},
    {'svg': 'public/favicon.svg', 'out': 'scripts/brand/.fonts/fav-16.png', 'w': 16},
    {'svg': 'public/favicon.svg', 'out': 'scripts/brand/.fonts/fav-32.png', 'w': 32},
    {'svg': 'public/favicon.svg', 'out': 'scripts/brand/.fonts/fav-48.png', 'w': 48},
]
with open(os.path.join(os.path.dirname(__file__), '.fonts', 'jobs.json'), 'w') as f:
    json.dump(jobs, f)
