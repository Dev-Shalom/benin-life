"""Builds the round Benin Life medallion (profile picture / app logo): public/brand/logo-medallion.svg.
Everything lives inside the circle (corners are transparent), so a circular crop (TikTok, WhatsApp) cuts nothing away.
Run: python3 scripts/brand/build_medallion.py   (needs fontTools + the Outfit woff files, see textpath.py)"""
import math, re, os, sys
sys.path.insert(0, os.path.dirname(__file__))
from textpath import text_path
root = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
mark = open(os.path.join(root, 'public/brand/logo-mark.svg')).read()
defs = re.search(r'<defs>(.*?)</defs>', mark, re.S).group(1)
body = mark.split('</defs>', 1)[1].rsplit('</svg>', 1)[0]
body = re.sub(r'<rect[^>]*/>', '', body)  # drop the dark tile; the medallion has its own background
C = 512
def arc(s, R, size, centre_deg, bottom=False, weight=800, tracking=0.16):
    advs = []
    for ch in s:
        if ch == ' ':
            advs.append(size * 0.34)
        else:
            _, w = text_path(ch, size, weight=weight)
            advs.append(w + tracking * size)
    total = sum(advs) - tracking * size
    span = total / R  # radians
    out = []
    a = (math.radians(centre_deg) + (span / 2 if bottom else -span / 2))
    for ch, adv in zip(s, advs):
        mid = a + (-adv / 2 / R if bottom else adv / 2 / R)
        if ch != ' ':
            d, w = text_path(ch, size, x=0, y=0, weight=weight, anchor='middle')
            rot = math.degrees(mid)
            flip = ' rotate(180)' if bottom else ''
            out.append(f'<path d="{d}" transform="translate({C} {C}) rotate({rot:.3f}) translate(0 {-R}){flip}"/>')
        a += (-adv / R if bottom else adv / R)
    return ''.join(out)
def pol(r, deg):
    t = math.radians(deg)
    return C + r * math.sin(t), C - r * math.cos(t)
beads = ''.join(f'<circle cx="{pol(486,i*7.5)[0]:.2f}" cy="{pol(486,i*7.5)[1]:.2f}" r="13.5" fill="url(#cr)"/>'
                f'<circle cx="{pol(486,i*7.5)[0]-4.6:.2f}" cy="{pol(486,i*7.5)[1]-5:.2f}" r="3.6" fill="#fff" fill-opacity=".38"/>' for i in range(48))
rays = ''.join(f'<path d="M{C} {C} L{pol(340,i*15-3.2)[0]:.1f} {pol(340,i*15-3.2)[1]:.1f} L{pol(340,i*15+3.2)[0]:.1f} {pol(340,i*15+3.2)[1]:.1f} Z"/>' for i in range(24))
studs = ''.join(f'<circle cx="{pol(451,i*15+7.5)[0]:.1f}" cy="{pol(451,i*15+7.5)[1]:.1f}" r="3.2" fill="#3A2108" fill-opacity=".55"/>' for i in range(24))
def diamond(deg, r=392, s=15):
    x, y = pol(r, deg)
    return f'<path d="M{x:.1f} {y-s:.1f} L{x+s*.72:.1f} {y:.1f} L{x:.1f} {y+s:.1f} L{x-s*.72:.1f} {y:.1f} Z" fill="url(#bz)" stroke="#7E5016" stroke-width="1.5"/>'
top = arc('BENIN LIFE', 392, 80, 0)
bot = arc('EDO · NIGERIA', 372, 40, 180, bottom=True, weight=700, tracking=0.2)
svg = f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" role="img" aria-label="Benin Life"><title>Benin Life</title>
<defs>{defs}
<radialGradient id="bg" cx="0.5" cy="0.42" r="0.62"><stop offset="0" stop-color="#4A1B10"/><stop offset="0.6" stop-color="#241109"/><stop offset="1" stop-color="#120a07"/></radialGradient>
<radialGradient id="disc" cx="0.5" cy="0.45" r="0.6"><stop offset="0" stop-color="#8A2A1B"/><stop offset="0.55" stop-color="#4E160E"/><stop offset="1" stop-color="#220C08"/></radialGradient>
<radialGradient id="glow" cx="0.5" cy="0.5" r="0.5"><stop offset="0" stop-color="#FFD98A" stop-opacity=".55"/><stop offset="1" stop-color="#FFD98A" stop-opacity="0"/></radialGradient>
<linearGradient id="ring" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#F4D58A"/><stop offset="0.5" stop-color="#C8922E"/><stop offset="1" stop-color="#7E5016"/></linearGradient>
<clipPath id="discclip"><circle cx="{C}" cy="{C}" r="338"/></clipPath>
<pattern id="plaque" width="44" height="44" patternUnits="userSpaceOnUse" patternTransform="rotate(45)"><path d="M22 4 L40 22 L22 40 L4 22 Z" fill="none" stroke="#E0B25A" stroke-opacity=".16" stroke-width="2"/><circle cx="22" cy="22" r="3" fill="#E0B25A" fill-opacity=".18"/></pattern></defs>
<circle cx="{C}" cy="{C}" r="512" fill="url(#bg)"/>
<circle cx="{C}" cy="{C}" r="486" fill="none" stroke="url(#ring)" stroke-width="5"/>
{beads}
<circle cx="{C}" cy="{C}" r="451" fill="none" stroke="url(#ring)" stroke-width="30"/>
<circle cx="{C}" cy="{C}" r="436" fill="none" stroke="#3A2108" stroke-opacity=".5" stroke-width="2"/>
<circle cx="{C}" cy="{C}" r="466" fill="none" stroke="#FFF1C9" stroke-opacity=".35" stroke-width="2"/>
{studs}
<circle cx="{C}" cy="{C}" r="345" fill="none" stroke="url(#ring)" stroke-width="8"/>
<circle cx="{C}" cy="{C}" r="426" fill="none" stroke="url(#ring)" stroke-width="3"/>
<g fill="url(#ring)" stroke="#5A3A10" stroke-width="2" stroke-linejoin="round">{top}</g>
<g fill="#F4D58A" fill-opacity=".92">{bot}</g>
{diamond(90)}{diamond(270)}
<circle cx="{C}" cy="{C}" r="338" fill="url(#disc)"/>
<g clip-path="url(#discclip)"><rect x="170" y="170" width="684" height="684" fill="url(#plaque)"/>
<g fill="#F4D58A" fill-opacity=".10">{rays}</g>
<circle cx="{C}" cy="{C-30}" r="250" fill="url(#glow)"/></g>
<g transform="translate({C} {C+4}) scale(5.05) translate(-64 -56)">{body}</g>
</svg>'''
out = os.path.join(root, 'public/brand/logo-medallion.svg')
open(out, 'w').write(svg)
print('wrote', out, len(svg))
