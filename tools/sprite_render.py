"""Pre-rendered sprite pipeline (Doom / Donkey Kong Country style).

Builds a low-poly 3D model out of boxes, cylinders and spheres, renders it from 8 angles with a
tiny software rasterizer, shrinks it to pixel art (palette-limited, dark outline) and writes a
sprite sheet: 8 frames side by side. Frame 0 = seen from the front, frame k = camera moved k*45
degrees around the model. The hub picks the frame from where you stand.

    python tools/sprite_render.py            # renders every model in MODELS into art/
    python tools/sprite_render.py guide_bot  # just one

Needs: Pillow, numpy. No 3D app required.
"""
import math
import os
import sys

import numpy as np
from PIL import Image

FRAMES = 8
FRAME_PX = 64          # final frame size (pixels)
SUPER = 4              # supersample factor before shrinking
PALETTE_COLORS = 28
OUTLINE = (11, 10, 20)
LIGHT = np.array([-0.45, 0.8, 0.6])
LIGHT = LIGHT / np.linalg.norm(LIGHT)
STEPS = 4              # cel-shading levels


# ------------------------------------------------------------------ mesh building
class Mesh:
    def __init__(self):
        self.tris = []   # (3x3 vertices, color rgb, emissive)

    def add(self, verts, color, emissive=False):
        self.tris.append((np.array(verts, dtype=float), np.array(color, dtype=float), emissive))

    def box(self, c, size, color, emissive=False):
        cx, cy, cz = c
        hx, hy, hz = size[0] / 2, size[1] / 2, size[2] / 2
        v = [(cx + sx * hx, cy + sy * hy, cz + sz * hz) for sx in (-1, 1) for sy in (-1, 1) for sz in (-1, 1)]
        idx = lambda sx, sy, sz: ((sx > 0) * 4) + ((sy > 0) * 2) + (sz > 0)
        faces = [
            [(1, -1, -1), (1, 1, -1), (1, 1, 1), (1, -1, 1)],      # +x
            [(-1, -1, 1), (-1, 1, 1), (-1, 1, -1), (-1, -1, -1)],  # -x
            [(-1, 1, -1), (-1, 1, 1), (1, 1, 1), (1, 1, -1)],      # +y
            [(-1, -1, 1), (-1, -1, -1), (1, -1, -1), (1, -1, 1)],  # -y
            [(-1, -1, 1), (1, -1, 1), (1, 1, 1), (-1, 1, 1)],      # +z (front)
            [(1, -1, -1), (-1, -1, -1), (-1, 1, -1), (1, 1, -1)],  # -z
        ]
        for f in faces:
            q = [v[idx(*p)] for p in f]
            self.add([q[0], q[1], q[2]], color, emissive)
            self.add([q[0], q[2], q[3]], color, emissive)

    def cyl(self, c, r, h, color, n=10, emissive=False):
        cx, cy, cz = c
        top, bot = cy + h / 2, cy - h / 2
        for i in range(n):
            a0, a1 = 2 * math.pi * i / n, 2 * math.pi * (i + 1) / n
            p0 = (cx + r * math.cos(a0), cz + r * math.sin(a0))
            p1 = (cx + r * math.cos(a1), cz + r * math.sin(a1))
            self.add([(p0[0], bot, p0[1]), (p1[0], bot, p1[1]), (p1[0], top, p1[1])], color, emissive)
            self.add([(p0[0], bot, p0[1]), (p1[0], top, p1[1]), (p0[0], top, p0[1])], color, emissive)
            self.add([(cx, top, cz), (p0[0], top, p0[1]), (p1[0], top, p1[1])], color, emissive)

    def sphere(self, c, r, color, lat=7, lon=12, emissive=False):
        cx, cy, cz = c
        def pt(i, j):
            th = math.pi * i / lat
            ph = 2 * math.pi * j / lon
            return (cx + r * math.sin(th) * math.cos(ph), cy + r * math.cos(th), cz + r * math.sin(th) * math.sin(ph))
        for i in range(lat):
            for j in range(lon):
                a, b, c2, d = pt(i, j), pt(i + 1, j), pt(i + 1, j + 1), pt(i, j + 1)
                self.add([a, c2, b], color, emissive)   # winding: outward-facing
                self.add([a, d, c2], color, emissive)


