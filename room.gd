extends RefCounted
# The hub room: a small isometric room you walk around. Furniture is simple boxes for now (it will be dressed to look like a real
# room); the three things you can walk up to are the computer (jack in to a world), the card binder and the shop.
#
# Grid: x runs toward the lower right, y toward the lower left. Screen = origin + ((x - y) * TW / 2, (x + y) * TH / 2 - z).
# Walls stand on the two far edges (x = 0 and y = 0).

const TW := 64.0
const TH := 32.0
const ROOM_W := 9.0
const ROOM_D := 9.0
const WALL_H := 100.0
const OX := 480.0
const OY := 196.0
const RADIUS := 0.28
const SPEED := 130.0          # screen pixels per second
const REACH := 1.25           # how close you must be to a piece of furniture to use it
const SPAWN := Vector2(3.3, 3.4)
const FACINGS := ["S", "SW", "W", "NW", "N", "NE", "E", "SE"]    # rows of art/room_hero.png

var pos := SPAWN
var face := 0
var walk_t := 0.0
var moving := false

# why each piece is here is written next to it ("why"); the interactive ones are the three the game is built around
var furniture: Array = [
	{"id": "desk", "x": 1.1, "y": 0.2, "w": 2.9, "d": 1.25, "h": 30.0, "c": Color("7a5a49"), "act": "computer", "label": "jack in at the computer",
		"why": "Where you leave from: the computer is the way into every world."},
	{"id": "monitor", "x": 1.9, "y": 0.45, "w": 1.1, "d": 0.5, "h": 30.0, "z0": 30.0, "c": Color("2b3350"), "screen": true, "solid": false},
	{"id": "shelf", "x": 0.15, "y": 3.2, "w": 0.75, "d": 2.2, "h": 84.0, "c": Color("5d4a63"), "act": "binder", "label": "open your card binder",
		"why": "Where your cards live: you choose which ones you bring."},
	{"id": "counter", "x": 6.0, "y": 0.2, "w": 2.5, "d": 1.15, "h": 34.0, "c": Color("4d7a78"), "act": "shop", "label": "visit the shop",
		"why": "Where you spend what a run brought back, to come back stronger."},
	{"id": "sign", "x": 6.3, "y": 0.3, "w": 1.9, "d": 0.3, "h": 18.0, "z0": 66.0, "c": Color("e9b949"), "solid": false, "glow": true},
	{"id": "bed", "x": 6.1, "y": 5.7, "w": 2.55, "d": 2.9, "h": 24.0, "c": Color("546a9e"),
		"why": "It is a room, and a room should look lived in; also keeps the corner from feeling empty."},
	{"id": "pillow", "x": 6.25, "y": 5.85, "w": 2.2, "d": 0.7, "h": 8.0, "z0": 24.0, "c": Color("e8dfe0"), "solid": false},
	{"id": "pouf", "x": 3.7, "y": 6.9, "w": 0.95, "d": 0.95, "h": 20.0, "c": Color("a2566b")},
]

func proj(x: float, y: float, z: float = 0.0) -> Vector2:
	return Vector2(OX + (x - y) * TW * 0.5, OY + (x + y) * TH * 0.5 - z)

func screen_to_world_delta(sx: float, sy: float) -> Vector2:
	var a := sx / (TW * 0.5)
	var b := sy / (TH * 0.5)
	return Vector2((a + b) * 0.5, (b - a) * 0.5)

func solid_rects() -> Array:
	var out: Array = []
	for f in furniture:
		if bool(f.get("solid", true)) and not f.has("z0"):
			out.append(Rect2(float(f["x"]) - RADIUS, float(f["y"]) - RADIUS, float(f["w"]) + RADIUS * 2.0, float(f["d"]) + RADIUS * 2.0))
	return out

func blocked(p: Vector2) -> bool:
	if p.x < RADIUS or p.y < RADIUS or p.x > ROOM_W - RADIUS or p.y > ROOM_D - RADIUS:
		return true
	for r in solid_rects():
		if (r as Rect2).has_point(p):
			return true
	return false

# v is the push in SCREEN space (x right, y down), length <= 1
func update(dt: float, v: Vector2) -> void:
	moving = v.length() > 0.15
	if moving:
		walk_t += dt
		var ang := rad_to_deg(atan2(v.y, v.x))
		var idx := posmod(int(round(ang / 45.0)), 8)       # 0 E, 1 SE, 2 S, 3 SW, 4 W, 5 NW, 6 N, 7 NE
		face = [6, 7, 0, 1, 2, 3, 4, 5][idx]
		var d := screen_to_world_delta(v.x * SPEED * dt, v.y * SPEED * dt)
		var nx := Vector2(pos.x + d.x, pos.y)
		if not blocked(nx):
			pos = nx
		var ny := Vector2(pos.x, pos.y + d.y)
		if not blocked(ny):
			pos = ny
	else:
		walk_t = 0.0

