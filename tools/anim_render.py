"""Animated pre-rendered sprites with a DSi-era 3D look (chunky low-poly, toon shading, shine, rim light).

Models are rigs: body parts built from boxes / cylinders / spheres, grouped under joints that rotate
(arms swing, torso leans, propellers spin). Each POSE is a short list of joint settings; every frame
is rendered with a tiny software rasterizer, shrunk to pixel art and outlined. Output per model:

    art/<name>.png    rows = poses, columns = frames (96px cells)
    art/<name>.json   {"fw", "world_h", "feet", "rows": {pose: {"row", "n", "fps", "loop"}}}

    python tools/anim_render.py            # all models
    python tools/anim_render.py duel_hero  # one model

All designs here are original. Needs Pillow + numpy; no 3D app.
"""
import json
import math
import os
import sys
from contextlib import contextmanager

import numpy as np
from PIL import Image

FRAME = 96
SUPER = 3
COLORS = 44
OUTLINE = (10, 8, 22)
STEPS = 4
LIGHT = np.array([-0.45, 0.70, 0.75]); LIGHT /= np.linalg.norm(LIGHT)
HALF = LIGHT + np.array([0.0, 0.0, 1.0]); HALF /= np.linalg.norm(HALF)
RIM = np.array([70.0, 110.0, 200.0])


def rot(rx=0.0, ry=0.0, rz=0.0):
    rx, ry, rz = math.radians(rx), math.radians(ry), math.radians(rz)
    mx = np.array([[1, 0, 0], [0, math.cos(rx), -math.sin(rx)], [0, math.sin(rx), math.cos(rx)]])
    my = np.array([[math.cos(ry), 0, math.sin(ry)], [0, 1, 0], [-math.sin(ry), 0, math.cos(ry)]])
    mz = np.array([[math.cos(rz), -math.sin(rz), 0], [math.sin(rz), math.cos(rz), 0], [0, 0, 1]])
    return mz @ my @ mx


# ------------------------------------------------------------------ mesh with joints
class Mesh:
    def __init__(self):
        self.tris = []
        self.stack = []

    @contextmanager
    def joint(self, pivot, rx=0.0, ry=0.0, rz=0.0, t=(0.0, 0.0, 0.0)):
        """Everything added inside rotates about `pivot` (degrees) and shifts by t."""
        self.stack.append((np.array(pivot, float), rot(rx, ry, rz), np.array(t, float)))
        try:
            yield
        finally:
            self.stack.pop()

    def _tx(self, v):
        v = np.array(v, float)
        for pivot, r, t in reversed(self.stack):
            v = pivot + r @ (v - pivot) + t
        return v

    def add(self, verts, color, emissive=False, gloss=0.0):
        self.tris.append((np.array([self._tx(v) for v in verts]), np.array(color, float), emissive, gloss))

    def box(self, c, size, color, emissive=False, gloss=0.0):
        cx, cy, cz = c
        hx, hy, hz = size[0] / 2, size[1] / 2, size[2] / 2
        v = {}
        for sx in (-1, 1):
            for sy in (-1, 1):
                for sz in (-1, 1):
                    v[(sx, sy, sz)] = (cx + sx * hx, cy + sy * hy, cz + sz * hz)
        faces = [
            [(1, -1, -1), (1, 1, -1), (1, 1, 1), (1, -1, 1)],
            [(-1, -1, 1), (-1, 1, 1), (-1, 1, -1), (-1, -1, -1)],
            [(-1, 1, -1), (-1, 1, 1), (1, 1, 1), (1, 1, -1)],
            [(-1, -1, 1), (-1, -1, -1), (1, -1, -1), (1, -1, 1)],
            [(-1, -1, 1), (1, -1, 1), (1, 1, 1), (-1, 1, 1)],
            [(1, -1, -1), (-1, -1, -1), (-1, 1, -1), (1, 1, -1)],
        ]
        for f in faces:
            q = [v[p] for p in f]
            self.add([q[0], q[1], q[2]], color, emissive, gloss)
            self.add([q[0], q[2], q[3]], color, emissive, gloss)

    def cyl(self, c, r, h, color, n=10, emissive=False, gloss=0.0):
        cx, cy, cz = c
        top, bot = cy + h / 2, cy - h / 2
        for i in range(n):
            a0, a1 = 2 * math.pi * i / n, 2 * math.pi * (i + 1) / n
            p0 = (cx + r * math.cos(a0), cz + r * math.sin(a0))
            p1 = (cx + r * math.cos(a1), cz + r * math.sin(a1))
            self.add([(p0[0], bot, p0[1]), (p1[0], bot, p1[1]), (p1[0], top, p1[1])], color, emissive, gloss)
            self.add([(p0[0], bot, p0[1]), (p1[0], top, p1[1]), (p0[0], top, p0[1])], color, emissive, gloss)
            self.add([(cx, top, cz), (p0[0], top, p0[1]), (p1[0], top, p1[1])], color, emissive, gloss)

    def sphere(self, c, r, color, squash=(1.0, 1.0, 1.0), lat=9, lon=16, emissive=False, gloss=0.0):
        cx, cy, cz = c

        def pt(i, j):
            th = math.pi * i / lat
            ph = 2 * math.pi * j / lon
            return (cx + r * squash[0] * math.sin(th) * math.cos(ph),
                    cy + r * squash[1] * math.cos(th),
                    cz + r * squash[2] * math.sin(th) * math.sin(ph))
        for i in range(lat):
            for j in range(lon):
                a, b, c2, d = pt(i, j), pt(i + 1, j), pt(i + 1, j + 1), pt(i, j + 1)
                self.add([a, c2, b], color, emissive, gloss)
                self.add([a, d, c2], color, emissive, gloss)


