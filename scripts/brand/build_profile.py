"""Round profile-picture version of the Benin Life share image (og-image): dark bronze-brown background with the
plaque leaf pattern, coral bead ring, Ada (left) and Eben (right) flanking a stacked "Benin / Life" wordmark.
Everything sits inside the circle, so TikTok / WhatsApp round crops cut nothing. Writes public/brand/logo-profile.svg.
Run: python3 scripts/brand/build_profile.py"""
import math, re, os, sys
sys.path.insert(0, os.path.dirname(__file__))
from textpath import text_path
root = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
og = open(os.path.join(root, 'public/brand/og-image.svg')).read()
defs = re.search(r'<defs>(.*?)</defs>', og, re.S).group(1)
groups = re.findall(r'<g transform="translate\([0-9.]+ 84\) rotate\(-?5\) scale\(0.95\)">(.*?)</g>', og, re.S)
ada, eben = groups[0], groups[1]
C = 512
IVORY, CORAL = '#F7EBD3', '#E8664F'
size = 168
d1, w1 = text_path('Benin', size, 0, 0, 800)
d2, w2 = text_path('Life', size, 0, 0, 800)
# stacked wordmark, centred; baselines chosen so the block is centred on the circle
b1, b2 = C - 18, C + 138
p1, _ = text_path('Benin', size, C, b1, 800, anchor='middle')
p2, _ = text_path('Life', size, C, b2, 800, anchor='middle')
def pol(r, deg):
    t = math.radians(deg); return C + r * math.sin(t), C - r * math.cos(t)
beads = ''.join(f'<circle cx="{pol(482, i*5)[0]:.1f}" cy="{pol(482, i*5)[1]:.1f}" r="8" fill="url(#ogcr)"/>' for i in range(72))
line_y = b2 + 46
divider = (f'<path d="M{C-210} {line_y} H{C-34} M{C+34} {line_y} H{C+210}" stroke="#C8922E" stroke-width="5" stroke-linecap="round"/>'
           f'<circle cx="{C-20}" cy="{line_y}" r="7.5" fill="url(#ogcr)"/><circle cx="{C}" cy="{line_y}" r="10.5" fill="url(#ogcr)"/><circle cx="{C+20}" cy="{line_y}" r="7.5" fill="url(#ogcr)"/>')
topdiv = (f'<path d="M{C-120} {b1-178} H{C+120}" stroke="#C8922E" stroke-opacity=".7" stroke-width="3" stroke-linecap="round"/>')
svg = f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" role="img" aria-label="Benin Life"><title>Benin Life</title>
<defs>{defs}<clipPath id="pc"><circle cx="{C}" cy="{C}" r="511"/></clipPath>
<filter id="psh" x="-30%" y="-30%" width="160%" height="160%"><feDropShadow dx="0" dy="6" stdDeviation="6" flood-color="#000" flood-opacity=".55"/></filter></defs>
<g clip-path="url(#pc)">
<rect width="1024" height="1024" fill="url(#ogbg)"/>
<rect width="1024" height="1024" fill="url(#ogpat)" opacity="0.13"/>
<rect width="1024" height="1024" fill="url(#ogfade)"/>
</g>
<circle cx="{C}" cy="{C}" r="508" fill="none" stroke="#C8922E" stroke-opacity=".35" stroke-width="3"/>
{beads}
<circle cx="{C}" cy="{C}" r="455" fill="none" stroke="#C8922E" stroke-opacity=".6" stroke-width="3"/>
<g filter="url(#psh)">
<g transform="translate(196 628) rotate(-6) scale(3.4)">{ada}</g>
<g transform="translate(838 628) rotate(6) scale(3.4)">{eben}</g>
<path d="{p1}" fill="{IVORY}"/>
<path d="{p2}" fill="{CORAL}"/>
</g>
{divider}
</svg>'''
out = os.path.join(root, 'public/brand/logo-profile.svg')
open(out, 'w').write(svg)
print('wrote', out, 'Benin width', round(w1), 'Life width', round(w2))
