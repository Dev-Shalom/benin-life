"""Builds the round Benin Life medallion (profile picture / app logo): public/brand/logo-medallion.svg.
Everything sits inside the circle (corners transparent), so a circular crop (TikTok, WhatsApp) cuts nothing.
Motifs: Ada (left) and Eben (right) ceremonial swords, an Oba-style coral-bead crown, coral necklace with
bronze spacers, a braided bronze border, and the four-petal "ebe-ame" leaf pattern of Benin plaques.
Run: python3 scripts/brand/build_medallion.py   (needs fontTools + the Outfit woff files, see textpath.py)"""
import math, re, os, sys
sys.path.insert(0, os.path.dirname(__file__))
from textpath import text_path
root = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
mark = open(os.path.join(root, 'public/brand/logo-mark.svg')).read()
groups = re.findall(r'<g transform="[^"]*">(.*?)</g>', mark, re.S)
ada, eben = groups[0], groups[1]
def metal(s):
    return s.replace('url(#bz)', 'url(#metal)').replace('url(#cr)', 'url(#coral)')
ada, eben = metal(ada), metal(eben)
C = 512
def pol(r, deg):
    t = math.radians(deg); return C + r * math.sin(t), C - r * math.cos(t)
def f(v): return f'{v:.1f}'
# ---------- curved text ----------
def arc(s, R, size, centre_deg, bottom=False, weight=800, tracking=0.16):
    advs = []
    for ch in s:
        advs.append(size * 0.34 if ch == ' ' else text_path(ch, size, weight=weight)[1] + tracking * size)
    total = sum(advs) - tracking * size
    span = total / R
    a = math.radians(centre_deg) + (span / 2 if bottom else -span / 2)
    out = []
    for ch, adv in zip(s, advs):
        mid = a + (-adv / 2 / R if bottom else adv / 2 / R)
        if ch != ' ':
            d, _ = text_path(ch, size, weight=weight, anchor='middle')
            out.append(f'<path d="{d}" transform="translate({C} {C}) rotate({math.degrees(mid):.3f}) translate(0 {-R}){" rotate(180)" if bottom else ""}"/>')
        a += (-adv / R if bottom else adv / R)
    return ''.join(out)
# ---------- coral necklace with bronze spacers ----------
neck = []
N = 40
for i in range(N):
    a = i * 360 / N
    x, y = pol(487, a)
    neck.append(f'<circle cx="{f(x)}" cy="{f(y)}" r="13" fill="url(#coral)"/><circle cx="{f(x-4.3)}" cy="{f(y-4.6)}" r="3.4" fill="#fff" fill-opacity=".45"/>')
    x2, y2 = pol(487, a + 180 / N)
    neck.append(f'<circle cx="{f(x2)}" cy="{f(y2)}" r="5.2" fill="url(#metal)" stroke="#5E3A0C" stroke-width="1"/>')
# ---------- braided bronze border ----------
braid = []
M = 90
for i in range(M):
    a = i * 360 / M
    x, y = pol(452, a)
    braid.append(f'<ellipse cx="{f(x)}" cy="{f(y)}" rx="17" ry="7.2" transform="rotate({a + 90 - 38:.1f} {f(x)} {f(y)})" fill="url(#metal)" stroke="#4A2C08" stroke-width="1.4"/>')
# ---------- engraved guilloche in the text band ----------
guil = ''.join(f'<circle cx="{C}" cy="{C}" r="{r}" fill="none" stroke="#E2B252" stroke-opacity=".07" stroke-width="1.2"/>' for r in range(352, 426, 9))
# ---------- side ornaments ----------
def orn(deg):
    x, y = pol(390, deg)
    return (f'<g transform="translate({f(x)} {f(y)})">'
            f'<path d="M0 -24 L10 0 L0 24 L-10 0 Z" fill="url(#metal)" stroke="#4A2C08" stroke-width="1.6"/>'
            f'<circle r="7.5" fill="url(#coral)"/><circle cx="-2.4" cy="-2.6" r="2.2" fill="#fff" fill-opacity=".5"/></g>')
