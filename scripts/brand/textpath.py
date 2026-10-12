"""Convert a string to an SVG path using Outfit (woff) via fontTools."""
import sys
from fontTools.ttLib import TTFont
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
import os
# Outfit woff files from the @fontsource/outfit npm package (npm pack @fontsource/outfit; tar xzf ...).
FONTS = os.environ.get('BL_OUTFIT_DIR', os.path.join(os.path.dirname(__file__), '.fonts', 'package', 'files')) + '/'
_cache = {}
def font(w):
    if w not in _cache: _cache[w] = TTFont(FONTS + f'outfit-latin-{w}-normal.woff')
    return _cache[w]
def text_path(s, size, x=0, y=0, weight=800, tracking=0.0, anchor='start'):
    """Returns (d, width). y is the baseline. tracking in em."""
    f = font(weight); gs = f.getGlyphSet(); cmap = f.getBestCmap(); upm = f['head'].unitsPerEm
    sc = size / upm
    hmtx = f['hmtx']
    # width
    names = [cmap[ord(c)] for c in s]
    adv = [hmtx[n][0] * sc + tracking * size for n in names]
    total = sum(adv) - tracking * size
    if anchor == 'middle': x -= total / 2
    elif anchor == 'end': x -= total
    pen = SVGPathPen(gs, ntos=lambda v: ('%.2f' % v).rstrip('0').rstrip('.'))
    cx = x
    for n, a in zip(names, adv):
        tp = TransformPen(pen, (sc, 0, 0, -sc, cx, y))
        gs[n].draw(tp)
        cx += a
    return pen.getCommands(), total
if __name__ == '__main__':
    print(text_path(sys.argv[1], 40))
