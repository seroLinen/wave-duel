extends RefCounted
# Remappable actions. The built-in defaults always work; buttons you add in Pause > Controls
# are stored in the profile and work alongside them. A binding is {"t": "key"|"joy"|"mouse", "c": code}.
# Steam and Windows can turn controller buttons into keys or mouse clicks before the game sees
# them, so "press the button you want" accepts whichever kind of event actually arrives.

const ACTIONS := [
	{"id": "confirm", "label": "Confirm / interact"},
	{"id": "menu", "label": "Pause menu"},
	{"id": "fire", "label": "Fire / charge buster"},
	{"id": "jump", "label": "Jump (platformer)"},
	{"id": "custom", "label": "Open Custom (card hand)"},
	{"id": "card", "label": "Play next card"},
	{"id": "lockon", "label": "Lock on / off (sword cards)"},
	{"id": "shield", "label": "Holo shield (guard)"},
]

const DEFAULTS := {
	"confirm": [{"t": "key", "c": KEY_E}, {"t": "key", "c": KEY_ENTER}, {"t": "key", "c": KEY_SPACE}, {"t": "joy", "c": JOY_BUTTON_A}],
	"menu": [{"t": "key", "c": KEY_TAB}, {"t": "joy", "c": JOY_BUTTON_START}, {"t": "joy", "c": JOY_BUTTON_BACK}],
	"fire": [{"t": "key", "c": KEY_SPACE}, {"t": "key", "c": KEY_J}, {"t": "joy", "c": JOY_BUTTON_X}, {"t": "joy", "c": JOY_BUTTON_B}, {"t": "joy", "c": JOY_BUTTON_RIGHT_SHOULDER}],
	"jump": [{"t": "key", "c": KEY_W}, {"t": "key", "c": KEY_UP}, {"t": "key", "c": KEY_ENTER}, {"t": "joy", "c": JOY_BUTTON_A}],
	"custom": [{"t": "key", "c": KEY_Q}, {"t": "key", "c": KEY_C}, {"t": "joy", "c": JOY_BUTTON_LEFT_SHOULDER}],
	"card": [{"t": "key", "c": KEY_ENTER}, {"t": "key", "c": KEY_K}, {"t": "joy", "c": JOY_BUTTON_A}],
	"lockon": [{"t": "key", "c": KEY_DOWN}, {"t": "key", "c": KEY_S}],   # a pad stick / D-pad pushed down also locks on
	"shield": [{"t": "key", "c": KEY_V}, {"t": "key", "c": KEY_SHIFT}, {"t": "joy", "c": JOY_BUTTON_Y}],
}

static var extra := {}   # action id -> Array of bindings added by the player

static func load_from(d: Dictionary) -> void:
	extra = {}
	for action in d:
		var arr: Array = []
		for b in d[action]:
			if b is Dictionary and b.has("t") and b.has("c"):
				arr.append({"t": str(b["t"]), "c": int(b["c"])})
		extra[str(action)] = arr

static func to_dict() -> Dictionary:
	return extra.duplicate(true)

static func same(a: Dictionary, b: Dictionary) -> bool:
	return str(a["t"]) == str(b["t"]) and int(a["c"]) == int(b["c"])

static func add(action: String, b: Dictionary) -> void:
	if not extra.has(action):
		extra[action] = []
	for e in extra[action]:
		if same(e, b):
			return
	extra[action].append(b)

static func clear(action: String) -> void:
	extra.erase(action)

static func hit(b: Dictionary, e: InputEvent) -> bool:
	match str(b["t"]):
		"key": return e is InputEventKey and e.pressed and not e.echo and e.keycode == int(b["c"])
		"joy": return e is InputEventJoypadButton and e.pressed and e.button_index == int(b["c"])
		"mouse": return e is InputEventMouseButton and e.pressed and e.button_index == int(b["c"])
	return false

const ADDITIVE := ["confirm", "menu", "shield"]   # their built-in keys always keep working

# Once you set a button for an action, those buttons are the only ones it uses (so two actions can
# no longer share a default by accident). Backspace in the Controls screen restores the defaults.
static func all_for(action: String) -> Array:
	var out: Array = []
	var mine: Array = extra.get(action, [])
	if ADDITIVE.has(action) or mine.is_empty():
		out.append_array(DEFAULTS.get(action, []))
	out.append_array(mine)
	return out

static func matches(action: String, e: InputEvent) -> bool:
	for b in all_for(action):
		if hit(b, e):
			return true
	return false

static func matches_extra(action: String, e: InputEvent) -> bool:
	for b in extra.get(action, []):
		if hit(b, e):
			return true
	return false

static func down(b: Dictionary) -> bool:
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

# The buttons an action uses once every button that another action owns is taken out. This is what
# stops "play a card" from also firing when both were bound to the same button.
static func effective_excluding(action: String, others: Array) -> Array:
	var banned: Array = []
	for o in others:
		banned.append_array(all_for(str(o)))
	var out: Array = []
	for b in all_for(action):
		var shared := false
		for x in banned:
			if same(x, b):
				shared = true
				break
		if not shared:
			out.append(b)
	return out

static func held_excluding(action: String, others: Array) -> bool:
	for b in effective_excluding(action, others):
		if down(b):
			return true
	return false

static func label(b: Dictionary) -> String:
	match str(b["t"]):
		"key": return "Key " + OS.get_keycode_string(int(b["c"]))
		"joy": return "Pad button %d" % int(b["c"])
		"mouse": return "Mouse button %d" % int(b["c"])
	return "?"

static func extras_text(action: String) -> String:
	var parts: Array = []
	for b in extra.get(action, []):
		parts.append(label(b))
	return ", ".join(parts) if not parts.is_empty() else "defaults only"

# What counts as "a button press" while listening for a new binding.
static func capture(e: InputEvent) -> Dictionary:
	if e is InputEventKey and e.pressed and not e.echo:
		return {"t": "key", "c": int(e.keycode)}
	if e is InputEventJoypadButton and e.pressed:
		return {"t": "joy", "c": int(e.button_index)}
	if e is InputEventMouseButton and e.pressed:
		return {"t": "mouse", "c": int(e.button_index)}
	return {}

static func short(b: Dictionary) -> String:
	match str(b["t"]):
		"key": return OS.get_keycode_string(int(b["c"]))
		"joy": return "Pad%d" % int(b["c"])
		"mouse": return "Mouse%d" % int(b["c"])
	return "?"

# What an action currently uses, for the Controls screen.
static func shown(action: String) -> String:
	var mine: Array = extra.get(action, [])
	var parts: Array = []
	for b in all_for(action):
		parts.append(short(b))
	if mine.is_empty():
		return "default: " + ", ".join(parts)
	return ("built-in + " if ADDITIVE.has(action) else "yours: ") + ", ".join(parts)

# Other actions that already use this button.
static func users_of(b: Dictionary, except_action: String) -> Array:
	var out: Array = []
	for a in ACTIONS:
		var id: String = a["id"]
		if id == except_action:
			continue
		for x in all_for(id):
			if same(x, b):
				out.append(str(a["label"]))
				break
	return out
