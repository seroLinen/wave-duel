# Audio

The game plays looping `hub.ogg` (hub, Bridge, menus) and `duel.ogg` (Wave Duel). It looks in `audio/music/` first, then `audio/_local/`. Press **M** in game to mute.

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
