extends "res://game_base.gd"
# Wave Duel: real-time card duel seen from behind your fighter.
#  - move freely left/right, hold fire to charge the buster, release to shoot
#  - the CUSTOM gauge fills; open it (Q / L) to pick up to 3 cards from a hand of 5
#  - cards fire in the order you set them (Enter / A). Solo, picking slows time to a crawl;
#    it only fully freezes while BOTH sides are in the card screen.
# Fighters are plain dictionaries driven by input (me) or AI (foe), so a second human could
# take over the foe's controls later without touching the battle rules.

const Cards = preload("res://cards.gd")
const Pad = preload("res://pad.gd")
const Binds = preload("res://binds.gd")

# --- camera: perspective projection of the arena (x sideways, z away from the camera)
const F := 700.0
const HORIZON := 62.0
const CAM_Z := 3.78
const CAM_H := 2.14
const ME_SCALE := 0.68        # on-screen size of your fighter (enemies have their own "scale")
const FIELD_X := 1.8
const FIELD_Z := 6.0
const SPR_H := 1.2            # world height of a 64px sprite frame
const FEET := 0.922           # where the sprite's feet sit inside its frame (see sprite_render.py)
const BASE_HP := 100
const MELEE := ["slash", "widesword"]   # sword cards: need lock-on, dash in and cut
const LOCK_SPEED := 0.55                 # you move slower while locked on
const PVP := false               # solo vs AI: time stops while you pick. In PvP it only stops when BOTH are picking.
const CUSTOM_TIME := 9.0         # seconds for a full Custom gauge - same for both sides, whatever the HP
const BUSTER_CHARGE_TIME := 1.8  # the buster charges itself; fire releases whatever is stored
const BUSTER_MIN := 0.25
const BUSTER_MIN_DMG := 2.0
const BUSTER_MAX_DMG := 12.0
const GUARD_TIME := 1.3          # holographic shield (Y): up this long
const GUARD_COOLDOWN := 3.0      # ...and ready again this long after it DROPS (not after it goes up)
const PERFECT_T := 0.16          # a shot that lands this soon after raising it is reflected
const PIERCE := ["wave", "tide"]  # the shield cannot stop these outright (nor sword strikes: body contact) but takes the edge off
const PIERCE_KEEP := 0.5         # share of a piercing hit that gets through a raised shield
const COUNTER_BONUS := 10.0
const CLEARED_TIME := 3.4        # breathing room between opponents

const ENEMIES := [
	{"name": "Hardhat Drone", "sheet": "duel_buzzcap", "scale": 1.5, "hp": 70, "speed": 1.2, "react": 0.45, "fire": 1.1, "kind": "drone"},
	{"name": "Wall Brute", "sheet": "duel_brute", "scale": 1.3, "hp": 130, "speed": 0.8, "react": 0.6, "fire": 2.3, "kind": "brute"},
	{"name": "Rival Navi", "sheet": "duel_rival", "scale": 1.05, "hp": 150, "speed": 1.6, "react": 0.28, "fire": 0.95, "kind": "rival"},
]

var bonus_hp := 0
var t := 0.0
var round_i := 0
var phase := "intro"          # intro | fight | cleared
var phase_t := 0.0
var intro_total := 1.7   # length of this round's opening cinematic
var next_called := false
var music_ref: Node
signal sting(name: String)
var me := {}
var foe := {}
var shots: Array = []
var popups: Array = []        # {x, z, text, color, t}
var draw_pile: Array = []
var used_pile: Array = []
var hand: Array = []
var queue: Array = []
var foe_queue: Array = []
var selecting := false
var picked: Array = []
var cur := 0
var gauge := 0.0
var foe_gauge := 0.0
var foe_selecting := 0.0
var foe_use_t := 0.0
var charge := 0.0
var fire_prev := false
var locked := false
var guard_t := 0.0
var guard_age := 0.0
var guard_cd := 0.0
var guard_hit_t := 0.0
var spawning_card := false      # shots created while a CARD is being played carry card = true
var bonus_play := false
var pending_counter := false
var me_vx := 0.0
var foe_vx := 0.0
var prev_me_x := 0.0
var prev_foe_x := 0.0
var result_t := 0.0
var result_won := false
var result_pending := false
var result_t_total := 2.8
var dead_t := 0.0      # how long you have been down (defeat animation)
var shoot_t := 0.0
var cast_t := 0.0
var hurt_t := 0.0
var foe_hurt_t := 0.0
var foe_atk_t := 0.0
var me_pose := "idle"
var me_pose_t0 := 0.0
var foe_pose := "idle"
var foe_pose_t0 := 0.0
var _meta := {}
var lock_prev := 0.0
var swing_pose := 0.0
var demo_strike := false
var struck := false
var buster_cd := 0.0
var hits := 0
var near_misses := 0
var nav_prev := 0.0
var banner := ""
var banner_t := 0.0
var _tex := {}
var bot_t := 0.0
var bot_dir := 0.0
var bot_hold := false
var demo_custom := false

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func apply_boon(id: String) -> void:
	super.apply_boon(id)
	if id == "skin":
		bonus_hp += 30

func setup(r: Dictionary, start_boons: Array = []) -> void:
	super.setup(r, start_boons)
	goal = 3.0
	if folder.size() < 5:
		folder = Cards.starter_folder()
	draw_pile = folder.duplicate()
	draw_pile.shuffle()
	me = make_fighter(BASE_HP + bonus_hp, 0.0)
	demo_custom = OS.get_cmdline_user_args().has("--duelcustom")
	demo_strike = OS.get_cmdline_user_args().has("--duelstrike")
	if OS.get_cmdline_user_args().has("--duelqueue"):
		queue = ["widesword", "tide", "triple"]
		gauge = 1.0
	if demo_custom:
		gauge = 1.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--round="):
			round_i = clampi(int(a.substr(8)), 0, ENEMIES.size() - 1)
	start_round()

func make_fighter(hp: int, z: float) -> Dictionary:
	return {"side": 0, "strike": {}, "mw": 0.0, "mw_id": "", "mw_aim": 0.0, "x": 0.0, "z": z, "hp": float(hp), "max": float(hp), "shield": 0.0, "shield_t": 0.0, "haste_t": 0.0,
		"frozen_t": 0.0, "flash": 0.0, "tx": 0.0, "react_t": 0.6, "fire_t": 1.6, "tele": 0.0, "gat": 0, "gat_t": 0.0, "gat_card": false, "spread": false}

func set_music(m: Node) -> void:
	music_ref = m

# Only the last opponent (the Navi) gets the full cinematic; the others just get a short round banner.
func is_navi_round() -> bool:
	return round_i >= ENEMIES.size() - 1

func intro_length(i: int) -> float:
	return 5.2 if i >= ENEMIES.size() - 1 else 1.7

func start_round() -> void:
	var e: Dictionary = ENEMIES[mini(round_i, ENEMIES.size() - 1)]
	foe = make_fighter(int(e["hp"]), FIELD_Z)
	foe["side"] = 1
	locked = false
	charge = 0.0
	foe_gauge = 0.0
	foe_queue.clear()
	foe_selecting = 0.0
	shots.clear()
	phase = "intro"
	intro_total = intro_length(round_i)
	phase_t = intro_total
	next_called = false
	banner_t = 0.0
	if not is_navi_round():
		banner = "ROUND %d   %s" % [round_i + 1, e["name"]]
		banner_t = intro_total

# ------------------------------------------------------------------ input
func _input(e: InputEvent) -> void:
	if auto:
		return
	if Binds.matches("shield", e):
		raise_guard()
		return
	if Binds.matches("lockon", e):
		toggle_lock()
		return
	if selecting and e is InputEventJoypadButton and e.pressed and (e.button_index == JOY_BUTTON_DPAD_LEFT or e.button_index == JOY_BUTTON_DPAD_RIGHT):
		card_step(1 if e.button_index == JOY_BUTTON_DPAD_RIGHT else -1)
		return
	var k := -1
	if Binds.matches("custom", e):
		k = KEY_Q
	elif Binds.matches("card", e):
		k = KEY_ENTER
	elif e is InputEventKey and e.pressed and not e.echo:
		k = e.keycode            # A / D / arrows move the card cursor
	if k != -1:
		handle_key(k)

# One card-cursor step per push, even if a pad reports a D-pad press as a button and a stick axis at once.
var step_at := -1.0
func card_step(d: int) -> void:
	if t - step_at < 0.14:
		return
	step_at = t
	cur = clampi(cur + d, 0, hand.size() - 1)

func handle_key(k: int) -> void:
	if phase == "intro" and is_navi_round() and k == KEY_ENTER and intro_total - phase_t > 1.6:
		phase_t = minf(phase_t, 0.4)       # confirm skips the rest of an opening you have already seen
		return
	if phase == "result" and k == KEY_ENTER and result_t < 7.0 and result_t_total - result_t > 2.0:
		result_t = 0.0       # confirm leaves the result screen once you have read it
		return
	if phase != "fight":
		return
	if selecting:
		match k:
			KEY_A, KEY_LEFT: cur = maxi(0, cur - 1)
			KEY_D, KEY_RIGHT: cur = mini(hand.size() - 1, cur + 1)
			KEY_ENTER, KEY_E, KEY_SPACE, KEY_K: toggle_pick()
			KEY_Q: confirm_custom()
		return
	if k == KEY_Q and gauge >= 1.0:
		open_custom()
	elif (k == KEY_ENTER or k == KEY_K) and not queue.is_empty():
		play_next_card()

func read_move(dt: float) -> float:
	if auto:
		bot_t -= dt
		if bot_t <= 0.0:
			bot_t = randf_range(0.3, 0.9)
			bot_dir = float(randi_range(-1, 1))
			bot_hold = randf() < 0.7
		return bot_dir
	var x := float(int(Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT)) - int(Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT)))
	return clampf(x + Pad.dir().x, -1.0, 1.0)

func read_fire() -> bool:
	if auto:
		return bot_hold
	return Binds.held("fire") or Pad.shoot()

