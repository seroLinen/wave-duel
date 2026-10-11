"""Draws the app icon (art/app_icon.png and art/app_icon.ico): the hero's head and shoulders in front of the dusk sky, with the wave line.

    python tools/make_icon.py

Needs: Pillow, numpy. (Uses art/room_hero.png: run tools/room_hero_render.py first if it is missing.)
"""
import os

import numpy as np
from PIL import Image, ImageDraw

ART = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "art")
SIZE = 256


def main():
    # dusk sky: violet at the top to orange at the horizon
    ys = np.linspace(0, 1, SIZE)[:, None]
    top = np.array([62, 36, 112], np.float32)
    mid = np.array([210, 92, 120], np.float32)
    low = np.array([255, 170, 80], np.float32)
    col = np.where(ys < 0.62, top * (1 - ys / 0.62) + mid * (ys / 0.62), mid * (1 - (ys - 0.62) / 0.38) + low * ((ys - 0.62) / 0.38))
    bg = Image.fromarray(np.broadcast_to(col[:, None, :] if col.ndim == 2 else col, (SIZE, SIZE, 3)).astype(np.uint8), "RGB").convert("RGBA")
    d = ImageDraw.Draw(bg)
    d.ellipse((150, 70, 230, 150), fill=(250, 170, 160, 255))                                 # the low sun
    for i in range(7):                                                                           # a few distant towers
        x = 8 + i * 38
        h = 34 + (i * 29) % 46
        d.rectangle((x, SIZE - 36 - h, x + 30, SIZE), fill=(40, 28, 78, 255))
    # the wave line
    pts = [(x, 214 + 8 * np.sin(x / 14.0)) for x in range(0, SIZE, 4)]
    d.line(pts, fill=(96, 230, 255, 255), width=5)
    # the hero, facing us
    sheet = Image.open(os.path.join(ART, "room_hero.png")).convert("RGBA")
    cell = sheet.crop((0, 0, 96, 96))                                                             # row S, frame 0
    box = cell.getbbox()
    head = cell.crop((box[0], box[1], box[2], box[1] + int((box[3] - box[1]) * 0.62)))
    scale = 205.0 / head.height
    head = head.resize((int(head.width * scale), int(head.height * scale)), Image.NEAREST)
    bg.alpha_composite(head, ((SIZE - head.width) // 2, SIZE - head.height - 10))
    # rounded corners
    mask = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, SIZE - 1, SIZE - 1), radius=44, fill=255)
    out = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    out.paste(bg, (0, 0), mask)
    out.save(os.path.join(ART, "app_icon.png"))
    out.save(os.path.join(ART, "app_icon.ico"), sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
    print("wrote art/app_icon.png and art/app_icon.ico")


if __name__ == "__main__":
    main()
