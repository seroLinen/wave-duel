extends RefCounted
# The hub room: a small isometric room you walk around, drawn as an original illustration of the owner's own room
# (bed with a sleeping cat, window with a blue glow, tapestry, desk corner, closet). Posters are simple stand-ins in similar
# colours, never copies of real artwork. The three things you can walk up to: the computer (jack in), the card binder, the shop.
#
# Grid: x runs toward the lower right, y toward the lower left. Screen = origin + ((x - y) * TW / 2, (x + y) * TH / 2 - z).
# Walls stand on the two far edges: the "left wall" is the plane x = 0 (position along it = y), the "right wall" is y = 0 (position = x).

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
const SPAWN := Vector2(4.2, 3.3)
const FACINGS := ["S", "SW", "W", "NW", "N", "NE", "E", "SE"]    # rows of art/room_hero.png

var pos := SPAWN
var face := 0
var walk_t := 0.0
var moving := false

# "why" says what each piece is for; the interactive ones are the three the game is built around
var furniture: Array = [
	{"id": "desk", "x": 0.35, "y": 0.2, "w": 3.2, "d": 1.3, "h": 30.0, "c": Color("34303f"), "act": "computer", "label": "jack in at the computer",
		"why": "Where you leave from: the computer is the way into every world."},
	{"id": "monitor_a", "x": 0.7, "y": 0.35, "w": 1.2, "d": 0.14, "h": 19.0, "z0": 30.0, "c": Color("1d2033"), "screen": 0, "solid": false},
	{"id": "monitor_b", "x": 2.1, "y": 0.35, "w": 1.2, "d": 0.14, "h": 19.0, "z0": 30.0, "c": Color("1d2033"), "screen": 1, "solid": false},
	{"id": "keys", "x": 1.3, "y": 0.95, "w": 1.3, "d": 0.4, "h": 2.0, "z0": 30.0, "c": Color("232235"), "keys": true, "solid": false},
	{"id": "chair", "x": 1.35, "y": 2.0, "w": 0.95, "d": 0.95, "h": 20.0, "c": Color("2a2733"),
		"why": "Somewhere to sit at the desk; a lived-in detail from the real room."},
	{"id": "dresser", "x": 6.4, "y": 0.2, "w": 2.3, "d": 1.05, "h": 36.0, "c": Color("8a6a4e"), "act": "binder", "label": "open your card binder",
		"why": "Where your cards live: you choose which ones you bring."},
	{"id": "lamp", "x": 7.7, "y": 0.35, "w": 0.5, "d": 0.5, "h": 34.0, "z0": 36.0, "c": Color("f3ead2"), "glow": true, "solid": false},
	{"id": "closet", "x": 0.02, "y": 1.7, "w": 0.4, "d": 2.5, "h": 84.0, "c": Color("a99b8c"), "act": "shop", "label": "visit the shop",
		"why": "Where you spend what a run brought back, to come back stronger: a stocked closet."},
	{"id": "headboard", "x": 0.02, "y": 4.9, "w": 0.4, "d": 2.8, "h": 50.0, "c": Color("26232f"), "solid": false},
	{"id": "bed", "x": 0.4, "y": 4.9, "w": 4.1, "d": 2.8, "h": 20.0, "c": Color("2b2a3a"),
		"why": "It is a bedroom: the bed (and the cat on it) makes it feel lived in."},
	{"id": "blanket", "x": 1.3, "y": 4.95, "w": 3.2, "d": 2.7, "h": 5.0, "z0": 20.0, "c": Color("c07a42"), "solid": false},
	{"id": "pillow", "x": 0.5, "y": 5.1, "w": 0.75, "d": 1.0, "h": 6.0, "z0": 20.0, "c": Color("ece6ee"), "solid": false},
	{"id": "pillow2", "x": 0.5, "y": 6.3, "w": 0.75, "d": 1.0, "h": 6.0, "z0": 20.0, "c": Color("c33a45"), "solid": false},
]

func proj(x: float, y: float, z: float = 0.0) -> Vector2:
	return Vector2(OX + (x - y) * TW * 0.5, OY + (x + y) * TH * 0.5 - z)

