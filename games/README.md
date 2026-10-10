# Adding a game to the hub

Drop a folder in `games/` (ships with the project) or in `user://games/` (drop-in, no rebuild;
on Windows that is `%APPDATA%\Godot\app_userdata\Cartridge Hub\games\`). It needs a `manifest.json`.
The hub scans on launch and adds a portal. Games cannot be deleted from the hub; remove the folder.

## Data-only game (a recipe; can be mashed with other recipe games)

```json
{
  "id": "gold_rush", "name": "Gold Rush", "color": "f4a261", "author": "you",
  "movement": "topdown",              // topdown | platformer | ship
  "abilities": ["shoot"],
  "spawners": ["coins", "chasers"]    // rain | coins | rocks | chasers (or any essence key a plugin added)
}
```

## Scripted game (its own mechanics and essences; not mashable yet)

```json
{
  "id": "pulse_garden", "name": "Pulse Garden", "color": "2ec4b6", "author": "you",
  "script": "world.gd",
  "essences": [ {"key": "echo", "name": "Echo", "color": "2ec4b6", "how": "orbs caught in your pulse"} ],
  "earn_keys": ["echo"],              // essences shown on the portal and given as a clear bonus
  "boons": ["skin", "sprint", "bounty", "ghost", "greed", "short"]   // Bridge boons this game supports
}
```

`world.gd` extends `res://game_base.gd` (read its header). Override `tick(dt)` and `_draw()`;
call `add_score()`, `gain_ess()`, `hurt()`, `finish()`. Use `speed_mul`, `lives`, etc. so boons work.
Use `auto` to drive a bot instead of real input (the hub's self test needs it to run your game headless).
See `games/pulse_garden/` for a complete example.
