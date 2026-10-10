# Audio

Track names the game looks for: `hub` (the room, Bridge, menus), `battle` (normal encounters), `boss` (the Navi), `title` (the title screen, starts when the logo appears),
and the one-shot jingles `victory` and `defeat` (the background music fades out while they play). To import finished tracks from a music-export folder in one go, run `python tools/import_music.py <folder>` (or put the path in `music_path.txt`); it reads the folder's `music_manifest.json`, maps each role to a game track name and writes `loops.json`. Or add a `loops.json` next to them by hand for any track
that should loop from a point other than the start, e.g. `{"title": 3.749977}` (the title theme's first play has an intro its repeats skip).
 It looks in `audio/_local/` first (your private tracks win), then `audio/music/` (the public set). Press **M** in game to mute.

- `audio/music/` is **committed and public**: only original or rights-cleared audio, rendered with sounds you have the rights to.
- `audio/_local/` is **git-ignored**: for music that stays on your own machine (for example, anything rendered with sound samples taken from a commercial game).

A track made from a game's own instrument samples (a ripped SoundFont, for instance) is still that game's audio, even if the notes are new, so keep it in `_local/`.

Drop finished tracks here as `.ogg` (e.g. `audio/music/duel_theme.ogg`, `audio/sfx/shield_up.ogg`).

**Only original or rights-cleared audio goes in this folder.** This repo is public, so anything committed here must be
music you composed (or properly licensed). Keep raw or in-progress material, and anything derived from a game or
soundtrack, in `audio/_raw/` or `audio/_unlicensed/` - both are git-ignored on purpose.

When adding a track, note it in the table below so provenance is clear.

| File | What it is | Made by | License |
|------|------------|---------|---------|
| *(none yet)* | | | |