# ---------- Oba-style coral crown ----------
def bead(x, y, r):
    return (f'<circle cx="{f(x)}" cy="{f(y)}" r="{r:.1f}" fill="url(#coral)" stroke="#5A1209" stroke-width=".9"/>'
            f'<circle cx="{f(x - r*.33)}" cy="{f(y - r*.36)}" r="{r*.28:.1f}" fill="#fff" fill-opacity=".5"/>')
crown = []
cx0, base, H, W = 512, 566, 140, 108
# dark net behind the beads
crown.append(f'<path d="M{cx0-W-6} {base} C{cx0-W-6} {base-H*1.05} {cx0+W+6} {base-H*1.05} {cx0+W+6} {base} Z" fill="#3E0D08"/>')
rows = 7
for k in range(rows):
    t = k / rows
    y = base - 8 - H * t
    hw = (W - 4) * math.sqrt(max(0.0, 1 - t ** 1.7))
    r = 10.5 - k * 0.6
    n = max(1, int(2 * hw / (2 * r + 1.5)))
    off = 0 if k % 2 == 0 else 0.5
    for j in range(n + 1):
        u = (j + off) / n
        if u > 1: continue
        crown.append(bead(cx0 - hw + 2 * hw * u, y, r))
# tall beaded peak
py = base - 8 - H
for k in range(5):
    crown.append(bead(cx0, py - 6 - k * 17, 8.6 - k * 0.6))
crown.append(f'<path d="M{cx0} {py-102} L{cx0+8} {py-88} L{cx0} {py-80} L{cx0-8} {py-88} Z" fill="url(#metal)" stroke="#4A2C08" stroke-width="1.2"/>')
# bronze headband with diamonds
crown.append(f'<path d="M{cx0-W-10} {base-6} Q{cx0} {base+20} {cx0+W+10} {base-6} L{cx0+W+10} {base+16} Q{cx0} {base+42} {cx0-W-10} {base+16} Z" fill="url(#metal)" stroke="#4A2C08" stroke-width="1.6"/>')
for u in (-0.66, -0.33, 0, 0.33, 0.66):
    x = cx0 + u * W; y = base + 5 + 13 * (1 - u * u)
    crown.append(f'<path d="M{f(x)} {f(y-8)} L{f(x+6)} {f(y)} L{f(x)} {f(y+8)} L{f(x-6)} {f(y)} Z" fill="#7E1E14" stroke="#3A1006" stroke-width="1"/>')
# beaded lappets hanging at the sides
for s in (-1, 1):
    for k in range(4):
        crown.append(bead(cx0 + s * (W + 4), base + 30 + k * 18, 8 - k * 0.7))
# ---------- swords ----------
sw = (f'<g filter="url(#sh)"><g transform="translate(340 676) rotate(-11) scale(3.8)">{ada}</g>'
      f'<g transform="translate(684 676) rotate(11) scale(3.8)">{eben}</g></g>')
