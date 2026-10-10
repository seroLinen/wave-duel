"""Pre-rendered lock-on art: beveled chevron arrows and reticle corners, green (locked) and red (no lock).

Uses the same tiny software rasterizer as sprite_render.py (boxes / extruded shapes, toon shading, palette-limited,
dark outline). Each arrow sheet is 8 frames of the cone turning one facet, so the light slides across it and the loop is seamless.

    python tools/arrow_render.py            # writes art/lock_arrow_{green,red}.png (8 frames) and art/lock_corner_{green,red}.png (4 corner frames)

Needs: Pillow, numpy.
"""
import math
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sprite_render as sr

HERE = os.path.dirname(os.path.abspath(__file__))
ART = os.path.join(HERE, "..", "art")
PX = 64
SUPER = 4

PALETTES = {
    "green": {"base": (24, 120, 62), "face": (70, 235, 120), "shine": (200, 255, 215)},
    "red": {"base": (130, 24, 36), "face": (245, 70, 70), "shine": (255, 205, 195)},
}


def extrude(mesh, poly, z0, z1, color, emissive=False):
    """Prism from a convex-ish 2D polygon (list of (x, y), counter-clockwise): front cap at z1, walls, no back cap."""
    n = len(poly)
    cx = sum(p[0] for p in poly) / n
    cy = sum(p[1] for p in poly) / n
    for i in range(n):                                       # front cap as a fan
        a, b = poly[i], poly[(i + 1) % n]
        mesh.add([(cx, cy, z1), (a[0], a[1], z1), (b[0], b[1], z1)], color, emissive)
    for i in range(n):                                       # walls
        a, b = poly[i], poly[(i + 1) % n]
        mesh.add([(a[0], a[1], z0), (b[0], b[1], z0), (b[0], b[1], z1)], color, False)
        mesh.add([(a[0], a[1], z0), (b[0], b[1], z1), (a[0], a[1], z1)], color, False)


def inset(poly, k):
    n = len(poly)
    cx = sum(p[0] for p in poly) / n
    cy = sum(p[1] for p in poly) / n
    return [(cx + (p[0] - cx) * (1 - k), cy + (p[1] - cy) * (1 - k)) for p in poly]


def cone(m, ring_y, tip_y, r, color, n=5, emissive=False, phase=0.0):
    """A low-poly cone pointing up (+y): n faceted sides, so turning it makes the light slide across the facets."""
    tip = (0.0, tip_y, 0.0)
    for i in range(n):
        a0 = phase + 2 * math.pi * i / n
        a1 = phase + 2 * math.pi * (i + 1) / n
        p0 = (r * math.cos(a0), ring_y, r * math.sin(a0))
        p1 = (r * math.cos(a1), ring_y, r * math.sin(a1))
        m.add([p0, tip, p1], color, emissive)


def chevron(pal):
    """Despite the name: a narrow arrow made of a faceted cone head and a thin stick behind it, with a small tail disc."""
    m = sr.Mesh()
    n = 5
    stick = tuple(int(b * 0.45 + f * 0.55) for b, f in zip(pal["base"], pal["face"]))
    m.cyl((0.0, -0.45, 0.0), 0.075, 1.05, stick, n=n)                         # the stick
    m.cyl((0.0, -0.98, 0.0), 0.16, 0.08, pal["face"], n=n, emissive=True)    # tail disc
    cone(m, 0.10, 1.05, 0.30, pal["face"], n=n)                              # the head
    m.cyl((0.0, 0.08, 0.0), 0.31, 0.05, pal["base"], n=n)                    # collar where the head meets the stick
    return m


def corner(pal):
    """One reticle corner: an L bracket, beveled."""
    m = sr.Mesh()
    w = 0.34
    # centred in the frame: the bracket's outer corner sits at (-0.6, -0.6), so the game can place it by that corner
    horiz = [(-0.6, -0.6), (0.6, -0.6), (0.6, -0.6 + w), (-0.6, -0.6 + w)]
    vert = [(-0.6, -0.6), (-0.6 + w, -0.6), (-0.6 + w, 0.6), (-0.6, 0.6)]
    for part in (horiz, vert):
        extrude(m, part, -0.10, 0.10, pal["base"])
        extrude(m, inset(part, 0.20), 0.10, 0.17, pal["face"], emissive=True)
    return m


def to_frame(mesh, yaw, elev, scale, cy):
    big = sr.render(mesh, yaw=yaw, size=PX * SUPER, scale=scale * SUPER, center_y=cy, elev=elev)
    return Image.fromarray(sr.to_pixel_art(big, PX), "RGBA")


def build():
    os.makedirs(ART, exist_ok=True)
    for name, pal in PALETTES.items():
        mesh = chevron(pal)
        sheet = Image.new("RGBA", (PX * 8, PX), (0, 0, 0, 0))
        for k in range(8):
            yaw = 2 * math.pi * k / 8 / 5                         # one facet's worth of turn over 8 frames, so it loops
            sheet.paste(to_frame(mesh, yaw, 0.0, 26.0, 0.0), (k * PX, 0))
        sheet.save(os.path.join(ART, "lock_arrow_%s.png" % name))
        cm = corner(pal)
        bl = to_frame(cm, 0.0, 0.0, 26.0, 0.0)                    # the bracket's outer corner is at the lower left
        corners = Image.new("RGBA", (PX * 4, PX), (0, 0, 0, 0))   # frames: top-left, top-right, bottom-left, bottom-right
        corners.paste(bl.transpose(Image.FLIP_TOP_BOTTOM), (0, 0))
        corners.paste(bl.transpose(Image.ROTATE_180), (PX, 0))
        corners.paste(bl, (PX * 2, 0))
        corners.paste(bl.transpose(Image.FLIP_LEFT_RIGHT), (PX * 3, 0))
        corners.save(os.path.join(ART, "lock_corner_%s.png" % name))
    print("wrote lock arrow + corner art into", os.path.abspath(ART))


if __name__ == "__main__":
    build()
