extends Node2D
# Plays any cartridge recipe: body (movement) + abilities + spawners.

const Carts = preload("res://carts.gd")
const Pad = preload("res://pad.gd")
const Binds = preload("res://binds.gd")

signal finished(won: bool, score: float)

const W := 960.0
const H := 540.0
const GROUND := 500.0
const GOAL := 15.0
const PLATFORMS := [Rect2(120, 400, 200, 12), Rect2(640, 400, 200, 12), Rect2(380, 290, 200, 12), Rect2(80, 200, 180, 12), Rect2(700, 190, 180, 12)]

var recipe: Dictionary
var auto := false          # bot-driven (for self tests / screenshots)
var pos := Vector2(480, 250)
var vel := Vector2.ZERO
var face := Vector2.RIGHT
var angle := -PI / 2
var on_floor := false
var lives := 3
var score := 0.0
var inv := 0.0
var shoot_cd := 0.0
var jump_buf := 0.0
var bullets: Array = []
var things: Array = []
var coins: Array = []
var timers := {}
var t := 0.0
var done := false
var boons: Array = []
var can_shoot := false
var speed_mul := 1.0
var thing_mul := 1.0
var fire_cd := 0.22
var magnet := 0.0
var score_mul := 1.0
var inv_time := 1.5
var ess_mul := 1
var goal := GOAL
var choosing := false
var sel := 0
var nav_prev := Vector2.ZERO
var pad_prev_up := false
var choices: Array = []
var next_draft := 0
const DRAFTS := [5.0, 10.0]
var essence := {}         # what this run brings back to the hub
var bot_dir := Vector2.ZERO
var bot_t := 0.0

func gain(spawner: String, n: int = 1) -> void:
	var nm: String = Carts.ESSENCE[spawner]["name"]
	essence[nm] = essence.get(nm, 0) + n * ess_mul

func add_score(x: float) -> void:
	score += x * score_mul

func apply_boon(id: String) -> void:
	boons.append(id)
	match id:
		"skin": lives += 1
		"sprint": speed_mul = 1.25
		"slow": thing_mul = 0.8
		"gun": can_shoot = true
		"rapid": fire_cd = 0.11
		"magnet": magnet = 150.0
		"bounty": score_mul = 1.5
		"ghost": inv_time = 3.0
		"greed": ess_mul = 2
		"short": goal = 11.0

func open_draft() -> void:
	choices = Carts.draft(recipe, boons, can_shoot)
	next_draft += 1
	if choices.is_empty():
		return
	choosing = true
	sel = 0
	if auto:
		pick(0)

func pick(i: int) -> void:
	if not choosing or i >= choices.size():
		return
	apply_boon(choices[i]["id"])
	choosing = false

func setup(r: Dictionary, start_boons: Array = []) -> void:
	recipe = r
	can_shoot = r["abilities"].has("shoot")
	for b in start_boons:
		apply_boon(b)
	match r["movement"]:
		"platformer":
			pos = Vector2(480, GROUND - 16)
		"ship":
			pos = Vector2(480, 270)
		_:
			pos = Vector2(480, 400)

func card_rect(i: int) -> Rect2:
	return Rect2(170 + i * 210, 190, 190, 150)

func _input(e: InputEvent) -> void:
	if not choosing and Binds.matches("jump", e):
		jump_buf = 0.12
	if e is InputEventJoypadButton and e.pressed:
		if choosing:
			if e.button_index == JOY_BUTTON_A or e.button_index == JOY_BUTTON_START:
				pick(sel)
		elif e.button_index == JOY_BUTTON_A:
			jump_buf = 0.12
		return
	if choosing and e is InputEventKey and e.pressed and not e.echo:
		match e.keycode:
			KEY_1: pick(0)
			KEY_2: pick(1)
			KEY_3: pick(2)
			KEY_A, KEY_LEFT: sel = maxi(0, sel - 1)
			KEY_D, KEY_RIGHT: sel = mini(choices.size() - 1, sel + 1)
			KEY_E, KEY_ENTER, KEY_SPACE: pick(sel)
		return
	if e is InputEventKey and e.pressed and not e.echo and (e.keycode == KEY_W or e.keycode == KEY_UP or e.keycode == KEY_ENTER):
		jump_buf = 0.12

func _physics_process(dt: float) -> void:
	if choosing:
		var v := Pad.dir()
		if absf(v.x) > 0.6 and absf(nav_prev.x) <= 0.6:
			sel = clampi(sel + int(signf(v.x)), 0, choices.size() - 1)
		nav_prev = v
	step(dt)
	queue_redraw()