# the nearest piece of furniture you can use, or {}
func target() -> Dictionary:
	var best := {}
	var best_d := REACH
	for f in furniture:
		if not f.has("act"):
			continue
		var r := Rect2(float(f["x"]), float(f["y"]), float(f["w"]), float(f["d"]))
		var cx := clampf(pos.x, r.position.x, r.end.x)
		var cy := clampf(pos.y, r.position.y, r.end.y)
		var d := Vector2(cx, cy).distance_to(pos)
		if d < best_d:
			best_d = d
			best = f
	return best

# ------------------------------------------------------------------ drawing
func _quad(c: CanvasItem, pts: Array, col: Color) -> void:
	c.draw_colored_polygon(PackedVector2Array(pts), col)

func draw_box(c: CanvasItem, x: float, y: float, w: float, d: float, h: float, z0: float, col: Color, glow: bool = false) -> void:
	var top := col.lightened(0.18)
	var left := col.darkened(0.12)
	var right := col.darkened(0.32)
	if glow:
		top = col.lightened(0.3)
		left = col
		right = col.darkened(0.15)
	var z1 := z0 + h
	_quad(c, [proj(x, y + d, z0), proj(x + w, y + d, z0), proj(x + w, y + d, z1), proj(x, y + d, z1)], left)          # the face toward the lower left
	_quad(c, [proj(x + w, y, z0), proj(x + w, y + d, z0), proj(x + w, y + d, z1), proj(x + w, y, z1)], right)        # the face toward the lower right
	_quad(c, [proj(x, y, z1), proj(x + w, y, z1), proj(x + w, y + d, z1), proj(x, y + d, z1)], top)
	var edge := Color(0, 0, 0, 0.35)
	c.draw_polyline(PackedVector2Array([proj(x, y + d, z1), proj(x + w, y + d, z1), proj(x + w, y, z1)]), edge, 1.0)
	c.draw_line(proj(x + w, y + d, z0), proj(x + w, y + d, z1), edge, 1.0)

func draw_room_shell(c: CanvasItem, t: float) -> void:
	# floor: two-tone boards
	for i in int(ROOM_W):
		for j in int(ROOM_D):
			var col := Color("46395e") if (i + j) % 2 == 0 else Color("3d3254")
			_quad(c, [proj(i, j), proj(i + 1, j), proj(i + 1, j + 1), proj(i, j + 1)], col)
	# rug
	_quad(c, [proj(2.6, 2.4), proj(5.6, 2.4), proj(5.6, 5.4), proj(2.6, 5.4)], Color("5a3f6e"))
	_quad(c, [proj(2.85, 2.65), proj(5.35, 2.65), proj(5.35, 5.15), proj(2.85, 5.15)], Color("6d4c82"))
	# back walls
	var wall_l := Color("5b4a78")
	var wall_r := Color("4a3b66")
	_quad(c, [proj(0, 0, 0), proj(0, ROOM_D, 0), proj(0, ROOM_D, WALL_H), proj(0, 0, WALL_H)], wall_l)      # the wall at x = 0
	_quad(c, [proj(0, 0, 0), proj(ROOM_W, 0, 0), proj(ROOM_W, 0, WALL_H), proj(0, 0, WALL_H)], wall_r)      # the wall at y = 0
	# baseboards and the corner line
	_quad(c, [proj(0, 0, 0), proj(0, ROOM_D, 0), proj(0, ROOM_D, 8), proj(0, 0, 8)], Color("2c2342"))
	_quad(c, [proj(0, 0, 0), proj(ROOM_W, 0, 0), proj(ROOM_W, 0, 8), proj(0, 0, 8)], Color("251d38"))
	c.draw_line(proj(0, 0, 0), proj(0, 0, WALL_H), Color(0, 0, 0, 0.35), 2.0)
	# window on the right wall (the sky is the same dusk as the fights)
	_quad(c, [proj(4.2, 0, 44), proj(6.4, 0, 44), proj(6.4, 0, 88), proj(4.2, 0, 88)], Color("ffb36b"))
	_quad(c, [proj(4.2, 0, 68), proj(6.4, 0, 68), proj(6.4, 0, 88), proj(4.2, 0, 88)], Color("c76aa8"))
	c.draw_polyline(PackedVector2Array([proj(4.2, 0, 44), proj(6.4, 0, 44), proj(6.4, 0, 88), proj(4.2, 0, 88), proj(4.2, 0, 44)]), Color("2c2342"), 3.0)
	c.draw_line(proj(5.3, 0, 44), proj(5.3, 0, 88), Color("2c2342"), 2.0)
	# a poster on the left wall
	_quad(c, [proj(0, 6.2, 40), proj(0, 7.6, 40), proj(0, 7.6, 84), proj(0, 6.2, 84)], Color("2f6f8f"))
	_quad(c, [proj(0, 6.4, 46), proj(0, 7.4, 46), proj(0, 7.4, 78), proj(0, 6.4, 78)], Color("e9b949"))

