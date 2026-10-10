"""Draws the title logo ("CHAKANA.EXE" over "KAGAMI NETWORK") from hand-built letter shapes: no font files, so nothing to license.

Each letter is a polyline on a small grid; the strokes are thickened, sheared into an italic, filled with a gradient,
given a bright inner edge, a dark outline and a drop shadow. The big top line is warm (gold to orange) with a cyan wave
swoosh under it; the second line is smaller and cool (white to cyan).

    python tools/title_render.py            # writes art/title_logo.png (transparent background)

Needs: Pillow, numpy.
"""
import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageChops

ART = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "art")
SHEAR = 0.22      # italic lean

# letters on a 6 x 8 grid (y down)
LETTERS = {
    "A": [[(0, 8), (3, 0), (6, 8)], [(1.1, 5.6), (4.9, 5.6)]],
    "C": [[(6, 1.2), (4.6, 0), (1.5, 0), (0, 1.5), (0, 6.5), (1.5, 8), (4.6, 8), (6, 6.8)]],
    "D": [[(0, 0), (3.6, 0), (6, 2.2), (6, 5.8), (3.6, 8), (0, 8), (0, 0)]],
    "E": [[(6, 0), (0, 0), (0, 8), (6, 8)], [(0, 4), (4.8, 4)]],
    "G": [[(6, 1.2), (4.6, 0), (1.5, 0), (0, 1.5), (0, 6.5), (1.5, 8), (4.6, 8), (6, 6.6), (6, 4.2), (3.4, 4.2)]],
    "H": [[(0, 0), (0, 8)], [(6, 0), (6, 8)], [(0, 4), (6, 4)]],
    "I": [[(1.4, 0), (4.6, 0)], [(3, 0), (3, 8)], [(1.4, 8), (4.6, 8)]],
    "K": [[(0, 0), (0, 8)], [(6, 0), (0, 4.6)], [(1.9, 3.3), (6, 8)]],
    "L": [[(0, 0), (0, 8), (6, 8)]],
    "M": [[(0, 8), (0, 0), (3, 5), (6, 0), (6, 8)]],
    "N": [[(0, 8), (0, 0), (6, 8), (6, 0)]],
    "O": [[(1.5, 0), (4.5, 0), (6, 1.5), (6, 6.5), (4.5, 8), (1.5, 8), (0, 6.5), (0, 1.5), (1.5, 0)]],
    "R": [[(0, 8), (0, 0), (4, 0), (6, 1.5), (6, 3), (4, 4.5), (0, 4.5)], [(3, 4.5), (6, 8)]],
    "T": [[(0, 0), (6, 0)], [(3, 0), (3, 8)]],
    "U": [[(0, 0), (0, 5.8), (2.2, 8), (3.8, 8), (6, 5.8), (6, 0)]],
    "V": [[(0, 0), (3, 8), (6, 0)]],
    "W": [[(0, 0), (1.6, 8), (3, 3.2), (4.4, 8), (6, 0)]],
    "X": [[(0, 0), (6, 8)], [(6, 0), (0, 8)]],
    ".": [[(2.2, 7.0), (2.2, 7.9)]],
}
NARROW = {".": 0.55}    # letters that take less room


