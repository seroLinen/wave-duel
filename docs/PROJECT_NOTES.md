# Cartridge Hub / Wave Duel - project notes

Everything the chat knew that the code does not say. Read this first when picking the project back up.

## Run it
    "C:\Users\mo_40\Downloads\Modding\MMZX3\tools\godot\Godot_v4.3-stable_win64.exe" --path "C:\Users\mo_40\Downloads\Godot\cartridge-hub"
Godot 4.3, Compatibility renderer. Save data is NOT in this folder: `%APPDATA%\Godot\app_userdata\Cartridge Hub\`
(`hub_save.json` = wallet, stats, card collection, folder, button bindings; `mashes.json` = saved mashes; `games\` = drop-in plug-ins).

## What it is
- **Hub**: first-person Wolfenstein-style raycaster (`hub3d.gd`) with pre-rendered sprite props (Mash Machine, Chip Folder terminal, guide bot).
  Walk into a portal and you lose control: screen-space warp shader (in `main.gd`), pulled in, then the Bridge (pick a boon with essences) and the world.
- **Wave Duel** (`games/wave_duel/`): the main game. Star Force-inspired real-time card duel from behind the fighter. Static camera, enemy high,
  fighter low, solid road, pre-rendered city backdrop. 3 opponents (Hardhat Drone, Wall Brute, Rival Navi). Result screen before returning to the hub.
- **Chip Folder**: 12-slot deck, max 3 copies. Wins can drop cards. 11 cards in `cards.gd`.
- Mini-games (Rainfall, Coin Hop, Rock Drift, Hounded, Gold Rush, Pulse Garden) are RETIRED/hidden (pause menu toggle). Code kept.
- Plug-in worlds: `games/<id>/manifest.json` (+ optional `world.gd` extending `game_base.gd`). See `games/README.md`.

## Wave Duel rules (current tuning)
- Buster charges itself over 1.8s, fire releases it; 2-12 damage (deliberately weak: cards do the damage). Charge resets each new opponent.
- Custom gauge 9s, same for both sides; solo, time STOPS in the card screen (`PVP` const would make it stop only when both pick). Pick up to 3 of 5, played in order.
- Lock-on (Down) only works when the NEXT card is a sword card; sword cards dash in and cut (exposed while doing it). Locked = slower movement. Silent no-op otherwise.
- Tide Blade = the special wave card (no lock-on needed).
- Holo shield (Y / V / Shift): ~1.1s, 3s cooldown, blocks shots but not waves/tide/sword strikes, costs buster charge, perfect guard (first 0.16s) reflects.
- Counter Hit: a CARD hit (not buster) on an opponent while it winds up cancels the attack, stuns 0.7s, +10 dmg, plays a free non-sword bonus card.
- Floor flash: opponent holds still while winding up; the lane/patch it will hit flashes red.
- Opponent sword attacks wind up 0.5s aimed at where you stood.
- Untuned guesses worth feel-testing: shield duration/cooldown, buster damage, custom gauge time, counter bonus.

## Controls (Esc > Controls shows them and the last button the game saw)
Keyboard: A/D move, Space/J fire, Q/C open Custom, Enter/K play next card (or pick in Custom), Down/S lock on, V/Shift shield, Esc/Tab menu, F11 fullscreen.
Pad (raw buttons reach the game; Godot names them by POSITION: A bottom, B right, X left, Y top): stick/D-pad move and move the card cursor,
bottom = play card / pick / confirm, left (or LB) = open Custom / confirm hand, right = shield, top = lock on, RB/ZR = fire buster, Start = menu.
In the Bridge, bottom and right both confirm (Esc leaves). Added bindings are ADDITIVE: built-ins always work; Backspace in Controls removes yours.
Old saved bindings (before bindings_v 3) are dropped on load. `--padtest` injects raw pad events into a live duel; `--shieldtest`, `--flowtest`, `--bindtest` also exist.
Stick drift after a reconnect is handled in `pad.gd` (settle + learned rest offset).

## Tools (Python 3 + Pillow + numpy, no 3D app)
- `tools/anim_render.py` - animated pixel sprites from small 3D rigs (hero, rival, Buzzcap drone, brute) -> `art/duel_*.png` + `.json`.
  Original designs: anime-reploid look (big eyes, cropped jackets, chunky boots, big hands). Buzzcap (the helicopter drone) is a favourite.
- `tools/backdrop_render.py` - the pre-rendered dusk city layers -> `art/bg_*.png`. (`bg_*_l*.png` light layers are unused now.)
- `tools/sprite_render.py` - 8-angle hub props (Mash Machine, terminal, guide bot).
Re-run after editing a model. Sprites can be skinned by dropping same-named PNGs in `%APPDATA%\Godot\app_userdata\Cartridge Hub\art\`.

## Test / debug flags (after `--path ... --`)
- `--selftest` all recipes headless with a bot; `--hudtest` duel HUD overlap/overflow check; `--bindtest` binding logic; `--reach` platform reachability.
- Screenshots: `--shot=path.png` plus `--start=0` (play world 0), `--shotdelay=SECONDS`, `--cam=x,y,deg` (hub camera), and demos:
  `--demo --bridge=0 --folderdemo --pausedemo --controlsdemo --duelcustom --duelqueue --duelstrike --duelguard --duelflash --duelcounter --duelresult`.
- NOTE: test windows steal focus, so stray key presses from the user can open the pause menu in a screenshot.

## Rules the user set (also see memory files)
- Original art/code only: never rip or reverse-engineer commercial games, ROMs or apps. Match the *look and feel*, not the assets.
- Camera is static; nothing depends on player movement. Battlefield is solid, not transparent. Menus are opaque.
- Check every HUD/UI addition for overlap: the duel HUD is a single layout table (`hud_items()` in `world.gd`) verified by `--hudtest`; also take screenshots.
- Portal warp: user LOVES the strong psychedelic effect. It only grips while approaching/facing a portal, never touches the top HUD, and a per-world
  `"dread"` in the manifest (default 1.0; >1 grips harder and keeps pulling when you look away) keeps the full power available for scary worlds.
- The user will write the story themself; the game should feel human/authentic.

## Gotchas learned
- When patching code with scripts, anchor on line CONTENT and copy indentation (tab counting kept failing); dry-run first.
- Shader `return` is not allowed in `fragment()`; warp shader must be written without early exits.
- `docs/starforce_battle_analysis.md` has the researched Star Force mechanics and what is still unbuilt (elements, card-cancel on hit).

## Ideas not built yet
Elements with weakness damage; a card shop (spend essences on cards); more opponents/bosses and stages each with its own landscape; 2-player (fighters are plain
dictionaries, only the foe needs a controller); story/dialogue tooling (user writes the words); higher-res face portraits; sound (none yet).
