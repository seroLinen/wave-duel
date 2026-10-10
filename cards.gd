extends RefCounted
# Battle cards for Wave Duel. You own cards (profile["cards"]: id -> count) and bring a
# folder of up to MAX_FOLDER of them (profile["folder"]: array of ids, at most MAX_COPIES each).

const MAX_FOLDER := 12
const MAX_COPIES := 3

# Elements. A simple loop: each one beats the next, and is beaten by the one before it. Hitting something your element beats
# does double damage; hitting something that beats yours does half. WHY: it gives picking a card a reason beyond the biggest
# number - you read the opponent, then choose - and it is the hook a future transformation (a "form") can hang abilities on.
const ELEMENTS := {
	"ember": {"name": "Ember", "color": "ff7b3a", "beats": "moss"},
	"moss": {"name": "Moss", "color": "6fcf6a", "beats": "spark"},
	"spark": {"name": "Spark", "color": "ffd93d", "beats": "tide"},
	"tide": {"name": "Tide", "color": "48cae4", "beats": "ember"},
}

static func multiplier(attack_el: String, defend_el: String) -> float:
	if attack_el == "" or defend_el == "" or not ELEMENTS.has(attack_el) or not ELEMENTS.has(defend_el):
		return 1.0
	if ELEMENTS[attack_el]["beats"] == defend_el:
		return 2.0
	if ELEMENTS[defend_el]["beats"] == attack_el:
		return 0.5
	return 1.0

static func weak_to(el: String) -> String:
	for k in ELEMENTS:
		if ELEMENTS[k]["beats"] == el:
			return k
	return ""

# Every card says what it is for ("why"). The HUD test fails if a card has no reason, so nothing here is decoration.
const CARDS := {
	"cannon": {"name": "Cannon", "desc": "Big, slow blast.\n40 damage.", "color": "ff9f1c", "el": "ember",
		"why": "One heavy hit you have to aim: your answer to something slow."},
	"triple": {"name": "Triple Shot", "desc": "Three shots in a fan.\n15 damage each.", "color": "4cc9f0", "el": "moss",
		"why": "A spread that covers lanes when the target will not hold still."},
	"gatling": {"name": "Gatling", "desc": "Six rapid shots.\n8 damage each.", "color": "ffd166", "el": "",
		"why": "Many small hits: pays off when you stand your ground and keep aiming."},
	"slash": {"name": "Sword", "desc": "Needs LOCK-ON (Down).\nDash in and slash.\n35 damage.", "color": "e63946", "el": "",
		"why": "Close-range damage for a risk: you leave your lane and must line up first."},
	"widesword": {"name": "Wide Sword", "desc": "Needs LOCK-ON (Down).\nA huge slash that\nreaches wide. 50 dmg.", "color": "ff6b6b", "el": "",
		"why": "The same risk with more reach, for a target that keeps stepping aside."},
	"tide": {"name": "Tide Blade", "desc": "SPECIAL. A sweeping\nblade sends a tide\nacross the field. 45 dmg.", "color": "48cae4", "el": "tide",
		"why": "The one attack a shield cannot stop: the answer to an opponent who defends."},
	"wave": {"name": "Shock Wave", "desc": "A wide wave that is\nhard to dodge. 35 damage.", "color": "9d4edd", "el": "spark",
		"why": "Hard to dodge: breaks a stalemate against something that keeps moving."},
	"heal": {"name": "Repair", "desc": "Recover 40 HP.", "color": "90be6d", "el": "",
		"why": "Makes a mistake survivable, at the cost of a slot that could have been damage."},
	"barrier": {"name": "Barrier", "desc": "Absorb 40 damage\nfor 6 seconds.", "color": "2ec4b6", "el": "",
		"why": "Trades a slot for a buffer, for a fight where you expect to be hit."},
	"haste": {"name": "Haste", "desc": "Move 60% faster\nfor 6 seconds.", "color": "f9c74f", "el": "",
		"why": "Footwork: makes lining up a sword and dodging easier for a few seconds."},
	"freeze": {"name": "Freeze", "desc": "Needs LOCK-ON (Down).\nThe opponent cannot\nmove or fire for 2.5s.", "color": "a8dadc", "el": "",
		"why": "Buys a free moment, but only if you are lined up in front of the target: the same risk as a sword."},
}

static func order() -> Array:
	return CARDS.keys()

static func starter_cards() -> Dictionary:
	return {"cannon": 2, "triple": 2, "heal": 2, "barrier": 2, "slash": 1, "gatling": 1, "haste": 1, "freeze": 1, "wave": 1, "widesword": 1, "tide": 1}

static func starter_folder() -> Array:
	return ["cannon", "cannon", "triple", "triple", "heal", "heal", "barrier", "barrier", "slash", "gatling", "haste", "freeze"]

static func random_id() -> String:
	var ids := order()
	return ids[randi() % ids.size()]
