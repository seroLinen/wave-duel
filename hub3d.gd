extends RefCounted
# First-person hub: a Wolfenstein-style raycaster. Walls are cast one column at a time;
# portals and the Mash Machine are flat 2D sprites that always face the camera and scale with
# distance. World units: 1 cell = 1 unit, eye height = half a wall.

const W := 960.0
const H := 540.0
const COLS := 240                 # wall columns (each W/COLS px wide)
const FOV_BASE := 1.15            # horizontal field of view, radians (~66 degrees); widens near a portal
const CAPTURE_R := 3.0            # inside this ring of a portal you are pulled in and lose control
const SPEED := 3.2
const WALL_H := 2.2               # wall height in units; the camera sits at EYE
const EYE := 1.0
const RADIUS := 0.22
const MACHINE := Vector2(12.0, 13.0)
# Pre-rendered props (see tools/sprite_render.py): sheet in art/<name>.png, 8 angles of 64px.
# scale / cy must match the values the model was rendered with.
const PROPS := [
	{"id": -2, "sheet": "mash_machine", "pos": Vector2(12.0, 13.0), "facing": -PI / 2.0, "scale": 32.0, "cy": 0.82, "block": 0.65, "label": "MASH MACHINE"},
	{"id": -4, "sheet": "terminal", "pos": Vector2(16.2, 12.3), "facing": -PI / 2.0 - 0.35, "scale": 32.0, "cy": 0.82, "block": 0.6, "label": "CHIP FOLDER"},
	{"id": -3, "sheet": "guide_bot", "pos": Vector2(8.6, 11.6), "facing": -PI / 2.0 + 0.5, "scale": 36.0, "cy": 0.75, "block": 0.45, "label": ""},
]
const MAP := [
	"########################",
	"#......................#",
	"#......................#",
	"#......................#",
	"#......................#",
	"#......................#",
	"#......................#",
	"#......................#",
	"#......................#",
	"#......................#",
	"#......................#",
	"#......................#",
	"#...PP............PP...#",
	"#...PP............PP...#",
	"#......................#",
	"########################",
]

var pos := Vector2(12.0, 10.0)
var ang := -PI / 2.0
var zbuf := PackedFloat32Array()
var proj := 0.0
var fov := FOV_BASE
var warp := 0.0                   # 0..1, how strongly the nearest portal is bending the view

func _init() -> void:
	zbuf.resize(COLS)
	proj = (W * 0.5) / tan(fov * 0.5)

static var count := 15   # how many portals the hub currently shows (set by the hub)

# Portals sit in rows of five, each row centred in the room.
static func portal_pos(i: int) -> Vector2:
	var row := i / 5
	var in_row := mini(5, count - row * 5)
	return Vector2(12.0 + ((i % 5) - (in_row - 1) * 0.5) * 4.25, 2.6 + row * 3.2)

func set_warp(w: float) -> void:
	warp = w
	fov = lerpf(FOV_BASE, 1.85, w * w)
	proj = (W * 0.5) / tan(fov * 0.5)

# Where a world point lands on screen horizontally (0..1); (0.5, 0.5) when it is behind you.
func screen_uv(p: Vector2) -> Vector2:
	var dir := Vector2(cos(ang), sin(ang))
	var plane := Vector2(-dir.y, dir.x) * tan(fov * 0.5)
	var inv := 1.0 / (plane.x * dir.y - dir.x * plane.y)
	var rel := p - pos
	var tx := inv * (dir.y * rel.x - dir.x * rel.y)
	var ty := inv * (-plane.y * rel.x + plane.x * rel.y)
	if ty < 0.2:
		return Vector2(0.5, 0.5)
	return Vector2(clampf(0.5 * (1.0 + tx / ty), -0.5, 1.5), 0.5)

# Being drawn in: the camera slides toward the target and turns to face it. No input involved.
func pull_toward(target: Vector2, dt: float, speed: float) -> void:
	var to := target - pos
	var d := to.length()
	if d > 0.001:
		pos += to / d * minf(d, speed * dt)
		ang = lerp_angle(ang, atan2(to.y, to.x), 1.0 - exp(-7.0 * dt))

func cell(x: int, y: int) -> String:
	if y < 0 or y >= MAP.size() or x < 0 or x >= MAP[0].length():
		return "#"
	return MAP[y][x]

func blocked(p: Vector2) -> bool:
	for pr in PROPS:
		if p.distance_to(pr["pos"]) < float(pr["block"]):
			return true
	for o in [Vector2(-RADIUS, -RADIUS), Vector2(RADIUS, -RADIUS), Vector2(-RADIUS, RADIUS), Vector2(RADIUS, RADIUS)]:
		if cell(int(floor(p.x + o.x)), int(floor(p.y + o.y))) != ".":
			return true
	return false

