extends RefCounted
# Finds installed games. Each game is a folder containing manifest.json:
#   res://games/<folder>/      ships with the project
#   user://games/<folder>/     drop-in installs (no rebuild needed)
# See games/README.md for the manifest format.

const Carts = preload("res://carts.gd")
const ROOTS := ["res://games", "user://games"]
const BODIES := ["topdown", "platformer", "ship"]

static func scan() -> Array:
	var out: Array = []
	var seen: Array = []
	for root in ROOTS:
		var d := DirAccess.open(root)
		if d == null:
			continue
		var subs := Array(d.get_directories())
		subs.sort()
		for sub in subs:
			var dir := "%s/%s" % [root, sub]
			var mpath := dir + "/manifest.json"
			if not FileAccess.file_exists(mpath):
				continue
			var m = JSON.parse_string(FileAccess.open(mpath, FileAccess.READ).get_as_text())
			var r := normalize(m, dir)
			if r.is_empty() or seen.has(r["id"]):
				continue
			seen.append(r["id"])
			out.append(r)
	return out

static func warn(dir: String, why: String) -> Dictionary:
	push_warning("game plugin skipped (%s): %s" % [dir, why])
	return {}

static func normalize(m, dir: String) -> Dictionary:
	if not (m is Dictionary) or not m.has("id") or not m.has("name"):
		return warn(dir, "manifest.json needs at least \"id\" and \"name\"")
	# essences this game introduces
	for e in m.get("essences", []):
		if e is Dictionary and e.has("key") and e.has("name") and not Carts.ESSENCE.has(e["key"]):
			Carts.ESSENCE[e["key"]] = {"name": e["name"], "color": e.get("color", "ffffff"), "how": e.get("how", "")}
	var r := {
		"id": str(m["id"]), "name": str(m["name"]), "color": str(m.get("color", "ffffff")),
		"author": str(m.get("author", "")), "base": true, "plugin": true,
		"dread": float(m.get("dread", 1.0)),   # portal warp: 1 normal; above 1 a spooky world grips harder and further
	}
	if m.has("script"):
		var path: String = dir + "/" + str(m["script"])
		if not FileAccess.file_exists(path):
			return warn(dir, "script not found: " + path)
		for k in m.get("earn_keys", []):
			if not Carts.ESSENCE.has(k):
				return warn(dir, "earn_keys names an unknown essence: " + str(k))
		r["script"] = path
		r["movement"] = "custom"
		r["abilities"] = []
		r["spawners"] = []
		r["earn_keys"] = m.get("earn_keys", [])
		r["boons"] = m.get("boons", [])
		return r
	# data-only game: a recipe built from the hub's own parts (can be mashed)
	if not BODIES.has(m.get("movement", "")):
		return warn(dir, "movement must be one of %s (or provide a script)" % [BODIES])
	for s in m.get("spawners", []):
		if not Carts.ESSENCE.has(s):
			return warn(dir, "unknown spawner: " + str(s))
	r["movement"] = m["movement"]
	r["abilities"] = m.get("abilities", [])
	r["spawners"] = m.get("spawners", [])
	return r

static func load_script(path: String) -> GDScript:
	if path.begins_with("res://"):
		return load(path) as GDScript
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var s := GDScript.new()
	s.source_code = f.get_as_text()
	if s.reload() != OK:
		return null
	return s