# ------------------------------------------------------------------ rasterizer
def render(mesh, yaw, size, scale, center_y=0.75, elev=0.22):
    """Orthographic render. Returns an RGBA uint8 array of size x size."""
    img = np.zeros((size, size, 4), dtype=np.float32)
    zbuf = np.full((size, size), -1e9, dtype=np.float32)
    cy_, sy_ = math.cos(yaw), math.sin(yaw)
    ce, se = math.cos(elev), math.sin(elev)
    rot_y = np.array([[cy_, 0, sy_], [0, 1, 0], [-sy_, 0, cy_]])
    rot_x = np.array([[1, 0, 0], [0, ce, -se], [0, se, ce]])
    rot = rot_x @ rot_y
    cx = size / 2
    base_y = size * 0.5
    for verts, color, emissive in mesh.tris:
        v = verts @ rot.T
        n = np.cross(v[1] - v[0], v[2] - v[0])
        ln = np.linalg.norm(n)
        if ln < 1e-9:
            continue
        n /= ln
        if n[2] < 0:       # facing away from the camera (camera looks down -z, sees +z)
            continue
        px = v[:, 0] * scale + cx
        py = base_y - (v[:, 1] - center_y) * scale
        pz = v[:, 2]
        x0, x1 = int(max(0, math.floor(px.min()))), int(min(size - 1, math.ceil(px.max())))
        y0, y1 = int(max(0, math.floor(py.min()))), int(min(size - 1, math.ceil(py.max())))
        if x1 < x0 or y1 < y0:
            continue
        gx, gy = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
        den = (py[1] - py[2]) * (px[0] - px[2]) + (px[2] - px[1]) * (py[0] - py[2])
        if abs(den) < 1e-9:
            continue
        w0 = ((py[1] - py[2]) * (gx - px[2]) + (px[2] - px[1]) * (gy - py[2])) / den
        w1 = ((py[2] - py[0]) * (gx - px[2]) + (px[0] - px[2]) * (gy - py[2])) / den
        w2 = 1 - w0 - w1
        inside = (w0 >= 0) & (w1 >= 0) & (w2 >= 0)
        if not inside.any():
            continue
        z = w0 * pz[0] + w1 * pz[1] + w2 * pz[2]
        sub = zbuf[y0:y1 + 1, x0:x1 + 1]
        win = inside & (z > sub)
        if not win.any():
            continue
        if emissive:
            shade = 1.15
        else:
            lam = max(0.0, float(np.dot(n, rot @ LIGHT)))
            shade = 0.50 + 0.55 * (math.floor(lam * STEPS) / STEPS if lam < 1 else 1.0)
        rgb = np.clip(color * shade, 0, 255)
        sub[win] = z[win]
        img[y0:y1 + 1, x0:x1 + 1][win] = (*rgb, 255)
    return img.astype(np.uint8)


def to_pixel_art(rgba, px):
    big = Image.fromarray(rgba, "RGBA")
    small = big.resize((px, px), Image.BOX)
    arr = np.array(small)
    solid = arr[..., 3] > 127
    arr[..., 3] = np.where(solid, 255, 0)
    rgb = Image.fromarray(arr[..., :3], "RGB").quantize(colors=PALETTE_COLORS, dither=Image.Dither.NONE).convert("RGB")
    out = np.array(rgb)
    res = np.zeros((px, px, 4), dtype=np.uint8)
    res[solid, :3] = out[solid]
    res[solid, 3] = 255
    # dark outline on every transparent pixel touching a solid one
    pad = np.pad(solid, 1)
    neigh = pad[:-2, 1:-1] | pad[2:, 1:-1] | pad[1:-1, :-2] | pad[1:-1, 2:]
    edge = neigh & ~solid
    res[edge] = (*OUTLINE, 255)
    return res