# ------------------------------------------------------------------ custom screen
func open_custom() -> void:
	if draw_pile.size() < 5:
		draw_pile.append_array(used_pile)
		used_pile.clear()
		draw_pile.shuffle()
	if draw_pile.is_empty():
		return
	hand.clear()
	for i in mini(5, draw_pile.size()):
		hand.append(draw_pile.pop_front())
	picked.clear()
	cur = 0
	selecting = true

func toggle_pick() -> void:
	if picked.has(cur):
		picked.erase(cur)
	elif picked.size() < 3:
		picked.append(cur)

func confirm_custom() -> void:
	var chosen: Array = []
	for i in picked:
		chosen.append(hand[i])
	for i in hand.size():
		if not picked.has(i):
			draw_pile.append(hand[i])     # unused cards go to the bottom
	hand.clear()
	selecting = false
	if chosen.is_empty():
		return                            # cancelled: keep the full gauge
	queue = chosen
	gauge = 0.0

func play_next_card() -> void:
	var id: String = queue[0]
	if MELEE.has(id):
		if not (me["strike"] as Dictionary).is_empty():
			return
		if not locked:
			popup(float(me["x"]), float(me["z"]), "LOCK ON FIRST  (Down)", Color("ff9f1c"))
			return
	queue.pop_front()
	used_pile.append(id)
	use_card(0, id)
	if not MELEE.has(id) and id != "tide":
		cast_t = 0.45
	gain_ess("static", 1)
	popup(me["x"], 0.0, Cards.CARDS[id]["name"], Color(Cards.CARDS[id]["color"]))

# ------------------------------------------------------------------ battle
func tick(dt: float) -> void:
	t += dt
	if result_pending:
		result_t -= dt
		if not result_won:
			dead_t += dt
		if result_t <= 0.0:
			result_pending = false
			finish_now(result_won)
	banner_t = maxf(0.0, banner_t - dt)
	swing_pose = maxf(0.0, swing_pose - dt)
	shoot_t = maxf(0.0, shoot_t - dt)
	cast_t = maxf(0.0, cast_t - dt)
	hurt_t = maxf(0.0, hurt_t - dt)
	foe_hurt_t = maxf(0.0, foe_hurt_t - dt)
	foe_atk_t = maxf(0.0, foe_atk_t - dt)
	for p in popups:
		p["t"] = float(p["t"]) + dt
	popups = popups.filter(func(p): return float(p["t"]) < 1.1)
	# the foe's card screen runs in real time; the world only freezes while we are in ours too
	if foe_selecting > 0.0:
		foe_selecting -= dt
		if foe_selecting <= 0.0:
			foe_ready_cards()
	var world_scale := 1.0
	if selecting:
		world_scale = 0.0 if (not PVP or foe_selecting > 0.0) else 0.2
	if demo_custom and not selecting and phase == "fight" and t > 1.2 and gauge >= 1.0:
		open_custom()
	if auto:
		bot_cards()
	if locked and (me["strike"] as Dictionary).is_empty() and (queue.is_empty() or not MELEE.has(str(queue[0]))):
		locked = false
	if OS.get_cmdline_user_args().has("--duellose") and phase == "fight" and t > 1.9:
		me["hp"] = 0.0
	if OS.get_cmdline_user_args().has("--duelresult") and phase == "fight" and t > 1.9:
		finish(true)
	if phase == "fight" and t > 1.9 and not struck:
		var da := OS.get_cmdline_user_args()
		if da.has("--duelguard"):
			struck = true
			raise_guard()
		elif da.has("--duelflash"):
			struck = true
			foe["tele"] = 3.0
		elif da.has("--duelcounter"):
			struck = true
			foe["tele"] = 0.6
			foe["tx"] = foe["x"]
			spawning_card = true
			spawn(0, float(foe["x"]), 0.5, 12.0, 0.2, 10.0, "buster")
			spawning_card = false
	if OS.get_cmdline_user_args().has("--duellock") and phase == "fight" and t > 1.9 and not struck:
		struck = true
		queue = ["widesword", "tide"]
		toggle_lock()
		play_next_card()
	if demo_strike and phase == "fight" and not struck:
		struck = true
		locked = true
		queue = ["slash"]
		play_next_card()
	if not auto and not selecting and phase == "fight":
		var ny := Pad.dir().y
		if ny > 0.7 and lock_prev <= 0.7:
			toggle_lock()
		lock_prev = ny
	if selecting:
		var nx := Pad.stick().x           # the D-pad moves the cursor from its button events (see _input)
		if absf(nx) > 0.6 and absf(nav_prev) <= 0.6:
			card_step(int(signf(nx)))
		nav_prev = nx
	var wdt := dt * world_scale
	if phase == "intro":
		phase_t -= wdt
		if phase_t <= 0.0:
			phase = "fight"
			if is_navi_round():
				banner = "FIGHT!"
				banner_t = 0.9
	elif phase == "cleared":
		phase_t -= wdt
		if phase_t < 1.3 and not next_called and round_i + 1 < ENEMIES.size():
			next_called = true
			banner = "NEXT   %s" % ENEMIES[round_i + 1]["name"]
			banner_t = 1.3
		if phase_t <= 0.0:
			round_i += 1
			me["hp"] = minf(float(me["max"]), float(me["hp"]) + 30.0)
			start_round()
	if phase == "fight" and wdt > 0.0:
		fight_step(wdt)
	for f in [me, foe]:
		f["flash"] = maxf(0.0, float(f["flash"]) - dt)
	var vdt := maxf(dt, 0.0001)
	me_vx = lerpf(me_vx, (float(me["x"]) - prev_me_x) / vdt, 0.25)
	foe_vx = lerpf(foe_vx, (float(foe["x"]) - prev_foe_x) / vdt, 0.25)
	prev_me_x = float(me["x"])
	prev_foe_x = float(foe["x"])
	update_poses()

# Which animation each fighter should be playing, and when it started.
func update_poses() -> void:
	var ms: Dictionary = me["strike"]
	var want := "idle"
	if not ms.is_empty():
		want = "slash" if int(ms["ph"]) == 1 else "dash"
	elif guard_t > 0.0:
		want = "guard"
	elif swing_pose > 0.0:
		want = "slash"
	elif hurt_t > 0.0:
		want = "hurt"
	elif cast_t > 0.0:
		want = "cast"
	elif shoot_t > 0.0:
		want = "shoot"
	elif absf(me_vx) > 0.6:
		want = "move"
	if want != me_pose:
		me_pose = want
		me_pose_t0 = t
	var e: Dictionary = ENEMIES[mini(round_i, ENEMIES.size() - 1)]
	var rival := str(e["kind"]) == "rival"
	var fs: Dictionary = foe["strike"]
	var fwant := "idle"
	if foe_hurt_t > 0.0:
		fwant = "hurt"
	elif not fs.is_empty():
		fwant = "slash" if int(fs["ph"]) == 1 else "dash"
	elif float(foe["mw"]) > 0.0:
		fwant = "slash"
		foe_pose_t0 = t                    # hold the wind-up on its first frame
	elif float(foe["tele"]) > 0.0 or foe_atk_t > 0.0:
		fwant = ("shoot" if rival else "attack")
	elif rival and absf(foe_vx) > 0.6:
		fwant = "move"
	if fwant != foe_pose:
		foe_pose = fwant
		foe_pose_t0 = t

# Lock-on only exists for sword cards: it needs a sword as the NEXT card, and it lets go when that changes.
func toggle_lock() -> void:
	if phase != "fight" or selecting:
		return
	if not locked and (queue.is_empty() or not MELEE.has(str(queue[0]))):
		return   # silent: the status line already says lock-on is for sword cards
	locked = not locked   # the reticle and the status line already say "locked on": no popup for it
	if not locked:
		popup(float(me["x"]), float(me["z"]), "lock released", Color.WHITE)

# The run ends on a result screen first, so it is clear whether you won or were deleted.
func finish(won: bool) -> void:
	if result_pending or done:
		return
	result_pending = true
	result_won = won
	result_t = 2.8
	result_t_total = 2.8
	if won:
		sting.emit("victory")
		if music_ref != null:
			result_t = clampf(float(music_ref.sting_length("victory")) + 0.6, 2.8, 9.0)
	result_t_total = result_t
	phase = "result"
	banner = "ALL OPPONENTS DELETED" if won else "YOU WERE DELETED"
	banner_t = result_t
	shots.clear()
	locked = false

func finish_now(won: bool) -> void:
	if won:
		for k in recipe.get("earn_keys", []):
			gain_ess(str(k), 2)   # clear bonus
	done = true
	finished.emit(won, score)

# Lost: the fighter takes the hit, tips over, flickers and breaks up into the floor.
func draw_defeated() -> void:
	var mz := float(me["z"])
	var fall := clampf(dead_t * 1.5, 0.0, 1.0)
	fall = fall * fall * (3.0 - 2.0 * fall)
	var a := clampf(1.0 - (dead_t - 1.0) / 1.5, 0.0, 1.0)
	if dead_t > 0.5 and int(dead_t * 30.0) % 3 == 0:
		a *= 0.35
	draw_shadow(float(me["x"]), mz, 0.34 * (1.0 - fall * 0.4))
	draw_anim("duel_hero", "hurt", 0.3, float(me["x"]), mz, 0.0, Color(1.6 - fall * 0.6, 1.0, 1.0 + fall * 0.4, a), ME_SCALE, fall * 1.35, -0.22 * fall, sin(dead_t * 70.0) * 5.0 * clampf(1.0 - dead_t * 2.5, 0.0, 1.0))