# a point on a wall: wall "L" is the plane x = 0 (u is y), wall "R" is the plane y = 0 (u is x); z is height
func wp(wall: String, u: float, z: float) -> Vector2:
	return proj(0.0, u, z) if wall == "L" else proj(u, 0.0, z)

func wall_rect(c: CanvasItem, wall: String, u0: float, u1: float, z0: float, z1: float, col: Color) -> void:
	c.draw_colored_polygon(PackedVector2Array([wp(wall, u0, z0), wp(wall, u1, z0), wp(wall, u1, z1), wp(wall, u0, z1)]), col)

func wall_poly(c: CanvasItem, wall: String, pts: Array, col: Color) -> void:
	var out := PackedVector2Array()
	for p in pts:
		out.append(wp(wall, float(p.x), float(p.y)))
	c.draw_colored_polygon(out, col)

func wall_line(c: CanvasItem, wall: String, a: Vector2, b: Vector2, col: Color, w: float = 1.0) -> void:
	c.draw_line(wp(wall, a.x, a.y), wp(wall, b.x, b.y), col, w)

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
	var edge := Color(0, 0, 0, 0.3)
	c.draw_polyline(PackedVector2Array([proj(x, y + d, z1), proj(x + w, y + d, z1), proj(x + w, y, z1)]), edge, 1.0)
	c.draw_line(proj(x + w, y + d, z0), proj(x + w, y + d, z1), edge, 1.0)

func draw_room_shell(c: CanvasItem, t: float) -> void:
	# floor: soft carpet in two close tones
	for i in int(ROOM_W):
		for j in int(ROOM_D):
			var col := Color("52465f") if (i + j) % 2 == 0 else Color("4d4159")
			_quad(c, [proj(i, j), proj(i + 1, j), proj(i + 1, j + 1), proj(i, j + 1)], col)
	# the walls, warm and a little lavender in the dusk light
	_quad(c, [proj(0, 0, 0), proj(0, ROOM_D, 0), proj(0, ROOM_D, WALL_H), proj(0, 0, WALL_H)], Color("7a6a8a"))      # the wall at x = 0
	_quad(c, [proj(0, 0, 0), proj(ROOM_W, 0, 0), proj(ROOM_W, 0, WALL_H), proj(0, 0, WALL_H)], Color("655776"))      # the wall at y = 0
	_quad(c, [proj(0, 0, 0), proj(0, ROOM_D, 0), proj(0, ROOM_D, 7), proj(0, 0, 7)], Color("a89c8c"))
	_quad(c, [proj(0, 0, 0), proj(ROOM_W, 0, 0), proj(ROOM_W, 0, 7), proj(0, 0, 7)], Color("8f8478"))
	c.draw_line(proj(0, 0, 0), proj(0, 0, WALL_H), Color(0, 0, 0, 0.3), 2.0)
	_draw_right_wall(c, t)
	_draw_left_wall(c)
	# a round rug in front of the bed
	var pts := PackedVector2Array()
	for k in 28:
		var a := TAU * float(k) / 28.0
		pts.append(proj(5.6 + cos(a) * 1.7, 4.9 + sin(a) * 1.5))
	c.draw_colored_polygon(pts, Color("5a4470"))
	var pts2 := PackedVector2Array()
	for k in 28:
		var a := TAU * float(k) / 28.0
		pts2.append(proj(5.6 + cos(a) * 1.15, 4.9 + sin(a) * 1.0))
	c.draw_colored_polygon(pts2, Color("73588c"))

