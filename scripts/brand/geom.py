# Sword geometry, drawn tip-up with the guard centre at (0,0). Units: ~1/100 of overall height.
import math
BRONZE_HI, BRONZE, BRONZE_LO = '#F4D58A', '#C8922E', '#7E5016'
CORAL_HI, CORAL, CORAL_LO = '#F07A62', '#C0392B', '#7E1E14'
INK, IVORY = '#1E1410', '#F7EBD3'

# ADA: long blade that flares toward a broad, rounded, blunt tip (slight J-lean to the right at the top).
ADA_BLADE = ('M-3.2 0 C-3.4 -22 -7.6 -44 -10.2 -58 C-11.6 -66 -6.8 -73 0.6 -73 '
             'C8 -73 12 -67 10.6 -59 C8.4 -45 3.6 -22 3.2 0 Z')
ADA_FULLER = 'M0 -4 C0.1 -24 0.4 -44 0.4 -62'
ADA_GUARD = 'M-9 0.5 Q0 -2.5 9 0.5 L8.2 4.5 Q0 2.5 -8.2 4.5 Z'
ADA_GRIP = 'M-3 4 H3 V23 H-3 Z'
ADA_POMMEL = (0, 28.5, 5.5)  # circle
ADA_BANDS = [(9.5, 2.2), (17, 2.2)]  # y, height (coral wraps)

# EBEN: broad leaf/fan blade, central spine, openwork perforations; short grip with a ring handle.
EBEN_OUT = ('M-3 0 C-3.6 -10 -18 -20 -18.5 -40 C-19 -58 -9 -69 0 -69 '
            'C9 -69 19 -58 18.5 -40 C18 -20 3.6 -10 3 0 Z')
def circle_sub(cx, cy, r):
    return f'M{cx-r:.2f} {cy:.2f} a{r} {r} 0 1 0 {2*r:.2f} 0 a{r} {r} 0 1 0 {-2*r:.2f} 0 Z'
def lozenge_sub(cx, cy, w, h):
    return f'M{cx:.2f} {cy-h/2:.2f} L{cx+w/2:.2f} {cy:.2f} L{cx:.2f} {cy+h/2:.2f} L{cx-w/2:.2f} {cy:.2f} Z'
EBEN_HOLES = ' '.join([
    circle_sub(-9.5, -45, 3.4), circle_sub(9.5, -45, 3.4),
    lozenge_sub(-7.5, -29, 5, 8), lozenge_sub(7.5, -29, 5, 8),
    circle_sub(-6, -58.5, 2.1), circle_sub(6, -58.5, 2.1),
    lozenge_sub(-12.5, -36, 2.6, 4.4), lozenge_sub(12.5, -36, 2.6, 4.4),
])
EBEN_BLADE = EBEN_OUT + ' ' + EBEN_HOLES  # fill-rule evenodd
# Favicon-size blade: a column of three big lozenge perforations so it still reads as openwork at 16-32 px.
EBEN_BLADE_SIMPLE = EBEN_OUT + ' ' + ' '.join([lozenge_sub(0, -55, 7, 11), lozenge_sub(0, -40, 9, 14), lozenge_sub(0, -25, 7, 11)])
EBEN_SPINE = 'M0 -3 V-64'
EBEN_COLLAR = 'M-5.5 0 H5.5 V4 H-5.5 Z'
EBEN_GRIP = 'M-2.8 4 H2.8 V14 H-2.8 Z'
EBEN_RING = (0, 20.5, 6.8, 5.2, 2.6)  # cx, cy, rx, ry, stroke

def defs(p=''):
    return f'''<linearGradient id="{p}bz" x1="0" y1="0" x2="1" y2="1">
 <stop offset="0" stop-color="{BRONZE_HI}"/><stop offset="0.45" stop-color="{BRONZE}"/><stop offset="1" stop-color="{BRONZE_LO}"/></linearGradient>
<linearGradient id="{p}bzv" x1="0" y1="0" x2="0" y2="1">
 <stop offset="0" stop-color="{BRONZE_HI}"/><stop offset="0.5" stop-color="{BRONZE}"/><stop offset="1" stop-color="{BRONZE_LO}"/></linearGradient>
<radialGradient id="{p}cr" cx="0.35" cy="0.3" r="0.75">
 <stop offset="0" stop-color="{CORAL_HI}"/><stop offset="0.55" stop-color="{CORAL}"/><stop offset="1" stop-color="{CORAL_LO}"/></radialGradient>'''

def ada(p='', stroke=None, detail=True, mono=None):
    f = mono or f'url(#{p}bz)'
    out = []
    sw = f' stroke="{stroke}" stroke-width="2.4" stroke-linejoin="round" paint-order="stroke"' if stroke else ''
    out.append(f'<path d="{ADA_BLADE}" fill="{f}"{sw}/>')
    if detail and not mono: out.append(f'<path d="{ADA_FULLER}" fill="none" stroke="{BRONZE_LO}" stroke-opacity="0.55" stroke-width="1.3" stroke-linecap="round"/>')
    grip_line = '' if mono else f' stroke="{BRONZE_LO}" stroke-width="1.1"'
    out.append(f'<path d="{ADA_GRIP}" fill="{mono or IVORY}"{sw or grip_line}/>')
    if not mono and detail:
        for y, h in ADA_BANDS: out.append(f'<rect x="-3.4" y="{y}" width="6.8" height="{h}" rx="1" fill="url(#{p}cr)"/>')
    out.append(f'<path d="{ADA_GUARD}" fill="{f}"{sw}/>')
    cx, cy, r = ADA_POMMEL
    out.append(f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="{mono or f"url(#{p}cr)"}"{sw}/>')
    return '\n'.join(out)

def eben(p='', stroke=None, detail=True, mono=None):
    f = mono or f'url(#{p}bz)'
    sw = f' stroke="{stroke}" stroke-width="2.4" stroke-linejoin="round" paint-order="stroke"' if stroke else ''
    out = [f'<path d="{EBEN_BLADE if detail else EBEN_BLADE_SIMPLE}" fill="{f}" fill-rule="evenodd"{sw}/>']
    if detail and not mono: out.append(f'<path d="{EBEN_SPINE}" stroke="{BRONZE_LO}" stroke-opacity="0.6" stroke-width="1.6" stroke-linecap="round"/>')
    grip_line = '' if mono else f' stroke="{BRONZE_LO}" stroke-width="1.1"'
    out.append(f'<path d="{EBEN_GRIP}" fill="{mono or IVORY}"{sw or grip_line}/>')
    out.append(f'<path d="{EBEN_COLLAR}" fill="{f}"{sw}/>')
    cx, cy, rx, ry, s = EBEN_RING
    out.append(f'<ellipse cx="{cx}" cy="{cy}" rx="{rx}" ry="{ry}" fill="none" stroke="{mono or f"url(#{p}cr)"}" stroke-width="{s}"/>')
    return '\n'.join(out)