# The buster charge: cyan EM-wave energy wrapped around the left glove, flaring off it and licking upward.
# Drawn after the fighter, so it is always in FRONT of the hand; nothing is hidden behind it.
func draw_charge_orb(mz: float) -> void:
	var p := proj(float(me["x"]), mz)
	var s := p.z * ME_SCALE
	var c := Vector2(p.x - 0.25 * s, p.y - 0.50 * s)     # the left glove, same depth as the body
	var hand_r := s * 0.055
	var length := s * (0.22 + charge * 0.46)
	var amp := s * 0.045 * (0.6 + charge)
	var strands := 9
	for k in strands:
		var th := TAU * float(k) / float(strands) + 0.3 * sin(t * 2.0)       # start points all round the glove
		var out := Vector2(cos(th), sin(th))
		var start := c + out * hand_r
		var len_k := length * (0.55 + 0.45 * absf(sin(float(k) * 2.3 + 0.8)))
		var prev := start
		var segs := 11
		for i in range(1, segs + 1):
			var u := float(i) / float(segs)
			# leaves the glove outward, then curls up into a flame
			var dir := (out * (1.0 - u) + Vector2(0.0, -1.0) * (0.35 + u)).normalized()
			var wob := sin(t * 8.0 - u * 6.0 + float(k) * 1.7) * amp * u
			var pt := start + dir * len_k * u + Vector2(wob, 0.0)
			var fade := 1.0 - u
			draw_line(prev, pt, Color(0.25, 0.75, 1.0, 0.6 * fade + 0.15), 9.0 * pow(fade, 0.8) + 1.4)
			draw_line(prev, pt, Color(0.85, 1.0, 1.0, 0.9 * fade), 4.0 * pow(fade, 0.8) + 0.8)
			prev = pt
	# a thin glowing sleeve around the glove so it reads as wrapped, not spawned behind
	draw_arc(c, hand_r * 1.15, 0.0, TAU, 20, Color(0.7, 0.97, 1.0, 0.5 + 0.3 * sin(t * 12.0)), 1.6)
	draw_arc(c, hand_r * 1.7, 0.0, TAU, 20, Color(0.35, 0.85, 1.0, 0.25), 1.2)
	if charge >= 1.0:
		for i in 3:
			var sp := fmod(t * 1.6 + float(i) * 0.33, 1.0)
			draw_circle(c + Vector2(sin(t * 9.0 + float(i) * 2.0) * s * 0.05, -length * (0.6 + sp)), 1.6, Color(0.8, 1.0, 1.0, 1.0 - sp))

# ------------------------------------------------------------------ holographic shield and counter hits
# Y raises a quick shield (about a second). It stops most shots, not waves or sword strikes, costs your buster
# charge, and a shot that hits the instant it goes up is a PERFECT GUARD: reflected back at the shooter.
func raise_guard() -> void:
	if phase != "fight" or selecting or guard_t > 0.0:
		return
	if guard_cd > 0.0:
		popup(float(me["x"]), float(me["z"]), "SHIELD RECHARGING", Color("ff9f1c"))
		return
	if not (me["strike"] as Dictionary).is_empty() or float(me["frozen_t"]) > 0.0:
		return
	guard_t = GUARD_TIME
	guard_age = 0.0
	guard_cd = GUARD_TIME + GUARD_COOLDOWN
	charge = 0.0

func block_shot(s: Dictionary) -> void:
	guard_hit_t = 0.28
	if guard_age <= PERFECT_T:
		popup(float(me["x"]), float(me["z"]), "PERFECT GUARD", Color("fff27a"))
		gain_ess("static", 1)
		spawn(0, float(s["x"]), 0.5, 13.0, float(s["r"]), float(s["dmg"]) * 0.7, "buster")   # reflected
		guard_cd = maxf(0.0, guard_cd - 1.5)
	else:
		popup(float(me["x"]), float(me["z"]), "BLOCKED", Color("7df9ff"))

# Hitting an opponent with a card while it winds up an attack cancels the attack, stuns it, and plays a free
# bonus card from your folder immediately. A bonus card cannot cause another counter.
func counter_hit() -> void:
	if float(foe["hp"]) <= 0.0:
		return
	foe["tele"] = 0.0
	foe["mw"] = 0.0
	foe_atk_t = 0.0
	foe["frozen_t"] = maxf(float(foe["frozen_t"]), 0.7)
	foe["hp"] = float(foe["hp"]) - COUNTER_BONUS
	banner = "COUNTER HIT!"
	banner_t = 0.9
	gain_ess("static", 2)
	var pool: Array = []
	for c in folder:
		if not MELEE.has(str(c)):
			pool.append(c)
	var cid := str(pool[randi() % pool.size()]) if not pool.is_empty() else "heal"
	bonus_play = true
	use_card(0, cid)
	bonus_play = false
	popup(float(me["x"]), float(me["z"]), "BONUS: " + str(Cards.CARDS[cid]["name"]), Color(Cards.CARDS[cid]["color"]))

func bot_cards() -> void:
	if phase != "fight":
		return
	if randf() < 0.01 and guard_cd <= 0.0 and not shots.is_empty():
		raise_guard()
	if gauge >= 1.0 and not selecting:
		open_custom()
		picked = [0, 1]
		confirm_custom()
	if not queue.is_empty() and randf() < 0.02:
		if MELEE.has(str(queue[0])):
			locked = true
		play_next_card()

func fight_step(dt: float) -> void:
	buster_cd -= dt
	guard_t = maxf(0.0, guard_t - dt)
	guard_age += dt
	guard_cd = maxf(0.0, guard_cd - dt)
	guard_hit_t = maxf(0.0, guard_hit_t - dt)
	if not selecting:
		if (me["strike"] as Dictionary).is_empty():
			move_fighter(me, read_move(dt), dt, speed_mul * (LOCK_SPEED if locked else 1.0) * (0.5 if guard_t > 0.0 else 1.0))
			if float(me["frozen_t"]) <= 0.0 and guard_t <= 0.0:
				charge = minf(1.0, charge + dt / BUSTER_CHARGE_TIME)
			var fire := read_fire()
			var pressed := fire and not fire_prev
			fire_prev = fire
			if buster_cd <= 0.0 and float(me["frozen_t"]) <= 0.0 and charge >= BUSTER_MIN and guard_t <= 0.0 and (pressed or (fire and charge >= 1.0)):
				var p := charge
				spawn(0, float(me["x"]), 0.5, 14.0, lerpf(0.12, 0.26, p), BUSTER_MIN_DMG + (BUSTER_MAX_DMG - BUSTER_MIN_DMG) * p * p, "charged" if p >= 0.99 else "buster")
				charge = 0.0
				buster_cd = 0.15
				shoot_t = 0.2
		else:
			fire_prev = true
	else:
		fire_prev = read_fire()
	if not (me["strike"] as Dictionary).is_empty():
		update_strike(me, dt)
	if not (foe["strike"] as Dictionary).is_empty():
		update_strike(foe, dt)
	gauge = minf(1.0, gauge + dt / CUSTOM_TIME)
	foe_gauge = minf(1.0, foe_gauge + dt / CUSTOM_TIME)
	update_ai(dt)
	for f in [me, foe]:
		tick_fighter(f, dt)
	update_shots(dt)
	if pending_counter:
		pending_counter = false
		counter_hit()
	if float(foe["hp"]) <= 0.0:
		phase = "cleared"
		phase_t = CLEARED_TIME
		banner = "DELETED!"
		banner_t = 1.6
		popup(float(me["x"]), 0.0, "HP +30", Color("90be6d"))
		shots.clear()
		if randf() < 0.55:
			var cid := Cards.random_id()
			cards_won.append(cid)
			popup(0.0, 3.0, "CARD GET: " + Cards.CARDS[cid]["name"], Color(Cards.CARDS[cid]["color"]))
		add_score(1.0)
		if done:
			return
	if float(me["hp"]) <= 0.0:
		banner = "DELETED..."
		finish(false)

func tick_fighter(f: Dictionary, dt: float) -> void:
	f["shield_t"] = maxf(0.0, float(f["shield_t"]) - dt)
	if float(f["shield_t"]) <= 0.0:
		f["shield"] = 0.0
	f["haste_t"] = maxf(0.0, float(f["haste_t"]) - dt)
	f["frozen_t"] = maxf(0.0, float(f["frozen_t"]) - dt)
	if int(f["gat"]) > 0:
		f["gat_t"] = float(f["gat_t"]) - dt
		if float(f["gat_t"]) <= 0.0:
			f["gat_t"] = 0.12
			f["gat"] = int(f["gat"]) - 1
			var owner := int(f["side"])
			spawning_card = bool(f.get("gat_card", false))
			spawn(owner, float(f["x"]), 0.5 if owner == 0 else FIELD_Z - 0.5, 15.0 if owner == 0 else -11.0, 0.12, 8.0, "buster")
			spawning_card = false

func move_fighter(f: Dictionary, dir: float, dt: float, mult: float) -> void:
	if float(f["frozen_t"]) > 0.0:
		return
	var sp := 2.7 * mult * (1.6 if float(f["haste_t"]) > 0.0 else 1.0)
	f["x"] = clampf(float(f["x"]) + dir * sp * dt, -FIELD_X + 0.2, FIELD_X - 0.2)

func spawn(owner: int, x: float, z: float, vz: float, r: float, dmg: float, kind: String) -> void:
	shots.append({"owner": owner, "x": x, "z": z, "vz": vz, "r": r, "dmg": dmg, "kind": kind, "done": false, "card": spawning_card and owner == 0})

func update_shots(dt: float) -> void:
	for s in shots:
		s["z"] = float(s["z"]) + float(s["vz"]) * dt
		if s["done"]:
			continue
		var target: Dictionary = foe if int(s["owner"]) == 0 else me
		var tz: float = target["z"]
		var crossed: bool = (float(s["vz"]) > 0.0 and float(s["z"]) >= tz) or (float(s["vz"]) < 0.0 and float(s["z"]) <= tz)
		if not crossed:
			continue
		s["done"] = true
		var gap := absf(float(s["x"]) - float(target["x"]))
		if int(s["owner"]) == 1 and guard_t > 0.0 and gap < 0.3 + float(s["r"]) + 0.25 and not PIERCE.has(str(s["kind"])):
			block_shot(s)
		elif gap < 0.3 + float(s["r"]):
			var dmg_in := float(s["dmg"])
			if int(s["owner"]) == 1 and guard_t > 0.0:
				dmg_in *= PIERCE_KEEP
				popup(float(me["x"]), float(me["z"]), "SHIELD HOLDS (HALF)", Color("7df9ff"))
			damage(target, dmg_in, int(s["owner"]), bool(s["card"]))
		elif int(s["owner"]) == 1 and gap < 0.3 + float(s["r"]) + 0.4:
			near_misses += 1
			if near_misses % 3 == 0:
				gain_ess("static", 1)       # every third close call
			popup(float(me["x"]), 0.0, "close!", Color("ffd166"))
	shots = shots.filter(func(s): return float(s["z"]) > -1.5 and float(s["z"]) < FIELD_Z + 1.5)

