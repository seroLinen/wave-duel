extends RefCounted
# Gamepad helpers. Godot maps controllers by button POSITION (A = bottom face button).
# On a Nintendo Pro Controller that means: bottom = B, right = A, left = Y, top = X.

const DEAD := 0.3

static func id() -> int:
	var j := Input.get_connected_joypads()
	return j[0] if j.size() > 0 else -1

# Stick drift guard. A pad that just (re)connected can report a stale or off-centre stick (it "slides right"),
# so: ignore the sticks for SETTLE_MS after the pad id changes, then learn the resting offset per axis.
# An axis that sits perfectly still off-centre for HOLD_MS is treated as rest too. Offsets are only learned below LEARN_MAX,
# so a deliberately held stick is never swallowed.
const SETTLE_MS := 700
const HOLD_MS := 1200
const LEARN_MAX := 0.5
static var _dev := -2
static var _settle_until := 0
static var _off := {}     # axis -> learned rest value
static var _last := {}    # axis -> last raw value
static var _still := {}   # axis -> msec since the value last changed

static func _watch(d: int) -> void:
	var now := Time.get_ticks_msec()
	if d != _dev:
		_dev = d
		_settle_until = now + SETTLE_MS
		_off.clear()
		_last.clear()
		_still.clear()
	if d < 0:
		return
	for a in [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y, JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y]:
		var raw := Input.get_joy_axis(d, a)
		if now < _settle_until:
			_off[a] = raw if absf(raw) < LEARN_MAX else 0.0
			_last[a] = raw
			_still[a] = now
			continue
		if not _last.has(a) or absf(raw - float(_last[a])) > 0.004:
			_still[a] = now
		_last[a] = raw
		if absf(raw) < LEARN_MAX and now - int(_still[a]) > HOLD_MS:
			_off[a] = raw

# One stick axis with the learned rest offset removed (0 while the pad is settling).
static func axis(a: int) -> float:
	var d := id()
	if d < 0:
		return 0.0
	_watch(d)
	if Time.get_ticks_msec() < _settle_until:
		return 0.0
	return clampf(Input.get_joy_axis(d, a) - float(_off.get(a, 0.0)), -1.0, 1.0)

# Left stick + D-pad as one vector (length <= 1).
static func dir() -> Vector2:
	var d := id()
	if d < 0:
		return Vector2.ZERO
	var v := Vector2(axis(JOY_AXIS_LEFT_X), axis(JOY_AXIS_LEFT_Y))
	if v.length() < DEAD:
		v = Vector2.ZERO
	v.x += int(Input.is_joy_button_pressed(d, JOY_BUTTON_DPAD_RIGHT)) - int(Input.is_joy_button_pressed(d, JOY_BUTTON_DPAD_LEFT))
	v.y += int(Input.is_joy_button_pressed(d, JOY_BUTTON_DPAD_DOWN)) - int(Input.is_joy_button_pressed(d, JOY_BUTTON_DPAD_UP))
	return v.limit_length(1.0)

# B, X, R / ZR (Y opens Custom in Wave Duel). (A is jump in platformer games.)
static func shoot() -> bool:
	var d := id()
	if d < 0:
		return false
	return Input.is_joy_button_pressed(d, JOY_BUTTON_X) or Input.is_joy_button_pressed(d, JOY_BUTTON_B) \
		or Input.is_joy_button_pressed(d, JOY_BUTTON_RIGHT_SHOULDER) or Input.get_joy_axis(d, JOY_AXIS_TRIGGER_RIGHT) > 0.5

# True while any stick is pushed (used to tell "playing with the pad" from "using the mouse").
static func active() -> bool:
	var d := id()
	if d < 0:
		return false
	for a in [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y, JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y]:
		if absf(axis(a)) > 0.35:
			return true
	return false