# wish.x = strafe right, wish.y = forward; turn in radians (already scaled by dt)
func move(wish: Vector2, turn: float, dt: float) -> void:
	ang += turn
	var dir := Vector2(cos(ang), sin(ang))
	var right := Vector2(-sin(ang), cos(ang))
	var step := (dir * wish.y + right * wish.x) * SPEED * dt
	if not blocked(Vector2(pos.x + step.x, pos.y)):
		pos.x += step.x
	if not blocked(Vector2(pos.x, pos.y + step.y)):
		pos.y += step.y

# ---------------- rendering ----------------
func render(ci: CanvasItem, f: Font, carts: Array, t: float, lit: int) -> void:
	var dir := Vector2(cos(ang), sin(ang))
	var plane := Vector2(-dir.y, dir.x) * tan(fov * 0.5)
	var cw := W / COLS
	_backdrop(ci)
	for c in COLS:
		var cam := 2.0 * (c + 0.5) / COLS - 1.0
		var rd := dir + plane * cam
		var mx := int(floor(pos.x))
		var my := int(floor(pos.y))
		var ddx := INF if rd.x == 0.0 else absf(1.0 / rd.x)
		var ddy := INF if rd.y == 0.0 else absf(1.0 / rd.y)
		var sx := 1 if rd.x > 0.0 else -1
		var sy := 1 if rd.y > 0.0 else -1
		var sdx := ((mx + 1.0 - pos.x) if rd.x > 0.0 else (pos.x - mx)) * ddx
		var sdy := ((my + 1.0 - pos.y) if rd.y > 0.0 else (pos.y - my)) * ddy
		var side := 0
		for _i in 48:
			if sdx < sdy:
				sdx += ddx
				mx += sx
				side = 0
			else:
				sdy += ddy
				my += sy
				side = 1
			if cell(mx, my) != ".":
				break
		var perp := maxf((sdx - ddx) if side == 0 else (sdy - ddy), 0.05)
		zbuf[c] = perp
		var hit := pos + rd * perp
		var texu := (hit.y - floorf(hit.y)) if side == 0 else (hit.x - floorf(hit.x))
		var line_h := proj * WALL_H / perp
		var top := H * 0.5 - proj * (WALL_H - EYE) / perp + sin(c * 0.22 + t * 7.0) * warp * 16.0
		var base := Color(0.20, 0.23, 0.46) if cell(mx, my) == "#" else Color(0.40, 0.20, 0.46)
		var shade := clampf(1.15 - perp * 0.075, 0.16, 1.0) * (0.78 if side == 1 else 1.0)
		if texu < 0.03 or texu > 0.97:
			shade *= 0.55   # panel seams
		var col := Color(base.r * shade, base.g * shade, base.b * shade).lerp(Color(0.55, 0.25, 0.9), warp * 0.35)
		var x := c * cw
		ci.draw_rect(Rect2(x, top, cw + 1.0, line_h), col)
		var neon := Color(0.3, 0.9, 1.0, 0.55 * shade) if cell(mx, my) == "#" else Color(1.0, 0.4, 0.9, 0.55 * shade)
		ci.draw_rect(Rect2(x, top + line_h * 0.10, cw + 1.0, maxf(2.0, line_h * 0.025)), neon)
		ci.draw_rect(Rect2(x, top + line_h * 0.88, cw + 1.0, maxf(2.0, line_h * 0.025)), neon)
	_sprites(ci, f, carts, t, lit, dir, plane)

func _backdrop(ci: CanvasItem) -> void:
	for i in 12:
		var k := i / 11.0
		var h := H * 0.5 / 12.0
		ci.draw_rect(Rect2(0, i * h, W, h + 1.0), Color("0a0720").lerp(Color("231a4d"), k))
		ci.draw_rect(Rect2(0, H * 0.5 + i * h, W, h + 1.0), Color("0c0a1c").lerp(Color("1f1838"), k))
	_floor_grid(ci)
	_threshold_rings(ci)

# A grid on the floor (one line per cell edge) projected with the same camera as the sprites.
func _floor_grid(ci: CanvasItem) -> void:
	var dir := Vector2(cos(ang), sin(ang))
	var plane := Vector2(-dir.y, dir.x) * tan(fov * 0.5)
	var inv := 1.0 / (plane.x * dir.y - dir.x * plane.y)
	for k in range(1, 24):
		_floor_line(ci, Vector2(k, 1), Vector2(k, 15), dir, plane, inv)
	for k in range(1, 16):
		_floor_line(ci, Vector2(1, k), Vector2(23, k), dir, plane, inv)

