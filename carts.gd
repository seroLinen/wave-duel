extends RefCounted
# Cartridge data: every game is a recipe of parts (body + abilities + spawners).

const Cards = preload("res://cards.gd")
const SAVE_PATH := "user://mashes.json"
const PROFILE_PATH := "user://hub_save.json"

# Each world-thing carries a signature essence, earned by the move that defines it.
static var ESSENCE := {
	"rain": {"name": "Nerve", "color": "4cc9f0", "how": "close-call dodges"},
	"coins": {"name": "Gold", "color": "f9c74f", "how": "coins collected"},
	"rocks": {"name": "Shards", "color": "adb5bd", "how": "rocks shattered"},
	"chasers": {"name": "Fangs", "color": "e63946", "how": "hunters put down"},
}

# Boons are game-agnostic modifiers: the bridge can bolt them onto any world.
# req: "" always | "shoot" needs a gun | "noshoot" only if you have none | "coins" world has coins
const BOONS := [
	{"id": "skin", "name": "Thick Skin", "desc": "+1 life", "ess": "coins", "cost": 3, "req": ""},
	{"id": "sprint", "name": "Sprint", "desc": "move 25% faster", "ess": "rain", "cost": 2, "req": ""},
	{"id": "slow", "name": "Heavy Air", "desc": "hazards move 20% slower", "ess": "rain", "cost": 3, "req": ""},
	{"id": "gun", "name": "Borrowed Gun", "desc": "you can shoot (SPACE)", "ess": "chasers", "cost": 3, "req": "noshoot"},
	{"id": "rapid", "name": "Rapid Fire", "desc": "shoot twice as fast", "ess": "chasers", "cost": 3, "req": "shoot"},
	{"id": "magnet", "name": "Magnet", "desc": "coins drift toward you", "ess": "coins", "cost": 2, "req": "coins"},
	{"id": "bounty", "name": "Bounty", "desc": "+50% score from everything", "ess": "rocks", "cost": 4, "req": ""},
	{"id": "ghost", "name": "Ghost Step", "desc": "2x invulnerability after a hit", "ess": "rain", "cost": 2, "req": ""},
	{"id": "greed", "name": "Greed", "desc": "essences earned x2 this run", "ess": "coins", "cost": 3, "req": ""},
	{"id": "short", "name": "Shortcut", "desc": "goal is 11 instead of 15", "ess": "rocks", "cost": 4, "req": ""},
]

static func boon(id: String) -> Dictionary:
	for b in BOONS:
		if b["id"] == id:
			return b
	return {}

static func draft(recipe: Dictionary, owned: Array, can_shoot: bool, n: int = 3) -> Array:
	var pool: Array = []
	for b in BOONS:
		if owned.has(b["id"]):
			continue
		if b["req"] == "shoot" and not can_shoot:
			continue
		if b["req"] == "noshoot" and can_shoot:
			continue
		if b["req"] == "coins" and not recipe["spawners"].has("coins"):
			continue
		if recipe.has("boons") and not recipe["boons"].has(b["id"]):
			continue
		pool.append(b)
	pool.shuffle()
	return pool.slice(0, n)

static func base_list() -> Array:
	return [
		{"id": "rainfall", "name": "Rainfall", "color": "4cc9f0", "movement": "topdown", "abilities": [], "spawners": ["rain"], "base": true},
		{"id": "coinhop", "name": "Coin Hop", "color": "f9c74f", "movement": "platformer", "abilities": [], "spawners": ["coins"], "base": true},
		{"id": "rockdrift", "name": "Rock Drift", "color": "f94144", "movement": "ship", "abilities": ["shoot"], "spawners": ["rocks"], "base": true},
		{"id": "hounded", "name": "Hounded", "color": "90be6d", "movement": "topdown", "abilities": ["shoot"], "spawners": ["chasers"], "base": true},
	]