# ------------------------------------------------------------------ rasterizer
def render(mesh, yaw_deg, size, scale, cy):
    img = np.zeros((size, size, 4), dtype=np.float32)
    zbuf = np.full((size, size), -1e9, dtype=np.float32)
    rot_all = rot(rx=9.0) @ rot(ry=yaw_deg)
    cx = size / 2
    base_y = size / 2
    for verts, color, emissive, gloss in mesh.tris:
        v = verts @ rot_all.T
        n = np.cross(v[1] - v[0], v[2] - v[0])
        ln = np.linalg.norm(n)
        if ln < 1e-9:
            continue
        n /= ln
        if n[2] < 0:
            continue
        px = v[:, 0] * scale + cx
        py = base_y - (v[:, 1] - cy) * scale
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
            rgb = color * 1.12
        else:
            lam = max(0.0, float(np.dot(n, LIGHT)))
            step = (math.floor(lam * STEPS) / STEPS) if lam < 1.0 else 1.0
            rgb = color * (0.46 + 0.60 * step)
            if gloss > 0.0 and max(0.0, float(np.dot(n, HALF))) ** 26 > 0.5:
                rgb = rgb + 255.0 * 0.38 * gloss          # toon shine band
            rim = (1.0 - max(0.0, float(n[2]))) ** 2.0 * 0.28
            rgb = rgb + RIM * rim
        rgb = np.clip(rgb, 0, 255)
        sub[win] = z[win]
        img[y0:y1 + 1, x0:x1 + 1][win] = (*rgb, 255)
    return img.astype(np.uint8)


def to_pixel_art(rgba, px):
    small = Image.fromarray(rgba, "RGBA").resize((px, px), Image.BOX)
    arr = np.array(small)
    solid = arr[..., 3] > 127
    arr[..., 3] = np.where(solid, 255, 0)
    q = Image.fromarray(arr[..., :3], "RGB").quantize(colors=COLORS, dither=Image.Dither.NONE).convert("RGB")
    out = np.array(q)
    res = np.zeros((px, px, 4), dtype=np.uint8)
    res[solid, :3] = out[solid]
    res[solid, 3] = 255
    pad = np.pad(solid, 1)
    neigh = pad[:-2, 1:-1] | pad[2:, 1:-1] | pad[1:-1, :-2] | pad[1:-1, 2:]
    res[neigh & ~solid] = (*OUTLINE, 255)
    return res