# The point of no return: a pulsing ring on the floor around every portal.
func _threshold_rings(ci: CanvasItem) -> void:
	var dir := Vector2(cos(ang), sin(ang))
	var plane := Vector2(-dir.y, dir.x) * tan(fov * 0.5)
	var inv := 1.0 / (plane.x * dir.y - dir.x * plane.y)
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * 3.0)
	for i in count:
		var c := portal_pos(i)
		if pos.distance_to(c) > 14.0:
			continue
		for k in 32:
			if k % 2 == 1:
				continue
			var a0 := TAU * k / 32.0
			var a1 := TAU * (k + 1) / 32.0
			_floor_line(ci, c + Vector2(cos(a0), sin(a0)) * CAPTURE_R, c + Vector2(cos(a1), sin(a1)) * CAPTURE_R, dir, plane, inv, Color(0.85, 0.35, 1.0, 0.35 + 0.45 * pulse), 3.0)

func _floor_line(ci: CanvasItem, a: Vector2, b: Vector2, dir: Vector2, plane: Vector2, inv: float, col: Color = Color(0.45, 0.55, 1.0, 0.16), width: float = 1.0) -> void:
	var ra := a - pos
	var rb := b - pos
	var ta := Vector2(inv * (dir.y * ra.x - dir.x * ra.y), inv * (-plane.y * ra.x + plane.x * ra.y))
	var tb := Vector2(inv * (dir.y * rb.x - dir.x * rb.y), inv * (-plane.y * rb.x + plane.x * rb.y))
	const NEAR := 0.3
	if ta.y < NEAR and tb.y < NEAR:
		return
	if ta.y < NEAR:
		ta = ta.lerp(tb, (NEAR - ta.y) / (tb.y - ta.y))
	elif tb.y < NEAR:
		tb = tb.lerp(ta, (NEAR - tb.y) / (ta.y - tb.y))
	var pa := Vector2(W * 0.5 * (1.0 + ta.x / ta.y), H * 0.5 + proj * EYE / ta.y)
	var pb := Vector2(W * 0.5 * (1.0 + tb.x / tb.y), H * 0.5 + proj * EYE / tb.y)
	ci.draw_line(pa, pb, col, width)

func _sprites(ci: CanvasItem, f: Font, carts: Array, t: float, lit: int, dir: Vector2, plane: Vector2) -> void:
	var list: Array = []
	for i in carts.size():
		list.append({"kind": "portal", "i": i, "pos": portal_pos(i)})
	for pr in PROPS:
		list.append({"kind": "prop", "i": pr["id"], "pos": pr["pos"], "prop": pr})
	var inv := 1.0 / (plane.x * dir.y - dir.x * plane.y)
	for s in list:
		var rel: Vector2 = s["pos"] - pos
		s["tx"] = inv * (dir.y * rel.x - dir.x * rel.y)
		s["ty"] = inv * (-plane.y * rel.x + plane.x * rel.y)
	list.sort_custom(func(a, b): return a["ty"] > b["ty"])
	for s in list:
		if float(s["ty"]) < 0.25:
			continue
		if s["kind"] == "portal":
			_portal(ci, f, carts[s["i"]], s, t, lit == s["i"])
		else:
			_prop(ci, f, s, t, lit == int(s["i"]))

func _fog(c: Color, ty: float) -> Color:
	var k := clampf(1.1 - ty * 0.06, 0.25, 1.0)
	return Color(c.r * k, c.g * k, c.b * k, c.a)

