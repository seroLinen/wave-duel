extends RefCounted
# Battle cards for Wave Duel. You own cards (profile["cards"]: id -> count) and bring a
# folder of up to MAX_FOLDER of them (profile["folder"]: array of ids, at most MAX_COPIES each).

const MAX_FOLDER := 12
const MAX_COPIES := 3

const CARDS := {
	"cannon": {"name": "Cannon", "desc": "Big, slow blast.\n40 damage.", "color": "ff9f1c"},
	"triple": {"name": "Triple Shot", "desc": "Three shots in a fan.\n15 damage each.", "color": "4cc9f0"},
	"gatling": {"name": "Gatling", "desc": "Six rapid shots.\n8 damage each.", "color": "ffd166"},
	"slash": {"name": "Sword", "desc": "Needs LOCK-ON (Down).\nDash in and slash.\n35 damage.", "color": "e63946"},
	"widesword": {"name": "Wide Sword", "desc": "Needs LOCK-ON (Down).\nA huge slash that\nreaches wide. 50 dmg.", "color": "ff6b6b"},
	"tide": {"name": "Tide Blade", "desc": "SPECIAL. A sweeping\nblade sends a tide\nacross the field. 45 dmg.", "color": "48cae4"},
	"wave": {"name": "Shock Wave", "desc": "A wide wave that is\nhard to dodge. 35 damage.", "color": "9d4edd"},
	"heal": {"name": "Repair", "desc": "Recover 40 HP.", "color": "90be6d"},
	"barrier": {"name": "Barrier", "desc": "Absorb 40 damage\nfor 6 seconds.", "color": "2ec4b6"},
	"haste": {"name": "Haste", "desc": "Move 60% faster\nfor 6 seconds.", "color": "f9c74f"},
	"freeze": {"name": "Freeze", "desc": "The opponent cannot\nmove or fire for 2.5s.", "color": "a8dadc"},
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
