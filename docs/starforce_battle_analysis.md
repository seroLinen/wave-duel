# Mega Man Star Force battle system - analysis and how Wave Duel compares

Compiled from fan wikis and guides (sources at the bottom). Where sources disagree it is marked.
This is a study of mechanics, not of assets: nothing here is taken from the games.

## 1. Presentation
- Battles switch to a 3D view from behind / over the shoulder of Mega Man. (Wikipedia, MMHP)
- The playfield is a 3x5 grid. Mega Man stands on the row nearest the camera and moves only left/right
  across its three panels; enemies hold the far 3x3 area and sometimes step into his row to attack. (Wikipedia, MMHP)
- The camera is "normally" over the shoulder and sometimes shifts; it can be switched off in the pause menu. (MMHP)
- Enemy attacks are telegraphed: the tiles about to be hit flash briefly, and that flash is the dodge cue. (MMHP)

## 2. Moving and defending
- Movement is lateral only; the enemy has the wider range. To compensate Mega Man gets a shield (guard) and lock-on. (Wikipedia, MMHP)
- Shield lasts a couple of seconds, blocks most shots, but not piercing attacks or body contact. (MMHP)
- Lock-on: press Down once (no hold). It targets enemies straight ahead or at 45 degrees, shows a cursor, and then
  using a Battle Card warps Mega Man in front of the target. He is NOT invulnerable while warping. (MMHP, RockmanEXEZone)
- Being hit knocks you out of your attack and loses the card you were using. (MMHP)

## 3. Mega Buster
- Charges automatically whenever it is not firing; hold the button for rapid fire; fully charged, press for a super shot.
- A charge is lost if you are hit, use the shield, or (in some games) use a card.
- Weak by design: base damage 1 per shot (+1 per Attack upgrade); charged shots do 10x. (MMHP)

## 4. Cards and the Custom Gauge
- The Custom Gauge fills during battle (about 8-10 seconds in the series); when full the Custom Screen opens. (MegaMan wiki)
- A battle starts with six cards drawn at random from your Folder; each card is usable once per battle; you pick the
  cards for each round and they are used in the order picked; icons show what is next. Up to six cards per round. (MMHP)
- Folder rules: Standard / Mega / Giga classes limit how many of each class (and of any one card) the folder holds. (Wikipedia)
- On the Custom Screen you normally pick cards that line up in a column (two); white cards pair with anything. (MMHP)
- Sources disagree on whether cards are drawn at random each round or chosen from the folder at will; the safe reading is
  "random draw from the folder, then you choose which to use".

## 5. Counter Hit (reward for good timing)
- Hitting an enemy with a card during a specific part of its attack (usually as it starts) triggers a Counter Hit and
  grants a random Bonus Card from your folder to use immediately. Bonus Cards cannot trigger another Counter Hit. (MMHP)
- Bosses flash invulnerable briefly after being hit; wait for the flash to end. (MMHP)

## 6. Later systems
- Elements (Heat/Aqua/Elec/Wood) with weakness = double damage. Star Force 3 adds Noise (builds as you win, unlocks forms),
  dimmed cards that can only be used for a support effect, and Star Force transformations with new charged shots.

## How Wave Duel compares
| Star Force | Wave Duel now |
|---|---|
| Behind-the-shoulder 3D view, static | Static perspective camera, solid road, enemy high / fighter low (matches) |
| 3-lane grid, lateral movement only | Free lateral movement (your choice: you dislike grids) |
| Buster charges itself, weak, charged = 10x | Buster charges itself over 1.8s, 2-12 damage (matches in spirit) |
| Lock-on, warp in front, not invulnerable | Lock-on + dash + slash, exposed during it (matches) |
| Custom Gauge ~8-10s, cards used in picked order | 9s gauge, up to 3 cards, used in order (matches) |
| 6 cards per round | hand of 5, pick up to 3 |
| Shield / guard | not built yet |
| Counter Hit -> bonus card | not built yet |
| Tile flash telegraph | enemy flashes before each attack (close); no floor marker yet |
| Elements | not built yet |

## Suggested next steps from this analysis
1. Shield (guard): a short window that blocks most shots but costs your buster charge - gives defence beyond dodging.
2. Counter Hit: landing a card during an enemy's wind-up grants a bonus card. Makes timing matter.
3. Floor telegraph: flash the part of the road an attack will hit (the Star Force dodge cue) instead of only flashing the enemy.
4. Elements on cards and enemies with double damage on weakness.
5. Card cancel rule: taking a hit while a card animation is playing cancels it and loses the card.

## Sources
- https://en.wikipedia.org/wiki/Mega_Man_Star_Force
- https://www.mmhp.net/Star/Tips.html
- https://megaman.fandom.com/wiki/Custom_Screen and /Custom_Gauge
- https://www.therockmanexezone.com/wiki/Mega_Man_Star_Force (and related wiki pages, via search summaries)