def line_image(word, S, stroke, gap, top, bot, wave, pad=30):
    adv = 6 + gap
    cols = 0.0
    for ch in word:
        cols += 0.7 if ch == " " else NARROW.get(ch, 1.0)
    width = int(cols * adv * S) + pad * 2 + 60
    height = int(8 * S) + pad * 2 + (int(S * 3) if wave else 20)
    size = (width, height)
    strokes = []
    x = pad + 20
    for ch in word:
        if ch == " ":
            x += 0.7 * adv * S
            continue
        for pts in LETTERS[ch]:
            strokes.append([(x + px * S, pad + py * S) for px, py in pts])
        x += NARROW.get(ch, 1.0) * adv * S
    m = Image.new("L", size, 0)
    d = ImageDraw.Draw(m)
    w = int(stroke * S)
    for pts in strokes:
        d.line(pts, fill=255, width=w, joint="curve")
        for p in (pts[0], pts[-1]):
            d.ellipse((p[0] - w / 2, p[1] - w / 2, p[0] + w / 2, p[1] + w / 2), fill=255)
    mask = m.transform(size, Image.AFFINE, (1, SHEAR, -SHEAR * (pad + 4 * S), 0, 1, 0), resample=Image.BICUBIC)

    def layer(arr, color):
        out = np.zeros((size[1], size[0], 4), np.uint8)
        out[..., :3] = color
        out[..., 3] = (np.clip(arr, 0, 1) * 255).astype(np.uint8)
        return Image.fromarray(out, "RGBA")

    k = max(1, int(S / 30 + 0.5))
    out = Image.new("RGBA", size, (0, 0, 0, 0))
    sh = mask.filter(ImageFilter.GaussianBlur(4 * k))
    shadow = Image.new("RGBA", size, (10, 4, 30, 0))
    shadow.putalpha(sh.point(lambda v: int(v * 0.7)))
    out.alpha_composite(shadow, (5 * k, 7 * k))
    out.alpha_composite(layer(np.array(mask.filter(ImageFilter.MaxFilter(8 * k + 1))) / 255.0, (22, 10, 56)))
    out.alpha_composite(layer(np.array(mask.filter(ImageFilter.MaxFilter(4 * k + 1))) / 255.0, (255, 245, 230)))
    ys = np.linspace(0, 1, size[1])[:, None, None]
    grad = np.array(top, np.float32)[None, None, :] * (1 - ys) + np.array(bot, np.float32)[None, None, :] * ys
    fill = Image.fromarray(np.broadcast_to(grad, (size[1], size[0], 3)).astype(np.uint8), "RGB").convert("RGBA")
    fill.putalpha(mask)
    out.alpha_composite(fill)
    gloss = ImageChops.subtract(mask, mask.transform(size, Image.AFFINE, (1, 0, 0, 0, 1, -5 * k)))
    out.alpha_composite(layer(np.array(gloss) / 255.0 * 0.85, (255, 255, 255)))
    if wave:
        wv = Image.new("L", size, 0)
        wd = ImageDraw.Draw(wv)
        y0 = pad + 8 * S + int(S * 1.1)
        n = int((width - 2 * pad - 20) / 4)
        pts = [(pad + 10 + i * 4, y0 + math.sin(i / 10.0) * 9 * (0.4 + 0.6 * math.sin(i / max(n, 1) * math.pi))) for i in range(n)]
        wd.line(pts, fill=255, width=6, joint="curve")
        out.alpha_composite(layer(np.array(wv.filter(ImageFilter.MaxFilter(7))) / 255.0, (22, 10, 56)))
        out.alpha_composite(layer(np.array(wv) / 255.0, (96, 230, 255)))
    return out.crop(out.getbbox())


def build():
    top = line_image("CHAKANA.EXE", S=30, stroke=1.15, gap=2.0, top=(255, 236, 130), bot=(255, 110, 64), wave=True)
    sub = line_image("KAGAMI NETWORK", S=16, stroke=1.2, gap=2.2, top=(255, 255, 255), bot=(120, 220, 255), wave=False)
    # the second line is centred under the first, scaled to about two thirds of its width
    target = int(top.width * 0.66)
    sub = sub.resize((target, int(sub.height * target / sub.width)), Image.LANCZOS)
    gap = 18
    out = Image.new("RGBA", (top.width, top.height + gap + sub.height), (0, 0, 0, 0))
    out.alpha_composite(top, (0, 0))
    out.alpha_composite(sub, ((top.width - sub.width) // 2, top.height + gap))
    os.makedirs(ART, exist_ok=True)
    path = os.path.join(ART, "title_logo.png")
    out.save(path)
    print("wrote", path, out.size)


if __name__ == "__main__":
    build()
