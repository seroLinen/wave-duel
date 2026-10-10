# CHAKANA.EXE KAGAMI NETWORK (project name "Cartridge Hub"; duel mode "Wave Duel") - instructions for Claude

Godot 4.3 game. Read `docs/PROJECT_NOTES.md` first (rules, tuning, test flags, gotchas), then `README.md` for the overview.

## Run and verify (do this before saying anything is done)
    GODOT="C:/Users/mo_40/Downloads/Modding/MMZX3/tools/godot/Godot_v4.3-stable_win64_console.exe"
    "$GODOT" --headless --path . --quit                 # compile check: no "error|parse|shader" output
    "$GODOT" --headless --path . -- --hudtest           # duel HUD must print "HUD LAYOUT OK"
    "$GODOT" --headless --path . -- --selftest          # every world with a bot (back up/restore user saves around it)
    "$GODOT" --path . -- --shot=shots/x.png --start=0 --shotdelay=2.2   # then LOOK at the screenshot
The user launches the game themselves with `play.bat` (also a "Wave Duel" shortcut on their Desktop); Godot's path is in the git-ignored `godot_path.txt`. Only launch for them when asked: Start-Process on the non-console exe and `--path <this folder>`. Kill the running game first when changing code.
The user's saves live in `%APPDATA%\Godot\app_userdata\Cartridge Hub\`; selftest overwrites them, so copy hub_save.json/mashes.json aside and restore.

## Hard rules from the user
1. **Originality.** Never rip, extract, decompile or reverse-engineer commercial games/ROMs/apps/soundtracks. Match the look and feel with original code and art.
   Do not add audio or art that isn't original or rights-cleared. This repo is meant to be PUBLIC (portfolio). Don't copy named characters or names.
2. **Static camera.** Nothing in the duel moves with the player. Battlefield is solid (not transparent). Menu screens are opaque.
3. **No overlapping UI.** Every HUD element is in `hud_items()` in `games/wave_duel/world.gd`; add new ones there and keep `--hudtest` green.
   Screenshot every screen you touch and check it by eye. The user reviews screenshots closely.
4. **Portal warp is loved, keep its power.** It only grips while approaching/facing a portal, never distorts the top HUD, and per-world `"dread"`
   (manifest, default 1.0) can raise it for scary worlds. Don't remove the full-strength effect.
5. The user writes the story. Don't invent lore/dialogue; build tooling if asked.
6. Be straightforward about what was tested vs not (you cannot press the user's controller). The user feels the gameplay; tuning numbers are guesses.

## Working conventions
- GDScript uses TABS. `:=` cannot infer from a Variant (e.g. Dictionary values, `floor()`): use an explicit type or `float(...)`/`int(...)`. Shader `fragment()` cannot `return`.
- Patch code by anchoring on line CONTENT and copying the anchor line's indentation (helper pattern: find line, reuse its tabs). Always dry-run a patch on a copy first.
  Tab-counting search strings broke repeatedly.
- Art is generated: edit the Python rigs/painters in `tools/`, re-render into `art/`, view the sheet. Don't hand-edit the PNGs.
- Controller buttons reach the game as KEYS/MOUSE via Steam Input; use `Binds` (`binds.gd`) actions, never hard-code a pad button for gameplay.
- Commit messages: short imperative summary; end with the Co-Authored-By line.

## Map
`main.gd` hub flow/menus/portal warp/pause/controls UI | `hub3d.gd` raycaster | `games/wave_duel/world.gd` the duel (logic, AI, HUD table, drawing)
`cards.gd` card data | `binds.gd` remappable actions | `carts.gd` profile/boons | `plugins.gd` world loader | `game_base.gd` base class for scripted worlds
`tools/` Python sprite/backdrop renderers | `art/` generated sprites | `docs/` notes, analysis, README screenshots | `audio/` original music only (see its README)