func draw_hero(c: CanvasItem, tex: Texture2D, meta: Dictionary, shadow: bool = true) -> void:
	var feet := proj(pos.x, pos.y)
	if shadow:
		c.draw_set_transform(feet, 0.0, Vector2(1.0, 0.45))
		c.draw_circle(Vector2.ZERO, 15.0, Color(0, 0, 0, 0.35))
		c.draw_set_transform_matrix(Transform2D.IDENTITY)
	if tex == null or meta.is_empty():
		c.draw_circle(feet - Vector2(0, 26), 12.0, Color("7df9ff"))
		return
	var fw := int(meta["fw"])
	var size := 112.0
	var frame := int(walk_t * float(meta["fps"])) % int(meta["n"]) if moving else 0
	var top_left := feet - Vector2(size * 0.5, size * float(meta["feet"]))
	c.draw_texture_rect_region(tex, Rect2(top_left, Vector2(size, size)), Rect2(frame * fw, face * fw, fw, fw))

func draw(c: CanvasItem, f: Font, t: float, tex: Texture2D, meta: Dictionary, tgt: Dictionary) -> void:
	draw_room_shell(c, t)
	# draw furniture and the hero back to front
	var items: Array = []
	for fu in furniture:
		items.append({"depth": float(fu["x"]) + float(fu["w"]) + float(fu["y"]) + float(fu["d"]) + (0.01 if fu.has("z0") else 0.0), "f": fu})
	items.append({"depth": pos.x + pos.y + 0.0, "hero": true})
	items.sort_custom(func(a, b): return float(a["depth"]) < float(b["depth"]))
	for it in items:
		if it.has("hero"):
			draw_hero(c, tex, meta)
			continue
		var fu: Dictionary = it["f"]
		draw_box(c, float(fu["x"]), float(fu["y"]), float(fu["w"]), float(fu["d"]), float(fu["h"]), float(fu.get("z0", 0.0)), fu["c"], bool(fu.get("glow", false)))
		if bool(fu.get("screen", false)):       # the monitor: a glowing screen on its lower-left face
			var a := proj(float(fu["x"]) + 0.08, float(fu["y"]) + float(fu["d"]), 32.0)
			var b := proj(float(fu["x"]) + float(fu["w"]) - 0.08, float(fu["y"]) + float(fu["d"]), 32.0)
			var pulse := 0.75 + 0.25 * sin(t * 2.0)
			c.draw_colored_polygon(PackedVector2Array([a, b, b + Vector2(0, -22), a + Vector2(0, -22)]), Color(0.3, 0.9, 1.0, pulse))
		if fu["id"] == "shelf":                 # book spines along the shelf's face
			for k in 5:
				var yy: float = float(fu["y"]) + 0.2 + k * 0.4
				c.draw_line(proj(float(fu["x"]) + float(fu["w"]), yy, 16.0 + k * 3.0), proj(float(fu["x"]) + float(fu["w"]), yy, 72.0), Color.from_hsv(0.08 + k * 0.17, 0.55, 0.95, 0.9), 5.0)
	# the use-marker over whatever you are near
	if not tgt.is_empty():
		var top := proj(float(tgt["x"]) + float(tgt["w"]) * 0.5, float(tgt["y"]) + float(tgt["d"]) * 0.5, float(tgt["h"]) + float(tgt.get("z0", 0.0)) + 26.0 + 4.0 * sin(t * 4.0))
		c.draw_colored_polygon(PackedVector2Array([top + Vector2(-9, -8), top + Vector2(9, -8), top + Vector2(0, 4)]), Color("ffd166"))