func damage(target: Dictionary, amount: float, owner: int, card: bool = false) -> void:
	if int(target["side"]) == 0:
		if inv > 0.0:
			return
		inv = 0.35 * inv_time / 1.5
	if float(target["shield"]) > 0.0:
		var absorbed := minf(float(target["shield"]), amount)
		target["shield"] = float(target["shield"]) - absorbed
		amount -= absorbed
	target["hp"] = float(target["hp"]) - amount
	target["flash"] = 0.18
	if int(target["side"]) == 0:
		hurt_t = 0.28
	else:
		foe_hurt_t = 0.28
	popup(float(target["x"]), float(target["z"]), str(int(round(amount))), Color("ffffff") if owner == 0 else Color("ff6b6b"))
	if card and owner == 0 and int(target["side"]) == 1 and phase == "fight" and not bonus_play and (float(target["tele"]) > 0.0 or float(target["mw"]) > 0.0):
		pending_counter = true   # hit it while it winds up: Counter Hit
	if owner == 0 and amount > 0.0:
		hits += 1
		if hits % 3 == 0:
			gain_ess("static", 1)

func popup(x: float, z: float, text: String, color: Color) -> void:
	for p in popups:   # never stack the same message on top of itself
		if str(p["text"]) == text and float(p["t"]) < 0.7:
			return
	popups.append({"x": x, "z": z, "text": text, "color": color, "t": 0.0})

# ------------------------------------------------------------------ cards (shared by both sides)
func use_card(owner: int, id: String) -> void:
	var f: Dictionary = me if owner == 0 else foe
	var tgt: Dictionary = foe if owner == 0 else me
	var dz := 1.0 if owner == 0 else -1.0
	var z0 := (0.5 if owner == 0 else FIELD_Z - 0.5)
	var fx_ := float(f["x"])
	spawning_card = (owner == 0 and not bonus_play)
	match id:
		"cannon": spawn(owner, fx_, z0, 7.0 * dz, 0.38, 40.0, "cannon")
		"triple":
			for dx in [-0.5, 0.0, 0.5]:
				spawn(owner, fx_ + dx, z0, 12.0 * dz, 0.16, 15.0, "buster")
		"gatling":
			f["gat"] = 6
			f["gat_t"] = 0.0
			f["gat_card"] = spawning_card
		"slash", "widesword":
			if owner == 0:
				start_strike(0, id)
			else:                      # the foe winds up first, aimed at where you stand NOW
				foe["mw"] = 0.5
				foe["mw_id"] = id
				foe["mw_aim"] = float(me["x"])
		"tide":
			spawn(owner, fx_, z0, 9.0 * dz, 0.9, 45.0, "tide")
			if owner == 0:
				swing_pose = 0.45
		"wave": spawn(owner, fx_, z0, 6.0 * dz, 0.95, 35.0, "wave")
		"heal": f["hp"] = minf(float(f["max"]), float(f["hp"]) + 40.0)
		"barrier":
			f["shield"] = 40.0
			f["shield_t"] = 6.0
		"haste": f["haste_t"] = 6.0
		"freeze": tgt["frozen_t"] = 2.5
	spawning_card = false

# ------------------------------------------------------------------ melee: dash in, cut, return
func start_strike(owner: int, id: String, aim_x: float = NAN) -> void:
	var f: Dictionary = me if owner == 0 else foe
	var tgt: Dictionary = foe if owner == 0 else me
	var wide := id == "widesword"
	if owner == 0:
		guard_t = 0.0   # swinging a sword drops the shield
	f["strike"] = {"ph": 0, "t": 0.0, "dmg": 50.0 if wide else 35.0, "reach": 1.0 if wide else 0.55, "hit": false,
		"track": owner == 0 and locked, "aim": float(tgt["x"]) if is_nan(aim_x) else aim_x, "z0": float(f["z"]),
		"zt": (float(tgt["z"]) - 1.0) if owner == 0 else (float(tgt["z"]) + 1.0), "owner": owner}

func update_strike(f: Dictionary, dt: float) -> void:
	var s: Dictionary = f["strike"]
	var tgt: Dictionary = foe if int(s["owner"]) == 0 else me
	s["t"] = float(s["t"]) + dt
	match int(s["ph"]):
		0:   # dash
			var u := clampf(float(s["t"]) / 0.22, 0.0, 1.0)
			f["z"] = lerpf(float(s["z0"]), float(s["zt"]), u * u * (3.0 - 2.0 * u))
			var aim := float(tgt["x"]) if s["track"] else float(s["aim"])   # lock-on keeps tracking the target
			f["x"] = move_toward(float(f["x"]), aim, 9.0 * dt)
			if u >= 1.0:
				s["ph"] = 1
				s["t"] = 0.0
		1:   # swing
			if float(s["t"]) >= 0.10 and not s["hit"]:
				s["hit"] = true
				if absf(float(f["x"]) - float(tgt["x"])) < float(s["reach"]) + 0.3:
					damage(tgt, float(s["dmg"]), int(s["owner"]), int(s["owner"]) == 0)
				else:
					popup(float(f["x"]), float(f["z"]), "miss", Color(1, 1, 1, 0.9))
			if float(s["t"]) >= 0.32:
				s["ph"] = 2
				s["t"] = 0.0
		2:   # back to your side
			var u2 := clampf(float(s["t"]) / 0.25, 0.0, 1.0)
			f["z"] = lerpf(float(s["zt"]), float(s["z0"]), u2)
			if u2 >= 1.0:
				f["z"] = float(s["z0"])
				f["strike"] = {}

# ------------------------------------------------------------------ opponent AI
func incoming_danger() -> bool:
	for s in shots:
		if int(s["owner"]) == 0 and not s["done"] and absf(float(s["x"]) - float(foe["x"])) < 0.55 + float(s["r"]) and float(s["z"]) > float(foe["z"]) - 4.5:
			return true
	return false

func update_ai(dt: float) -> void:
	if float(foe["frozen_t"]) > 0.0 or not (foe["strike"] as Dictionary).is_empty():
		return
	if float(foe["mw"]) > 0.0:       # winding up a sword attack
		foe["mw"] = float(foe["mw"]) - dt
		if float(foe["mw"]) <= 0.0:
			start_strike(1, str(foe["mw_id"]), float(foe["mw_aim"]))
		return
	var e: Dictionary = ENEMIES[mini(round_i, ENEMIES.size() - 1)]
	foe["react_t"] = float(foe["react_t"]) - dt
	if float(foe["react_t"]) <= 0.0:
		foe["react_t"] = float(e["react"]) * randf_range(0.7, 1.3)
		if incoming_danger():
			var away := 1.0 if float(foe["x"]) < 0.0 else -1.0
			foe["tx"] = clampf(float(foe["x"]) + away * 0.9, -FIELD_X + 0.3, FIELD_X - 0.3)
		elif randf() < 0.55:
			foe["tx"] = clampf(float(me["x"]) + randf_range(-0.4, 0.4), -FIELD_X + 0.3, FIELD_X - 0.3)
		else:
			foe["tx"] = randf_range(-FIELD_X + 0.3, FIELD_X - 0.3)
	var gap := float(foe["tx"]) - float(foe["x"])
	if absf(gap) > 0.05 and float(foe["tele"]) <= 0.0:
		move_fighter(foe, signf(gap), dt, float(e["speed"]))
	# attacks: a short telegraph (the foe flashes) before every shot so it can be dodged
	if float(foe["tele"]) > 0.0:
		foe["tele"] = float(foe["tele"]) - dt
		if float(foe["tele"]) <= 0.0:
			foe_fire(str(e["kind"]))
	else:
		foe["fire_t"] = float(foe["fire_t"]) - dt
		if float(foe["fire_t"]) <= 0.0:
			foe["tele"] = 0.55 if str(e["kind"]) == "brute" else 0.32
			foe["spread"] = str(e["kind"]) == "drone" and randf() < 0.25
			foe["fire_t"] = float(e["fire"]) * randf_range(0.8, 1.4)
	if str(e["kind"]) == "rival":
		if foe_gauge >= 1.0 and foe_selecting <= 0.0 and foe_queue.is_empty():
			foe_selecting = 1.4
		if not foe_queue.is_empty():
			foe_use_t -= dt
			if foe_use_t <= 0.0:
				foe_use_t = 1.3
				var cid: String = foe_queue.pop_front()
				use_card(1, cid)
				foe_atk_t = 0.45
				popup(float(foe["x"]), FIELD_Z, Cards.CARDS[cid]["name"], Color(Cards.CARDS[cid]["color"]))

func foe_ready_cards() -> void:
	var pool := ["cannon", "triple", "slash", "widesword", "wave", "tide", "barrier", "gatling"]
	pool.shuffle()
	foe_queue = pool.slice(0, 2)
	foe_gauge = 0.0
	foe_use_t = 0.4

func foe_fire(kind: String) -> void:
	foe_atk_t = 0.35
	var fx_ := float(foe["x"])
	var z0 := FIELD_Z - 0.5
	match kind:
		"drone":
			spawn(1, fx_, z0, -11.0, 0.18, 8.0, "buster")
			if bool(foe.get("spread", false)):
				spawn(1, fx_ + 0.45, z0, -11.0, 0.18, 8.0, "buster")
				spawn(1, fx_ - 0.45, z0, -11.0, 0.18, 8.0, "buster")
		"brute": spawn(1, fx_, z0, -6.0, 0.62, 22.0, "wave")
		_: spawn(1, fx_, z0, -12.0, 0.18, 9.0, "buster")

# ------------------------------------------------------------------ drawing
func proj(x: float, z: float) -> Vector3:
	var d := z + CAM_Z
	var k := F / d
	return Vector3(W * 0.5 + x * k, HORIZON + CAM_H * k, k)