func step(dt: float) -> void:
	if done or choosing:
		return
	t += dt
	inv = maxf(0.0, inv - dt)
	shoot_cd = maxf(0.0, shoot_cd - dt)
	jump_buf = maxf(0.0, jump_buf - dt)
	var d := read_dir(dt)
	move_player(d, dt)
	if read_shoot() and can_shoot and shoot_cd <= 0.0:
		bullets.append({"pos": pos + face * 18.0, "vel": face * 540.0, "life": 1.2})
		shoot_cd = fire_cd
	run_spawners(dt)
	update_things(dt)
	update_bullets(dt)
	update_coins(dt)
	if score >= goal:
		for sp in recipe["spawners"]:
			gain(sp, 2)   # clear bonus
		done = true
		finished.emit(true, score)
	elif lives <= 0:
		done = true
		finished.emit(false, score)
	elif next_draft < DRAFTS.size() and score >= DRAFTS[next_draft]:
		open_draft()

# ---------- input ----------
func read_dir(dt: float) -> Vector2:
	if auto:
		bot_t -= dt
		if bot_t <= 0.0:
			bot_t = randf_range(0.3, 1.0)
			bot_dir = Vector2(randi_range(-1, 1), randi_range(-1, 1))
			if randf() < 0.3:
				jump_buf = 0.1
		return bot_dir
	var x := int(Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT)) - int(Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT))
	var y := int(Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN)) - int(Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP))
	var pd := Pad.dir()
	if pd.y < -0.6 and not pad_prev_up:
		jump_buf = 0.12
	pad_prev_up = pd.y < -0.6
	return (Vector2(x, y) + pd).limit_length(1.0)

func read_shoot() -> bool:
	if auto:
		return true
	return Binds.held_excluding("fire", ["jump"]) or Pad.shoot()

# ---------- body ----------
func move_player(d: Vector2, dt: float) -> void:
	match recipe["movement"]:
		"topdown":
			vel = d.normalized() * 240.0 * speed_mul
			if d != Vector2.ZERO:
				face = d.normalized()
			pos += vel * dt
			pos = pos.clamp(Vector2(14, 14), Vector2(W - 14, H - 14))
		"platformer":
			vel.x = d.x * 250.0 * speed_mul
			if d.x != 0.0:
				face = Vector2(signf(d.x), 0)
			vel.y += 1500.0 * dt
			if on_floor and jump_buf > 0.0:
				vel.y = -700.0
				jump_buf = 0.0
			var prev_bottom := pos.y + 16.0
			pos += vel * dt
			on_floor = false
			pos.x = clampf(pos.x, 14.0, W - 14.0)
			var bottom := pos.y + 16.0
			if bottom >= GROUND:
				pos.y = GROUND - 16.0
				vel.y = 0.0
				on_floor = true
			elif vel.y >= 0.0:
				for p in PLATFORMS:
					if pos.x + 10.0 > p.position.x and pos.x - 10.0 < p.end.x and prev_bottom <= p.position.y and bottom >= p.position.y:
						pos.y = p.position.y - 16.0
						vel.y = 0.0
						on_floor = true
						break
			if pos.y < 16.0:
				pos.y = 16.0
				vel.y = maxf(vel.y, 0.0)
		"ship":
			angle += d.x * 3.6 * dt
			face = Vector2.RIGHT.rotated(angle)
			if d.y < 0.0:
				vel += face * 420.0 * dt
			vel *= pow(0.45, dt)
			pos += vel * dt
			pos.x = wrapf(pos.x, 0.0, W)
			pos.y = wrapf(pos.y, 0.0, H)

# ---------- world ----------
func edge_pos() -> Vector2:
	match randi() % 4:
		0: return Vector2(randf_range(0, W), -30)
		1: return Vector2(randf_range(0, W), H + 30)
		2: return Vector2(-30, randf_range(0, H))
		_: return Vector2(W + 30, randf_range(0, H))

func make_rock() -> Dictionary:
	var p := edge_pos()
	var target := Vector2(randf_range(200, W - 200), randf_range(120, H - 120))
	return {"kind": "rock", "pos": p, "vel": (target - p).normalized() * randf_range(60, 110), "r": 28.0, "hp": 2}

func coin_pos() -> Vector2:
	if recipe["movement"] == "platformer":
		if randf() < 0.3:
			return Vector2(randf_range(40, W - 40), GROUND - 22)
		var p: Rect2 = PLATFORMS[randi() % PLATFORMS.size()]
		return Vector2(randf_range(p.position.x + 10, p.end.x - 10), p.position.y - 22)
	return Vector2(randf_range(40, W - 40), randf_range(60, H - 40))