# ------------------------------------------------------------------ models. y up, front = +z, feet at y=0
def hero(p, pal, rival=False):
    """Original anime-reploid look: big glowing eyes, hair, cropped jacket with bare midriff,
    trailing scarf, baggy pants, chunky boots, oversized hands. Front = +z."""
    skin, hair, main, dark, acc, trim, eye = pal
    m = Mesh()
    sway = p.get("sway", p.get("bob", 0.0) * 500.0)
    for sx in (-1, 1):                                                      # baggy legs + chunky boots, hip-swing joints
        with m.joint((sx * 0.125, 0.66, 0), rx=p.get("ll", 0.0) if sx < 0 else p.get("lr", 0.0)):
            m.cyl((sx * 0.125, 0.43, 0), 0.115, 0.40, dark, n=11, gloss=0.2)
            m.cyl((sx * 0.125, 0.25, 0), 0.138, 0.09, trim, n=11)
            m.box((sx * 0.125, 0.075, 0.06), (0.23, 0.15, 0.33), main, gloss=0.6)
            m.box((sx * 0.125, 0.15, 0.21), (0.17, 0.05, 0.06), acc, emissive=True)
    m.box((0, 0.68, 0), (0.42, 0.17, 0.28), dark)
    m.box((0, 0.77, 0), (0.45, 0.05, 0.30), trim)                           # belt
    m.box((0, 0.77, 0.16), (0.09, 0.06, 0.02), acc, emissive=True)
    with m.joint((0, 0.68, 0), rx=p.get("lean", 0.0), t=(0, p.get("bob", 0.0), 0)):
        m.box((0, 0.87, 0), (0.30, 0.17, 0.22), skin)                       # bare midriff
        m.box((0, 1.07, 0), (0.46, 0.27, 0.30), main, gloss=0.7)            # cropped jacket
        for sx in (-1, 1):
            m.box((sx * 0.22, 0.95, 0.01), (0.09, 0.12, 0.27), main, gloss=0.4)        # jacket hem flaps
            m.sphere((sx * 0.31, 1.13, 0), 0.125 if not rival else 0.15, main, squash=(1, 0.85, 1), gloss=0.8)
            if rival:
                m.box((sx * 0.36, 1.25, 0), (0.05, 0.17, 0.05), trim)       # shoulder spikes
        m.box((0, 1.222, 0), (0.34, 0.07, 0.27), trim)                      # collar
        m.box((0, 1.02, 0.158), (0.20, 0.11, 0.025), acc, emissive=True)    # chest light
        m.box((0, 1.03, -0.20), (0.26, 0.26, 0.10), dark)                   # wave unit
        m.box((0, 1.08, -0.255), (0.20, 0.035, 0.02), acc, emissive=True)
        m.box((0, 0.98, -0.255), (0.20, 0.035, 0.02), acc, emissive=True)
        with m.joint((0, 1.20, -0.16), rx=sway):                            # scarf tails
            m.box((0.05, 0.93, -0.22), (0.15, 0.58, 0.05), acc, gloss=0.3)
            m.box((-0.07, 0.86, -0.25), (0.13, 0.50, 0.05), acc, gloss=0.3)
        with m.joint((0, 1.24, 0), rx=p.get("head", 0.0)):
            m.sphere((0, 1.47, 0), 0.27, skin, squash=(1.0, 0.98, 1.0), gloss=0.5)          # face
            for sx in (-1, 1):
                m.sphere((sx * 0.105, 1.465, 0.24), 0.095, (255, 255, 255), squash=(1, 1.25, 0.45), lat=7, lon=12)   # big eyes
                m.sphere((sx * 0.105, 1.455, 0.275), 0.068, eye, squash=(1, 1.3, 0.4), emissive=True, lat=6, lon=10)
                m.sphere((sx * 0.085, 1.50, 0.29), 0.022, (255, 255, 255), emissive=True, lat=4, lon=6)   # eye shine
                m.sphere((sx * 0.20, 1.40, 0.19), 0.04, (255, 160, 160), squash=(1, 0.6, 0.4), lat=4, lon=6)   # blush
            m.box((0, 1.37, 0.262), (0.05, 0.012, 0.01), (120, 50, 60))                     # mouth
            m.sphere((0, 1.54, -0.12), 0.30, hair, squash=(1.05, 1.0, 1.0), gloss=0.9)       # hair mass (behind the face)
            for x, rzv in ((-0.15, 18), (-0.05, 6), (0.05, -6), (0.15, -18)):                 # fringe
                with m.joint((x, 1.66, 0.2), rz=rzv):
                    m.box((x, 1.64, 0.2), (0.10, 0.15, 0.07), hair, gloss=0.8)
            for sx in (-1, 1):
                m.box((sx * 0.28, 1.42, 0.06), (0.07, 0.27, 0.11), hair, gloss=0.6)             # side locks
                m.sphere((sx * 0.285, 1.47, 0), 0.085, main, lat=6, lon=10, gloss=0.7)          # ear piece
                with m.joint((sx * 0.30, 1.52, -0.02), rz=-sx * 28):
                    m.box((sx * 0.37, 1.54, -0.05), (0.14, 0.06, 0.20), acc, gloss=0.5)         # ear fin
            m.cyl((0, 1.585, 0), 0.265, 0.05, trim, n=14)                                       # circlet
            m.box((0, 1.585, 0.265), (0.07, 0.07, 0.03), acc, emissive=True)                    # forehead gem
            with m.joint((0, 1.5, -0.26), rx=sway * 0.8):
                if rival:                                                                       # long ponytail
                    m.box((0, 1.38, -0.34), (0.13, 0.22, 0.10), hair, gloss=0.8)
                    m.box((0, 1.20, -0.40), (0.11, 0.24, 0.09), hair, gloss=0.8)
                    m.box((0, 1.02, -0.44), (0.09, 0.22, 0.08), hair, gloss=0.8)
                else:                                                                           # spiky tail
                    m.box((0, 1.42, -0.32), (0.14, 0.2, 0.10), hair, gloss=0.8)
                    m.box((0.03, 1.28, -0.38), (0.10, 0.2, 0.08), hair, gloss=0.8)
        # arms: bare upper arm, gauntlet forearm, oversized hand
        for sx, ar, er, name in ((-1, p.get("al", 0.0), p.get("el", 0.0), "l"), (1, p.get("ar", 0.0), p.get("er", 0.0), "r")):
            with m.joint((sx * 0.36, 1.12, 0), rx=ar):
                m.cyl((sx * 0.36, 0.98, 0), 0.065, 0.28, skin, n=10, gloss=0.3)
                with m.joint((sx * 0.36, 0.84, 0), rx=er):
                    if name == "r" and p.get("cannon", False):
                        m.cyl((sx * 0.36, 0.67, 0.0), 0.105, 0.36, dark, n=10, gloss=0.5)
                        m.sphere((sx * 0.36, 0.46, 0), 0.075 + p.get("flash", 0.0), acc, emissive=True, lat=6, lon=10)
                    else:
                        m.cyl((sx * 0.36, 0.71, 0), 0.085, 0.26, main, n=10, gloss=0.4)
                        m.sphere((sx * 0.36, 0.55, 0), 0.115, trim, squash=(1.0, 1.1, 0.9), lat=7, lon=12, gloss=0.5)   # big hand
                        if name == "r" and p.get("blade", False):
                            m.box((sx * 0.36, 0.62, 0), (0.26, 0.05, 0.12), trim)
                            m.box((sx * 0.36, 0.30, 0), (0.12, 0.62, 0.14), (200, 255, 255), emissive=True)
                        g = p.get("glow_" + name, 0.0)
                        if g > 0:
                            m.sphere((sx * 0.36, 0.48, 0.05), g, acc, emissive=True, lat=6, lon=10)
    return m


