"""Pre-rendered duel backdrop: a dusk megacity seen from above, built as parallax layers.

Composition goals: a dark purple sky with a thin hot-orange horizon band, a landmark tower with a
glowing crown, dense teal-grey blocks full of warm lit windows and horizontal light bands, purple rooftop
pipes, and an avenue of traffic lights running to the tower. All painted here from scratch.

Painted at 560x270 (shown at 2x so it matches the chunky sprites), ordered dithering, no anti-aliasing.
Output in art/:
  bg_sky.png      sky + orange horizon band
  bg_clouds.png   faint haze streaks (tiles horizontally; the game drifts them)
  bg_far.png      hazy far skyline + the landmark tower
  bg_mid.png      mid-distance blocks and the avenue
  bg_near.png     large foreground blocks
  bg_mid_l0..2.png, bg_near_l0..2.png   bright window lights in three groups; the game fades each group
                                         on its own rhythm, so windows twinkle without anything moving

    python tools/backdrop_render.py [seed]
Needs Pillow + numpy.
"""
import math
import os
import random
import sys

import numpy as np
from PIL import Image, ImageDraw

W, H = 560, 270
HORIZON = 62
TOWER_X = 288
BAYER = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]) / 16.0


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def stops_color(stops, t):
    for i in range(len(stops) - 1):
        t0, c0 = stops[i]
        t1, c1 = stops[i + 1]
        if t <= t1:
            return lerp(c0, c1, (t - t0) / max(1e-6, t1 - t0))
    return stops[-1][1]