def make_sheet(mesh, scale, center_y):
    sheet = Image.new("RGBA", (FRAME_PX * FRAMES, FRAME_PX), (0, 0, 0, 0))
    for k in range(FRAMES):
        big = render(mesh, yaw=2 * math.pi * k / FRAMES, size=FRAME_PX * SUPER, scale=scale * SUPER, center_y=center_y)
        sheet.paste(Image.fromarray(to_pixel_art(big, FRAME_PX), "RGBA"), (k * FRAME_PX, 0))
    return sheet


# ------------------------------------------------------------------ models (front of a model = +z)
def mash_machine():
    m = Mesh()
    m.box((0, 0.10, 0), (1.5, 0.20, 1.0), (60, 28, 90))                 # plinth
    m.box((0, 0.55, 0), (1.3, 0.72, 0.9), (110, 52, 160))               # body
    m.box((0, 0.97, 0), (1.34, 0.14, 0.94), (190, 120, 250))            # lid
    m.box((0, 0.58, 0.46), (0.95, 0.42, 0.05), (26, 11, 46))            # window
    m.sphere((-0.24, 0.58, 0.50), 0.13, (76, 201, 240), emissive=True)  # cyan orb
    m.sphere((0.24, 0.58, 0.50), 0.13, (249, 199, 79), emissive=True)   # gold orb
    m.cyl((0.45, 1.25, 0), 0.05, 0.5, (150, 150, 170))                  # antenna
    m.sphere((0.45, 1.55, 0), 0.09, (255, 90, 170), emissive=True)
    m.box((-0.3, 0.34, 0.47), (0.22, 0.10, 0.04), (230, 230, 240))      # slot
    return m


def guide_bot():
    m = Mesh()
    teal, dark, light = (46, 196, 182), (28, 120, 120), (190, 245, 235)
    m.box((-0.14, 0.18, 0), (0.16, 0.36, 0.20), dark)                   # legs
    m.box((0.14, 0.18, 0), (0.16, 0.36, 0.20), dark)
    m.box((0, 0.58, 0), (0.56, 0.46, 0.34), teal)                       # torso
    m.box((0, 0.62, 0.18), (0.30, 0.20, 0.03), light)                   # chest plate
    m.box((-0.38, 0.58, 0), (0.12, 0.38, 0.16), dark)                   # arms
    m.box((0.38, 0.58, 0), (0.12, 0.38, 0.16), dark)
    m.box((0, 1.0, 0), (0.42, 0.34, 0.34), teal)                        # head
    m.box((0, 1.02, 0.18), (0.30, 0.10, 0.03), (255, 240, 120), emissive=True)   # visor
    m.cyl((0, 1.28, 0), 0.025, 0.22, (200, 200, 210))                   # antenna
    m.sphere((0, 1.42, 0), 0.06, (255, 90, 170), emissive=True)
    return m


# name: (builder, pixels-per-unit, vertical centre of the model)
def hero(main, dark, accent, sword=False):
    """Fighter. Front = +z; the backpack and fin make the back view readable.
    sword=True raises the right arm with a glowing blade (used for the swing frame)."""
    m = Mesh()
    m.box((-0.13, 0.2, 0), (0.16, 0.4, 0.2), dark)                      # legs
    m.box((0.13, 0.2, 0), (0.16, 0.4, 0.2), dark)
    m.box((0, 0.62, 0), (0.52, 0.46, 0.32), main)                       # torso
    m.box((0, 0.64, -0.19), (0.34, 0.34, 0.08), dark)                   # backpack
    m.box((0, 0.66, -0.24), (0.14, 0.14, 0.04), accent, emissive=True)  # backpack light
    m.box((-0.36, 0.62, 0), (0.14, 0.36, 0.18), main)                   # left arm
    if sword:
        m.box((0.38, 0.92, 0.04), (0.16, 0.42, 0.18), dark)             # right arm raised
        m.box((0.38, 1.16, 0.04), (0.18, 0.07, 0.10), (230, 230, 240))  # hilt
        m.box((0.38, 1.40, 0.04), (0.07, 0.42, 0.07), (190, 255, 255), emissive=True)   # blade
    else:
        m.box((0.36, 0.62, 0.08), (0.16, 0.16, 0.4), dark)              # right arm = buster
        m.sphere((0.36, 0.62, 0.30), 0.09, accent, emissive=True)       # muzzle glow
    m.sphere((0, 1.08, 0), 0.27, main)                                  # helmet
    m.box((0, 1.10, 0.2), (0.3, 0.12, 0.06), accent, emissive=True)     # visor
    m.box((0, 1.40, -0.05), (0.06, 0.28, 0.22), accent)                 # fin
    return m