top = arc('BENIN LIFE', 392, 82, 0)
bot = arc('EDO · NIGERIA', 372, 38, 180, bottom=True, weight=700, tracking=0.22)
svg = f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" role="img" aria-label="Benin Life"><title>Benin Life</title>
<defs>
<linearGradient id="metal" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#FCEBB0"/><stop offset=".22" stop-color="#E7B95A"/><stop offset=".5" stop-color="#B07A24"/><stop offset=".72" stop-color="#E2B252"/><stop offset="1" stop-color="#6B430E"/></linearGradient>
<linearGradient id="metalv" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#FFF0BE"/><stop offset=".35" stop-color="#E2B252"/><stop offset=".7" stop-color="#A06A1C"/><stop offset="1" stop-color="#5E3A0C"/></linearGradient>
<radialGradient id="coral" cx=".36" cy=".3" r=".78"><stop offset="0" stop-color="#FF9A7E"/><stop offset=".45" stop-color="#D5402C"/><stop offset="1" stop-color="#6E1A10"/></radialGradient>
<radialGradient id="bg" cx=".5" cy=".42" r=".62"><stop offset="0" stop-color="#3A160D"/><stop offset=".65" stop-color="#1C0D08"/><stop offset="1" stop-color="#0E0705"/></radialGradient>
<radialGradient id="disc" cx=".5" cy=".42" r=".62"><stop offset="0" stop-color="#9A2F1C"/><stop offset=".5" stop-color="#5A1A0F"/><stop offset="1" stop-color="#1E0A06"/></radialGradient>
<radialGradient id="glow" cx=".5" cy=".5" r=".5"><stop offset="0" stop-color="#FFD98A" stop-opacity=".5"/><stop offset="1" stop-color="#FFD98A" stop-opacity="0"/></radialGradient>
<radialGradient id="band" cx=".5" cy=".5" r=".5"><stop offset=".66" stop-color="#140906"/><stop offset=".84" stop-color="#2A140B"/><stop offset="1" stop-color="#140906"/></radialGradient>
<filter id="sh" x="-30%" y="-30%" width="160%" height="160%"><feDropShadow dx="0" dy="7" stdDeviation="7" flood-color="#000" flood-opacity=".6"/></filter>
<filter id="tsh" x="-10%" y="-10%" width="120%" height="120%"><feDropShadow dx="0" dy="4" stdDeviation="2.5" flood-color="#000" flood-opacity=".7"/></filter>
<clipPath id="discclip"><circle cx="{C}" cy="{C}" r="336"/></clipPath>
<pattern id="leaf" width="64" height="64" patternUnits="userSpaceOnUse">
 <g transform="translate(32 32)" fill="none" stroke="#E7B95A" stroke-opacity=".17" stroke-width="2">
  <path d="M0 -4 C8 -12 8 -24 0 -28 C-8 -24 -8 -12 0 -4 Z"/><path d="M0 4 C8 12 8 24 0 28 C-8 24 -8 12 0 4 Z"/>
  <path d="M4 0 C12 -8 24 -8 28 0 C24 8 12 8 4 0 Z"/><path d="M-4 0 C-12 -8 -24 -8 -28 0 C-24 8 -12 8 -4 0 Z"/>
  <circle r="3" fill="#E7B95A" fill-opacity=".2"/></g></pattern>
</defs>
<circle cx="{C}" cy="{C}" r="511" fill="url(#bg)"/>
<circle cx="{C}" cy="{C}" r="505" fill="none" stroke="url(#metal)" stroke-width="3"/>
<circle cx="{C}" cy="{C}" r="487" fill="none" stroke="#E2B252" stroke-opacity=".55" stroke-width="2.5"/>
<g filter="url(#sh)">{''.join(neck)}</g>
<circle cx="{C}" cy="{C}" r="429" fill="url(#band)"/>
<circle cx="{C}" cy="{C}" r="470" fill="none" stroke="url(#metal)" stroke-width="4"/>
<circle cx="{C}" cy="{C}" r="434" fill="none" stroke="url(#metal)" stroke-width="4"/>
<g filter="url(#sh)">{''.join(braid)}</g>
{guil}
<g filter="url(#tsh)"><g fill="url(#metalv)" stroke="#3A2306" stroke-width="2.2" stroke-linejoin="round">{top}</g></g>
<g fill="#F2D287">{bot}</g>
{orn(90)}{orn(270)}
<circle cx="{C}" cy="{C}" r="346" fill="none" stroke="url(#metal)" stroke-width="10"/>
<circle cx="{C}" cy="{C}" r="352" fill="none" stroke="#FFF1C9" stroke-opacity=".35" stroke-width="1.5"/>
<circle cx="{C}" cy="{C}" r="336" fill="url(#disc)"/>
<g clip-path="url(#discclip)"><rect x="170" y="170" width="684" height="684" fill="url(#leaf)"/>
<circle cx="{C}" cy="{C-40}" r="270" fill="url(#glow)"/>
<circle cx="{C}" cy="{C}" r="336" fill="none" stroke="#000" stroke-opacity=".45" stroke-width="40"/></g>
{sw}
<g filter="url(#sh)">{''.join(crown)}</g>
</svg>'''
out = os.path.join(root, 'public/brand/logo-medallion.svg')
open(out, 'w').write(svg)
print('wrote', out, len(svg))
