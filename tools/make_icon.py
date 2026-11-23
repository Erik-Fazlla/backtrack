"""Draw the Backtrack app icon: neon breadcrumb trail on black.

Concept: the way out is a dotted breadcrumb trail; the way back is a
solid glowing line that loops round and points home to the start dot.

Usage: python tools/make_icon.py
Writes assets/icon/icon.png (full, black bg) and
       assets/icon/icon_fg.png (adaptive-icon foreground, transparent).
"""
import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

S = 2048  # supersampled canvas, downscaled to 1024
OUT = Path("assets/icon")
OUT.mkdir(parents=True, exist_ok=True)

CORE = (255, 240, 214)
MID = (255, 138, 28)
OUTER = (255, 80, 0)


def bezier(p0, p1, p2, p3, n):
    t = np.linspace(0, 1, n)[:, None]
    p0, p1, p2, p3 = map(np.array, (p0, p1, p2, p3))
    return list(map(tuple, (1 - t) ** 3 * p0 + 3 * (1 - t) ** 2 * t * p1
                    + 3 * (1 - t) * t ** 2 * p2 + t ** 3 * p3))


# Unit coordinates (0..1, y down).
START = (0.40, 0.76)
# Out: wavy breadcrumb path up and to the left, to the top.
OUT_PATH = (bezier(START, (0.22, 0.62), (0.40, 0.42), (0.30, 0.30), 300)
            + bezier((0.30, 0.30), (0.26, 0.22), (0.40, 0.17), (0.50, 0.19), 150)[1:])
# Back: from the top, down the right side, curving left toward the start.
BACK_PATH = (bezier((0.50, 0.19), (0.72, 0.22), (0.76, 0.45), (0.72, 0.60), 300)
             + bezier((0.72, 0.60), (0.68, 0.74), (0.58, 0.78), (0.50, 0.77), 200)[1:])


def render(fg_only: bool, scale: float) -> Image.Image:
    def place(p):
        x, y = p
        return ((0.5 + (x - 0.5) * scale) * S, (0.5 + (y - 0.5) * scale) * S)

    out = [place(p) for p in OUT_PATH]
    back = [place(p) for p in BACK_PATH]
    start = place(START)
    w = S * 0.030 * scale  # line width in px

    # arrowhead: tip at end of BACK_PATH, aligned with the last direction
    (x1, y1), (x2, y2) = back[-12], back[-1]
    ang = math.atan2(y2 - y1, x2 - x1)

    def arrow(size):
        tip = (x2 + math.cos(ang) * size * 0.9, y2 + math.sin(ang) * size * 0.9)
        left = (x2 + math.cos(ang + 2.4) * size, y2 + math.sin(ang + 2.4) * size)
        right = (x2 + math.cos(ang - 2.4) * size, y2 + math.sin(ang - 2.4) * size)
        return [tip, left, right]

    def stroke(d, pts, radius, fill):
        # round brush: smooth edges at any curvature
        for x, y in pts[::2]:
            d.ellipse([x - radius, y - radius, x + radius, y + radius], fill=fill)

    def layer(k, color, blur):
        im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        d = ImageDraw.Draw(im)
        # breadcrumbs on the way out (skip near the start dot)
        n = len(out)
        for i in range(n // 9, n, n // 10):
            x, y = out[i]
            r = w * 0.42 * k
            d.ellipse([x - r, y - r, x + r, y + r], fill=color)
        stroke(d, back, w * 0.5 * k, color)
        d.polygon(arrow(w * 1.9 * (1 + (k - 1) * 0.35)), fill=color)
        r = w * 1.05 * (1 + (k - 1) * 0.5)
        d.ellipse([start[0] - r, start[1] - r, start[0] + r, start[1] + r],
                  fill=color)
        return im.filter(ImageFilter.GaussianBlur(blur)) if blur else im

    img = Image.new("RGBA", (S, S), (0, 0, 0, 0 if fg_only else 255))
    for lay in (
        layer(4.0, OUTER + (120,), S * 0.040 * scale),
        layer(2.2, OUTER + (190,), S * 0.014 * scale),
        layer(1.25, MID + (255,), S * 0.003),
        layer(0.55, CORE + (255,), S * 0.0012),
    ):
        img = Image.alpha_composite(img, lay)
    return img.resize((1024, 1024), Image.LANCZOS)


render(fg_only=False, scale=1.0).save(OUT / "icon.png")
# Adaptive icons crop to roughly the centre 66 %: keep the artwork inside.
render(fg_only=True, scale=0.66).save(OUT / "icon_fg.png")
print("wrote", OUT / "icon.png", OUT / "icon_fg.png")
