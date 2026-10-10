extends Node2D
# Base class for scripted plugin games. Extend this, override tick() and _draw().
#
#   extends "res://game_base.gd"
#   func tick(dt: float) -> void: ...          # your game logic, called every physics frame
#   add_score(1.0)        # score; reaching `goal` wins the run
#   gain_ess("echo", 1)   # earn one of the essences your manifest declared
#   hurt()                # lose a life (respects invulnerability); 0 lives ends the run
#   finish(true/false)    # end the run yourself
#
# Boons from the Bridge work automatically if you use these fields:
#   lives, speed_mul (multiply your move speed), score_mul (add_score applies it),
#   inv_time (hurt() applies it), ess_mul (gain_ess applies it), goal.
# List the boon ids your game supports in manifest.json ("boons": [...]).

signal finished(won: bool, score: float)

const Carts = preload("res://carts.gd")
const W := 960.0
const H := 540.0

var recipe: Dictionary = {}
var auto := false          # bot-driven (self tests / screenshots): use this instead of real input
var boons: Array = []      # ids applied this run
var folder: Array = []     # the player's card folder (set by the hub before setup)
var cards_won: Array = []  # card ids earned this run; the hub adds them to the collection
var essence := {}          # essence NAME -> amount, brought back to the hub
var score := 0.0
var lives := 3
var goal := 15.0
var speed_mul := 1.0
var score_mul := 1.0
var inv_time := 1.5
var ess_mul := 1
var inv := 0.0
var done := false

func setup(r: Dictionary, start_boons: Array = []) -> void:
	recipe = r
	for b in start_boons:
		apply_boon(b)

func apply_boon(id: String) -> void:
	boons.append(id)
	match id:
		"skin": lives += 1
		"sprint": speed_mul = 1.25
		"bounty": score_mul = 1.5
		"ghost": inv_time = 3.0
		"greed": ess_mul = 2
		"short": goal = 11.0

func gain_ess(key: String, n: int = 1) -> void:
	var nm: String = Carts.ESSENCE[key]["name"]
	essence[nm] = essence.get(nm, 0) + n * ess_mul

func add_score(x: float) -> void:
	score += x * score_mul
	if score >= goal:
		finish(true)

func hurt() -> void:
	if inv > 0.0 or done:
		return
	lives -= 1
	inv = inv_time
	if lives <= 0:
		finish(false)

func finish(won: bool) -> void:
	if done:
		return
	if won:
		for k in recipe.get("earn_keys", []):
			gain_ess(k, 2)   # clear bonus
	done = true
	finished.emit(won, score)

# Called by the hub's physics loop and by headless self tests.
func step(dt: float) -> void:
	if done:
		return
	inv = maxf(0.0, inv - dt)
	tick(dt)

func tick(_dt: float) -> void:
	pass

func _physics_process(dt: float) -> void:
	step(dt)
	queue_redraw()
