"""High-res close-up renders for the opening cinematics (one idle frame per opponent, 4x the in-fight resolution).

Same rig and pipeline as anim_render.py, just rendered large so the camera can push in on boots, hands and faces
without the pixels turning to mush.

    python tools/intro_render.py            # art/intro_<model>.png for every model listed in CLOSEUPS
    python tools/intro_render.py duel_rival
"""
import os
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import anim_render as ar

CLOSEUPS = ["duel_rival", "duel_brute", "duel_buzzcap"]
SCALE_UP = 4          # 96 px cell -> 384 px
SUPER = 2             # extra supersampling before shrinking (keeps edges clean)


def build(name, art_dir):
    builder, yaw, scale, cy, poses, _ = ar.MODELS[name]
    idle = poses["idle"]["frames"][0]
    size = ar.FRAME * SCALE_UP
    big = ar.render(builder(idle), yaw, size * SUPER, scale * SCALE_UP * SUPER, cy)
    img = Image.fromarray(ar.to_pixel_art(big, size), "RGBA")
    img.save(os.path.join(art_dir, "intro_%s.png" % name.replace("duel_", "")))
    print("wrote intro_%s.png" % name.replace("duel_", ""), img.size)


if __name__ == "__main__":
    art = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "art")
    for n in (sys.argv[1:] or CLOSEUPS):
        build(n, art)