func sheet(sheet_name: String) -> Texture2D:
	if _tex.has(sheet_name):
		return _tex[sheet_name]
	var tex: Texture2D = null
	for path in ["user://art/%s.png" % sheet_name, "res://art/%s.png" % sheet_name]:
		if FileAccess.file_exists(path):
			var img := Image.load_from_file(path)
			if img:
				tex = ImageTexture.create_from_image(img)
				break
	_tex[sheet_name] = tex
	return tex

func quad(x0: float, x1: float, z0: float, z1: float, col: Color) -> void:
	var a := proj(x0, z0)
	var b := proj(x1, z0)
	var c := proj(x1, z1)
	var d := proj(x0, z1)
	draw_colored_polygon(PackedVector2Array([Vector2(a.x, a.y), Vector2(b.x, b.y), Vector2(c.x, c.y), Vector2(d.x, d.y)]), col)

func gline(x0: float, z0: float, x1: float, z1: float, col: Color, w: float = 1.0) -> void:
	var a := proj(x0, z0)
	var b := proj(x1, z1)
	draw_line(Vector2(a.x, a.y), Vector2(b.x, b.y), col, w)

func draw_sprite(sheet_name: String, frame: int, x: float, z: float, lift: float, tint: Color) -> void:
	var tex := sheet(sheet_name)
	if tex == null:
		return
	var p := proj(x, z)
	var size := p.z * SPR_H
	var top := p.y - lift * p.z - size * FEET
	draw_texture_rect_region(tex, Rect2(p.x - size * 0.5, top, size, size), Rect2(frame * 64, 0, 64, 64), tint)

func draw_shadow(x: float, z: float, r: float) -> void:
	var p := proj(x, z)
	var pts := PackedVector2Array()
	for i in 14:
		var a := TAU * i / 14.0
		pts.append(Vector2(p.x + cos(a) * r * p.z, p.y + sin(a) * r * p.z * 0.28))
	draw_colored_polygon(pts, Color(0, 0, 0, 0.4))

func _draw() -> void:
	if recipe.is_empty():
		return
	var f := ThemeDB.fallback_font
	draw_arena()
	draw_actors()
	draw_hud(f)
	if phase == "intro" and is_navi_round():
		draw_intro(f)
	if selecting:
		draw_custom(f)

