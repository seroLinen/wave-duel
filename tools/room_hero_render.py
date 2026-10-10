"""The hero walking around the room: 8 facings x 8 walk frames (96 px cells), relaxed arms, no arm cannon.

Same rig and renderer as anim_render.py. Row r faces the direction named in FACINGS (screen directions: S is toward
the camera). Frame 0 of a row is also the standing pose (the game holds it when you stop).

    python tools/room_hero_render.py        # art/room_hero.png + art/room_hero.json
"""
import json
import math
import os
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import anim_render as ar

S, TAU, PI = ar.S, ar.TAU, ar.PI
# yaw (degrees) that makes the model face each screen direction. Checked by eye: see art/room_hero_preview.png
FACINGS = {"S": 0, "SW": 45, "W": 90, "NW": 135, "N": 180, "NE": 225, "E": 270, "SE": 315}


def walk_frames():
    return ar.cyc(8, lambda u: {
        "bob": 0.03 * abs(S(TAU * u)), "lean": 3 + 1.5 * S(TAU * 2 * u), "head": 1.5 * S(TAU * u),
        "ll": 28 * S(TAU * u), "lr": -28 * S(TAU * u),
        "al": 24 * S(TAU * u + PI), "ar": 24 * S(TAU * u), "el": -8, "er": -8, "cannon": False,
        "sway": 10 + 8 * S(TAU * u - 1.0)})


def build(art_dir):
    builder, _yaw, scale, cy, _poses, world_h = ar.MODELS["duel_hero"]
    frames = walk_frames()
    sheet = Image.new("RGBA", (ar.FRAME * len(frames), ar.FRAME * len(FACINGS)), (0, 0, 0, 0))
    meta = {"fw": ar.FRAME, "world_h": world_h, "feet": (ar.FRAME / 2 + cy * scale) / ar.FRAME, "facings": list(FACINGS), "n": len(frames), "fps": 12}
    for row, (name, yaw) in enumerate(FACINGS.items()):
        for col, frame in enumerate(frames):
            big = ar.render(builder(frame), yaw, ar.FRAME * ar.SUPER, scale * ar.SUPER, cy)
            sheet.paste(Image.fromarray(ar.to_pixel_art(big, ar.FRAME), "RGBA"), (col * ar.FRAME, row * ar.FRAME))
    sheet.save(os.path.join(art_dir, "room_hero.png"))
    with open(os.path.join(art_dir, "room_hero.json"), "w") as f:
        json.dump(meta, f)
    # a contact sheet to check the facings by eye: one frame per facing
    prev = Image.new("RGBA", (ar.FRAME * 8, ar.FRAME), (60, 50, 100, 255))
    for row in range(8):
        prev.alpha_composite(sheet.crop((0, row * ar.FRAME, ar.FRAME, (row + 1) * ar.FRAME)), (row * ar.FRAME, 0))
    prev.save(os.path.join(art_dir, "room_hero_preview.png"))
    print("wrote room_hero.png", sheet.size)


if __name__ == "__main__":
    art = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "art")
    build(art)