def buzzcap(p):
    """Hard-hat drone: round body, yellow dome helmet, big eye, spinning propeller."""
    m = Mesh()
    steel = (84, 84, 108)
    with m.joint((0, 0.85, 0), rz=p.get("tilt", 0.0), t=(0, p.get("bob", 0.0), 0)):
        m.sphere((0, 0.85, 0), 0.38, (232, 84, 70), squash=(1.0, 0.95, 1.0), gloss=0.7)
        m.cyl((0, 0.70, 0), 0.355, 0.06, steel, n=16)
        m.sphere((0, 1.05, 0), 0.34, (250, 202, 64), squash=(1.0, 0.72, 1.0), gloss=1.0)
        m.cyl((0, 0.97, 0), 0.47, 0.05, (255, 218, 96), n=18, gloss=0.5)
        m.sphere((0, 0.86, 0.33), 0.13 + p.get("glow", 0.0), (255, 255, 170), emissive=True, lat=7, lon=12)
        m.sphere((p.get("look", 0.0) * 0.06, 0.86 + p.get("lookv", 0.0) * 0.03, 0.45), 0.05, (40, 20, 40), lat=5, lon=8)
        for sx in (-1, 1):
            with m.joint((sx * 0.40, 0.84, 0), rx=-p.get("arm", 0.0)):
                m.cyl((sx * 0.42, 0.76, 0), 0.035, 0.14, steel)
                m.sphere((sx * 0.44, 0.66, 0.04), 0.09, (240, 240, 250), lat=6, lon=10, gloss=0.4)
        m.cyl((0, 1.30, 0), 0.03, 0.14, steel)
        with m.joint((0, 1.37, 0), ry=p.get("prop", 0.0)):
            m.box((0, 1.37, 0), (0.95, 0.03, 0.12), (214, 214, 230))
            m.box((0, 1.37, 0), (0.12, 0.03, 0.95), (214, 214, 230))
    return m


