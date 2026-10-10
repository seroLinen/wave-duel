# Design intent: nothing is here by accident

The rule for this project: **every card, element, opponent and HUD element has a stated reason to exist** ("why"). If we cannot
say why it is there, it does not go in. This is enforced, not just hoped for:

- `Cards.CARDS[...]["why"]`, `ENEMIES[...]["why"]` and `HUD_WHY[...]` in `games/wave_duel/world.gd` hold the reasons.
- `--hudtest` fails if any card, opponent or HUD element has no reason (see `why_problems()`).

When you add something, write its reason first. If it is only aesthetic, say what the aesthetic does for the player.

## Elements
Four elements in a loop: **Ember** beats **Moss**, Moss beats **Spark**, Spark beats **Tide**, Tide beats Ember.
A hit your element beats does double damage; a hit into something that beats yours does half. Neutral cards are neutral.
*Why:* choosing a card becomes reading the opponent, not just picking the biggest number. Opponents carry an element
(shown as a small coloured diamond by their name or arc), and the Custom screen says what the current opponent is weak to.
Elements are also the planned hook for transformations (a "form" the fighter takes), which would carry its own abilities.

## Between opponents
When an opponent is deleted: the cards you had queued go **back into the folder** (nothing is lost), the folder reshuffles, your
Custom gauge and buster charge start empty, and the next opponent's gauge also starts empty.
*Why:* every encounter starts clean and equal; nothing saved up carries over as an advantage, and nothing is taken from you.