func _portal(ci: CanvasItem, f: Font, cart: Dictionary, s: Dictionary, t: float, lit: bool) -> void:
	var ty: float = s["ty"]
	var cw := W / COLS
	var sx: float = W * 0.5 * (1.0 + float(s["tx"]) / ty)
	var pdist: float = (s["pos"] as Vector2).distance_to(pos)
	var engulf := clampf(1.0 - (pdist - 1.2) / 5.5, 0.0, 1.0)
	var r: float = proj / ty * 0.72 * (1.0 + engulf * engulf * 2.6)   # swells until it fills your view
	var cy: float = H * 0.5 + sin(t * 1.6 + float(s["i"])) * 0.03 * proj / ty
	var cols: Array = cart.get("colors", [cart["color"]])
	var c0 := maxi(0, int((sx - r) / cw))
	var c1 := mini(COLS - 1, int((sx + r) / cw))
	var th := maxf(3.0, r * 0.07)
	var seen_center := false
	for c in range(c0, c1 + 1):
		if ty >= zbuf[c]:
			continue
		var x := c * cw
		var u := ((c + 0.5) * cw - sx) / r
		var ua := ((c * cw) - sx) / r
		var ub := (((c + 1) * cw) - sx) / r
		if absf(u) <= 1.0:
			var hh := r * sqrt(maxf(0.0, 1.0 - u * u))
			ci.draw_rect(Rect2(x, cy - hh, cw + 1.0, hh * 2.0), _fog(Color(Color(cols[0]), 0.34 if lit else 0.18), ty))
			for k in 4:   # swirling energy inside the disc
				var ph := t * (1.4 + k * 0.45) + k * 1.9
				var yy := cy + sin(u * 3.2 + ph) * hh * 0.72
				ci.draw_rect(Rect2(x, yy - 2.0 - k, cw + 1.0, 4.0 + k * 1.6), _fog(Color(Color(cols[k % cols.size()]).lightened(0.35), 0.28 + 0.2 * engulf), ty))
			if absf(u) < 0.28:
				var ih := r * 0.22 * sqrt(maxf(0.0, 1.0 - pow(u / 0.28, 2.0)))
				ci.draw_rect(Rect2(x, cy - ih, cw + 1.0, ih * 2.0), _fog(Color(Color(cols[0]).lightened(0.5), 0.75), ty))
		for k in cols.size():
			var kr := 1.0 - k * 0.2
			var col := _fog(Color(cols[k]), ty)
			var spin := t * (1.0 + k * 0.6) * (1.0 if k % 2 == 0 else -1.0)
			if absf(u) > kr:
				continue
			var ha := r * kr * sqrt(maxf(0.0, 1.0 - pow(clampf(ua / kr, -1.0, 1.0), 2.0)))
			var hb := r * kr * sqrt(maxf(0.0, 1.0 - pow(clampf(ub / kr, -1.0, 1.0), 2.0)))
			var seg := absf(ha - hb) + th
			var top_y := cy - maxf(ha, hb)
			# dashed ring: gaps rotate with time
			var phase := fposmod(atan2(-1.0, u) + spin, TAU)
			if phase < TAU * 0.78:
				ci.draw_rect(Rect2(x, top_y, cw + 1.0, seg), col)
			var phase2 := fposmod(atan2(1.0, u) + spin, TAU)
			if phase2 < TAU * 0.78:
				ci.draw_rect(Rect2(x, cy + minf(ha, hb) - th, cw + 1.0, seg), col)
	var mid := clampi(int(sx / cw), 0, COLS - 1)
	if sx > 0.0 and sx < W and ty < zbuf[mid] and ty < 12.0:
		var fs := clampi(int(proj / ty * 0.16), 9, 22)
		ci.draw_string(f, Vector2(sx - 100, cy - r - 10.0), cart["name"], HORIZONTAL_ALIGNMENT_CENTER, 200, fs, Color(1, 1, 1, 1.0 if lit else 0.8))

var _tex := {}

func _sheet(sheet_name: String) -> Texture2D:
	if _tex.has(sheet_name):
		return _tex[sheet_name]
	var tex: Texture2D = null
	for path in ["user://art/%s.png" % sheet_name, "res://art/%s.png" % sheet_name]:   # user:// wins: drop-in skins
		if FileAccess.file_exists(path):
			var img := Image.load_from_file(path)
			if img:
				tex = ImageTexture.create_from_image(img)
				break
	_tex[sheet_name] = tex
	return tex

# A pre-rendered sprite: pick the frame matching where the camera stands, draw it column by column.
func _prop(ci: CanvasItem, f: Font, s: Dictionary, t: float, lit: bool) -> void:
	var p: Dictionary = s["prop"]
	var tex := _sheet(p["sheet"])
	if tex == null:
		if int(p["id"]) == -2:
			_machine(ci, f, s, t, lit)
		return
	var ty: float = s["ty"]
	var cw := W / COLS
	var sx: float = W * 0.5 * (1.0 + float(s["tx"]) / ty)
	var scale: float = p["scale"]
	var size_px := proj * (64.0 / scale) / ty
	var top_world: float = float(p["cy"]) + 32.0 / scale
	var top_y := H * 0.5 - proj * (top_world - EYE) / ty
	var left := sx - size_px * 0.5
	var v := pos - (p["pos"] as Vector2)
	var rel := wrapf(atan2(v.y, v.x) - float(p["facing"]), -PI, PI)
	var frame := posmod(roundi(rel / (TAU / 8.0)), 8)
	var k := clampf(1.1 - ty * 0.06, 0.3, 1.0) * (1.18 if lit else 1.0)
	var mod := Color(k, k, k, 1.0)
	var c0 := maxi(0, int(left / cw))
	var c1 := mini(COLS - 1, int((left + size_px) / cw))
	for c in range(c0, c1 + 1):
		if ty >= zbuf[c]:
			continue
		var u := ((c + 0.5) * cw - left) / size_px
		if u < 0.0 or u >= 1.0:
			continue
		ci.draw_texture_rect_region(tex, Rect2(c * cw, top_y, cw + 1.0, size_px), Rect2(frame * 64 + int(u * 64.0), 0, 1, 64), mod)
	var mid := clampi(int(sx / cw), 0, COLS - 1)
	if str(p["label"]) != "" and sx > 0.0 and sx < W and ty < zbuf[mid] and ty < 12.0:
		var fs := clampi(int(proj / ty * 0.14), 9, 20)
		ci.draw_string(f, Vector2(sx - 100, top_y + size_px * 0.04), str(p["label"]), HORIZONTAL_ALIGNMENT_CENTER, 200, fs, Color("c77dff"))

