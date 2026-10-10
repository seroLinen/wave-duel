extends Node2D
# Hub world: walk into a portal to enter that game's world. Bring essences back.
# The Mash Machine (E) fuses two worlds into a new portal.

const Carts = preload("res://carts.gd")
const Runner = preload("res://game_run.gd")
const Pad = preload("res://pad.gd")
const Plugins = preload("res://plugins.gd")
const Hub3D = preload("res://hub3d.gd")
const Cards = preload("res://cards.gd")
const Binds = preload("res://binds.gd")

enum S { HUB, ENTER, BRIDGE, PLAY, MASH, FOLDER }
const W := 960.0
const H := 540.0
const MAX_CARTS := 15
const WARP_RANGE := 6.0          # portals start bending the view this far away (times the world's "dread")
const WARP_SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;
uniform vec2 center = vec2(0.5, 0.5);
uniform float strength = 0.0;
uniform float time_s = 0.0;
uniform vec4 tint : source_color = vec4(0.62, 0.28, 1.0, 1.0);
void fragment() {
	vec2 uv = SCREEN_UV;
	float st = strength * step(0.172, uv.y);   // the top HUD strip gets zero strength: left alone
	vec2 d = uv - center;
	d.x *= 1.7778;
	float r = length(d);
	float falloff = 1.0 - smoothstep(0.0, 1.3, r);
	float a_rot = st * falloff * falloff * 6.0;
	float s = sin(a_rot);
	float c = cos(a_rot);
	vec2 dr = vec2(d.x * c - d.y * s, d.x * s + d.y * c);
	dr *= 1.0 - st * falloff * 0.38;
	dr.x /= 1.7778;
	vec2 suv = center + dr;
	suv.y = mix(suv.y, max(suv.y, 0.18), step(0.0001, st));   // never pull the top strip's pixels into the swirl
	float ca = st * 0.02 * falloff;
	vec3 col;
	col.r = texture(screen_tex, suv + vec2(ca, 0.0)).r;
	col.g = texture(screen_tex, suv).g;
	col.b = texture(screen_tex, suv - vec2(ca, 0.0)).b;
	float ang = atan(d.y, d.x);
	float veil = 0.5 + 0.5 * sin(ang * 6.0 + r * 16.0 - time_s * 3.0 + st * 8.0);
	col = mix(col, tint.rgb * (0.55 + 0.9 * veil), st * falloff * falloff * 0.7);
	float vig = smoothstep(0.30, 1.30, length((uv - vec2(0.5)) * vec2(1.25, 1.0)));
	col *= 1.0 - st * vig * 0.6;
	COLOR = vec4(col, 1.0);
}
"""
const RETIRED := ["rainfall", "coinhop", "rockdrift", "hounded", "gold_rush", "pulse_garden"]   # hidden unless shown in the pause menu

var state := S.HUB
var carts: Array = []
var profile: Dictionary = {}
var hub3d := Hub3D.new()   # first-person hub view and player position
var near := -1            # -1 none, -2 mash machine, >=0 portal index
var armed := true         # must step away from portals before re-entering
var runner: Node2D
var enter_idx := 0
var enter_t := 0.0
var fade := 0.0
var fade_col := Color.BLACK
var report: Dictionary = {}
var report_t := 0.0
var msg := ""
var msg_t := 0.0
var t := 0.0
var mash_step := 0
var mash_cursor := 0
var mash_a := 0
var mash_b := 0
var pending: Dictionary = {}
var shot_path := ""
var bridge_recipe: Dictionary = {}
var bridge_idx := -1
var bridge_choices: Array = []
var bridge_t := 0.0
var bridge_sel := 0
var nav_prev := Vector2.ZERO
var mash_pool: Array = []      # carts that can be mashed (recipe games, not scripted ones)
var fold_panel := 0          # chip folder screen: 0 = collection, 1 = folder
var fold_cur := [0, 0]
var captured := -1             # index of the portal that has taken hold of you (no control while >= 0)
var capture_t := 0.0
var warp_rect: ColorRect
var warp_mat: ShaderMaterial
var capture_label: Label
var bind_mode := 0           # 0 off, 1 choosing an action, 2 listening for a button
var bind_sel := 0
var bind_col := 0             # 0 = keyboard slot, 1 = controller slot
var bind_last := ""
var bind_note := ""
var bind_note_t := 0.0
var pause_open := false
var pause_sel := 0
var overlay: Node2D            # draws the pause menu above everything (incl. the running game)

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST   # crisp pixel sprites
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	var sh := Shader.new()
	sh.code = WARP_SHADER
	warp_mat = ShaderMaterial.new()
	warp_mat.shader = sh
	warp_rect = ColorRect.new()
	warp_rect.size = Vector2(W, H)
	warp_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	warp_rect.material = warp_mat
	warp_rect.visible = false
	layer.add_child(warp_rect)
	var layer2 := CanvasLayer.new()   # above the warp, so this line is never distorted
	layer2.layer = 30
	add_child(layer2)
	capture_label = Label.new()
	capture_label.text = "There is no turning back."
	capture_label.position = Vector2(0, 396)
	capture_label.size = Vector2(W, 34)
	capture_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	capture_label.add_theme_font_size_override("font_size", 20)
	capture_label.add_theme_color_override("font_outline_color", Color(0, 0, 0.05, 1))
	capture_label.add_theme_constant_override("outline_size", 8)
	capture_label.visible = false
	layer2.add_child(capture_label)
	overlay = Node2D.new()
	overlay.z_index = 100
	overlay.draw.connect(draw_pause)
	add_child(overlay)
	apply_cursor()
	refresh_carts()
	profile = Carts.load_profile()
	Binds.load_from(profile.get("bindings", {}))
	Input.joy_connection_changed.connect(func(dev: int, on: bool):
		write_log("controller %d %s: %s" % [dev, "CONNECTED" if on else "DISCONNECTED", Input.get_joy_name(dev) if on else ""]))
	for d in Input.get_connected_joypads():
		write_log("controller %d already connected at start: %s" % [d, Input.get_joy_name(d)])
	refresh_carts()
	var args := OS.get_cmdline_user_args()
	var start := -1
	var bridge_demo := -1
	if "--padinfo" in args:
		await get_tree().create_timer(1.5).timeout
		for j in Input.get_connected_joypads():
			print("PAD ", j, ": ", Input.get_joy_name(j), " | ", Input.get_joy_guid(j))
		print("pads connected: ", Input.get_connected_joypads().size())
		get_tree().quit()
		return
	for a in args:
		if a.begins_with("--shot="):
			shot_path = a.substr(7)
		if a.begins_with("--start="):
			start = int(a.substr(8))
		if a.begins_with("--cam="):   # screenshots: --cam=x,y,degrees
			var cp := a.substr(6).split(",")
			hub3d.pos = Vector2(float(cp[0]), float(cp[1]))
			hub3d.ang = deg_to_rad(float(cp[2]))
		if a.begins_with("--bridge="):
			bridge_demo = int(a.substr(9))
	if "--mashtest" in args:
		run_mashtest()
		return
	if "--bindtest" in args:
		run_bindtest()
		return
	if "--hudtest" in args:
		run_hudtest()
		return
	if "--padtest" in args:
		run_padtest()
		return
	if "--shieldtest" in args:
		run_shieldtest()
		return
	if "--flowtest" in args:
		run_flowtest()
		return
	if "--reach" in args:
		run_reach()
		return
	if "--selftest" in args:
		run_selftest()
		return
	if "--demo" in args:   # fake a returned run so the hub UI can be checked
		profile["wallet"] = {"Nerve": 12, "Gold": 31, "Shards": 7, "Fangs": 3}
		profile["stats"] = {"rainfall": {"best": 15.0, "runs": 4, "wins": 2}}
		report = {"name": "Rainfall", "won": true, "score": 15.0, "gains": {"Nerve": 6, "Gold": 2}}
		report_t = 30.0
	if bridge_demo >= 0:
		profile["wallet"] = {"Nerve": 5, "Gold": 2, "Shards": 4, "Fangs": 0}
		go_bridge(carts[bridge_demo], bridge_demo)
	elif start >= 0 and "--draftdemo" in args:
		start_play(carts[start], false)
		runner.score = 5.0
	elif start >= 0:
		start_play(carts[start], true)
	elif start == -2:
		open_mash()
	if "--folderdemo" in args:
		state = S.FOLDER
	if "--controlsdemo" in args:
		open_pause()
		bind_mode = 1
		bind_sel = 4
		bind_col = 1
	if "--pausedemo" in args:
		open_pause()
	if shot_path != "":
		var delay := 2.0
		for a in args:
			if a.begins_with("--shotdelay="):
				delay = float(a.substr(12))
		await get_tree().create_timer(delay).timeout
		get_viewport().get_texture().get_image().save_png(shot_path)
		get_tree().quit()

# The mouse is locked to the game while it is focused. The pause menu frees it.
func apply_cursor() -> void:
	if DisplayServer.get_name() == "headless":
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if pause_open else Input.MOUSE_MODE_CAPTURED

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN or what == NOTIFICATION_WM_WINDOW_FOCUS_IN:
		apply_cursor()
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		if DisplayServer.get_name() != "headless":
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func toggle_fullscreen() -> void:
	var m := DisplayServer.window_get_mode()
	var full := m == DisplayServer.WINDOW_MODE_FULLSCREEN or m == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)

func refresh_carts() -> void:
	carts = Carts.base_list() + Plugins.scan() + Carts.load_saved()
	if not bool(profile.get("show_retired", false)):
		carts = carts.filter(func(c): return not RETIRED.has(c["id"]))
	Hub3D.count = carts.size()

# ---------- flow ----------
func begin_enter(i: int) -> void:
	enter_idx = i
	enter_t = 0.0
	armed = false
	state = S.ENTER

func go_bridge(recipe: Dictionary, idx: int) -> void:
	bridge_recipe = recipe
	bridge_idx = idx
	bridge_choices = Carts.draft(recipe, [], recipe["abilities"].has("shoot"))
	var wallet: Dictionary = profile["wallet"]
	var can_buy := false
	for b in bridge_choices:
		if int(wallet.get(Carts.ESSENCE[b["ess"]]["name"], 0)) >= int(b["cost"]):
			can_buy = true
	if not can_buy:
		start_play(recipe)
		return
	bridge_t = 0.0
	bridge_sel = 0
	fade_col = Color(recipe["color"])
	fade = 1.0
	state = S.BRIDGE

func bridge_pick(i: int) -> void:
	if i >= bridge_choices.size():
		return
	var b: Dictionary = bridge_choices[i]
	var en: String = Carts.ESSENCE[b["ess"]]["name"]
	var wallet: Dictionary = profile["wallet"]
	if int(wallet.get(en, 0)) < int(b["cost"]):
		msg = "Not enough %s for %s" % [en, b["name"]]
		msg_t = 2.0
		return
	wallet[en] = int(wallet[en]) - int(b["cost"])
	Carts.save_profile(profile)
	start_play(bridge_recipe, false, [b["id"]])

func leave_bridge() -> void:
	write_log("left the Bridge (last input: %s)" % last_input)
	place_at(bridge_idx)
	armed = false
	state = S.HUB

func place_at(idx: int) -> void:
	captured = -1
	capture_t = 0.0
	if idx >= 0:
		hub3d.pos = Hub3D.portal_pos(idx) + Vector2(0, 6.0)
		hub3d.ang = PI / 2.0
		fade_col = Color(carts[idx]["color"])
	else:   # unsaved test-play: come back at the mash machine
		hub3d.pos = Hub3D.MACHINE + Vector2(0, -2.0)
		hub3d.ang = PI / 2.0
		fade_col = Color("c77dff")
	fade = 1.0

func start_play(recipe: Dictionary, auto := false, boons: Array = []) -> void:
	runner = make_world(recipe)
	if runner == null:
		msg = "Could not load " + recipe["name"]
		msg_t = 4.0
		place_at(-1)
		state = S.HUB
		return
	runner.auto = auto
	if "folder" in runner:
		runner.folder = (profile["folder"] as Array).duplicate()
	runner.setup(recipe, boons)
	runner.finished.connect(func(won: bool, sc: float): return_to_hub(won, sc))
	add_child(runner)
	state = S.PLAY

func make_world(recipe: Dictionary) -> Node2D:
	if recipe.has("script"):
		var sc: GDScript = Plugins.load_script(recipe["script"])
		return sc.new() if sc else null
	return Runner.new()

# Leave a world and bring back whatever was earned, win or lose.
func return_to_hub(won: bool, sc: float) -> void:
	if runner == null:
		return
	var recipe: Dictionary = runner.recipe
	var gains: Dictionary = runner.essence.duplicate()
	var won_cards: Array = []
	var wc = runner.get("cards_won")
	if wc != null:
		won_cards = (wc as Array).duplicate()
	runner.queue_free()
	runner = null
	var wallet: Dictionary = profile["wallet"]
	for k in gains:
		wallet[k] = int(wallet.get(k, 0)) + int(gains[k])
	var st: Dictionary = profile["stats"].get(recipe["id"], {"best": 0.0, "runs": 0, "wins": 0})
	st["best"] = maxf(float(st["best"]), sc)
	st["runs"] = int(st["runs"]) + 1
	st["wins"] = int(st["wins"]) + (1 if won else 0)
	profile["stats"][recipe["id"]] = st
	Carts.save_profile(profile)
	for cid in won_cards:
		profile["cards"][cid] = int(profile["cards"].get(cid, 0)) + 1
	Carts.save_profile(profile)
	report = {"name": recipe["name"], "won": won, "score": sc, "gains": gains, "cards": won_cards}
	report_t = 7.0
	var idx := -1
	for i in carts.size():
		if carts[i]["id"] == recipe["id"]:
			idx = i
	place_at(idx)
	armed = false
	state = S.HUB

func open_mash() -> void:
	mash_pool = carts.filter(func(c): return not c.has("script"))
	if mash_pool.size() < 2:
		msg = "Nothing to fuse yet - the mini-games are retired (Esc > Retired mini-games)"
		msg_t = 4.0
		return
	state = S.MASH
	mash_step = 0
	mash_cursor = 0

# Buttons are read by LABEL (A confirm, B back, X/Y extra), which is how a Pro Controller reports.
func pad_key(b: int) -> int:
	match b:
		JOY_BUTTON_A: return KEY_E                           # confirm / interact
		JOY_BUTTON_B:
			# A Pro Controller's right-hand button arrives as "B". On the Bridge it is confirm, never back
			# (it used to kick you out of the boon screen); Esc / the pause menu still leave.
			if state == S.BRIDGE and not pause_open:
				return KEY_E
			return KEY_ESCAPE if (state != S.PLAY or pause_open) else 0   # back (B shoots in games)
		JOY_BUTTON_START, JOY_BUTTON_BACK: return KEY_TAB   # menu
		JOY_BUTTON_X, JOY_BUTTON_Y:
			if pause_open and bind_mode == 1: return KEY_BACKSPACE   # reset the selected row
			if state == S.MASH: return KEY_P
			if state == S.BRIDGE: return KEY_BACKSPACE
			return 0   # (X deletes a mash in the hub: keyboard only, so a stray pad press can never do it)
		JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT:
			if state == S.PLAY and not pause_open:
				return 0   # the world reads the D-pad itself
			if state == S.HUB and not pause_open:
				return 0   # walking is polled
			match b:
				JOY_BUTTON_DPAD_UP: return KEY_W
				JOY_BUTTON_DPAD_DOWN: return KEY_S
				JOY_BUTTON_DPAD_LEFT: return KEY_A
				JOY_BUTTON_DPAD_RIGHT: return KEY_D
	return 0

# Diagnostic: every button/key press the game really receives goes to user://input_log.txt
# and the latest one shows at the bottom-left of the hub.
var last_input := ""
var log_started := false

func log_input(e: InputEvent) -> void:
	var line := ""
	if e is InputEventJoypadButton and e.pressed:
		line = "pad device=%d button=%d" % [e.device, e.button_index]
	elif e is InputEventKey and e.pressed and not e.echo:
		line = "key " + OS.get_keycode_string(e.keycode)
	elif e is InputEventMouseButton and e.pressed:
		line = "mouse button=%d" % e.button_index
	else:
		return
	last_input = line
	var f := FileAccess.open("user://input_log.txt", FileAccess.READ_WRITE if log_started else FileAccess.WRITE)
	if f:
		f.seek_end()
		f.store_line("%6.1fs  state=%d paused=%s  %s  (pads connected: %s)" % [t, state, pause_open, line, Input.get_connected_joypads()])
		log_started = true

func _input(e: InputEvent) -> void:
	log_input(e)
	if bind_mode == 2:   # listening for the new button of the chosen slot
		if e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_ESCAPE:
			bind_mode = 1
			return
		var slot := "kb" if bind_col == 0 else "pad"
		var b := Binds.capture(e, slot)
		if not b.is_empty():
			var aid := str(Binds.ACTIONS[bind_sel]["id"])
			var lost := Binds.set_slot(aid, slot, b)
			bind_note = "%s  ->  %s" % [Binds.label_of(aid), Binds.short(b)]
			if not lost.is_empty():
				bind_note += "     (taken from: %s)" % ", ".join(lost)
			bind_note_t = 5.0
			save_binds()
			bind_mode = 1
		return
	if bind_mode == 0:
		if Binds.matches("menu", e):
			on_key(KEY_TAB)
			return
		if Binds.matches("confirm", e):
			on_key(KEY_E)
			return
	if state == S.HUB and not pause_open and e is InputEventMouseMotion:
		if captured < 0:
			hub3d.ang += e.relative.x * 0.003
		return
	if pause_open and bind_mode == 0 and e is InputEventMouseMotion:
		var items := pause_items()
		for i in items.size():
			if pause_rect(i).has_point(e.position):
				pause_sel = i
		return
	if pause_open and bind_mode == 0 and e is InputEventMouseButton:
		if e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			var items := pause_items()
			for i in items.size():
				if pause_rect(i).has_point(e.position):
					pause_choose(items[i]["id"])
					return
		return
	if e is InputEventJoypadButton and e.pressed:
		var pk := pad_key(e.button_index)
		if pk == KEY_W or pk == KEY_S or pk == KEY_A or pk == KEY_D:
			pad_nav(pk)
		elif pk != 0:
			on_key(pk)
		return
	if not (e is InputEventKey and e.pressed and not e.echo):
		return
	if e.keycode == KEY_F11:
		toggle_fullscreen()
		return
	on_key(e.keycode)

# ---------- pause menu (the only place the mouse is free) ----------
func pause_items() -> Array:
	var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	var items: Array = [
		{"id": "resume", "label": "Resume"},
		{"id": "full", "label": "Fullscreen: %s   (F11)" % ("ON" if full else "OFF")},
		{"id": "controls", "label": "Controls (rebind buttons)"},
		{"id": "retired", "label": "Retired mini-games: %s" % ("SHOWN" if bool(profile.get("show_retired", false)) else "HIDDEN")},
	]
	if state == S.PLAY:
		items.append({"id": "leave", "label": "Leave game (keep what you earned)"})
	elif state == S.BRIDGE or state == S.MASH or state == S.FOLDER:
		items.append({"id": "leave", "label": "Back to hub"})
	items.append({"id": "quit", "label": "Quit game"})
	return items

func pause_rect(i: int) -> Rect2:
	return Rect2(330, 190 + i * 52, 300, 40)

func open_pause() -> void:
	pause_open = true
	pause_sel = 0
	if runner:
		runner.process_mode = Node.PROCESS_MODE_DISABLED
	apply_cursor()
	if DisplayServer.get_name() != "headless":
		get_viewport().warp_mouse(Vector2(480, 210))

func close_pause() -> void:
	pause_open = false
	bind_mode = 0
	if runner:
		runner.process_mode = Node.PROCESS_MODE_INHERIT
	apply_cursor()
	overlay.queue_redraw()

func pause_choose(id: String) -> void:
	if id == "resume":
		close_pause()
	elif id == "full":
		toggle_fullscreen()
	elif id == "controls":
		bind_mode = 1
		bind_sel = 0
	elif id == "retired":
		profile["show_retired"] = not bool(profile.get("show_retired", false))
		Carts.save_profile(profile)
		refresh_carts()
	elif id == "leave":
		close_pause()
		if state == S.PLAY and runner:
			return_to_hub(false, runner.score)
		elif state == S.BRIDGE:
			leave_bridge()
		elif state == S.MASH or state == S.FOLDER:
			state = S.HUB
	elif id == "quit":
		get_tree().quit()

func pad_status() -> String:
	var id := Pad.id()
	if id < 0:
		return "CONTROLLER: not detected (turn it on; if Steam is starting, wait a few seconds)"
	return "CONTROLLER: connected - " + Input.get_joy_name(id)

func save_binds() -> void:
	profile["bindings"] = Binds.to_dict()
	profile["bindings_v"] = 4
	Carts.save_profile(profile)

func draw_controls(f: Font) -> void:
	overlay.draw_rect(Rect2(0, 0, W, H), Color(0.01, 0.02, 0.05, 1.0))
	overlay.draw_string(f, Vector2(0, 62), "CONTROLS", HORIZONTAL_ALIGNMENT_CENTER, W, 32, Color("4cc9f0"))
	overlay.draw_string(f, Vector2(0, 90), "pick a button to change; the new one replaces the old one", HORIZONTAL_ALIGNMENT_CENTER, W, 14, Color(1, 1, 1, 0.6))
	overlay.draw_string(f, Vector2(400, 112), "KEYBOARD", HORIZONTAL_ALIGNMENT_CENTER, 190, 12, Color(1, 1, 1, 0.5))
	overlay.draw_string(f, Vector2(610, 112), "CONTROLLER", HORIZONTAL_ALIGNMENT_CENTER, 190, 12, Color("7df9ff"))
	var n := Binds.ACTIONS.size()
	for i in n + 1:
		var r := Rect2(120, 120 + i * 40, 720, 34)
		var row_sel := i == bind_sel
		overlay.draw_rect(r, Color(1, 1, 1, 0.10 if row_sel else 0.04))
		overlay.draw_rect(r, Color(1, 1, 1, 0.5 if row_sel else 0.2), false, 1.0)
		if i == n:
			overlay.draw_string(f, Vector2(r.position.x + 16, r.position.y + 23), "Reset ALL controls to defaults", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color("ff9f1c") if row_sel else Color(1, 1, 1, 0.7))
			continue
		var a: Dictionary = Binds.ACTIONS[i]
		overlay.draw_string(f, Vector2(r.position.x + 16, r.position.y + 23), str(a["label"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color.WHITE)
		for c in 2:
			var cell := Rect2(r.position.x + 280 + c * 210, r.position.y + 3, 190, 28)
			var csel := row_sel and bind_col == c
			var b: Dictionary = Binds.get_slot(str(a["id"]), "kb" if c == 0 else "pad")
			overlay.draw_rect(cell, Color(0.3, 0.8, 1.0, 0.28) if csel else Color(0, 0, 0, 0.25))
			overlay.draw_rect(cell, Color("ffd166") if csel else Color(1, 1, 1, 0.18), false, 2.0 if csel else 1.0)
			var col := Color(1, 1, 1, 0.9) if c == 0 else Color("7df9ff")
			if b.is_empty():
				col = Color(1, 1, 1, 0.3)
			overlay.draw_string(f, Vector2(cell.position.x, cell.position.y + 20), Binds.short(b), HORIZONTAL_ALIGNMENT_CENTER, cell.size.x, 15, col)
	if bind_note_t > 0.0:
		overlay.draw_string(f, Vector2(0, 494), bind_note, HORIZONTAL_ALIGNMENT_CENTER, W, 15, Color("ff9f1c") if bind_note.contains("taken from") else Color("90be6d"))
	overlay.draw_string(f, Vector2(0, H - 30), pad_status() + "    last: " + (last_input if last_input != "" else "-"), HORIZONTAL_ALIGNMENT_CENTER, W, 13, Color("7df9ff"))
	overlay.draw_string(f, Vector2(0, H - 14), "up/down row    left/right column    Enter: change    Backspace: reset this row    Esc: back", HORIZONTAL_ALIGNMENT_CENTER, W, 13, Color(1, 1, 1, 0.6))
	if bind_mode == 2:
		overlay.draw_rect(Rect2(0, 0, W, H), Color(0, 0, 0, 0.85))
		overlay.draw_string(f, Vector2(0, 210), "Press the new %s for:" % ("keyboard key" if bind_col == 0 else "controller button"), HORIZONTAL_ALIGNMENT_CENTER, W, 22, Color(1, 1, 1, 0.8))
		overlay.draw_string(f, Vector2(0, 266), str(Binds.ACTIONS[bind_sel]["label"]), HORIZONTAL_ALIGNMENT_CENTER, W, 38, Color("ffd166"))
		overlay.draw_string(f, Vector2(0, 322), "(Esc cancels)", HORIZONTAL_ALIGNMENT_CENTER, W, 16, Color(1, 1, 1, 0.5))

func pause_key(k: int) -> void:
	if bind_mode == 1:
		var na := Binds.ACTIONS.size() + 1      # the last row is "reset all"
		match k:
			KEY_W, KEY_UP: bind_sel = (bind_sel - 1 + na) % na
			KEY_S, KEY_DOWN: bind_sel = (bind_sel + 1) % na
			KEY_A, KEY_LEFT: bind_col = 0
			KEY_D, KEY_RIGHT: bind_col = 1
			KEY_E, KEY_ENTER, KEY_SPACE:
				if bind_sel == na - 1:
					Binds.reset_all()
					bind_note = "All controls are back to the defaults"
					bind_note_t = 4.0
					save_binds()
				else:
					bind_mode = 2
			KEY_BACKSPACE, KEY_DELETE:
				if bind_sel == na - 1:
					Binds.reset_all()
					bind_note = "All controls are back to the defaults"
				else:
					Binds.reset(str(Binds.ACTIONS[bind_sel]["id"]))
					bind_note = "%s is back to its defaults" % Binds.ACTIONS[bind_sel]["label"]
				bind_note_t = 4.0
				save_binds()
			KEY_ESCAPE, KEY_TAB: bind_mode = 0
		return
	var n := pause_items().size()
	match k:
		KEY_W, KEY_UP: pause_sel = (pause_sel - 1 + n) % n
		KEY_S, KEY_DOWN: pause_sel = (pause_sel + 1) % n
		KEY_E, KEY_ENTER, KEY_SPACE: pause_choose(pause_items()[pause_sel]["id"])
		KEY_ESCAPE, KEY_TAB: close_pause()

func draw_pause() -> void:
	if not pause_open:
		return
	var f := ThemeDB.fallback_font
	if bind_mode > 0:
		draw_controls(f)
		return
	overlay.draw_rect(Rect2(0, 0, W, H), Color(0.01, 0.02, 0.05, 0.9 if state == S.PLAY else 1.0))
	overlay.draw_string(f, Vector2(0, 140), "PAUSED", HORIZONTAL_ALIGNMENT_CENTER, W, 34, Color.WHITE)
	var items := pause_items()
	for i in items.size():
		var r := pause_rect(i)
		var sel := i == pause_sel
		overlay.draw_rect(r, Color(1, 1, 1, 0.16 if sel else 0.05))
		overlay.draw_rect(r, Color(1, 1, 1, 0.8 if sel else 0.25), false, 2)
		overlay.draw_string(f, Vector2(r.position.x, r.position.y + 26), items[i]["label"], HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 17, Color.WHITE)
	overlay.draw_string(f, Vector2(0, H - 14), "the mouse is free while this menu is open    Esc / Plus / B: resume", HORIZONTAL_ALIGNMENT_CENTER, W, 14, Color(1, 1, 1, 0.6))

# One menu step per push, even if a pad reports the same D-pad press as a button AND a stick axis.
var nav_last := -1.0
func pad_nav(k: int) -> void:
	if t - nav_last < 0.14:
		return
	nav_last = t
	on_key(k)

# A button mashed or held on one screen must not act on the next one (Bridge/hub/world hand-offs).
const SCREEN_GRACE := 0.35
var seen_state := -1
var state_since := 0.0

func note_state() -> void:
	if state != seen_state:
		write_log("state %s -> %s   (last input: %s)" % [S.keys()[seen_state] if seen_state >= 0 else "-", S.keys()[state], last_input])
		seen_state = state
		state_since = t

func write_log(line: String) -> void:
	var f := FileAccess.open("user://input_log.txt", FileAccess.READ_WRITE if log_started else FileAccess.WRITE)
	if f:
		f.seek_end()
		f.store_line("%6.1fs  %s" % [t, line])
		log_started = true

func on_key(k: int) -> void:
	if pause_open:
		pause_key(k)
		return
	if (state == S.BRIDGE or state == S.HUB) and t - state_since < SCREEN_GRACE and k != KEY_TAB:
		return
	if k == KEY_TAB or (k == KEY_ESCAPE and (state == S.PLAY or state == S.HUB)):
		open_pause()
		return
	match state:
		S.HUB:
			if (k == KEY_E or k == KEY_ENTER or k == KEY_SPACE) and near == -4:
				state = S.FOLDER
				fold_panel = 0
				fold_cur = [0, 0]
			elif (k == KEY_E or k == KEY_ENTER or k == KEY_SPACE) and near == -2:
				open_mash()
			elif k == KEY_X and near >= 0 and not carts[near].get("base", false):
				msg = "Deleted " + carts[near]["name"]
				msg_t = 3.0
				carts.remove_at(near)
				Carts.save_saved(carts)
		S.BRIDGE:
			if k == KEY_1: bridge_pick(0)
			elif k == KEY_2: bridge_pick(1)
			elif k == KEY_3: bridge_pick(2)
			elif k == KEY_A or k == KEY_LEFT: bridge_sel = maxi(0, bridge_sel - 1)
			elif k == KEY_D or k == KEY_RIGHT: bridge_sel = mini(bridge_choices.size(), bridge_sel + 1)
			elif k == KEY_E or k == KEY_ENTER or k == KEY_SPACE:
				if bridge_sel >= bridge_choices.size():
					start_play(bridge_recipe)
				else:
					bridge_pick(bridge_sel)
			elif k == KEY_BACKSPACE: start_play(bridge_recipe)
			elif k == KEY_ESCAPE: leave_bridge()
		S.PLAY:
			pass
		S.MASH:
			mash_key(k)
		S.FOLDER:
			folder_key(k)

func mash_key(k: int) -> void:
	if k == KEY_ESCAPE:
		if mash_step == 0:
			state = S.HUB
		else:
			mash_step -= 1
			mash_cursor = mash_a if mash_step == 1 else 0
		return
	if mash_step < 2:
		if k == KEY_W or k == KEY_UP:
			mash_cursor = (mash_cursor - 1 + mash_pool.size()) % mash_pool.size()
		elif k == KEY_S or k == KEY_DOWN:
			mash_cursor = (mash_cursor + 1) % mash_pool.size()
		elif k == KEY_ENTER or k == KEY_E or k == KEY_SPACE:
			if mash_step == 0:
				mash_a = mash_cursor
				mash_cursor = 0
				mash_step = 1
			else:
				mash_b = mash_cursor
				pending = Carts.mash(mash_pool[mash_a], mash_pool[mash_b])
				mash_step = 2
	else:
		if k == KEY_P:
			go_bridge(pending, -1)
		elif k == KEY_ENTER or k == KEY_E or k == KEY_SPACE:
			if carts.size() >= MAX_CARTS:
				msg = "Hub is full (%d portals). Delete one with X." % MAX_CARTS
			else:
				carts.append(pending)
				Carts.save_saved(carts)
				msg = "New portal opened: " + pending["name"]
			msg_t = 4.0
			state = S.HUB

# ---------- hub ----------
func _process(dt: float) -> void:
	t += dt
	note_state()
	msg_t = maxf(0.0, msg_t - dt)
	bind_note_t = maxf(0.0, bind_note_t - dt)
	report_t = maxf(0.0, report_t - dt)
	fade = maxf(0.0, fade - dt * 1.6)
	if pause_open:
		overlay.queue_redraw()
	if state == S.BRIDGE or state == S.MASH or state == S.FOLDER or pause_open:
		# stick / D-pad navigation in menus: one step per push
		var v := Pad.stick()    # stick only: the D-pad arrives as button events (pad_key), so polling it too skipped every other item
		if absf(v.x) > 0.6 and absf(nav_prev.x) <= 0.6:
			pad_nav(KEY_D if v.x > 0 else KEY_A)
		if absf(v.y) > 0.6 and absf(nav_prev.y) <= 0.6:
			pad_nav(KEY_S if v.y > 0 else KEY_W)
		nav_prev = v
	if state == S.BRIDGE:
		bridge_t += dt
	if state == S.ENTER:
		enter_t += dt
		if enter_t >= 0.5:
			go_bridge(carts[enter_idx], enter_idx)
	elif state == S.HUB and not pause_open:
		# W/S forward-back, A/D strafe, arrows turn (and forward-back), stick moves, right stick / mouse looks
		var strafe := int(Input.is_key_pressed(KEY_D)) - int(Input.is_key_pressed(KEY_A))
		var fwd := int(Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP)) - int(Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN))
		var pd := Pad.dir()
		var turn := float(int(Input.is_key_pressed(KEY_RIGHT)) - int(Input.is_key_pressed(KEY_LEFT))) * 2.2 * dt
		var pid := Pad.id()
		if pid >= 0:
			var rx := Pad.axis(JOY_AXIS_RIGHT_X)
			if absf(rx) > 0.2:
				turn += rx * 2.6 * dt
		if captured < 0:
			hub3d.move(Vector2(strafe + pd.x, fwd - pd.y).limit_length(1.0), turn, dt)
		near = -1
		var min_d := 99.0
		if hub3d.pos.distance_to(Hub3D.MACHINE) < 1.9:
			near = -2
		elif hub3d.pos.distance_to(Vector2(16.2, 12.3)) < 1.9:
			near = -4
		for i in carts.size():
			var d := hub3d.pos.distance_to(Hub3D.portal_pos(i))
			min_d = minf(min_d, d)
			if d < 2.4 and near != -2:
				near = i
			if d < Hub3D.CAPTURE_R and armed and captured < 0:
				captured = i
				capture_t = 0.0
		if captured >= 0:
			capture_t += dt
			var tp := Hub3D.portal_pos(captured)
			hub3d.pull_toward(tp, dt, 0.8 + capture_t * 2.6)   # accelerating, no input involved
			if hub3d.pos.distance_to(tp) < 0.7:
				begin_enter(captured)
		if min_d > Hub3D.CAPTURE_R + 0.8:
			armed = true
	update_warp()
	queue_redraw()

# How hard the nearest portal is bending the world, from first tug at 7 units to total at the portal.
func update_warp() -> void:
	var w := 0.0
	var centre := Vector2(0.5, 0.5)
	if (state == S.HUB or state == S.ENTER) and not pause_open and carts.size() > 0:
		var best := 99.0
		var bi := 0
		for i in carts.size():
			var d := hub3d.pos.distance_to(Hub3D.portal_pos(i))
			if d < best:
				best = d
				bi = i
		var dread := float(carts[bi].get("dread", 1.0))
		w = clampf(1.0 - (best - 0.6) / (WARP_RANGE * dread - 0.6), 0.0, 1.0)
		w = w * w * (3.0 - 2.0 * w)
		var to_p := (Hub3D.portal_pos(bi) - hub3d.pos).normalized()
		var facing := Vector2(cos(hub3d.ang), sin(hub3d.ang)).dot(to_p)
		w *= lerpf(0.12 if dread <= 1.0 else 0.7, 1.0, clampf((facing + 0.2) / 1.2, 0.0, 1.0))
		if captured < 0:
			w = minf(w, 0.62 * dread)
		else:
			w = maxf(w, minf(0.9, 0.5 + capture_t * 0.6))
		if state == S.ENTER:
			w = 1.0
		centre = hub3d.screen_uv(Hub3D.portal_pos(bi))
	hub3d.set_warp(w)
	warp_rect.visible = w > 0.01
	if warp_rect.visible:
		warp_mat.set_shader_parameter("strength", w)
		warp_mat.set_shader_parameter("center", Vector2(centre.x, 0.5))
		warp_mat.set_shader_parameter("time_s", t)
	capture_label.visible = captured >= 0 and (state == S.HUB or state == S.ENTER) and not pause_open
	if capture_label.visible:
		capture_label.modulate.a = clampf(capture_t * 1.2, 0.0, 1.0)

func _draw() -> void:
	if state == S.PLAY:
		return
	var f := ThemeDB.fallback_font
	if state == S.BRIDGE:
		draw_bridge(f)
		if fade > 0.0:
			draw_rect(Rect2(0, 0, W, H), Color(fade_col.r, fade_col.g, fade_col.b, fade))
		return
	hub3d.render(self, f, carts, t, near)
	# the top bar always stays; the minimap and report step aside as a portal takes hold
	var wp := hub3d.warp
	draw_rect(Rect2(0, 0, W, 92), Color(0, 0, 0, 0.62))
	draw_string(f, Vector2(24, 36), "CARTRIDGE HUB", HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color("f1faee"))
	if true:
		draw_string(f, Vector2(W - 564, 32), ("stick move   right stick / mouse look   walk into a portal   A machine   Plus: menu" if Pad.id() >= 0 else "WASD move   mouse / arrows look   walk into a portal   E machine   Esc: menu   F11"), HORIZONTAL_ALIGNMENT_RIGHT, 540, 13, Color(1, 1, 1, 0.5))
	if true:
		draw_wallet(f)
	if wp < 0.20:
		hub3d.minimap(self, carts)
	if report_t > 0.0 and wp < 0.15:
		draw_report(f)
	if wp < 0.5:
		draw_circle(Vector2(W * 0.5, H * 0.5), 2.0, Color(1, 1, 1, 0.6))   # crosshair dot
	# prompts
	if near == -4 and state == S.HUB:
		draw_string(f, Vector2(0, H - 10), ("A button" if Pad.id() >= 0 else "E") + ": open your chip folder (build your card deck)", HORIZONTAL_ALIGNMENT_CENTER, W, 18, Color.WHITE)
	elif near == -2:
		draw_string(f, Vector2(0, H - 10), ("A button" if Pad.id() >= 0 else "E") + ": fuse two worlds into a new portal", HORIZONTAL_ALIGNMENT_CENTER, W, 18, Color.WHITE)
	elif near >= 0 and state == S.HUB:
		var c: Dictionary = carts[near]
		draw_string(f, Vector2(0, H - 32), Carts.describe(c), HORIZONTAL_ALIGNMENT_CENTER, W, 13, Color(1, 1, 1, 0.7))
		var extra := "" if c.get("base", false) else ("   (Y: delete)" if Pad.id() >= 0 else "   (X: delete)")
		draw_string(f, Vector2(0, H - 10), c["name"] + extra, HORIZONTAL_ALIGNMENT_CENTER, W, 18, Color.WHITE)
	if msg_t > 0.0:
		draw_string(f, Vector2(0, H - 60), msg, HORIZONTAL_ALIGNMENT_CENTER, W, 20, Color("ffd166"))
	if state == S.MASH:
		draw_mash(f)
	if state == S.FOLDER:
		draw_folder(f)
	if state == S.ENTER:
		var u := clampf(enter_t / 0.5, 0.0, 1.0)
		var col := Color(carts[enter_idx]["color"])
		draw_circle(Vector2(W * 0.5, H * 0.5), lerpf(40.0, 1200.0, u * u), col)
	if fade > 0.0:
		draw_rect(Rect2(0, 0, W, H), Color(fade_col.r, fade_col.g, fade_col.b, fade))

func draw_bridge(f: Font) -> void:
	# The bridge has no substance: just drifting islands and motes.
	draw_rect(Rect2(0, 0, W, H), Color("06131a"))
	draw_circle(Vector2(W * 0.5, H * 0.55), 360, Color(0.1, 0.35, 0.4, 0.10))
	draw_circle(Vector2(W * 0.5, H * 0.55), 220, Color(0.15, 0.5, 0.55, 0.10))
	for i in 14:
		var sz := 18.0 + float((i * 13) % 34)
		var x := float((i * 173) % int(W))
		var y := fposmod(float(i * 97) - bridge_t * (8.0 + (i % 5) * 4.0), H + 140.0) - 70.0
		var pts := PackedVector2Array()
		for k in 6:
			pts.append(Vector2(x, y) + Vector2.RIGHT.rotated(TAU * k / 6.0 + i) * sz * (0.75 + 0.25 * sin(k * 3.0 + i)))
		draw_colored_polygon(pts, Color(0.08, 0.22, 0.26, 0.9))
		pts.append(pts[0])
		draw_polyline(pts, Color(0.35, 0.8, 0.85, 0.35), 1.5)
	for i in 60:
		var mx := fposmod(float(i * 211) + sin(bridge_t * 0.5 + i) * 30.0, W)
		var my := fposmod(float(i * 67) - bridge_t * (14.0 + (i % 7) * 6.0), H)
		draw_circle(Vector2(mx, my), 1.5, Color(0.7, 1.0, 1.0, 0.25 + 0.2 * sin(bridge_t * 2.0 + i)))
	draw_string(f, Vector2(24, 36), "THE BRIDGE", HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color("c8f7ff"))
	draw_string(f, Vector2(250, 36), ">  " + bridge_recipe["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(bridge_recipe["color"]).lightened(0.2))
	draw_wallet(f)
	draw_string(f, Vector2(0, 140), "Nothing here is real. Take something with you - it only lasts one run.", HORIZONTAL_ALIGNMENT_CENTER, W, 15, Color(0.78, 0.97, 1.0, 0.7))
	var wallet: Dictionary = profile["wallet"]
	for i in bridge_choices.size():
		var b: Dictionary = bridge_choices[i]
		var e: Dictionary = Carts.ESSENCE[b["ess"]]
		var ec := Color(e["color"])
		var have := int(wallet.get(e["name"], 0))
		var ok := have >= int(b["cost"])
		var bob := sin(bridge_t * 1.6 + i * 2.0) * 5.0
		var r := Rect2(170 + i * 210, 190 + bob, 190, 180)
		draw_rect(r, Color(0.04, 0.09, 0.11, 0.95))
		draw_rect(r, ec if ok else ec.darkened(0.6), false, 2)
		if i == bridge_sel:
			draw_rect(r.grow(5), Color.WHITE, false, 3)
		draw_string(f, Vector2(r.position.x, r.position.y + 32), "[%d]" % (i + 1), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 22, ec if ok else Color(1, 1, 1, 0.3))
		draw_string(f, Vector2(r.position.x, r.position.y + 72), b["name"], HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 18, Color.WHITE if ok else Color(1, 1, 1, 0.4))
		draw_string(f, Vector2(r.position.x + 8, r.position.y + 100), b["desc"], HORIZONTAL_ALIGNMENT_CENTER, r.size.x - 16, 12, Color(1, 1, 1, 0.7 if ok else 0.35))
		draw_string(f, Vector2(r.position.x, r.position.y + 150), "costs %d %s" % [b["cost"], e["name"]], HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 15, ec if ok else ec.darkened(0.5))
		draw_string(f, Vector2(r.position.x, r.position.y + 168), "you have %d" % have, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 11, Color(1, 1, 1, 0.45))
	if msg_t > 0.0:
		draw_string(f, Vector2(0, 420), msg, HORIZONTAL_ALIGNMENT_CENTER, W, 18, Color("ffd166"))
	var er := Rect2(370, 400, 220, 36)
	var esel := bridge_sel >= bridge_choices.size()
	draw_rect(er, Color(1, 1, 1, 0.14 if esel else 0.05))
	draw_rect(er, Color(1, 1, 1, 0.8 if esel else 0.3), false, 2)
	draw_string(f, Vector2(er.position.x, er.position.y + 24), "Go in empty-handed", HORIZONTAL_ALIGNMENT_CENTER, er.size.x, 15, Color.WHITE)
	draw_string(f, Vector2(0, H - 16), "A/D or stick: choose    Enter / E / A: confirm    Esc / B: back    Y: skip", HORIZONTAL_ALIGNMENT_CENTER, W, 14, Color(1, 1, 1, 0.6))

func draw_wallet(f: Font) -> void:
	draw_line(Vector2(0, 92), Vector2(W, 92), Color(1, 1, 1, 0.12))
	var wallet: Dictionary = profile["wallet"]
	var keys: Array = Carts.ESSENCE.keys()
	var step := minf(232.0, 900.0 / keys.size())
	for n in keys.size():
		var e: Dictionary = Carts.ESSENCE[keys[n]]
		var x := 30.0 + n * step
		var col := Color(e["color"])
		var pts := PackedVector2Array([Vector2(x, 54), Vector2(x + 9, 64), Vector2(x, 74), Vector2(x - 9, 64)])
		draw_colored_polygon(pts, col)
		draw_string(f, Vector2(x + 18, 70), "%s  %d" % [e["name"], int(wallet.get(e["name"], 0))], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)
		draw_string(f, Vector2(x + 18, 86), e["how"], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col.darkened(0.1))

# ---------- chip folder (deck building) ----------
func collection_ids() -> Array:
	var cards: Dictionary = profile["cards"]
	return Cards.order().filter(func(id): return int(cards.get(id, 0)) > 0)

func in_folder(id: String) -> int:
	var n := 0
	for c in profile["folder"]:
		if c == id:
			n += 1
	return n

func folder_key(k: int) -> void:
	var ids := collection_ids()
	var fol: Array = profile["folder"]
	var sizes := [ids.size(), fol.size()]
	match k:
		KEY_ESCAPE:
			Carts.save_profile(profile)
			state = S.HUB
			return
		KEY_A, KEY_LEFT: fold_panel = 0
		KEY_D, KEY_RIGHT: fold_panel = 1
		KEY_W, KEY_UP: fold_cur[fold_panel] -= 1
		KEY_S, KEY_DOWN: fold_cur[fold_panel] += 1
		KEY_E, KEY_ENTER, KEY_SPACE:
			if fold_panel == 0 and ids.size() > 0:
				var id: String = ids[clampi(fold_cur[0], 0, ids.size() - 1)]
				if fol.size() >= Cards.MAX_FOLDER:
					msg = "Folder is full (%d). Remove a card first." % Cards.MAX_FOLDER
					msg_t = 2.0
				elif in_folder(id) >= mini(Cards.MAX_COPIES, int(profile["cards"][id])):
					msg = "No more copies of %s to add." % Cards.CARDS[id]["name"]
					msg_t = 2.0
				else:
					fol.append(id)
			elif fold_panel == 1 and fol.size() > 0:
				fol.remove_at(clampi(fold_cur[1], 0, fol.size() - 1))
	fold_cur[0] = clampi(fold_cur[0], 0, maxi(0, ids.size() - 1))
	fold_cur[1] = clampi(fold_cur[1], 0, maxi(0, fol.size() - 1))
	Carts.save_profile(profile)

func draw_folder(f: Font) -> void:
	draw_rect(Rect2(0, 0, W, H), Color(0.01, 0.02, 0.05, 1.0))
	draw_string(f, Vector2(0, 56), "CHIP FOLDER", HORIZONTAL_ALIGNMENT_CENTER, W, 30, Color("4cc9f0"))
	var ids := collection_ids()
	var fol: Array = profile["folder"]
	draw_string(f, Vector2(0, 82), "your battle deck for Wave Duel   -   %d / %d cards   (max %d copies of any card)" % [fol.size(), Cards.MAX_FOLDER, Cards.MAX_COPIES], HORIZONTAL_ALIGNMENT_CENTER, W, 14, Color(1, 1, 1, 0.6))
	for panel in 2:
		var x0 := 60.0 + panel * 440.0
		var on := panel == fold_panel
		draw_rect(Rect2(x0, 100, 400, 330), Color(1, 1, 1, 0.05))
		draw_rect(Rect2(x0, 100, 400, 330), Color(1, 1, 1, 0.8 if on else 0.25), false, 2.0)
		draw_string(f, Vector2(x0 + 12, 124), "COLLECTION  (owned)" if panel == 0 else "FOLDER  (carried into duels)", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE)
		var n: int = ids.size() if panel == 0 else fol.size()
		for i in n:
			var id: String = ids[i] if panel == 0 else fol[i]
			var c: Dictionary = Cards.CARDS[id]
			var y := 150.0 + i * 22.0
			if y > 420.0:
				break
			var sel: bool = on and i == int(fold_cur[panel])
			if sel:
				draw_rect(Rect2(x0 + 6, y - 15, 388, 21), Color(1, 1, 1, 0.16))
			draw_rect(Rect2(x0 + 12, y - 12, 10, 14), Color(c["color"]))
			var label: String = c["name"]
			if panel == 0:
				label += "   x%d owned   (%d in folder)" % [int(profile["cards"][id]), in_folder(id)]
			draw_string(f, Vector2(x0 + 30, y), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE if sel else Color(1, 1, 1, 0.7))
	var cur_id := ""
	if fold_panel == 0 and ids.size() > 0:
		cur_id = ids[clampi(fold_cur[0], 0, ids.size() - 1)]
	elif fold_panel == 1 and fol.size() > 0:
		cur_id = fol[clampi(fold_cur[1], 0, fol.size() - 1)]
	if cur_id != "":
		draw_multiline_string(f, Vector2(60, 456), "%s - %s" % [Cards.CARDS[cur_id]["name"], str(Cards.CARDS[cur_id]["desc"]).replace("\n", " ")], HORIZONTAL_ALIGNMENT_LEFT, 840, 15, 2, Color("ffd166"))
	if msg_t > 0.0:
		draw_string(f, Vector2(0, 490), msg, HORIZONTAL_ALIGNMENT_CENTER, W, 16, Color("ff9f1c"))
	draw_string(f, Vector2(0, H - 16), "A/D switch panel    W/S move    Enter / A: add or remove    Esc / B: back", HORIZONTAL_ALIGNMENT_CENTER, W, 14, Color(1, 1, 1, 0.6))

func draw_report(f: Font) -> void:
	var box := Rect2(16, 104, 340, 124)   # left side: never covers a portal or its label
	draw_rect(box, Color(0.05, 0.04, 0.1, 0.92))
	draw_rect(box, Color("ffd166"), false, 2)
	var head: String = ("CLEARED  " if report["won"] else "RUN ENDED  ") + str(report["name"])
	draw_string(f, Vector2(box.position.x, box.position.y + 28), head, HORIZONTAL_ALIGNMENT_CENTER, box.size.x, 20, Color("ffd166"))
	draw_string(f, Vector2(box.position.x, box.position.y + 48), "score %.1f" % float(report["score"]), HORIZONTAL_ALIGNMENT_CENTER, box.size.x, 13, Color(1, 1, 1, 0.6))
	var gains: Dictionary = report["gains"]
	var got: Array = report.get("cards", [])
	if not got.is_empty():
		var names: Array = []
		for cid in got:
			names.append(Cards.CARDS[cid]["name"])
		draw_string(f, Vector2(box.position.x, box.position.y + 108), "New card: " + ", ".join(names), HORIZONTAL_ALIGNMENT_CENTER, box.size.x, 15, Color("ffd166"))
	if gains.is_empty():
		draw_string(f, Vector2(box.position.x, box.position.y + 84), "Nothing brought back this time.", HORIZONTAL_ALIGNMENT_CENTER, box.size.x, 15, Color(1, 1, 1, 0.7))
		return
	var x := box.position.x + 20.0
	var y := box.position.y + 84.0
	for sp in Carts.ESSENCE.keys():
		var e: Dictionary = Carts.ESSENCE[sp]
		if gains.has(e["name"]):
			draw_string(f, Vector2(x, y), "+%d %s" % [gains[e["name"]], e["name"]], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(e["color"]))
			x += 90.0

func draw_mash(f: Font) -> void:
	draw_rect(Rect2(0, 0, W, H), Color(0.01, 0.02, 0.05, 1.0))
	var mc := Color("c77dff")
	draw_string(f, Vector2(0, 60), "MASH MACHINE", HORIZONTAL_ALIGNMENT_CENTER, W, 30, mc)
	var titles := ["1/2  Pick the BODY world (how you move)", "2/2  Pick the ADD-ON world (its things, abilities and essences join in)", "Result"]
	draw_string(f, Vector2(0, 92), titles[mash_step], HORIZONTAL_ALIGNMENT_CENTER, W, 18, Color.WHITE)
	if mash_step < 2:
		for i in mash_pool.size():
			var y := 130.0 + i * 24.0
			var sel := i == mash_cursor
			var c: Dictionary = mash_pool[i]
			draw_rect(Rect2(260, y - 15, 14, 14), Color(c["color"]))
			draw_string(f, Vector2(284, y), ("> " if sel else "  ") + c["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE if sel else Color(1, 1, 1, 0.55))
		draw_string(f, Vector2(0, H - 16), "W/S or stick, then E / A button: choose    ESC / B: back    Plus: menu", HORIZONTAL_ALIGNMENT_CENTER, W, 14, Color(1, 1, 1, 0.6))
	else:
		draw_string(f, Vector2(0, 200), pending["name"], HORIZONTAL_ALIGNMENT_CENTER, W, 30, Color(pending["color"]).lightened(0.3))
		draw_string(f, Vector2(0, 250), Carts.describe(pending), HORIZONTAL_ALIGNMENT_CENTER, W, 15, Color(1, 1, 1, 0.8))
		draw_string(f, Vector2(0, 330), "ENTER / A: open portal in hub        P / Y: test play (unsaved)        ESC / B: change picks", HORIZONTAL_ALIGNMENT_CENTER, W, 16, Color.WHITE)

# ---------- platformer reachability (headless): which platforms can the player really reach? ----------
func run_reach() -> void:
	var rects: Array = [Rect2(0, 500, 960, 12)]
	rects.append_array(Runner.PLATFORMS)
	var r := {"id": "t", "name": "t", "color": "ffffff", "movement": "platformer", "abilities": [], "spawners": []}
	var reach := {}   # from index -> array of reachable target indexes
	for fi in rects.size():
		reach[fi] = []
		for ti in range(1, rects.size()):
			if fi == ti:
				continue
			var fr: Rect2 = rects[fi]
			var tg: Rect2 = rects[ti]
			var ok := false
			var x := maxf(fr.position.x, 14.0)
			while x <= minf(fr.end.x, 946.0) and not ok:
				for dir in [-1, 1]:
					for delay in [0.0, 0.1, 0.2, 0.3, 0.5]:
						var g = Runner.new()
						g.auto = true
						g.setup(r)
						g.pos = Vector2(x, fr.position.y - 16.0)
						g.on_floor = true
						g.bot_t = 999.0
						g.bot_dir = Vector2(dir, 0)
						for n in 120:
							if n == int(delay * 60.0):
								g.jump_buf = 0.1
							g.step(1.0 / 60.0)
							if n > 10 and g.on_floor and absf(g.pos.y - (tg.position.y - 16.0)) < 1.0 and g.pos.x > tg.position.x - 10.0 and g.pos.x < tg.end.x + 10.0:
								ok = true
								break
						g.free()
						if ok:
							break
					if ok:
						break
				x += 10.0
			if ok:
				reach[fi].append(ti)
	var seen := [0]
	var queue := [0]
	while not queue.is_empty():
		var c: int = queue.pop_front()
		for n in reach[c]:
			if not seen.has(n):
				seen.append(n)
				queue.append(n)
	print("platform edges reachable: ", reach)
	print("reachable from the ground: ", seen, " of ", rects.size(), " (index 0 = ground)")
	get_tree().quit()

func run_bindtest() -> void:
	Binds.load_from({})
	var ok := true
	var left := InputEventMouseButton.new()
	left.button_index = MOUSE_BUTTON_LEFT
	left.pressed = true
	Binds.set_slot("custom", "kb", Binds.capture(left, "kb"))
	var q := InputEventKey.new()
	q.keycode = KEY_Q
	q.pressed = true
	print("new key REPLACES the old one: mouse1 fires custom=", Binds.matches("custom", left), " | old Q still fires=", Binds.matches("custom", q))
	ok = ok and Binds.matches("custom", left) and not Binds.matches("custom", q)
	var lost := Binds.set_slot("shield", "pad", {"t": "joy", "c": JOY_BUTTON_Y})   # Y belongs to lock-on by default
	print("rebinding a taken button steals it: lock-on pad is now '", Binds.short(Binds.get_slot("lockon", "pad")), "', took from: ", lost)
	ok = ok and Binds.get_slot("lockon", "pad").is_empty() and lost.size() == 1
	Binds.set_slot("fire", "pad", {"t": "joy", "c": JOY_BUTTON_A})   # A is also Play next card: both are duel actions
	print("fire stole A from card: card pad = '", Binds.short(Binds.get_slot("card", "pad")), "'")
	ok = ok and Binds.get_slot("card", "pad").is_empty()
	Binds.load_from(JSON.parse_string(JSON.stringify(Binds.to_dict())))
	print("save/load round trip keeps it: ", Binds.short(Binds.get_slot("shield", "pad")), " / ", Binds.short(Binds.get_slot("custom", "kb")))
	ok = ok and Binds.short(Binds.get_slot("shield", "pad")) == "top"
	Binds.reset("shield")
	print("reset one row: shield pad = ", Binds.short(Binds.get_slot("shield", "pad")), " kb = ", Binds.short(Binds.get_slot("shield", "kb")))
	ok = ok and Binds.short(Binds.get_slot("shield", "pad")) == "right"
	Binds.reset_all()
	print("reset all: custom kb = ", Binds.short(Binds.get_slot("custom", "kb")), ", card pad = ", Binds.short(Binds.get_slot("card", "pad")))
	ok = ok and Binds.short(Binds.get_slot("custom", "kb")) == "Q" and Binds.short(Binds.get_slot("card", "pad")) == "bottom"
	Binds.load_from({"fire": [{"t": "key", "c": KEY_ENTER}], "card": [{"t": "key", "c": KEY_ENTER}]})   # an old-format save
	print("old-format save is ignored safely: fire kb = ", Binds.short(Binds.get_slot("fire", "kb")))
	ok = ok and Binds.short(Binds.get_slot("fire", "kb")) == "Space"
	print("BINDINGS OK" if ok else "BINDINGS BROKEN")
	get_tree().quit()

# ---------- self test (headless) ----------
func run_selftest() -> void:
	var plugins := Plugins.scan()
	print("plugin games found: ", plugins.map(func(p): return p["name"]))
	var base := Carts.base_list() + plugins.filter(func(p): return not p.has("script"))
	var all: Array = Carts.base_list() + plugins
	for a in base:
		for b in base:
			all.append(Carts.mash(a, b))
	for r in all:
		var g = make_world(r)
		g.auto = true
		var bs: Array = Carts.draft(r, [], r["abilities"].has("shoot"), 2).map(func(b): return b["id"])
		g.setup(r, bs)
		var res := []
		g.finished.connect(func(won, sc): res.append([won, sc]))
		var steps := 0
		while res.is_empty() and steps < 6000:
			g.step(1.0 / 60.0)
			steps += 1
		print("%-26s %-8s %5.1fs score %4.1f  brought back: %s  boons: %s" % [r["name"], ("WON" if res and res[0][0] else ("LOST" if res else "timeout")), steps / 60.0, g.score, g.essence, g.boons])
		g.free()
	# profile + mash save round trips
	var p := {"wallet": {"Gold": 5}, "stats": {"x": {"best": 1.0, "runs": 1, "wins": 0}}}
	Carts.save_profile(p)
	print("profile reloaded: ", Carts.load_profile())
	DirAccess.remove_absolute(Carts.PROFILE_PATH)
	get_tree().quit()

# Drives the real input path with controller buttons: A at the machine, pick body, pick add-on, confirm.
func run_mashtest() -> void:
	state = S.HUB
	near = -2
	var before := carts.size()
	on_key(pad_key(JOY_BUTTON_A))
	print("A at machine -> state=", state, " (MASH=", S.MASH, ") pool=", mash_pool.size())
	on_key(pad_key(JOY_BUTTON_A))
	on_key(KEY_S)
	on_key(pad_key(JOY_BUTTON_A))
	print("after two picks -> step=", mash_step, " result=", pending.get("name", "<none>"))
	on_key(pad_key(JOY_BUTTON_A))
	print("after confirm -> state=", state, " portals ", before, " -> ", carts.size(), "  saved on disk: ", Carts.load_saved().size())
	print("B in hub opens menu? ", pad_key(JOY_BUTTON_B) == KEY_ESCAPE, " | Start -> ", pad_key(JOY_BUTTON_START) == KEY_TAB)
	get_tree().quit()

# Fails loudly if any duel HUD element overlaps another or a text overflows its box.
func run_hudtest() -> void:
	var recipe: Dictionary = {}
	for c in carts:
		if c["id"] == "wave_duel":
			recipe = c
	var g = make_world(recipe)
	g.setup(recipe, [])
	var problems: Array = g.layout_problems()
	if problems.is_empty():
		print("HUD LAYOUT OK: no overlaps, every text fits its box")
	else:
		for pr in problems:
			print("HUD PROBLEM: ", pr)
	g.free()
	get_tree().quit()

# Hub <-> world round trip with a real (non-bot) run: die, return, re-enter the portal, pick a boon, and stay in the world.
func run_flowtest() -> void:
	var idx := -1
	for i in carts.size():
		if carts[i]["id"] == "wave_duel":
			idx = i
	profile["wallet"] = {"Nerve": 9, "Gold": 9, "Shards": 9, "Fangs": 9, "Static": 9}
	var ok := true
	for lap in 2:
		start_play(carts[idx], false)
		await get_tree().create_timer(2.5).timeout
		print("lap %d: playing -> state=%s runner=%s" % [lap, S.keys()[state], runner != null])
		ok = ok and state == S.PLAY and runner != null
		if runner == null:
			break
		runner.me["hp"] = 0.0
		await get_tree().create_timer(4.0).timeout
		print("lap %d: after death -> state=%s runner=%s" % [lap, S.keys()[state], runner != null])
		ok = ok and state == S.HUB and runner == null
		hub3d.pos = Hub3D.portal_pos(idx) + Vector2(0, 1.0)
		begin_enter(idx)
		await get_tree().create_timer(1.0).timeout
		print("lap %d: portal -> state=%s" % [lap, S.keys()[state]])
		if state == S.BRIDGE:
			var ev := InputEventKey.new()
			ev.keycode = KEY_ENTER
			ev.pressed = true
			Input.parse_input_event(ev)
			await get_tree().create_timer(1.5).timeout
			print("lap %d: boon picked -> state=%s runner=%s" % [lap, S.keys()[state], runner != null])
			ok = ok and state == S.PLAY and runner != null
			if runner:
				runner.queue_free()
				runner = null
	print("FLOW OK" if ok else "FLOW BROKEN")
	get_tree().quit()

# Presses every key that should raise the shield (with the saved bindings) and reports whether it went up.
func run_shieldtest() -> void:
	var idx := 0
	for i in carts.size():
		if carts[i]["id"] == "wave_duel":
			idx = i
	print("shield binds: ", Binds.all_for("shield"))
	start_play(carts[idx], false)
	await get_tree().create_timer(2.3).timeout
	for b in Binds.all_for("shield"):
		runner.guard_t = 0.0
		runner.guard_cd = 0.0
		var ev: InputEvent
		if str(b["t"]) == "key":
			ev = InputEventKey.new()
			ev.keycode = int(b["c"])
		elif str(b["t"]) == "joy":
			ev = InputEventJoypadButton.new()
			ev.button_index = int(b["c"])
		else:
			continue
		ev.pressed = true
		Input.parse_input_event(ev)
		await get_tree().create_timer(0.2).timeout
		print("  ", Binds.short(b), " -> phase=%s guard_t=%.2f cd=%.2f" % [runner.phase, runner.guard_t, runner.guard_cd])
	get_tree().quit()

func pad_event(button: int, down: bool) -> void:
	var ev := InputEventJoypadButton.new()
	ev.device = 0
	ev.button_index = button
	ev.pressed = down
	Input.parse_input_event(ev)

func pad_tap(button: int, hold := 0.12) -> void:
	pad_event(button, true)
	await get_tree().create_timer(hold).timeout
	pad_event(button, false)
	await get_tree().create_timer(0.1).timeout

# Raw pad buttons (as a Pro Controller reaches the game) into a live duel: does each one do its job?
func run_padtest() -> void:
	var idx := 0
	for i in carts.size():
		if carts[i]["id"] == "wave_duel":
			idx = i
	start_play(carts[idx], false)
	await get_tree().create_timer(2.3).timeout
	var w = runner
	var ok := true
	w.gauge = 1.0
	await pad_tap(JOY_BUTTON_LEFT_SHOULDER)
	print("LB opens Custom: ", w.selecting); ok = ok and w.selecting
	var c0: int = w.cur
	await pad_tap(JOY_BUTTON_DPAD_RIGHT)
	print("D-right moves cursor: ", w.cur, " (was ", c0, ")"); ok = ok and w.cur == c0 + 1
	await pad_tap(JOY_BUTTON_A)
	print("bottom (A) picks a card: ", w.picked.size()); ok = ok and w.picked.size() == 1
	await pad_tap(JOY_BUTTON_LEFT_SHOULDER)
	print("LB confirms: selecting=", w.selecting, " queued=", w.queue.size()); ok = ok and (not w.selecting) and w.queue.size() == 1
	var shot_before: int = w.shots.size()
	await pad_tap(JOY_BUTTON_B)
	print("right (B) raises shield: guard_t=%.2f" % w.guard_t); ok = ok and w.guard_t > 0.0
	w.guard_t = 0.0
	w.guard_cd = 0.0
	await pad_tap(JOY_BUTTON_RIGHT_SHOULDER)
	print("RB does not raise the shield: ", w.guard_t == 0.0); ok = ok and w.guard_t == 0.0
	# held-button polling cannot be injected without a real pad, so check the fire binding list instead
	var fire_pad := Binds.short(Binds.get_slot("fire", "pad"))
	print("pad button that fires: ", fire_pad, " (plus the ZR trigger)"); ok = ok and fire_pad == "RB"
	await pad_tap(JOY_BUTTON_Y)
	print("top (Y) with no sword queued does nothing harmful: locked=", w.locked); ok = ok and not w.locked
	print("PAD LAYOUT OK" if ok else "PAD LAYOUT BROKEN")
	get_tree().quit()
