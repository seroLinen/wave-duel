"""Copies FINISHED music (.ogg) from a music-export folder into audio/_local/ under the names the game looks for.

The export folder holds music_manifest.json (written by whoever makes the music): each track has a "role" and a
"loop_offset_s". This script maps roles to game track names, copies the files, and writes audio/_local/loops.json with any
non-zero loop offsets. It only ever copies finished .ogg files and the numbers from the manifest.

    python tools/import_music.py "path/to/exports"       # or put the path on one line in music_path.txt (git-ignored)

audio/_local/ is git-ignored on purpose: private music never ends up in the public repo. Public-safe music goes in audio/music/.
"""
import json
import os
import shutil
import sys

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEST = os.path.join(HERE, "audio", "_local")
ROLES = {"overworld": "hub", "battle": "battle", "boss": "boss", "title": "title", "victory": "victory", "defeat": "defeat"}


def main():
    src = sys.argv[1] if len(sys.argv) > 1 else None
    if not src:
        p = os.path.join(HERE, "music_path.txt")
        if os.path.exists(p):
            src = open(p, encoding="utf-8").read().strip()
    if not src or not os.path.isdir(src):
        sys.exit("Give me the export folder: python tools/import_music.py <folder>   (or put its path in music_path.txt)")
    manifest = json.load(open(os.path.join(src, "music_manifest.json"), encoding="utf-8"))
    os.makedirs(DEST, exist_ok=True)
    loops = {}
    for fname, e in manifest["tracks"].items():
        name = ROLES.get(e.get("role", ""))
        if not name:
            print("skipped (no game track for role '%s'): %s" % (e.get("role"), fname))
            continue
        src_file = os.path.join(src, fname)
        if not os.path.exists(src_file):
            print("missing:", fname)
            continue
        shutil.copyfile(src_file, os.path.join(DEST, name + ".ogg"))
        off = float(e.get("loop_offset_s", 0.0))
        if off > 0.0:
            loops[name] = off
        print("%-9s <- %-28s %s%s" % (name, fname, "loops" if e.get("loop") else "plays once", ("  (loop from %.2fs)" % off) if off > 0 else ""))
    json.dump(loops, open(os.path.join(DEST, "loops.json"), "w"), indent=2)
    print("done -> audio/_local/")


if __name__ == "__main__":
    main()
