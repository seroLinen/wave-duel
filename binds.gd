extends RefCounted
# Remappable controls. Every action has exactly two slots: "kb" (a key or mouse button) and "pad" (a controller button).
# Binding a button REPLACES that slot, and if another action in the same group already used the button it loses it
# (so one button never does two jobs at once). A binding is {"t": "key"|"mouse"|"joy", "c": code}; {} means unbound.
# Controller buttons are named by POSITION: bottom / right / left / top (a Nintendo Pro Controller prints them as B / A / Y / X).

const ACTIONS := [
	{"id": "confirm", "label": "Confirm / interact"},
	{"id": "menu", "label": "Pause menu"},
	{"id": "back", "label": "Back (menus)"},
	{"id": "fire", "label": "Fire / charge buster"},
	{"id": "jump", "label": "Jump (platformer)"},
	{"id": "custom", "label": "Open Custom (card hand)"},
	{"id": "card", "label": "Play next card"},
	{"id": "lockon", "label": "Lock on / off (sword cards)"},
	{"id": "shield", "label": "Holo shield (guard)"},
]

# Actions that are live at the same time. Only these can conflict with each other.
const GROUPS := [
	["fire", "custom", "card", "lockon", "shield"],   # the duel
	["fire", "jump"],                                  # the platformer worlds
	["confirm", "menu", "back"],                       # menus
]

# The defaults are the layout the game was tuned and played with. (Pad buttons are by position: A bottom, B right, X left, Y top.)
const DEFAULTS := {
	"confirm": {"kb": {"t": "key", "c": KEY_E}, "pad": {"t": "joy", "c": JOY_BUTTON_B}},
	"menu": {"kb": {"t": "key", "c": KEY_TAB}, "pad": {"t": "joy", "c": JOY_BUTTON_START}},
	"back": {"kb": {"t": "key", "c": KEY_BACKSPACE}, "pad": {"t": "joy", "c": JOY_BUTTON_X}},      # (Esc always goes back too)
	"fire": {"kb": {"t": "key", "c": KEY_SPACE}, "pad": {"t": "joy", "c": JOY_BUTTON_A}},
	"jump": {"kb": {"t": "key", "c": KEY_W}, "pad": {}},
	"custom": {"kb": {"t": "key", "c": KEY_Q}, "pad": {"t": "joy", "c": JOY_BUTTON_RIGHT_SHOULDER}},
	"card": {"kb": {"t": "key", "c": KEY_ENTER}, "pad": {"t": "joy", "c": JOY_BUTTON_B}},
	"lockon": {"kb": {"t": "key", "c": KEY_DOWN}, "pad": {"t": "joy", "c": JOY_BUTTON_DPAD_DOWN}},
	"shield": {"kb": {"t": "key", "c": KEY_V}, "pad": {"t": "joy", "c": JOY_BUTTON_Y}},
}

# Option: either shoulder button opens Custom once the gauge is full (as in the games this is inspired by).
# The extra bumper is only used if no other duel action has claimed it.
static var both_bumpers := true

static var map := {}   # action id -> {"kb": binding, "pad": binding}

static func _fresh() -> Dictionary:
	return DEFAULTS.duplicate(true)

static func ensure() -> void:
	if map.is_empty():
		map = _fresh()

static func reset_all() -> void:
	map = _fresh()

static func reset(action: String) -> void:
	ensure()
	map[action] = (DEFAULTS[action] as Dictionary).duplicate(true)

static func load_from(d: Dictionary) -> void:
	map = _fresh()
	for action in d:
		if not map.has(str(action)) or not (d[action] is Dictionary):
			continue
		for slot in ["kb", "pad"]:
			if (d[action] as Dictionary).has(slot):
				var v = d[action][slot]
				if v is Dictionary and v.has("t") and v.has("c"):
					map[str(action)][slot] = {"t": str(v["t"]), "c": int(v["c"])}
				else:
					map[str(action)][slot] = {}

static func to_dict() -> Dictionary:
	ensure()
	return map.duplicate(true)

static func same(a: Dictionary, b: Dictionary) -> bool:
	if a.is_empty() or b.is_empty():
		return false
	return str(a["t"]) == str(b["t"]) and int(a["c"]) == int(b["c"])

static func get_slot(action: String, slot: String) -> Dictionary:
	ensure()
	return map[action][slot]