func count_kind(k: String) -> int:
	var n := 0
	for th in things:
		if th["kind"] == k:
			n += 1
	return n

func run_spawners(dt: float) -> void:
	for s in recipe["spawners"]:
		timers[s] = timers.get(s, 0.0) - dt
		if timers[s] > 0.0:
			continue
		match s:
			"rain":
				timers[s] = 0.4
				things.append({"kind": "rain", "pos": Vector2(randf_range(10, W - 10), -10), "vel": Vector2(randf_range(-40, 40), randf_range(180, 300)), "r": 9.0, "hp": 1})
			"coins":
				timers[s] = 1.0
				if coins.size() < 3:
					coins.append(coin_pos())
			"rocks":
				timers[s] = 2.6
				if count_kind("rock") < 8:
					things.append(make_rock())
			"chasers":
				timers[s] = 3.0
				if count_kind("chaser") < 6:
					things.append({"kind": "chaser", "pos": edge_pos(), "vel": Vector2.ZERO, "r": 14.0, "hp": 1})

func hurt() -> void:
	lives -= 1
	inv = inv_time

func update_things(dt: float) -> void:
	var i := things.size() - 1
	while i >= 0:
		var th: Dictionary = things[i]
		if th["kind"] == "chaser":
			th["pos"] = th["pos"] + (pos - th["pos"]).normalized() * 95.0 * thing_mul * dt
		else:
			th["pos"] = th["pos"] + th["vel"] * dt * thing_mul
		var p: Vector2 = th["pos"]
		var floor_y := GROUND if recipe["movement"] == "platformer" else H + 20.0
		if th["kind"] == "rain" and p.distance_to(pos) < float(th["r"]) + 34.0:
			th["close"] = true
		if th["kind"] == "rain" and p.y > floor_y:
			add_score(0.25)
			if th.get("close", false):
				gain("rain")
			things.remove_at(i)
		elif p.x < -150 or p.x > W + 150 or p.y < -150 or p.y > H + 150:
			things.remove_at(i)
		elif inv <= 0.0 and p.distance_to(pos) < float(th["r"]) + 11.0:
			hurt()
			things.remove_at(i)
		i -= 1

func update_bullets(dt: float) -> void:
	var i := bullets.size() - 1
	while i >= 0:
		var b: Dictionary = bullets[i]
		b["pos"] = b["pos"] + b["vel"] * dt
		b["life"] = float(b["life"]) - dt
		var gone: bool = b["life"] <= 0.0
		if not gone:
			for j in range(things.size() - 1, -1, -1):
				var th: Dictionary = things[j]
				if (b["pos"] as Vector2).distance_to(th["pos"]) < float(th["r"]) + 4.0:
					th["hp"] = int(th["hp"]) - 1
					gone = true
					if th["hp"] <= 0:
						kill(th)
						things.remove_at(j)
					break
		if gone:
			bullets.remove_at(i)
		i -= 1

func kill(th: Dictionary) -> void:
	match th["kind"]:
		"rock":
			if float(th["r"]) > 20.0:
				add_score(0.5)
				for s in [-1.0, 1.0]:
					things.append({"kind": "rock", "pos": th["pos"], "vel": (th["vel"] as Vector2).rotated(s * 0.9) * 1.4, "r": 14.0, "hp": 1})
			else:
				add_score(1.0)
				gain("rocks")
		"chaser":
			add_score(1.0)
			gain("chasers")
		"rain":
			add_score(0.5)

func update_coins(dt: float) -> void:
	for i in range(coins.size() - 1, -1, -1):
		if magnet > 0.0 and (coins[i] as Vector2).distance_to(pos) < magnet:
			coins[i] = (coins[i] as Vector2).move_toward(pos, 260.0 * dt)
		if (coins[i] as Vector2).distance_to(pos) < 24.0:
			add_score(1.0)
			gain("coins")
			coins.remove_at(i)

# ---------- drawing ----------
func _draw() -> void:
	if recipe.is_empty():
		return
	var col := Color(recipe["color"])
	draw_rect(Rect2(0, 0, W, H), col.darkened(0.8))
	if recipe["movement"] == "platformer":
		draw_rect(Rect2(0, GROUND, W, H - GROUND), col.darkened(0.4))
		for p in PLATFORMS:
			draw_rect(p, col.darkened(0.2))
	for c in coins:
		draw_circle(c, 10, Color("f9c74f"))
		draw_arc(c, 10, 0, TAU, 20, Color.WHITE, 2)
	for th in things:
		draw_thing(th)
	for b in bullets:
		draw_circle(b["pos"], 4, Color.WHITE)
	if inv <= 0.0 or int(t * 20) % 2 == 0:
		draw_player()
	draw_hud(col)
	if choosing:
		draw_draft()