def brute(p):
    """Heavy plated golem with a glowing core."""
    m = Mesh()
    main, dark, core = (112, 82, 192), (66, 46, 128), (255, 196, 70)
    for sx in (-1, 1):
        m.box((sx * 0.22, 0.28, 0), (0.30, 0.56, 0.32), dark, gloss=0.2)
        m.box((sx * 0.22, 0.05, 0.05), (0.34, 0.10, 0.42), main)
    with m.joint((0, 0.56, 0), rx=p.get("lean", 0.0), t=(0, p.get("bob", 0.0), 0)):
        m.box((0, 0.88, 0), (0.92, 0.62, 0.52), main, gloss=0.6)
        m.box((0, 0.88, 0.27), (0.50, 0.30, 0.05), (30, 20, 50))
        m.box((0, 0.88, 0.30), (0.34 + p.get("glow", 0.0), 0.18 + p.get("glow", 0.0), 0.03), core, emissive=True)
        m.box((0, 0.58, 0), (0.70, 0.10, 0.46), dark)
        for sx in (-1, 1):
            m.sphere((sx * 0.55, 1.12, 0), 0.20, main, squash=(1, 0.8, 1), gloss=0.8)
            with m.joint((sx * 0.56, 1.05, 0), rx=p.get("arm", 0.0)):
                m.cyl((sx * 0.60, 0.85, 0), 0.12, 0.40, dark, n=10)
                m.sphere((sx * 0.60, 0.58, 0.06), 0.21, main, gloss=0.6)
                m.box((sx * 0.60, 0.56, 0.18), (0.18, 0.05, 0.05), dark)
        m.box((0, 1.34, 0), (0.40, 0.28, 0.36), main, gloss=0.7)
        m.box((0, 1.36, 0.19), (0.30, 0.08, 0.04), (255, 80, 80), emissive=True)
        for sx in (-1, 1):
            with m.joint((sx * 0.14, 1.50, 0), rz=-sx * 25):
                m.box((sx * 0.14, 1.60, 0), (0.06, 0.20, 0.06), dark)
    return m


# skin, hair, jacket, dark, glow, trim, eye
PAL_BLUE = ((255, 218, 192), (248, 168, 66), (44, 96, 214), (30, 44, 100), (96, 226, 255), (240, 244, 255), (70, 226, 255))
PAL_RED = ((250, 214, 196), (232, 232, 246), (208, 52, 74), (96, 24, 44), (255, 170, 70), (255, 236, 210), (255, 214, 84))

S, PI = math.sin, math.pi
TAU = 2 * math.pi


def cyc(n, fn):
    """n frames of a seamless loop: fn gets the phase u in [0, 1)."""
    return [fn(i / n) for i in range(n)]