static func mash(a: Dictionary, b: Dictionary) -> Dictionary:
	var sp: Array = a["spawners"].duplicate()
	for s in b["spawners"]:
		if not sp.has(s):
			sp.append(s)
	var ab: Array = a["abilities"].duplicate()
	for s in b["abilities"]:
		if not ab.has(s):
			ab.append(s)
	var col := Color(a["color"]).lerp(Color(b["color"]), 0.5)
	return {
		"id": "mash_%d" % Time.get_ticks_usec(),
		"name": ("%s x %s" % [a["name"], b["name"]]).substr(0, 30),
		"color": col.to_html(false),
		"colors": uniq(a.get("colors", [a["color"]]) + b.get("colors", [b["color"]])).slice(0, 4),
		"movement": a["movement"],
		"abilities": ab,
		"spawners": sp,
		"base": false,
	}

static func uniq(arr: Array) -> Array:
	var out: Array = []
	for x in arr:
		if not out.has(x):
			out.append(x)
	return out

static func earns(r: Dictionary) -> Array:
	var out: Array = []
	for s in r.get("earn_keys", r["spawners"]):
		out.append(ESSENCE[s])
	return out

static func fresh_profile() -> Dictionary:
	return {"wallet": {}, "stats": {}, "cards": Cards.starter_cards(), "folder": Cards.starter_folder(), "bindings": {}, "bindings_v": 4, "cards_v": 2, "show_retired": false, "music": true, "both_bumpers": true}

static func load_profile() -> Dictionary:
	var prof := {"wallet": {}, "stats": {}, "cards": Cards.starter_cards(), "folder": Cards.starter_folder(), "bindings": {}, "bindings_v": 4, "cards_v": 2, "show_retired": false}
	if FileAccess.file_exists(PROFILE_PATH):
		var data = JSON.parse_string(FileAccess.open(PROFILE_PATH, FileAccess.READ).get_as_text())
		if data is Dictionary:
			prof["wallet"] = data.get("wallet", {})
			prof["stats"] = data.get("stats", {})
			prof["cards"] = data.get("cards", prof["cards"])
			prof["folder"] = data.get("folder", prof["folder"])
			# v4: bindings are one keyboard slot + one pad slot per action. Older formats are dropped (defaults come back).
			prof["bindings"] = data.get("bindings", {}) if int(data.get("bindings_v", 1)) >= 4 else {}
			prof["show_retired"] = bool(data.get("show_retired", false))
			prof["music"] = bool(data.get("music", true))
			prof["both_bumpers"] = bool(data.get("both_bumpers", true))
			var v := int(data.get("cards_v", 1))
			if v < 2:   # one-time gift: the new sword cards
				var owned: Dictionary = prof["cards"]
				for cid in ["widesword", "tide"]:
					owned[cid] = int(owned.get(cid, 0)) + 1
			prof["cards_v"] = 2
	return prof

static func save_profile(prof: Dictionary) -> void:
	FileAccess.open(PROFILE_PATH, FileAccess.WRITE).store_string(JSON.stringify(prof))

static func describe(r: Dictionary) -> String:
	var parts: Array = []
	if r.has("script"):
		parts.append("custom world" + ((" by " + r["author"]) if r.get("author", "") != "" else ""))
	else:
		parts.append("body: " + str(r["movement"]))
		parts.append("abilities: " + (", ".join(r["abilities"]) if r["abilities"].size() > 0 else "none"))
		parts.append("world: " + ", ".join(r["spawners"]))
	var names: Array = []
	for e in earns(r):
		names.append(e["name"])
	parts.append("earns: " + ", ".join(names))
	return "   |   ".join(parts)

static func load_saved() -> Array:
	if not FileAccess.file_exists(SAVE_PATH):
		return []
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var data = JSON.parse_string(f.get_as_text())
	if data is Array:
		return data
	return []

static func save_saved(all_carts: Array) -> void:
	var out: Array = []
	for c in all_carts:
		if not c.get("base", false):
			out.append(c)
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(out))
