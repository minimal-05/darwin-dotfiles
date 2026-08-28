#!/usr/bin/env python3
# btop-style cpu graph: per-column color ramp green -> yellow -> red,
# rendered at 2x into a PNG the bar shows inside the pill.
import sys
from PIL import Image, ImageDraw

out = sys.argv[1]
vals = [min(100, max(0, int(float(v)))) for v in sys.argv[2:]]

N = 30            # history slots
W, H = 120, 36    # 2x retina -> 60x18pt
cw = W / N

# theme ramp anchors
GREEN = (0xA8, 0xD5, 0xA2)
YELLOW = (0xE8, 0xC4, 0x8A)
RED = (0xF2, 0xB8, 0xB5)

def ramp(v):
    if v <= 50:
        t = v / 50.0
        a, b = GREEN, YELLOW
    else:
        t = (v - 50) / 50.0
        a, b = YELLOW, RED
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))

im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
d = ImageDraw.Draw(im)
for i, v in enumerate(vals[-N:]):
    x0 = W - (len(vals[-N:]) - i) * cw
    h = max(2, round(v / 100.0 * H))
    d.rectangle([x0 + 1, H - h, x0 + cw - 1, H], fill=ramp(v) + (235,))
im.save(out)
print("ok")