HERO_POSES = {
    # breathing, weight shift, head drift, arm swing; scarf / ponytail lag behind the body
    "idle": {"fps": 8, "loop": True, "frames": cyc(8, lambda u: {
        "bob": 0.014 * S(TAU * u), "lean": 1.4 * S(TAU * u + 0.6), "head": 2.2 * S(TAU * u + 1.2),
        "al": 6 + 4 * S(TAU * u + 0.4), "el": -4, "ar": -26 + 3 * S(TAU * u + 0.9), "er": -32, "cannon": True,
        "sway": 7 * S(TAU * u - 0.8), "ll": 1.5 * S(TAU * u), "lr": -1.5 * S(TAU * u)})},
    # run / strafe cycle: legs scissor, arms counter-swing, body bobs and leans into the move
    "move": {"fps": 14, "loop": True, "frames": cyc(8, lambda u: {
        "bob": 0.035 * abs(S(TAU * u)), "lean": 6 + 2 * S(TAU * 2 * u), "head": -2 + 2 * S(TAU * u),
        "ll": 30 * S(TAU * u), "lr": -30 * S(TAU * u),
        "al": 26 * S(TAU * u + PI), "ar": -28 - 14 * S(TAU * u), "er": -36, "cannon": True,
        "sway": 20 + 10 * S(TAU * u - 1.0)})},
    "shoot": {"fps": 14, "loop": False, "frames": [
        {"ar": -80, "er": -4, "cannon": True, "flash": 0.10, "lean": 1, "al": 10, "sway": 4},
        {"ar": -90, "er": -4, "cannon": True, "flash": 0.19, "lean": 4, "al": 14, "head": 2, "sway": 10},
        {"ar": -96, "er": -4, "cannon": True, "flash": 0.10, "lean": 3, "al": 12, "bob": -0.012, "sway": 14},
        {"ar": -86, "er": -6, "cannon": True, "flash": 0.0, "lean": 2, "al": 9, "sway": 8},
        {"ar": -66, "er": -14, "cannon": True, "flash": 0.0, "lean": 0, "al": 7, "sway": 3}]},
    "cast": {"fps": 9, "loop": False, "frames": [
        {"al": -50, "ar": -50, "el": -20, "er": -20, "glow_l": 0.04, "glow_r": 0.04, "bob": -0.02, "lean": 3, "sway": -4},
        {"al": -90, "ar": -90, "el": -24, "er": -24, "glow_l": 0.08, "glow_r": 0.08, "bob": 0.01, "head": -4, "sway": 6},
        {"al": -118, "ar": -118, "el": -28, "er": -28, "glow_l": 0.13, "glow_r": 0.13, "bob": 0.04, "head": -8, "sway": 14},
        {"al": -128, "ar": -128, "el": -30, "er": -30, "glow_l": 0.17, "glow_r": 0.17, "bob": 0.055, "head": -10, "sway": 20}]},
    "slash": {"fps": 14, "loop": False, "frames": [
        {"ar": -158, "er": -10, "blade": True, "lean": -8, "al": 18, "sway": -8},
        {"ar": -140, "er": -8, "blade": True, "lean": -3, "al": 22, "sway": 4},
        {"ar": -100, "er": -8, "blade": True, "lean": 6, "al": 26, "sway": 14},
        {"ar": -46, "er": -6, "blade": True, "lean": 13, "al": 30, "sway": 24},
        {"ar": -20, "er": -6, "blade": True, "lean": 16, "al": 34, "sway": 18}]},
    "hurt": {"fps": 9, "loop": False, "frames": [
        {"lean": -18, "head": -14, "al": 30, "ar": 24, "er": 0, "cannon": True, "sway": 24, "bob": -0.02},
        {"lean": -12, "head": -9, "al": 24, "ar": 14, "er": -4, "cannon": True, "sway": 12},
        {"lean": -5, "head": -3, "al": 14, "ar": 2, "er": -14, "cannon": True, "sway": 2}]},
    "dash": {"fps": 12, "loop": True, "frames": cyc(4, lambda u: {
        "lean": 24, "al": 34 + 4 * S(TAU * u), "ar": -22, "er": -10, "cannon": True, "bob": 0.02 * S(TAU * u),
        "ll": 40 * S(TAU * u), "lr": -40 * S(TAU * u), "sway": 26})},
    # holographic guard: left hand thrown forward, projecting the shield
    "guard": {"fps": 12, "loop": False, "frames": [
        {"al": -70, "el": -10, "ar": -30, "er": -34, "cannon": True, "lean": 2, "glow_l": 0.05, "sway": 6},
        {"al": -92, "el": -6, "ar": -28, "er": -32, "cannon": True, "lean": 4, "head": 2, "glow_l": 0.10, "sway": 12},
        {"al": -98, "el": -4, "ar": -28, "er": -32, "cannon": True, "lean": 5, "head": 3, "glow_l": 0.14, "sway": 10}]},
}

