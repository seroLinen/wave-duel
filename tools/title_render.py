"""Draws the title logo ("WAVE DUEL") from hand-built letter shapes: no font files, so nothing to license.

Each letter is a polyline on a small grid; the strokes are thickened, sheared into an italic, filled with a warm gradient,
given a bright inner edge, a dark outline and a drop shadow, then a cyan wave swoosh is drawn underneath.

    python tools/title_render.py            # writes art/title_logo.png (transparent background)

Needs: Pillow, numpy.
"""
import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageChops

ART = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "art")
S = 30            # pixels per grid unit
STROKE = 1.15     # stroke width in grid units
GAP = 2.0         # space between letters (grid units)
SHEAR = 0.22      # italic lean

# letters on a 6 x 8 grid (y down)
LETTERS = {
    "W": [[(0, 0), (1.6, 8), (3, 3.2), (4.4, 8), (6, 0)]],
    "A": [[(0, 8), (3, 0), (6, 8)], [(1.1, 5.6), (4.9, 5.6)]],
    "V": [[(0, 0), (3, 8), (6, 0)]],
    "E": [[(6, 0), (0, 0), (0, 8), (6, 8)], [(0, 4), (4.8, 4)]],
    "D": [[(0, 0), (3.6, 0), (6, 2.2), (6, 5.8), (3.6, 8), (0, 8), (0, 0)]],
    "U": [[(0, 0), (0, 5.8), (2.2, 8), (3.8, 8), (6, 5.8), (6, 0)]],
    "L": [[(0, 0), (0, 8), (6, 8)]],
}
WORD = ["W", "A", "V", "E", " ", "D", "U", "E", "L"]


def stroke_mask(size, letters_xy):
    m = Image.new("L", size, 0)
    d = ImageDraw.Draw(m)
    w = int(STROKE * S)
    for pts in letters_xy:
        d.line(pts, fill=255, width=w, joint="curve")
        for p in (pts[0], pts[-1]):                       # rounded ends
            d.ellipse((p[0] - w / 2, p[1] - w / 2, p[0] + w / 2, p[1] + w / 2), fill=255)
    return m


def build():
    pad = 40
    adv = 6 + GAP
    cols = sum((0.9 if ch == " " else 1) for ch in WORD)
    width = int(cols * adv * S) + pad * 2 + 80
    height = int(8 * S) + pad * 2 + 90
    size = (width, height)
    strokes = []
    x = pad + 30
    for ch in WORD:
        if ch == " ":
            x += 0.9 * adv * S
            continue
        for pts in LETTERS[ch]:
            strokes.append([(x + px * S, pad + py * S) for px, py in pts])
        x += adv * S
    mask = stroke_mask(size, strokes)
    # italic lean
    mask = mask.transform(size, Image.AFFINE, (1, SHEAR, -SHEAR * (pad + 4 * S), 0, 1, 0), resample=Image.BICUBIC)
    m = np.array(mask).astype(np.float32) / 255.0

    def layer(arr, color):
        out = np.zeros((size[1], size[0], 4), np.uint8)
        out[..., :3] = color
        out[..., 3] = (np.clip(arr, 0, 1) * 255).astype(np.uint8)
        return Image.fromarray(out, "RGBA")

    out = Image.new("RGBA", size, (0, 0, 0, 0))
    # drop shadow
    sh = mask.filter(ImageFilter.GaussianBlur(4))
    shadow = Image.new("RGBA", size, (10, 4, 30, 0))
    shadow.putalpha(sh.point(lambda v: int(v * 0.7)))
    out.alpha_composite(shadow, (5, 7))
    # dark outline
    outline = mask.filter(ImageFilter.MaxFilter(9))
    out.alpha_composite(layer(np.array(outline) / 255.0, (22, 10, 56)))
    thin = mask.filter(ImageFilter.MaxFilter(5))
    out.alpha_composite(layer(np.array(thin) / 255.0, (255, 245, 220)))                # light rim
    # gradient fill
    ys = np.linspace(0, 1, size[1])[:, None]
    grad = np.zeros((size[1], size[0], 3), np.float32)
    top = np.array([255, 236, 130], np.float32)
    bot = np.array([255, 110, 64], np.float32)
    grad[:] = (top * (1 - ys) + bot * ys)[:, None, :] if False else (top[None, None, :] * (1 - ys[..., None]) + bot[None, None, :] * ys[..., None])
    fill = Image.fromarray(grad.astype(np.uint8), "RGB").convert("RGBA")
    fill.putalpha(mask)
    out.alpha_composite(fill)
    # inner gloss: a lighter band along the top of every stroke
    gloss = ImageChops.subtract(mask, mask.transform(size, Image.AFFINE, (1, 0, 0, 0, 1, -5)))
    out.alpha_composite(layer(np.array(gloss) / 255.0 * 0.85, (255, 255, 255)))
    # the wave swoosh under the word
    wave = Image.new("L", size, 0)
    wd = ImageDraw.Draw(wave)
    y0 = pad + 8 * S + 34
    pts = [(pad + 20 + i * 4, y0 + math.sin(i / 10.0) * 9 * (0.4 + 0.6 * math.sin(i / 220.0 * math.pi))) for i in range(int((width - 2 * pad - 40) / 4))]
    wd.line(pts, fill=255, width=6, joint="curve")
    wmask = np.array(wave).astype(np.float32) / 255.0
    out.alpha_composite(layer(np.array(wave.filter(ImageFilter.MaxFilter(7))) / 255.0, (22, 10, 56)))
    out.alpha_composite(layer(wmask, (96, 230, 255)))
    out = out.crop(out.getbbox())
    os.makedirs(ART, exist_ok=True)
    path = os.path.join(ART, "title_logo.png")
    out.save(path)
    print("wrote", path, out.size)


if __name__ == "__main__":
    build()