def drone():
    m = Mesh()
    steel = (90, 90, 112)
    m.sphere((0, 0.85, 0), 0.42, (220, 70, 90))
    m.cyl((0, 0.85, 0), 0.62, 0.07, steel, n=14)
    m.sphere((0, 0.88, 0.34), 0.14, (255, 230, 120), emissive=True)     # eye
    m.box((-0.58, 0.85, 0), (0.22, 0.10, 0.3), steel)
    m.box((0.58, 0.85, 0), (0.22, 0.10, 0.3), steel)
    m.cyl((0, 0.36, 0), 0.05, 0.5, steel)
    m.box((0, 1.36, -0.05), (0.08, 0.22, 0.08), (255, 230, 120))
    return m


def brute():
    m = Mesh()
    a, d = (120, 90, 200), (70, 50, 130)
    m.box((-0.22, 0.25, 0), (0.30, 0.5, 0.30), d)
    m.box((0.22, 0.25, 0), (0.30, 0.5, 0.30), d)
    m.box((0, 0.82, 0), (0.9, 0.7, 0.5), a)
    m.box((0, 0.84, 0.27), (0.46, 0.28, 0.05), (255, 200, 60), emissive=True)   # core
    m.box((-0.58, 0.92, 0), (0.2, 0.46, 0.2), a)
    m.box((0.58, 0.92, 0), (0.2, 0.46, 0.2), a)
    m.sphere((-0.58, 0.60, 0.04), 0.2, d)
    m.sphere((0.58, 0.60, 0.04), 0.2, d)
    m.box((0, 1.30, 0), (0.38, 0.30, 0.34), a)
    m.box((0, 1.32, 0.18), (0.28, 0.08, 0.05), (255, 80, 80), emissive=True)
    return m


def terminal():
    m = Mesh()
    m.box((0, 0.10, 0), (1.0, 0.20, 0.8), (40, 60, 80))
    m.box((0, 0.55, -0.05), (0.8, 0.7, 0.55), (60, 90, 120))
    m.box((0, 0.78, 0.24), (0.62, 0.4, 0.05), (14, 26, 40))                      # screen
    m.box((-0.12, 0.8, 0.27), (0.16, 0.24, 0.03), (255, 159, 28), emissive=True) # card icons
    m.box((0.12, 0.8, 0.27), (0.16, 0.24, 0.03), (76, 201, 240), emissive=True)
    m.box((0, 0.45, 0.26), (0.5, 0.06, 0.04), (255, 255, 255), emissive=True)   # card slot
    m.box((0, 1.0, -0.05), (0.7, 0.1, 0.5), (110, 150, 190))
    return m


MODELS = {
    "mash_machine": (mash_machine, 32, 0.82),
    "guide_bot": (guide_bot, 36, 0.75),
    "hero_blue": (lambda: hero((60, 120, 230), (30, 60, 140), (120, 240, 255)), 36, 0.75),
    "hero_blue_sword": (lambda: hero((60, 120, 230), (30, 60, 140), (120, 240, 255), sword=True), 36, 0.75),
    "hero_red": (lambda: hero((220, 60, 70), (120, 30, 40), (255, 200, 90)), 36, 0.75),
    "drone": (drone, 36, 0.75),
    "brute": (brute, 36, 0.75),
    "terminal": (terminal, 32, 0.82),
}

if __name__ == "__main__":
    out_dir = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "art")
    os.makedirs(out_dir, exist_ok=True)
    names = sys.argv[1:] or list(MODELS)
    for name in names:
        build, scale, cy = MODELS[name]
        make_sheet(build(), scale, cy).save(os.path.join(out_dir, name + ".png"))
        print("wrote", name + ".png", f"({FRAMES} frames of {FRAME_PX}px)")
