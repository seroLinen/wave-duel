extends RefCounted
# Gamepad helpers. Godot maps controllers by button POSITION (A = bottom face button).
# On a Nintendo Pro Controller that means: bottom = B, right = A, left = Y, top = X.

const DEAD := 0.3

static func id() -> int:
	var j := Input.get_connected_joypads()
	return j[0] if j.size() > 0 else -1

# Left stick + D-pad as one vector (length <= 1).
static func dir() -> Vector2:
	var d := id()
	if d < 0:
		return Vector2.ZERO
	var v := Vector2(Input.get_joy_axis(d, JOY_AXIS_LEFT_X), Input.get_joy_axis(d, JOY_AXIS_LEFT_Y))
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
		if absf(Input.get_joy_axis(d, a)) > 0.35:
			return true
	return false