# Bind a button to an action's keyboard/pad slot. Returns the labels of actions that lost the button to it.
static func set_slot(action: String, slot: String, b: Dictionary) -> Array:
	ensure()
	var lost: Array = []
	for g in GROUPS:
		if not (g as Array).has(action):
			continue
		for other in g:
			if other == action:
				continue
			if same(map[other][slot], b):
				map[other][slot] = {}
				var nm := label_of(str(other))
				if not lost.has(nm):
					lost.append(nm)
	map[action][slot] = b
	return lost

static func label_of(id: String) -> String:
	for a in ACTIONS:
		if a["id"] == id:
			return str(a["label"])
	return id

static func all_for(action: String) -> Array:
	ensure()
	var out: Array = []
	for slot in ["kb", "pad"]:
		var b: Dictionary = map[action][slot]
		if not b.is_empty():
			out.append(b)
	return out

static func hit(b: Dictionary, e: InputEvent) -> bool:
	if b.is_empty():
		return false
	match str(b["t"]):
		"key": return e is InputEventKey and e.pressed and not e.echo and e.keycode == int(b["c"])
		"joy": return e is InputEventJoypadButton and e.pressed and e.button_index == int(b["c"])
		"mouse": return e is InputEventMouseButton and e.pressed and e.button_index == int(b["c"])
	return false

static func matches(action: String, e: InputEvent) -> bool:
	for b in all_for(action):
		if hit(b, e):
			return true
	if action == "custom" and both_bumpers and e is InputEventJoypadButton and e.pressed:
		var other := -1
		if e.button_index == JOY_BUTTON_LEFT_SHOULDER:
			other = JOY_BUTTON_LEFT_SHOULDER
		elif e.button_index == JOY_BUTTON_RIGHT_SHOULDER:
			other = JOY_BUTTON_RIGHT_SHOULDER
		if other >= 0:
			var taken := false
			for a in GROUPS[0]:
				if a != "custom" and same(get_slot(str(a), "pad"), {"t": "joy", "c": other}):
					taken = true
			return not taken
	return false

static func down(b: Dictionary) -> bool:
	if b.is_empty():
		return false
	match str(b["t"]):
		"key": return Input.is_key_pressed(int(b["c"]))
		"joy":
			for d in Input.get_connected_joypads():
				if Input.is_joy_button_pressed(d, int(b["c"])):
					return true
		"mouse": return Input.is_mouse_button_pressed(int(b["c"]))
	return false

static func held(action: String) -> bool:
	for b in all_for(action):
		if down(b):
			return true
	return false

# What counts as "a button press" while listening for a new binding in the given slot.
static func capture(e: InputEvent, slot: String) -> Dictionary:
	if slot == "kb":
		if e is InputEventKey and e.pressed and not e.echo and e.keycode != KEY_ESCAPE:
			return {"t": "key", "c": int(e.keycode)}
		if e is InputEventMouseButton and e.pressed:
			return {"t": "mouse", "c": int(e.button_index)}
	elif e is InputEventJoypadButton and e.pressed:
		return {"t": "joy", "c": int(e.button_index)}
	return {}

# Godot names face buttons by position: A bottom, B right, X left, Y top.
static func pad_name(i: int) -> String:
	match i:
		JOY_BUTTON_A: return "bottom"
		JOY_BUTTON_B: return "right"
		JOY_BUTTON_X: return "left"
		JOY_BUTTON_Y: return "top"
		JOY_BUTTON_BACK: return "Back"
		JOY_BUTTON_START: return "Start"
		JOY_BUTTON_LEFT_STICK: return "L-stick"
		JOY_BUTTON_RIGHT_STICK: return "R-stick"
		JOY_BUTTON_LEFT_SHOULDER: return "LB"
		JOY_BUTTON_RIGHT_SHOULDER: return "RB"
		JOY_BUTTON_DPAD_UP: return "D-up"
		JOY_BUTTON_DPAD_DOWN: return "D-down"
		JOY_BUTTON_DPAD_LEFT: return "D-left"
		JOY_BUTTON_DPAD_RIGHT: return "D-right"
	return "button %d" % i

static func short(b: Dictionary) -> String:
	if b.is_empty():
		return "unbound"
	match str(b["t"]):
		"key": return OS.get_keycode_string(int(b["c"]))
		"joy": return pad_name(int(b["c"]))
		"mouse": return "Mouse%d" % int(b["c"])
	return "?"