func _draw_right_wall(c: CanvasItem, t: float) -> void:
	# the big corner poster: blue sky, a pink sun and a palm (a stand-in in the same colours, drawn fresh)
	wall_rect(c, "R", 0.15, 3.8, 22.0, 98.0, Color("3d7fc4"))
	wall_rect(c, "R", 0.15, 3.8, 22.0, 52.0, Color("6aa7d8"))
	var sun: Array = []
	for k in 26:
		var a := TAU * float(k) / 26.0
		sun.append(Vector2(2.75 + cos(a) * 0.62, 66.0 + sin(a) * 19.0))
	wall_poly(c, "R", sun, Color("f4a9a0"))
	wall_poly(c, "R", [Vector2(1.1, 22), Vector2(1.22, 22), Vector2(1.34, 62), Vector2(1.26, 78), Vector2(1.18, 62)], Color("5e3a7a"))      # trunk
	for fr in [[Vector2(1.25, 80), Vector2(0.4, 70), Vector2(0.55, 64)], [Vector2(1.25, 80), Vector2(0.55, 90), Vector2(0.4, 82)], [Vector2(1.25, 80), Vector2(1.0, 96), Vector2(1.5, 93)],
			[Vector2(1.25, 80), Vector2(2.1, 90), Vector2(2.0, 82)], [Vector2(1.25, 80), Vector2(2.15, 72), Vector2(1.95, 66)]]:
		wall_poly(c, "R", fr, Color("8a3f94"))
	# the window: dusk blue light through blinds, with a plaid blanket hung over the lower half
	wall_rect(c, "R", 4.3, 6.5, 42.0, 94.0, Color("2e3a52"))
	wall_rect(c, "R", 4.4, 6.4, 46.0, 92.0, Color("5fc8ff").lerp(Color.WHITE, 0.15 + 0.05 * sin(t * 1.4)))
	for k in 9:
		var zz := 48.0 + float(k) * 5.0
		wall_line(c, "R", Vector2(4.4, zz), Vector2(6.4, zz), Color(1, 1, 1, 0.55), 1.0)       # blinds
	wall_rect(c, "R", 4.45, 6.35, 20.0, 66.0, Color("b8323a"))                                  # the plaid blanket
	for k in 8:
		var uu := 4.45 + float(k) * 0.24
		wall_line(c, "R", Vector2(uu, 20.0), Vector2(uu, 66.0), Color("1f6b45") if k % 2 == 0 else Color("f1ead0"), 5.0)
	for k in 7:
		var zz2 := 22.0 + float(k) * 7.0
		wall_line(c, "R", Vector2(4.45, zz2), Vector2(6.35, zz2), Color(0.12, 0.42, 0.27, 0.8), 3.0)
	# two small framed prints (colour stand-ins)
	wall_rect(c, "R", 7.1, 7.8, 54.0, 82.0, Color("efe4c8"))
	wall_rect(c, "R", 7.2, 7.7, 60.0, 76.0, Color("3a8f6a"))
	wall_rect(c, "R", 8.0, 8.65, 48.0, 66.0, Color("8c2f3a"))

func _draw_left_wall(c: CanvasItem) -> void:
	# the green tapestry over the bed: a border and nested diamonds
	wall_rect(c, "L", 4.7, 7.9, 34.0, 94.0, Color("3f6a45"))
	wall_rect(c, "L", 4.85, 7.75, 38.0, 90.0, Color("56885a"))
	wall_poly(c, "L", [Vector2(6.3, 42), Vector2(7.2, 64), Vector2(6.3, 86), Vector2(5.4, 64)], Color("2f5236"))
	wall_poly(c, "L", [Vector2(6.3, 50), Vector2(6.85, 64), Vector2(6.3, 78), Vector2(5.75, 64)], Color("7fb27d"))
	wall_poly(c, "L", [Vector2(6.3, 58), Vector2(6.55, 64), Vector2(6.3, 70), Vector2(6.05, 64)], Color("e9c46a"))
	# a tall orange banner and a couple of small stand-in posters
	wall_rect(c, "L", 8.2, 8.75, 30.0, 96.0, Color("c9602e"))
	wall_rect(c, "L", 8.3, 8.65, 40.0, 60.0, Color("f0b27a"))
	wall_rect(c, "L", 0.6, 1.4, 56.0, 90.0, Color("2d2a52"))
	wall_rect(c, "L", 0.7, 1.3, 62.0, 84.0, Color("d6455a"))