func draw_thing(th: Dictionary) -> void:
	var p: Vector2 = th["pos"]
	var r: float = th["r"]
	match th["kind"]:
		"rain":
			draw_circle(p, r, Color("4cc9f0"))
			draw_colored_polygon(PackedVector2Array([p + Vector2(0, -r * 2.2), p + Vector2(-r * 0.9, -r * 0.4), p + Vector2(r * 0.9, -r * 0.4)]), Color("4cc9f0"))
		"rock":
			var pts := PackedVector2Array()
			for k in 9:
				var a := TAU * k / 9.0
				pts.append(p + Vector2.RIGHT.rotated(a) * r * (0.82 + 0.18 * sin(k * 7.0)))
			draw_colored_polygon(pts, Color("8d99ae"))
			pts.append(pts[0])
			draw_polyline(pts, Color("edf2f4"), 2)
		"chaser":
			draw_circle(p, r, Color("e63946"))
			var dir := (pos - p).normalized()
			draw_circle(p + dir * 5 + Vector2(-4, -3), 3, Color.WHITE)
			draw_circle(p + dir * 5 + Vector2(4, -3), 3, Color.WHITE)

func draw_player() -> void:
	match recipe["movement"]:
		"topdown":
			draw_circle(pos, 12, Color.WHITE)
			draw_circle(pos + face * 12, 4, Color("ffb703"))
		"platformer":
			draw_rect(Rect2(pos - Vector2(10, 16), Vector2(20, 32)), Color.WHITE)
			draw_circle(pos + Vector2(face.x * 5, -7), 3, Color.BLACK)
		"ship":
			var pts := PackedVector2Array([pos + face * 16, pos + face.rotated(2.5) * 12, pos + face.rotated(-2.5) * 12])
			draw_colored_polygon(pts, Color.WHITE)

func draw_hud(col: Color) -> void:
	var f := ThemeDB.fallback_font
	draw_string(f, Vector2(16, 28), "%s    score %.1f / %d" % [recipe["name"], score, int(goal)], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)
	var parts: Array = []
	for k in essence:
		parts.append("%s %d" % [k, essence[k]])
	draw_string(f, Vector2(0, H - 10), "   ".join(parts), HORIZONTAL_ALIGNMENT_RIGHT, W - 16, 15, Color("ffd166"))
	for i in lives:
		draw_circle(Vector2(W - 24 - i * 24, 22), 8, Color("e63946"))
	var bn: Array = []
	for id in boons:
		bn.append(Carts.boon(id)["name"])
	if not bn.is_empty():
		draw_string(f, Vector2(0, 28), ", ".join(bn), HORIZONTAL_ALIGNMENT_CENTER, W, 13, Color("c8f7ff"))
	var hint := ""
	match recipe["movement"]:
		"topdown": hint = "WASD move"
		"platformer": hint = "A/D move, W jump"
		"ship": hint = "A/D turn, W thrust"
	if recipe["abilities"].has("shoot"):
		hint += "   SPACE shoot"
	draw_string(f, Vector2(16, H - 10), hint + "   ESC / Plus: menu", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.6))

func draw_draft() -> void:
	var f := ThemeDB.fallback_font
	draw_rect(Rect2(0, 0, W, H), Color(0, 0, 0, 0.78))
	draw_string(f, Vector2(0, 110), "THE BRIDGE OFFERS", HORIZONTAL_ALIGNMENT_CENTER, W, 28, Color("c8f7ff"))
	draw_string(f, Vector2(0, 140), "free pick - lasts until this run ends     (A/D or stick, then A button / Enter)", HORIZONTAL_ALIGNMENT_CENTER, W, 14, Color(1, 1, 1, 0.55))
	for i in choices.size():
		var b: Dictionary = choices[i]
		var r := card_rect(i)
		var ec := Color(Carts.ESSENCE[b["ess"]]["color"])
		draw_rect(r, Color(0.04, 0.09, 0.11, 0.95))
		draw_rect(r, ec, false, 2)
		if i == sel:
			draw_rect(r.grow(5), Color.WHITE, false, 3)
		draw_string(f, Vector2(r.position.x, r.position.y + 30), "[%d]" % (i + 1), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 22, ec)
		draw_string(f, Vector2(r.position.x, r.position.y + 70), b["name"], HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 18, Color.WHITE)
		draw_string(f, Vector2(r.position.x + 8, r.position.y + 100), b["desc"], HORIZONTAL_ALIGNMENT_CENTER, r.size.x - 16, 12, Color(1, 1, 1, 0.7))