func _machine(ci: CanvasItem, f: Font, s: Dictionary, t: float, lit: bool) -> void:
	var ty: float = s["ty"]
	var cw := W / COLS
	var sx: float = W * 0.5 * (1.0 + float(s["tx"]) / ty)
	var half: float = proj / ty * 0.65
	var floor_y: float = H * 0.5 + proj * EYE / ty
	var top: float = floor_y - proj * 0.9 / ty
	var hgt := floor_y - top
	var c0 := maxi(0, int((sx - half) / cw))
	var c1 := mini(COLS - 1, int((sx + half) / cw))
	var body := Color("5b2a86")
	var o1 := cos(t * 2.0) * 0.4
	for c in range(c0, c1 + 1):
		if ty >= zbuf[c]:
			continue
		var x := c * cw
		var u := ((c + 0.5) * cw - sx) / half
		ci.draw_rect(Rect2(x, top, cw + 1.0, hgt), _fog(body.lightened(0.18) if absf(u) > 0.92 else body, ty))
		ci.draw_rect(Rect2(x, top, cw + 1.0, hgt * 0.12), _fog(Color("c77dff"), ty))
		if absf(u) < 0.72:
			ci.draw_rect(Rect2(x, top + hgt * 0.24, cw + 1.0, hgt * 0.40), _fog(Color("1a0b2e"), ty))
		var orb := hgt * 0.10
		for pair in [[o1, Color("4cc9f0")], [-o1, Color("f9c74f")]]:
			var d: float = (u - pair[0]) * half / orb
			if absf(d) < 1.0:
				var hh := orb * sqrt(1.0 - d * d)
				ci.draw_rect(Rect2(x, top + hgt * 0.44 - hh, cw + 1.0, hh * 2.0), _fog(pair[1], ty))
		if lit:
			ci.draw_rect(Rect2(x, top - 3.0, cw + 1.0, 3.0), Color(1, 1, 1, 0.9))
	var mid := clampi(int(sx / cw), 0, COLS - 1)
	if sx > 0.0 and sx < W and ty < zbuf[mid] and ty < 12.0:
		var fs := clampi(int(proj / ty * 0.14), 9, 20)
		ci.draw_string(f, Vector2(sx - 100, top - 8.0), "MASH MACHINE", HORIZONTAL_ALIGNMENT_CENTER, 200, fs, Color("c77dff"))

func minimap(ci: CanvasItem, carts: Array) -> void:
	var cell_px := 5.0
	var origin := Vector2(W - 24.0 * cell_px - 10.0, 100.0)
	ci.draw_rect(Rect2(origin - Vector2(3, 3), Vector2(24 * cell_px + 6, 16 * cell_px + 6)), Color(0, 0, 0, 0.5))
	for y in MAP.size():
		for x in MAP[0].length():
			if MAP[y][x] != ".":
				ci.draw_rect(Rect2(origin + Vector2(x, y) * cell_px, Vector2(cell_px, cell_px)), Color(0.35, 0.4, 0.7, 0.8))
	for i in carts.size():
		ci.draw_circle(origin + portal_pos(i) * cell_px, 2.2, Color(carts[i]["color"]))
	ci.draw_rect(Rect2(origin + MACHINE * cell_px - Vector2(3, 2), Vector2(6, 4)), Color("c77dff"))
	ci.draw_circle(origin + Vector2(8.6, 11.6) * cell_px, 2.0, Color("2ec4b6"))
	var p := origin + pos * cell_px
	ci.draw_line(p, p + Vector2(cos(ang), sin(ang)) * 9.0, Color.WHITE, 1.5)
	ci.draw_circle(p, 2.4, Color.WHITE)