func draw_cat(c: CanvasItem, t: float) -> void:
	var at := proj(2.9, 6.3, 29.0)
	var breathe := 1.0 + 0.04 * sin(t * 1.6)
	c.draw_set_transform(at, 0.0, Vector2(1.0, 0.55 * breathe))
	c.draw_circle(Vector2.ZERO, 11.0, Color("d9843a"))                       # the curled body
	c.draw_circle(Vector2(-7, 2), 7.0, Color("e59a4b"))
	c.draw_set_transform_matrix(Transform2D.IDENTITY)
	c.draw_colored_polygon(PackedVector2Array([at + Vector2(-13, -6), at + Vector2(-9, -12), at + Vector2(-6, -5)]), Color("d9843a"))      # ears
	c.draw_colored_polygon(PackedVector2Array([at + Vector2(-8, -8), at + Vector2(-4, -13), at + Vector2(-2, -5)]), Color("d9843a"))
	c.draw_arc(at + Vector2(8, 1), 7.0, -0.6, 2.4, 10, Color("c7742f"), 3.0)                                                              # the tail

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
	# furniture and the hero, back to front
	var items: Array = []
	for fu in furniture:
		items.append({"depth": float(fu["x"]) + float(fu["w"]) + float(fu["y"]) + float(fu["d"]) + (0.5 if fu.has("z0") else 0.0), "f": fu})
	items.append({"depth": pos.x + pos.y, "hero": true})
	items.sort_custom(func(a, b): return float(a["depth"]) < float(b["depth"]))
	for it in items:
		if it.has("hero"):
			draw_hero(c, tex, meta)
			continue
		var fu: Dictionary = it["f"]
		draw_box(c, float(fu["x"]), float(fu["y"]), float(fu["w"]), float(fu["d"]), float(fu["h"]), float(fu.get("z0", 0.0)), fu["c"], bool(fu.get("glow", false)))
		if fu.has("screen"):       # a monitor: a glowing screen on its lower-left face
			var a := proj(float(fu["x"]) + 0.07, float(fu["y"]) + float(fu["d"]), float(fu["z0"]) + 2.0)
			var b := proj(float(fu["x"]) + float(fu["w"]) - 0.07, float(fu["y"]) + float(fu["d"]), float(fu["z0"]) + 2.0)
			var pulse := 0.75 + 0.25 * sin(t * 2.0 + float(fu["screen"]))
			var tint := Color(0.3, 0.85, 1.0, pulse) if int(fu["screen"]) == 0 else Color(0.6, 0.55, 1.0, pulse)
			c.draw_colored_polygon(PackedVector2Array([a, b, b + Vector2(0, -15), a + Vector2(0, -15)]), tint)
			for k in 4:
				c.draw_line(a + Vector2(3, -3.0 - 3.0 * k), b + Vector2(-3, -3.0 - 3.0 * k), Color(1, 1, 1, 0.35), 1.0)
		if bool(fu.get("keys", false)):     # the keyboard's rainbow glow
			for k in 8:
				c.draw_line(proj(float(fu["x"]) + 0.1 + k * 0.15, float(fu["y"]) + 0.12, 33.0), proj(float(fu["x"]) + 0.1 + k * 0.15, float(fu["y"]) + 0.3, 33.0), Color.from_hsv(fmod(float(k) * 0.12 + t * 0.2, 1.0), 0.8, 1.0), 3.0)
		if fu["id"] == "closet":            # two doors on its face
			var yc: float = float(fu["y"]) + float(fu["d"]) * 0.5
			var xf: float = float(fu["x"]) + float(fu["w"])
			c.draw_line(proj(xf, yc, 4.0), proj(xf, yc, 80.0), Color(0, 0, 0, 0.45), 2.0)
			c.draw_colored_polygon(PackedVector2Array([proj(xf, yc - 0.12, 38.0), proj(xf, yc - 0.05, 38.0), proj(xf, yc - 0.05, 46.0), proj(xf, yc - 0.12, 46.0)]), Color("e0d2b0"))
		if fu["id"] == "blanket":
			draw_cat(c, t)
	# the use-marker over whatever you are near
	if not tgt.is_empty():
		var top := proj(float(tgt["x"]) + float(tgt["w"]) * 0.5, float(tgt["y"]) + float(tgt["d"]) * 0.5, float(tgt["h"]) + float(tgt.get("z0", 0.0)) + 26.0 + 4.0 * sin(t * 4.0))
		c.draw_colored_polygon(PackedVector2Array([top + Vector2(-9, -8), top + Vector2(9, -8), top + Vector2(0, 4)]), Color("ffd166"))