BUZZ_POSES = {
    "idle": {"fps": 8, "loop": True, "frames": cyc(8, lambda u: {
        "bob": 0.04 * S(TAU * u), "prop": 62 * u * 8, "arm": 8 + 6 * S(TAU * u + 0.5), "tilt": 4 * S(TAU * u + 1.0),
        "look": S(TAU * u * 0.5 + 0.3), "lookv": 0.6 * S(TAU * u + 2.0)})},
    "attack": {"fps": 11, "loop": False, "frames": [
        {"arm": 10, "glow": 0.00, "prop": 40, "bob": -0.03, "tilt": -6},
        {"arm": 40, "glow": 0.03, "prop": 120, "bob": -0.04, "tilt": -9},
        {"arm": 72, "glow": 0.07, "prop": 200, "bob": 0.0, "tilt": 3},
        {"arm": 84, "glow": 0.12, "prop": 280, "bob": 0.04, "tilt": 6}]},
    "hurt": {"fps": 9, "loop": False, "frames": [
        {"tilt": 24, "prop": 60, "arm": 34, "bob": -0.03}, {"tilt": -14, "prop": 140, "arm": 22},
        {"tilt": 6, "prop": 220, "arm": 12}]},
}

BRUTE_POSES = {
    "idle": {"fps": 6, "loop": True, "frames": cyc(8, lambda u: {
        "bob": 0.03 * S(TAU * u), "arm": 5 + 4 * S(TAU * u + 0.3), "lean": 1.6 * S(TAU * u + 1.0), "glow": 0.015 + 0.015 * S(TAU * u * 2)})},
    "attack": {"fps": 9, "loop": False, "frames": [
        {"arm": -30, "glow": 0.0, "lean": -2}, {"arm": -80, "glow": 0.03, "lean": -5},
        {"arm": -130, "glow": 0.08, "lean": -8}, {"arm": -152, "glow": 0.13, "lean": -9}]},
    "hurt": {"fps": 9, "loop": False, "frames": [{"lean": -14, "arm": 16}, {"lean": -9, "arm": 10}, {"lean": -3, "arm": 4}]},
}

# name: (builder, yaw, pixels per unit, vertical centre, poses, world height of a frame)
MODELS = {
    "duel_hero": (lambda p: hero(p, PAL_BLUE), 180, 42.0, 1.0, HERO_POSES, 1.7),
    "duel_rival": (lambda p: hero(p, PAL_RED, rival=True), 0, 42.0, 1.0, HERO_POSES, 1.7),
    "duel_buzzcap": (buzzcap, 0, 50.0, 0.82, BUZZ_POSES, 1.28),
    "duel_brute": (brute, 0, 44.0, 0.9, BRUTE_POSES, 1.45),
}


def build(name, art_dir):
    builder, yaw, scale, cy, poses, world_h = MODELS[name]
    cols = max(len(v["frames"]) for v in poses.values())
    sheet = Image.new("RGBA", (FRAME * cols, FRAME * len(poses)), (0, 0, 0, 0))
    meta = {"fw": FRAME, "world_h": world_h, "feet": (FRAME / 2 + cy * scale) / FRAME, "rows": {}}
    for row, (pose_name, spec) in enumerate(poses.items()):
        for col, frame in enumerate(spec["frames"]):
            big = render(builder(frame), yaw, FRAME * SUPER, scale * SUPER, cy)
            sheet.paste(Image.fromarray(to_pixel_art(big, FRAME), "RGBA"), (col * FRAME, row * FRAME))
        meta["rows"][pose_name] = {"row": row, "n": len(spec["frames"]), "fps": spec["fps"], "loop": spec["loop"]}
    sheet.save(os.path.join(art_dir, name + ".png"))
    with open(os.path.join(art_dir, name + ".json"), "w") as f:
        json.dump(meta, f)
    print("wrote", name, f"({len(poses)} poses)")


if __name__ == "__main__":
    art = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "art")
    os.makedirs(art, exist_ok=True)
    for n in (sys.argv[1:] or list(MODELS)):
        build(n, art)