def dither(arr, step=9):
    h, w = arr.shape[:2]
    b = np.tile(BAYER, (h // 4 + 1, w // 4 + 1))[:h, :w][..., None]
    return (np.floor((arr + b * step) / step) * step).clip(0, 255).astype(np.uint8)


def new_layer():
    return Image.new("RGBA", (W, H), (0, 0, 0, 0))


def road_x(y):
    return TOWER_X + (y - (HORIZON + 34)) * 0.30


def road_hw(y):
    return 2.5 + max(0.0, y - (HORIZON + 34)) * 0.17


# ---------------------------------------------------------------- sky
def sky():
    stops = [(0.0, (22, 14, 58)), (0.55, (50, 28, 96)), (0.80, (96, 40, 118)), (0.92, (190, 70, 96)), (1.0, (255, 120, 44))]
    arr = np.zeros((H, W, 3), dtype=np.float32)
    for y in range(H):
        arr[y, :, :] = stops_color(stops, min(1.0, y / (HORIZON + 2))) if y <= HORIZON + 2 else (40, 30, 76)
    img = Image.fromarray(dither(arr), "RGB").convert("RGBA")
    d = ImageDraw.Draw(img)
    d.rectangle([0, HORIZON - 1, W, HORIZON + 1], fill=(255, 150, 58, 255))      # the hot horizon line
    return img


def clouds():
    img = new_layer()
    d = ImageDraw.Draw(img)
    rng = random.Random(11)
    for _ in range(8):
        cx, cy = rng.randrange(W), rng.randrange(26, HORIZON - 4)
        rx, ry = rng.randrange(50, 110), rng.randrange(1, 3)
        for off in (-W, 0, W):
            d.ellipse([cx + off - rx, cy - ry, cx + off + rx, cy + ry], fill=(255, 140, 120, 46))
    return img


# ---------------------------------------------------------------- buildings
def new_lights():
    return [new_layer() for _ in range(3)]


def building(d, lights, x, base, w, h, depth, pal, rng, lit_p, win, gap):
    dx, dy = depth, int(depth * 0.55)
    top = base - h
    d.polygon([(x + w, top), (x + w + dx, top - dy), (x + w + dx, base - dy), (x + w, base)], fill=pal["side"])
    d.rectangle([x, top, x + w - 1, base - 1], fill=pal["front"])
    d.polygon([(x, top), (x + dx, top - dy), (x + w + dx, top - dy), (x + w, top)], fill=pal["roof"])
    d.line([(x, top), (x + w, top)], fill=pal["edge"], width=1)
    d.line([(x, top), (x, base - 1)], fill=pal["edge"], width=1)
    d.line([(x + w, top), (x + w, base - 1)], fill=pal["edge"], width=1)

    def light(wx, wy, ww, wh, g):
        d.rectangle([wx, wy, wx + ww - 1, wy + wh - 1], fill=pal["litbase"])          # always on, warm
        ImageDraw.Draw(lights[g]).rectangle([wx, wy, wx + ww - 1, wy + wh - 1], fill=pal["lit"])   # twinkles brighter

    for wy in range(top + 4, base - 3, gap + 1):
        for wx in range(x + 3, x + w - win - 1, gap):
            if rng.random() < lit_p:
                light(wx, wy, win, win, rng.randrange(3))
            elif rng.random() < 0.6:
                d.rectangle([wx, wy, wx + win - 1, wy + win - 1], fill=pal["dim"])
    if h > 30 and rng.random() < 0.7:                                                  # horizontal light bands
        for _ in range(rng.randrange(1, 4)):
            by = rng.randrange(top + 5, max(top + 6, base - 6))
            light(x + 2, by, max(3, w - 5), 2, rng.randrange(3))
    dxm = x + dx // 2
    if rng.random() < 0.6:                                                             # purple rooftop pipes
        px = x + rng.randrange(2, max(3, w - 9))
        d.rectangle([px + dx // 2, top - dy - 3, px + dx // 2 + 8, top - dy - 1], fill=(120, 68, 160, 255))
        d.line([(px + dx // 2, top - dy - 3), (px + dx // 2 + 8, top - dy - 3)], fill=(176, 120, 210, 255))
    if rng.random() < 0.35:                                                            # olive roof patch
        d.polygon([(x + 3, top - 1), (x + 3 + dx // 2, top - dy // 2), (x + w // 2 + dx // 2, top - dy // 2), (x + w // 2, top - 1)], fill=(124, 130, 80, 255))
    if rng.random() < 0.45:
        ax = dxm + w // 2
        d.line([(ax, top - dy), (ax, top - dy - rng.randrange(5, 12))], fill=pal["edge"], width=1)
    if rng.random() < 0.4:                                                             # neon trim
        col = rng.choice([(176, 90, 220, 255), (255, 160, 70, 255), (100, 226, 255, 255)])
        d.line([(x + w, top), (x + w + dx, top - dy)], fill=col, width=1)


def place_row(rng, base, wmin, wmax, hmin, hmax, extra=0):
    x = -rng.randrange(0, 12)
    out = []
    xc, hw = road_x(base), road_hw(base) + extra
    while x < W:
        w = rng.randrange(wmin, wmax)
        if x + w + 6 > xc - hw and x < xc + hw:
            x = int(xc + hw) + rng.randrange(1, 4)
            continue
        out.append((x, w, rng.randrange(hmin, hmax)))
        x += w + rng.randrange(0, 5)
    return out


def city_layer(rows, seed, pal, lit_p, extra=0, d_pre=None):
    img = new_layer()
    d = ImageDraw.Draw(img)
    if d_pre:
        d_pre(d)
    lights = new_lights()
    rng = random.Random(seed)
    for base, wmin, wmax, hmin, hmax, depth, win, gap in rows:
        for x, w, h in place_row(rng, base, wmin, wmax, hmin, hmax, extra):
            building(d, lights, x, base, w, h, depth, pal, rng, lit_p, win, gap)
    return img, lights


def avenue(d):
    """A lit street that runs to the tower, with a slow stream of headlights and tail lights."""
    y0 = HORIZON + 34
    d.rectangle([0, y0, W, H], fill=(24, 26, 48, 255))          # street-level shadow between the blocks
    for y in range(y0, H):
        xc, hw = road_x(y), road_hw(y)
        d.line([(xc - hw, y), (xc + hw, y)], fill=(34, 36, 62, 255))
        d.point((int(xc - hw), y), fill=(120, 90, 170, 255))
        d.point((int(xc + hw), y), fill=(120, 90, 170, 255))
    rng = random.Random(21)
    y = y0 + 2
    while y < H:
        xc, hw = road_x(y), road_hw(y)
        for lane, col in ((-0.45, (255, 232, 160, 255)), (0.45, (255, 90, 90, 255)), (-0.15, (255, 232, 160, 255)), (0.15, (255, 90, 90, 255))):
            if rng.random() < 0.55:
                px = int(xc + lane * hw)
                d.point((px, int(y)), fill=col)
                if y > y0 + 40:
                    d.point((px + 1, int(y)), fill=col)
        y += 2 + (y - y0) * 0.035


def far_layer():
    img = new_layer()
    d = ImageDraw.Draw(img)
    rng = random.Random(3)
    for i in range(0, W, 6):                                         # hazy far skyline, tiny lit windows
        h = rng.randrange(8, 40)
        w = rng.randrange(6, 14)
        d.rectangle([i, HORIZON + 40 - h, i + w, HORIZON + 40], fill=(64, 58, 106, 255))
        for _ in range(max(1, h // 6)):
            wx, wy = i + rng.randrange(1, max(2, w - 1)), HORIZON + 40 - rng.randrange(3, h)
            if rng.random() < 0.65:
                d.point((wx, wy), fill=(255, 196, 124, 255))
    tx, base = TOWER_X, HORIZON + 36                                  # the landmark tower
    d.polygon([(tx - 13, base), (tx + 13, base), (tx + 8, 40), (tx - 8, 40)], fill=(34, 36, 74, 255))
    d.polygon([(tx + 8, 40), (tx + 13, base), (tx + 4, base), (tx + 3, 40)], fill=(24, 26, 58, 255))
    for y in (58, 74, 90):                                            # cyan glow bands
        inset = (y - 40) // 8
        d.rectangle([tx - 12 + inset, y, tx + 12 - inset, y + 1], fill=(96, 232, 255, 255))
    d.line([(tx - 8, 40), (tx - 13, base)], fill=(96, 232, 255, 255))
    glow = np.zeros((H, W, 4), dtype=np.uint8)                        # crown glow
    yy, xx = np.mgrid[0:H, 0:W]
    dist = np.sqrt(((xx - tx) / 26.0) ** 2 + ((yy - 34) / 18.0) ** 2)
    a = np.clip(1.0 - dist, 0, 1)
    glow[..., :3] = (255, 110, 200)
    glow[..., 3] = (a * 120).astype(np.uint8)
    img = Image.alpha_composite(img, Image.fromarray(glow, "RGBA"))
    d = ImageDraw.Draw(img)
    for i, (dx, hgt) in enumerate(((-14, 16), (-9, 22), (-4, 27), (0, 31), (4, 27), (9, 22), (14, 16))):   # crown petals
        cx = tx + dx
        d.polygon([(cx - 3, 40), (cx, 40 - hgt), (cx + 3, 40)], fill=(255, 130, 210, 255))
        d.line([(cx, 40 - hgt + 2), (cx, 38)], fill=(255, 210, 238, 255))
    d.rectangle([tx - 12, 38, tx + 12, 41], fill=(60, 40, 110, 255))
    # glow where the sunset meets the city
    band = np.zeros((H, W, 4), dtype=np.uint8)
    for y in range(HORIZON - 10, HORIZON + 26):
        t = 1 - abs(y - (HORIZON + 4)) / 18
        if t > 0:
            band[y, :, :3] = (255, 130, 60)
            band[y, :, 3] = int(70 * t)
    return Image.alpha_composite(img, Image.fromarray(band, "RGBA"))


PAL_MID = {"front": (86, 102, 124, 255), "side": (54, 66, 90, 255), "roof": (118, 134, 152, 255), "edge": (28, 32, 54, 255),
           "dim": (56, 64, 88, 255), "litbase": (196, 160, 98, 255), "lit": (255, 230, 152, 255)}
PAL_NEAR = {"front": (62, 74, 98, 255), "side": (38, 46, 68, 255), "roof": (92, 106, 128, 255), "edge": (18, 20, 38, 255),
            "dim": (44, 50, 74, 255), "litbase": (206, 160, 92, 255), "lit": (255, 224, 140, 255)}


def build(out_dir, seed=5):
    os.makedirs(out_dir, exist_ok=True)
    sky().save(os.path.join(out_dir, "bg_sky.png"))
    clouds().save(os.path.join(out_dir, "bg_clouds.png"))
    far_layer().save(os.path.join(out_dir, "bg_far.png"))
    mid, mid_l = city_layer([
        (HORIZON + 56, 10, 20, 12, 30, 4, 2, 4), (HORIZON + 72, 14, 26, 16, 40, 5, 2, 4),
        (HORIZON + 90, 18, 32, 20, 52, 6, 2, 4), (HORIZON + 112, 22, 40, 24, 64, 8, 2, 4)],
        seed, PAL_MID, 0.62, d_pre=avenue)
    mid.save(os.path.join(out_dir, "bg_mid.png"))
    near, near_l = city_layer([
        (HORIZON + 146, 30, 60, 30, 70, 12, 3, 6), (HORIZON + 186, 44, 84, 40, 90, 16, 3, 7),
        (HORIZON + 226, 56, 100, 40, 80, 18, 3, 7)], seed + 1, PAL_NEAR, 0.55, extra=18)
    near.save(os.path.join(out_dir, "bg_near.png"))
    for i in range(3):
        mid_l[i].save(os.path.join(out_dir, f"bg_mid_l{i}.png"))
        near_l[i].save(os.path.join(out_dir, f"bg_near_l{i}.png"))
    print("wrote backdrop layers to", out_dir)


def preview(out_dir):
    def ld(n):
        return Image.open(os.path.join(out_dir, n)).convert("RGBA")
    img = ld("bg_sky.png")
    for n in ("bg_clouds.png", "bg_far.png", "bg_mid.png"):
        img = Image.alpha_composite(img, ld(n))
    for i in range(3):
        img = Image.alpha_composite(img, ld(f"bg_mid_l{i}.png"))
    img = Image.alpha_composite(img, ld("bg_near.png"))
    for i in range(3):
        img = Image.alpha_composite(img, ld(f"bg_near_l{i}.png"))
    return img


if __name__ == "__main__":
    art = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "art")
    build(art, int(sys.argv[1]) if len(sys.argv) > 1 else 5)
    pv = preview(art)
    pv.crop((40, 0, 520, 270)).resize((960, 540), Image.NEAREST).save(os.path.join(os.path.dirname(art), "shots", "backdrop_preview.png"))