# ------------------------------------------------------------------ opening cinematic
func ease_out(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return 1.0 - pow(1.0 - x, 3.0)

func draw_portrait(sheet_name: String, pose: String, at: float, center: Vector2, size: float, tint: Color) -> void:
	var tex := sheet(sheet_name)
	var md := meta(sheet_name)
	if tex == null or md.is_empty():
		return
	var rows: Dictionary = md["rows"]
	var r: Dictionary = rows[pose] if rows.has(pose) else rows["idle"]
	var n := int(r["n"])
	var idx := posmod(int(at * float(r["fps"])), n)
	var fw := int(md["fw"])
	draw_texture_rect_region(tex, Rect2(center.x - size * 0.5, center.y - size * 0.5, size, size), Rect2(idx * fw, int(r["row"]) * fw, fw, fw), tint)

func draw_intro(f: Font) -> void:
	var e: Dictionary = ENEMIES[mini(round_i, ENEMIES.size() - 1)]
	var boss := round_i >= ENEMIES.size() - 1
	var tt := intro_total - phase_t
	var kcol: Color = [Color("ffb703"), Color("ef476f"), Color("b5179e")][mini(round_i, 2)]
	var a_in := clampf(tt / 0.3, 0.0, 1.0)
	var a_out := clampf(phase_t / 0.35, 0.0, 1.0)
	var a := minf(a_in, a_out)
	var centre := Vector2(W * 0.5, 262.0)
	# backdrop: dark wash, then rays turning slowly around the opponent
	draw_rect(Rect2(0, 0, W, H), Color(0.02, 0.01, 0.06, 0.95 * a))
	var rays := 22
	for i in rays:
		if i % 2 == 0:
			continue
		var a0 := TAU * float(i) / float(rays) + tt * (0.35 if not boss else 0.6)
		var a1 := a0 + TAU / float(rays)
		var far := 900.0
		draw_colored_polygon(PackedVector2Array([centre, centre + Vector2(cos(a0), sin(a0)) * far, centre + Vector2(cos(a1), sin(a1)) * far]), Color(kcol, 0.14 * a))
	# the opponent: swings in from the right, then zooms in while the view drifts left to right
	var prog := clampf(tt / intro_total, 0.0, 1.0)
	var slide := (1.0 - ease_out(tt / 0.6)) * 520.0
	var pan := lerpf(-90.0, 90.0, prog) if boss else lerpf(-50.0, 50.0, prog)
	var zoom := lerpf(0.78, 1.28, ease_out(prog))
	var size := (330.0 if not boss else 360.0) * zoom * float(e["scale"]) / 1.3
	var pc := centre + Vector2(pan + slide, -10.0 * sin(tt * 2.0))
	draw_portrait(str(e["sheet"]), "idle", tt, pc + Vector2(8, 10), size, Color(0, 0, 0, 0.45 * a))     # shadow
	draw_portrait(str(e["sheet"]), "idle", tt, pc, size, Color(1, 1, 1, a))
	# letterbox bars with the text
	var bar_in := ease_out(tt / 0.4) * (1.0 if phase_t > 0.3 else clampf(phase_t / 0.3, 0.0, 1.0))
	var top_h := 78.0 * bar_in
	var bot_h := 118.0 * bar_in
	draw_rect(Rect2(0, 0, W, top_h), Color(0.01, 0.0, 0.04, 1.0))
	draw_rect(Rect2(0, H - bot_h, W, bot_h), Color(0.01, 0.0, 0.04, 1.0))
	draw_rect(Rect2(0, top_h - 3.0, W, 3.0), kcol)
	draw_rect(Rect2(0, H - bot_h, W, 3.0), kcol)
	if bar_in > 0.9:
		if boss:
			# warning stripes crawl along the top bar, and the label flashes
			for i in range(-2, 22):
				var x := float(i) * 56.0 + fmod(tt * 120.0, 56.0)
				draw_colored_polygon(PackedVector2Array([Vector2(x, 0), Vector2(x + 28, 0), Vector2(x + 8, 22), Vector2(x - 20, 22)]), Color(1.0, 0.25, 0.25, 0.85))
			var blink := 1.0 if int(tt * 4.0) % 2 == 0 else 0.35
			draw_string(f, Vector2(0, 58), "FINAL OPPONENT", HORIZONTAL_ALIGNMENT_CENTER, W, 28, Color(1.0, 0.85, 0.85, blink))
		else:
			draw_string(f, Vector2(0, 52), "ROUND %d / %d" % [round_i + 1, ENEMIES.size()], HORIZONTAL_ALIGNMENT_CENTER, W, 26, Color(1, 1, 1, 0.9))
		# name plate slides in from the left a moment later
		var nx := (1.0 - ease_out((tt - 0.5) / 0.5)) * -700.0
		var ty := H - bot_h
		draw_string(f, Vector2(nx, ty + 62), str(e["name"]).to_upper(), HORIZONTAL_ALIGNMENT_CENTER, W, 48, Color.WHITE)
		draw_string(f, Vector2(-nx, ty + 96), "HP %d    SPEED %s" % [int(e["hp"]), "FAST" if float(e["speed"]) > 1.4 else ("SLOW" if float(e["speed"]) < 1.0 else "NORMAL")], HORIZONTAL_ALIGNMENT_CENTER, W, 16, Color(kcol, 0.95))
	# white flash as it opens and as it hands over to the fight
	var flash := maxf(clampf(1.0 - tt / 0.25, 0.0, 1.0), clampf(1.0 - phase_t / 0.25, 0.0, 1.0)) * 0.8
	if flash > 0.0:
		draw_rect(Rect2(0, 0, W, H), Color(1, 1, 1, flash))
	if tt > 1.6:
		draw_string(f, Vector2(W - 190, H - bot_h - 10), "confirm: skip", HORIZONTAL_ALIGNMENT_RIGHT, 180, 12, Color(1, 1, 1, 0.4))

func bg(layer: String, dx: float, tint: Color = Color.WHITE) -> void:
	var tx := sheet(layer)
	if tx != null:
		draw_texture_rect(tx, Rect2(-80.0 + dx, 0.0, 1120.0, 540.0), false, tint)

# Pre-rendered city (tools/backdrop_render.py). The camera and the layers never move; only the clouds
# drift. The lit windows are painted into the layers. Kept dim and hazy so it never competes with the fight.
func draw_arena() -> void:
	var px := 0.0   # the camera is static: nothing here follows the player
	var haze := Color(0.84, 0.84, 0.92)
	bg("bg_sky", -px * 2.0)
	var cloud_tex := sheet("bg_clouds")
	if cloud_tex != null:
		var cd := fposmod(t * 5.0, 1120.0)
		for k in 2:
			draw_texture_rect(cloud_tex, Rect2(-80.0 - px * 4.0 - cd + k * 1120.0, 0.0, 1120.0, 540.0), false, Color(1, 1, 1, 0.85))
	bg("bg_far", 0.0, haze)
	var mid_dx := 0.0
	bg("bg_mid", mid_dx, haze)
	var near_dx := 0.0
	bg("bg_near", near_dx, Color(0.78, 0.78, 0.88))
	for j in 3:   # a few tiny craft crossing the sky
		var cx := fposmod(j * 380.0 + t * (22.0 + j * 7.0), W + 80.0) - 40.0
		draw_rect(Rect2(cx, 70.0 + j * 14.0, 6, 2), Color(1.0, 0.95, 0.85, 0.8))
		draw_rect(Rect2(cx - 14.0, 71.0 + j * 14.0, 14, 1), Color(1.0, 0.8, 0.6, 0.25))
	for i in 14:   # calm the area behind the road
		draw_rect(Rect2(0, 150 + i * 28, W, 29), Color(0.02, 0.01, 0.08, 0.52 * float(i) / 13.0))
	# the wave road: a solid strip over the city that runs on toward the horizon (nothing see-through)
	quad(-FIELD_X - 0.14, FIELD_X + 0.14, 0.0, FIELD_Z, Color(0.02, 0.02, 0.10, 1.0))
	for i in 8:
		var z0 := FIELD_Z + i * 1.8
		var k := float(i) / 8.0
		quad(-FIELD_X, FIELD_X, z0, z0 + 1.8, Color(0.34, 0.10, 0.22).lerp(Color(0.12, 0.07, 0.20), k))
	quad(-FIELD_X, FIELD_X, 0.0, FIELD_Z * 0.5, Color(0.10, 0.26, 0.62, 1.0))
	quad(-FIELD_X, FIELD_X, FIELD_Z * 0.5, FIELD_Z, Color(0.58, 0.12, 0.22, 1.0))
	for i in range(-3, 4):
		var gx := i * 0.6
		gline(gx, 0.0, gx, FIELD_Z, Color(1, 1, 1, 0.20))
		gline(gx, FIELD_Z, gx, 30.0, Color(1, 1, 1, 0.07))
	for z in range(0, 7):
		gline(-FIELD_X, float(z), FIELD_X, float(z), Color(1, 1, 1, 0.18))
	gline(-FIELD_X, 0.0, -FIELD_X, FIELD_Z, Color(0.5, 0.9, 1.0, 0.9), 2.0)
	gline(FIELD_X, 0.0, FIELD_X, FIELD_Z, Color(0.5, 0.9, 1.0, 0.9), 2.0)
	gline(-FIELD_X, FIELD_Z, -FIELD_X, 30.0, Color(0.5, 0.9, 1.0, 0.30), 1.0)
	gline(FIELD_X, FIELD_Z, FIELD_X, 30.0, Color(0.5, 0.9, 1.0, 0.30), 1.0)
	gline(-FIELD_X, FIELD_Z * 0.5, FIELD_X, FIELD_Z * 0.5, Color(1, 1, 1, 0.75), 2.0)

var text_rects: Array = []   # screen boxes of floating text this frame, so new text can avoid sitting on old text

# Moves a box up until it no longer overlaps any text already placed this frame, then claims it.
func place_text(rect: Rect2) -> Rect2:
	for guard in 10:
		var hit := false
		for r in text_rects:
			if rect.intersects(r):
				hit = true
				break
		if not hit:
			break
		rect.position.y -= rect.size.y + 2.0
	text_rects.append(rect)
	return rect

func draw_actors() -> void:
	text_rects.clear()
	draw_telegraph()
	var e: Dictionary = ENEMIES[mini(round_i, ENEMIES.size() - 1)]
	var list: Array = [{"z": float(foe["z"]), "k": "foe"}, {"z": float(me["z"]), "k": "me"}]
	for s in shots:
		list.append({"z": s["z"], "k": "shot", "s": s})
	list.sort_custom(func(a, b): return float(a["z"]) > float(b["z"]))
	for it in list:
		match it["k"]:
			"foe":
				var fade := 1.0
				if phase == "cleared":
					fade = clampf((phase_t - 1.4) / 1.9, 0.0, 1.0)
				elif float(foe["hp"]) <= 0.0:
					fade = clampf(result_t / 2.8, 0.0, 1.0)
				var flash := float(foe["flash"]) > 0.0
				var tint := Color(2.2, 2.2, 2.2, fade) if flash else Color(1, 1, 1, fade)
				if (float(foe["tele"]) > 0.0 or float(foe["mw"]) > 0.0) and int(t * 24) % 2 == 0:
					tint = Color(1.8, 1.4, 0.9, fade)
				if float(foe["frozen_t"]) > 0.0:
					tint = Color(0.6, 0.9, 1.6, fade)
				var fz := float(foe["z"])
				draw_shadow(float(foe["x"]), fz, 0.5)
				draw_anim(str(e["sheet"]), foe_pose, t - foe_pose_t0, float(foe["x"]), fz, 0.0, tint, float(e["scale"]), clampf(foe_vx * 0.04, -0.14, 0.14), 0.014 * sin(t * 2.1 + 1.0) - (0.05 if foe_pose == "attack" else 0.0), sin(t * 90.0) * 4.0 * clampf(foe_hurt_t / 0.28, 0.0, 1.0))
				draw_shield(foe, fz, float(e["scale"]))
				if locked:
					draw_reticle()
				if not (foe["strike"] as Dictionary).is_empty() and int((foe["strike"] as Dictionary)["ph"]) == 1:
					draw_slash(foe, float((foe["strike"] as Dictionary)["t"]), Color(1.0, 0.5, 0.4), float(e["scale"]))
			"me":
				if phase == "result" and not result_won:
					draw_defeated()
					continue
				var tint2 := Color(2.2, 2.2, 2.2, 1) if float(me["flash"]) > 0.0 else Color.WHITE
				if float(me["frozen_t"]) > 0.0:
					tint2 = Color(0.6, 0.9, 1.6, 1)
				if inv > 0.0 and int(t * 30) % 2 == 0:
					tint2.a = 0.45
				var mz := float(me["z"])
				var ms: Dictionary = me["strike"]
				var mph := int(ms["ph"]) if not ms.is_empty() else -1
				draw_shadow(float(me["x"]), mz, 0.34)
				if mph == 0:   # dash afterimages
					for g in [0.35, 0.7]:
						draw_anim("duel_hero", "dash", t, float(me["x"]), lerpf(float(ms["z0"]), mz, g), 0.0, Color(0.6, 0.9, 1.4, 0.32 * (1.0 - g)), ME_SCALE)
				draw_anim("duel_hero", me_pose, t - me_pose_t0, float(me["x"]), mz, 0.0, tint2, ME_SCALE, clampf(me_vx * 0.045, -0.16, 0.16), 0.014 * sin(t * 2.3) + (0.035 if me_pose == "cast" else 0.0) - (0.03 if me_pose == "shoot" else 0.0), sin(t * 90.0) * 5.0 * clampf(hurt_t / 0.28, 0.0, 1.0))
				draw_shield(me, mz, ME_SCALE)
				if guard_t > 0.0:
					draw_holo_shield(mz)
				if mph == 1:
					draw_slash(me, float(ms["t"]), Color(0.8, 1.0, 1.0), ME_SCALE)
				if charge > 0.04 and mph < 0:
					draw_charge_orb(mz)
			"shot":
				draw_shot(it["s"])
	for pp in popups:
		var p := proj(float(pp["x"]), float(pp["z"]))
		var a := 1.0 - float(pp["t"]) / 1.1
		var pf := ThemeDB.fallback_font
		var tw := pf.get_string_size(str(pp["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
		var base_y := p.y - (1.3 + float(pp["t"]) * 0.8) * p.z
		var box := place_text(Rect2(p.x - tw * 0.5, base_y - 18.0, tw, 22.0))
		draw_string(pf, Vector2(box.position.x, box.position.y + 18.0), str(pp["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(pp["color"], a))

func meta(sheet_name: String) -> Dictionary:
	if _meta.has(sheet_name):
		return _meta[sheet_name]
	var m: Dictionary = {}
	for path in ["user://art/%s.json" % sheet_name, "res://art/%s.json" % sheet_name]:
		if FileAccess.file_exists(path):
			var d = JSON.parse_string(FileAccess.open(path, FileAccess.READ).get_as_text())
			if d is Dictionary:
				m = d
				break
	_meta[sheet_name] = m
	return m

# One frame of an animated pre-rendered sheet (rows = poses, columns = frames).
func draw_anim(sheet_name: String, pose: String, at: float, x: float, z: float, lift: float, tint: Color, mult: float = 1.0, lean: float = 0.0, squash: float = 0.0, shake: float = 0.0) -> void:
	var tex := sheet(sheet_name)
	var md := meta(sheet_name)
	if tex == null or md.is_empty():
		return
	var rows: Dictionary = md["rows"]
	if not rows.has(pose):
		pose = "idle"
	var r: Dictionary = rows[pose]
	var n := int(r["n"])
	var idx := int(at * float(r["fps"]))
	idx = posmod(idx, n) if bool(r["loop"]) else mini(idx, n - 1)
	var fw := int(md["fw"])
	var p := proj(x, z)
	var size := p.z * float(md["world_h"]) * mult
	var top := p.y - lift * p.z - size * float(md["feet"])
	# lean into the motion, breathe (squash and stretch), shake on a hit: all pivoting on the feet
	var feet_pt := Vector2(p.x + shake, p.y - lift * p.z)
	var sy := 1.0 + squash
	draw_set_transform_matrix(Transform2D(lean, Vector2(1.0 / sy, sy), 0.0, feet_pt))
	draw_texture_rect_region(tex, Rect2(-size * 0.5, -size * float(md["feet"]), size, size), Rect2(idx * fw, int(r["row"]) * fw, fw, fw), tint)
	draw_set_transform_matrix(Transform2D.IDENTITY)

# The floor flashes where an attack is about to land (the opponent holds still while it winds up).
func draw_telegraph() -> void:
	if phase != "fight":
		return
	var e: Dictionary = ENEMIES[mini(round_i, ENEMIES.size() - 1)]
	var pulse := 0.5 + 0.5 * sin(t * 26.0)
	var edge := Color(1.0, 0.55, 0.45, 0.95)
	if float(foe["tele"]) > 0.0:
		var half := (0.62 if str(e["kind"]) == "brute" else 0.18) + 0.3
		var xs: Array = [float(foe["x"])]
		if bool(foe.get("spread", false)):
			xs.append(float(foe["x"]) + 0.45)
			xs.append(float(foe["x"]) - 0.45)
		for xv in xs:
			var lx := float(xv)
			quad(lx - half, lx + half, 0.0, FIELD_Z, Color(1.0, 0.22, 0.18, 0.20 + 0.22 * pulse))
			gline(lx - half, 0.0, lx - half, FIELD_Z, edge, 2.0)
			gline(lx + half, 0.0, lx + half, FIELD_Z, edge, 2.0)
	if float(foe["mw"]) > 0.0:
		var rw := (1.0 if str(foe["mw_id"]) == "widesword" else 0.55) + 0.3
		var ax := float(foe["mw_aim"])
		quad(ax - rw, ax + rw, 0.0, 2.6, Color(1.0, 0.22, 0.18, 0.26 + 0.24 * pulse))
		gline(ax - rw, 0.0, ax - rw, 2.6, edge, 2.0)
		gline(ax + rw, 0.0, ax + rw, 2.6, edge, 2.0)
		gline(ax - rw, 2.6, ax + rw, 2.6, edge, 2.0)

# A holographic panel in front of the fighter: a hex grid that snaps open, flickers, ripples when hit.
func draw_holo_shield(mz: float) -> void:
	var p := proj(float(me["x"]), mz + 0.8)
	var s := p.z * ME_SCALE
	var open := clampf(guard_age / 0.12, 0.0, 1.0)
	var a := open * clampf(guard_t / 0.25, 0.0, 1.0)
	var hit := guard_hit_t / 0.28
	var cx := p.x
	var cy := p.y - 0.8 * s
	var rx := 1.0 * s * open
	var ry := 0.9 * s * open
	var rim := PackedVector2Array()
	for i in 33:
		var ang := TAU * i / 32.0
		rim.append(Vector2(cx + cos(ang) * rx, cy + sin(ang) * ry))
	draw_colored_polygon(rim, Color(0.3, 0.8, 1.0, (0.14 + 0.25 * hit) * a))
	var hs := 0.2 * s
	for row in range(-7, 8):
		for col in range(-7, 8):
			var hx := cx + col * 1.5 * hs
			var hy := cy + (row * 1.732 + posmod(col, 2) * 0.866) * hs
			var nx := (hx - cx) / maxf(rx, 1.0)
			var ny := (hy - cy) / maxf(ry, 1.0)
			if nx * nx + ny * ny > 0.86:
				continue
			var flick := 0.3 + 0.7 * (0.5 + 0.5 * sin(t * 6.0 + hx * 0.07 + hy * 0.05))
			var pts := PackedVector2Array()
			for k in 7:
				var ha := TAU * k / 6.0
				pts.append(Vector2(hx + cos(ha) * hs * 0.92, hy + sin(ha) * hs * 0.92))
			draw_polyline(pts, Color(0.6, 0.95, 1.0, (0.42 * flick + 0.4 * hit) * a), 1.0)
	var sweep := fposmod(t * 1.6, 1.0)
	draw_line(Vector2(cx - rx * 0.9, cy + ry * (0.9 - 1.8 * sweep)), Vector2(cx + rx * 0.9, cy + ry * (0.9 - 1.8 * sweep)), Color(0.8, 1.0, 1.0, 0.35 * a), 2.0)
	rim.append(rim[0])
	draw_polyline(rim, Color(0.65, 0.97, 1.0, (0.9 + 0.1 * hit) * a), 3.0 + 3.0 * hit)

func draw_reticle() -> void:
	var e: Dictionary = ENEMIES[mini(round_i, ENEMIES.size() - 1)]
	var p := proj(float(foe["x"]), float(foe["z"]))
	var size := p.z * 1.3 * float(e["scale"])
	var c := Vector2(p.x, p.y - size * 0.42)
	var r := size * 0.34 * (1.0 + 0.06 * sin(t * 8.0))
	var col := Color("ff4d4d")
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var corner := c + Vector2(sx * r, sy * r)
			draw_line(corner, corner - Vector2(sx * r * 0.38, 0.0), col, 3.0)
			draw_line(corner, corner - Vector2(0.0, sy * r * 0.38), col, 3.0)
	var lab := place_text(Rect2(c.x - 30, c.y - r - 18, 60, 16))
	draw_string(ThemeDB.fallback_font, Vector2(lab.position.x - 10, lab.position.y + 13), "LOCK-ON", HORIZONTAL_ALIGNMENT_CENTER, 80, 12, col)

# the slash arc of a sword card: sweeps across in front of the swinger
func draw_slash(f: Dictionary, st: float, col: Color, mult: float = 1.0) -> void:
	var p := proj(float(f["x"]), float(f["z"]) + (0.5 if int(f["side"]) == 0 else -0.5))
	var s := p.z * mult
	var c := Vector2(p.x, p.y - 0.9 * s)
	var r := 0.95 * s
	var a0 := -2.5 + clampf(st / 0.32, 0.0, 1.0) * 2.3
	draw_arc(c, r, a0, a0 + 1.4, 16, Color(col, 0.95), 8.0)
	draw_arc(c, r * 0.82, a0 + 0.1, a0 + 1.3, 14, Color(col, 0.5), 4.0)

func draw_shield(f: Dictionary, z: float, mult: float = 1.0) -> void:
	if float(f["shield"]) <= 0.0:
		return
	var p := proj(float(f["x"]), z)
	var s := p.z * mult
	var pts := PackedVector2Array()
	for i in 20:
		var a := TAU * i / 20.0
		pts.append(Vector2(p.x + cos(a) * 0.6 * s, p.y - 0.6 * s + sin(a) * 0.75 * s))
	pts.append(pts[0])
	draw_polyline(pts, Color(0.4, 1.0, 0.9, 0.8), 2.0)

func draw_shot(s: Dictionary) -> void:
	var p := proj(float(s["x"]), float(s["z"]))
	var r := float(s["r"]) * p.z
	var mine := int(s["owner"]) == 0
	var col := Color("7df9ff") if mine else Color("ff6b6b")
	var c := Vector2(p.x, p.y - 0.5 * p.z)
	match str(s["kind"]):
		"blade":
			draw_rect(Rect2(c.x - r, c.y - r * 0.9, r * 2.0, r * 1.8), Color(1, 1, 1, 0.85))
			draw_rect(Rect2(c.x - r, c.y - r * 0.9, r * 2.0, r * 1.8), col, false, 3.0)
		"tide":
			draw_rect(Rect2(c.x - r, c.y - r * 0.4, r * 2.0, r * 0.8), Color(0.3, 0.7, 1.0, 0.5))
			draw_arc(c + Vector2(0, r * 0.35), r, PI, TAU, 18, Color(0.85, 1.0, 1.0), 5.0)
			draw_arc(c + Vector2(0, r * 0.35), r * 0.7, PI, TAU, 18, Color(0.5, 0.9, 1.0, 0.8), 3.0)
		"wave":
			draw_rect(Rect2(c.x - r, c.y - r * 0.35, r * 2.0, r * 0.7), Color(col, 0.55))
			draw_rect(Rect2(c.x - r, c.y - r * 0.35, r * 2.0, r * 0.7), col, false, 3.0)
		_:
			draw_circle(c, r * 1.5, Color(col, 0.35))
			draw_circle(c, r, col)
			draw_circle(c, r * 0.5, Color.WHITE)

func bar(x: float, y: float, w: float, h: float, frac: float, col: Color) -> void:
	draw_rect(Rect2(x, y, w, h), Color(0, 0, 0, 0.6))
	draw_rect(Rect2(x, y, w * clampf(frac, 0.0, 1.0), h), col)
	draw_rect(Rect2(x, y, w, h), Color(1, 1, 1, 0.5), false, 1.0)

# ------------------------------------------------------------------ HUD layout (single source of truth)
# Every HUD element lives in this table. The drawing code reads its rectangles from here and
# `layout_problems()` (run by `--hudtest`) fails if any two siblings overlap or a text overflows its box.
func hud_items() -> Array:
	var items: Array = [
		{"id": "title", "rect": Rect2(12, 8, 262, 20), "size": 14, "samples": ["Wave Duel  -  beaten 3 / 3"]},
		{"id": "foe_plate", "rect": Rect2(286, 4, 388, 62)},
		{"id": "foe_name", "rect": Rect2(296, 8, 368, 20), "parent": "foe_plate", "size": 18, "samples": ["Hardhat Drone", "Wall Brute", "Rival Navi"]},
		{"id": "foe_hp", "rect": Rect2(300, 32, 360, 14), "parent": "foe_plate"},
		{"id": "foe_gauge", "rect": Rect2(300, 50, 360, 8), "parent": "foe_plate"},
		{"id": "essence", "rect": Rect2(686, 8, 262, 20), "size": 14, "samples": ["Static 9999"]},
		{"id": "foe_custom", "rect": Rect2(286, 70, 388, 18), "size": 14, "samples": ["OPPONENT: CUSTOM"]},
		{"id": "panel", "rect": Rect2(0, 480, 960, 60)},
		{"id": "hp_label", "rect": Rect2(16, 483, 56, 16), "parent": "panel", "size": 12, "samples": ["HP"]},
		{"id": "hp_bar", "rect": Rect2(76, 484, 220, 14), "parent": "panel", "size": 11, "samples": ["999 / 999"]},
		{"id": "buster_label", "rect": Rect2(16, 503, 56, 12), "parent": "panel", "size": 10, "samples": ["BUSTER"]},
		{"id": "buster_bar", "rect": Rect2(76, 504, 220, 8), "parent": "panel"},
		{"id": "custom_bar", "rect": Rect2(316, 484, 236, 14), "parent": "panel", "size": 11, "samples": ["CUSTOM READY  -  press Q / LB"]},
		{"id": "shield_bar", "rect": Rect2(560, 484, 56, 14), "parent": "panel", "size": 9, "samples": ["SHIELD"]},
		{"id": "status", "rect": Rect2(316, 502, 300, 16), "parent": "panel", "size": 11,
			"samples": ["Lock-on: sword cards only", "Down: LOCK ON, then use the sword card", "LOCKED ON - Enter / A: slash!", "Enter / A: use next card"]},
		{"id": "slot0", "rect": Rect2(632, 484, 96, 34), "parent": "panel", "size": 12, "samples": ["Triple Shot"], "inset": 14},
		{"id": "slot1", "rect": Rect2(736, 484, 96, 34), "parent": "panel", "size": 12, "samples": ["Wide Sword"], "inset": 14},
		{"id": "slot2", "rect": Rect2(840, 484, 96, 34), "parent": "panel", "size": 12, "samples": ["Tide Blade"], "inset": 14},
		{"id": "hint", "rect": Rect2(16, 522, 928, 14), "parent": "panel", "size": 11,
			"samples": ["A/D move    Shield: right button    Lock on: top button / Down (sword cards)    fire (R) releases the buster    Esc: menu"]},
		{"id": "banner", "rect": Rect2(180, 236, 600, 56), "size": 36, "samples": ["ROUND 3   Rival Navi", "ALL OPPONENTS DELETED", "YOU WERE DELETED", "COUNTER HIT!"]},
	]
	return items

var _hud_cache := {}

func hud_rect(id: String) -> Rect2:
	if _hud_cache.is_empty():
		for it in hud_items():
			_hud_cache[it["id"]] = it["rect"]
	return _hud_cache[id]

# Returns a list of problems (empty = clean). Used by `--hudtest` and safe to call any time.
func layout_problems() -> Array:
	var f := ThemeDB.fallback_font
	var items := hud_items()
	var out: Array = []
	for i in items.size():
		var a: Dictionary = items[i]
		var ra: Rect2 = a["rect"]
		if not Rect2(0, 0, W, H).encloses(ra):
			out.append("%s is outside the screen" % a["id"])
		if a.has("parent"):
			for p in items:
				if p["id"] == a["parent"] and not (p["rect"] as Rect2).encloses(ra):
					out.append("%s is not inside %s" % [a["id"], a["parent"]])
		if a.has("samples"):
			var inner := float(ra.size.x) - float(a.get("inset", 0))
			for s in a["samples"]:
				var w := f.get_string_size(str(s), HORIZONTAL_ALIGNMENT_LEFT, -1, int(a["size"])).x
				if w > inner:
					out.append("%s: '%s' is %.0fpx wide but its box is %.0fpx" % [a["id"], s, w, inner])
		for j in range(i + 1, items.size()):
			var b: Dictionary = items[j]
			var same_group: bool = a.get("parent", "") == b.get("parent", "")
			var is_container: bool = a["id"] == b.get("parent", "") or b["id"] == a.get("parent", "")
			if same_group and not is_container and ra.intersects(b["rect"]):
				out.append("%s overlaps %s" % [a["id"], b["id"]])
	return out

func hud_text(f: Font, id: String, text: String, col: Color, size: int, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> void:
	var r := hud_rect(id)
	var base := Vector2(r.position.x, r.position.y + r.size.y * 0.5 + size * 0.36)
	draw_string_outline(f, base, text, align, r.size.x, size, 4, Color(0.0, 0.0, 0.05, 0.95))
	draw_string(f, base, text, align, r.size.x, size, col)

func hud_bar(id: String, frac: float, col: Color) -> void:
	var r := hud_rect(id)
	draw_rect(r, Color(0, 0, 0, 0.75))
	draw_rect(Rect2(r.position, Vector2(r.size.x * clampf(frac, 0.0, 1.0), r.size.y)), col)
	draw_rect(r, Color(1, 1, 1, 0.55), false, 1.0)

func draw_hud(f: Font) -> void:
	var e: Dictionary = ENEMIES[mini(round_i, ENEMIES.size() - 1)]
	var plate := Color(0.03, 0.02, 0.09, 0.96)
	# top: opponent plate (solid, so the skyline never fights the text)
	hud_text(f, "title", "Wave Duel  -  beaten %d / %d" % [int(score), int(goal)], Color(1, 1, 1, 0.85), 14)
	draw_rect(hud_rect("foe_plate"), plate)
	draw_rect(hud_rect("foe_plate"), Color(1, 1, 1, 0.2), false, 1.0)
	hud_text(f, "foe_name", str(e["name"]), Color.WHITE, 18, HORIZONTAL_ALIGNMENT_CENTER)
	hud_bar("foe_hp", float(foe["hp"]) / float(foe["max"]), Color("e63946"))
	hud_bar("foe_gauge", foe_gauge, Color("ff9f1c"))   # the opponent's Custom gauge, so tempo is visible
	var parts: Array = []
	for k in essence:
		parts.append("%s %d" % [k, essence[k]])
	hud_text(f, "essence", "   ".join(parts), Color("ffd166"), 14, HORIZONTAL_ALIGNMENT_RIGHT)
	if foe_selecting > 0.0:
		hud_text(f, "foe_custom", "OPPONENT: CUSTOM", Color("ff9f1c"), 14, HORIZONTAL_ALIGNMENT_CENTER)
	# bottom: one solid panel; nothing in it can overlap because every box comes from hud_items()
	draw_rect(hud_rect("panel"), plate)
	draw_line(Vector2(0, 480), Vector2(W, 480), Color(1, 1, 1, 0.25), 1.0)
	hud_text(f, "hp_label", "HP", Color(1, 1, 1, 0.85), 12)
	hud_bar("hp_bar", float(me["hp"]) / float(me["max"]), Color("90be6d"))
	if float(me["shield"]) > 0.0:
		hud_bar("hp_bar", float(me["shield"]) / 40.0, Color(0.4, 1.0, 0.9, 0.8))
	hud_text(f, "hp_bar", "%d / %d" % [int(me["hp"]), int(me["max"])], Color.WHITE, 11, HORIZONTAL_ALIGNMENT_CENTER)
	hud_text(f, "buster_label", "BUSTER", Color(1, 1, 1, 0.7), 10)
	hud_bar("buster_bar", charge, Color("7df9ff") if charge < 1.0 else Color.WHITE)
	var ready := gauge >= 1.0
	hud_bar("custom_bar", gauge, Color("ffd166") if ready and int(t * 4) % 2 == 0 else Color("c77dff"))
	hud_text(f, "custom_bar", "CUSTOM READY  -  press Q / LB" if ready else "CUSTOM", Color.WHITE, 11, HORIZONTAL_ALIGNMENT_CENTER)
	hud_bar("shield_bar", 1.0 - guard_cd / (GUARD_TIME + GUARD_COOLDOWN), Color("5ee7ff") if guard_cd <= 0.0 else Color("ff9f1c"))
	hud_text(f, "shield_bar", "SHIELD", Color.WHITE, 9, HORIZONTAL_ALIGNMENT_CENTER)
	var status := "Lock-on: sword cards only"
	var scol := Color(1, 1, 1, 0.45)
	var sword_next := not queue.is_empty() and MELEE.has(str(queue[0]))
	if sword_next and not locked:
		status = "Down: LOCK ON, then use the sword card"
		scol = Color("ff9f1c")
	elif sword_next and locked:
		status = "LOCKED ON - Enter / A: slash!"
		scol = Color("ff5d5d")
	elif not queue.is_empty():
		status = "Enter / A: use next card"
		scol = Color(1, 1, 1, 0.85)
	hud_text(f, "status", status, scol, 11)
	for i in 3:
		var r := hud_rect("slot%d" % i)
		draw_rect(r, Color(0, 0, 0, 0.7))
		if i < queue.size():
			var c: Dictionary = Cards.CARDS[queue[i]]
			draw_rect(Rect2(r.position, Vector2(8, r.size.y)), Color(c["color"]))
			var tr := Rect2(r.position.x + 12, r.position.y, r.size.x - 14, r.size.y)
			draw_string_outline(f, Vector2(tr.position.x, tr.position.y + r.size.y * 0.5 + 4), str(c["name"]), HORIZONTAL_ALIGNMENT_LEFT, tr.size.x, 12, 4, Color(0, 0, 0.05, 0.9))
			draw_string(f, Vector2(tr.position.x, tr.position.y + r.size.y * 0.5 + 4), str(c["name"]), HORIZONTAL_ALIGNMENT_LEFT, tr.size.x, 12, Color.WHITE)
			draw_rect(r, Color.WHITE if i == 0 else Color(1, 1, 1, 0.35), false, 2.0 if i == 0 else 1.0)
		else:
			draw_rect(r, Color(1, 1, 1, 0.16), false, 1.0)
	hud_text(f, "hint", "A/D move    Shield: right button    Lock on: top button / Down (sword cards)    fire (R) releases the buster    Esc: menu", Color(1, 1, 1, 0.5), 11)
	if banner_t > 0.0:
		var br := hud_rect("banner")
		var a := clampf(banner_t * 2.0, 0.0, 1.0)
		draw_rect(br, Color(0.03, 0.02, 0.09, 0.9 * a))
		hud_text(f, "banner", banner, Color(1, 1, 1, a), 36, HORIZONTAL_ALIGNMENT_CENTER)

func draw_custom(f: Font) -> void:
	draw_rect(Rect2(0, 0, W, H), Color(0, 0, 0, 0.72))
	draw_string(f, Vector2(0, 110), "CUSTOM", HORIZONTAL_ALIGNMENT_CENTER, W, 34, Color("ffd166"))
	var sub := "TIME STOPPED - take your time" if (not PVP or foe_selecting > 0.0) else "time is nearly stopped - the opponent has not set cards yet"
	draw_string(f, Vector2(0, 138), sub, HORIZONTAL_ALIGNMENT_CENTER, W, 14, Color(1, 1, 1, 0.6))
	for i in hand.size():
		var c: Dictionary = Cards.CARDS[hand[i]]
		var r := Rect2(56 + i * 172, 170, 160, 230)
		var on := picked.has(i)
		draw_rect(r, Color(0.05, 0.05, 0.1, 0.96))
		draw_rect(Rect2(r.position, Vector2(r.size.x, 56)), Color(c["color"]).darkened(0.35))
		draw_string(f, Vector2(r.position.x, r.position.y + 36), str(c["name"]), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 20, Color.WHITE)
		draw_multiline_string(f, Vector2(r.position.x + 10, r.position.y + 96), str(c["desc"]), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 20, 14, 4, Color(1, 1, 1, 0.8))
		draw_rect(r, Color(c["color"]) if not on else Color("ffd166"), false, 3.0 if on else 1.5)
		if i == cur:
			draw_rect(r.grow(6), Color.WHITE, false, 3.0)
		if on:
			draw_string(f, Vector2(r.position.x, r.position.y + 210), "SET #%d" % (picked.find(i) + 1), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 22, Color("ffd166"))
	draw_string(f, Vector2(0, 440), "A / D or stick: choose     Enter / A: set card (max 3, in order)     Q / Y: confirm", HORIZONTAL_ALIGNMENT_CENTER, W, 15, Color(1, 1, 1, 0.75))
	draw_string(f, Vector2(0, 465), "confirming with nothing set keeps your gauge", HORIZONTAL_ALIGNMENT_CENTER, W, 12, Color(1, 1, 1, 0.45))
