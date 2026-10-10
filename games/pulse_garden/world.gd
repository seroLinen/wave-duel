extends "res://game_base.gd"
# Pulse Garden: hold to charge a pulse, release to pop every orb the ring sweeps over.
# Pop 3+ with one pulse for a bonus. Orbs hurt on touch. Earns Echo.

const Pad = preload("res://pad.gd")
const Binds = preload("res://binds.gd")

var pos := Vector2(480, 300)
var orbs: Array = []
var charge := 0.0
var ring_c := Vector2.ZERO
var ring_r := -1.0
var ring_max := 0.0
var ring_hits := 0
var spawn_t := 0.0
var t := 0.0
var bot_t := 0.0
var bot_dir := Vector2.ZERO
var bot_hold := false

func read_dir(dt: float) -> Vector2:
	if auto:
		bot_t -= dt
		if bot_t <= 0.0:
			bot_t = randf_range(0.4, 1.0)
			bot_dir = Vector2(randi_range(-1, 1), randi_range(-1, 1))
			bot_hold = not bot_hold
		return bot_dir
	var x := int(Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT)) - int(Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT))
	var y := int(Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN)) - int(Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP))
	return (Vector2(x, y) + Pad.dir()).limit_length(1.0)

func read_hold() -> bool:
	if auto:
		return bot_hold
	return Binds.held("fire") or Pad.shoot()

func edge_pos() -> Vector2:
	match randi() % 4:
		0: return Vector2(randf_range(0, W), -30)
		1: return Vector2(randf_range(0, W), H + 30)
		2: return Vector2(-30, randf_range(0, H))
		_: return Vector2(W + 30, randf_range(0, H))

func tick(dt: float) -> void:
	t += dt
	pos += read_dir(dt).limit_length(1.0) * 210.0 * speed_mul * dt
	pos = pos.clamp(Vector2(16, 16), Vector2(W - 16, H - 16))
	if read_hold():
		charge = minf(charge + dt, 1.2)
	else:
		if charge > 0.05 and ring_r < 0.0:
			ring_c = pos
			ring_max = 70.0 + charge * 210.0
			ring_r = 0.0
			ring_hits = 0
		charge = 0.0
	if ring_r >= 0.0:
		ring_r += 540.0 * dt
		var reach := minf(ring_r, ring_max)
		for i in range(orbs.size() - 1, -1, -1):
			if (orbs[i]["pos"] as Vector2).distance_to(ring_c) <= reach:
				orbs.remove_at(i)
				ring_hits += 1
				gain_ess("echo", 1)
				add_score(1.0)
		if ring_r >= ring_max:
			ring_r = -1.0
			if ring_hits >= 3:
				gain_ess("echo", 1)
				add_score(1.0)
	spawn_t -= dt
	if spawn_t <= 0.0 and orbs.size() < 14:
		spawn_t = 0.55
		var p := edge_pos()
		var target := Vector2(randf_range(150, W - 150), randf_range(100, H - 100))
		orbs.append({"pos": p, "vel": (target - p).normalized() * randf_range(45, 85)})
	for i in range(orbs.size() - 1, -1, -1):
		var o: Dictionary = orbs[i]
		o["pos"] = o["pos"] + o["vel"] * dt
		var op: Vector2 = o["pos"]
		if op.x < -160 or op.x > W + 160 or op.y < -160 or op.y > H + 160:
			orbs.remove_at(i)
		elif inv <= 0.0 and op.distance_to(pos) < 22.0:
			orbs.remove_at(i)
			hurt()

func _draw() -> void:
	if recipe.is_empty():
		return
	var f := ThemeDB.fallback_font
	var teal := Color(recipe["color"])
	draw_rect(Rect2(0, 0, W, H), teal.darkened(0.85))
	for i in 40:
		draw_circle(Vector2(fposmod(i * 97.0, W), fposmod(i * 61.0 + 30.0, H)), 2, Color(teal, 0.12))
	for o in orbs:
		draw_circle(o["pos"], 12, Color("ff9f1c"))
		draw_circle(o["pos"] + Vector2(-3, -3), 4, Color(1, 1, 1, 0.5))
	if ring_r >= 0.0:
		var rr := minf(ring_r, ring_max)
		draw_circle(ring_c, rr, Color(teal, 0.10))
		draw_arc(ring_c, rr, 0, TAU, 72, teal, 4)
	if charge > 0.0:
		draw_arc(pos, 70.0 + charge * 210.0, 0, TAU, 72, Color(1, 1, 1, 0.3), 2)
	if inv <= 0.0 or int(t * 20) % 2 == 0:
		draw_circle(pos, 11, Color.WHITE)
		draw_circle(pos, 11 + charge * 6.0, Color(teal, 0.5), false, 2)
	draw_string(f, Vector2(16, 28), "%s    score %.1f / %d" % [recipe["name"], score, int(goal)], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)
	for i in lives:
		draw_circle(Vector2(W - 24 - i * 24, 22), 8, Color("e63946"))
	var parts: Array = []
	for k in essence:
		parts.append("%s %d" % [k, essence[k]])
	draw_string(f, Vector2(0, H - 10), "   ".join(parts), HORIZONTAL_ALIGNMENT_RIGHT, W - 16, 15, Color("ffd166"))
	draw_string(f, Vector2(16, H - 10), "move   hold SPACE / B / X / ZR to charge, release to pulse   ESC / Plus: menu", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.6))
