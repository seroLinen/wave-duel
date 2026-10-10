extends Node
# Background music. Plays looping .ogg files from audio/_local/ (hub.ogg, duel.ogg) if they exist, and stays silent if not.
# That folder is git-ignored on purpose: anything committed to audio/ must be original or rights-cleared (see audio/README.md).
# Anyone cloning the repo plays audio/music/ (cleared tracks) instead; your _local/ files override it on your machine.
# M toggles the music (remembered in the save).

const FOLDERS := ["res://audio/_local/", "res://audio/music/"]   # your private tracks win; everyone else gets the public set
const VOLUME_DB := -9.0
const FADE := 0.7

var player := AudioStreamPlayer.new()
var streams := {}       # track name -> AudioStream or null (cached lookups)
var want := ""          # track that should be playing
var current := ""
var enabled := true
var fade_level := 0.0   # 0..1

func _ready() -> void:
	player.volume_db = -80.0
	add_child(player)

func find(track: String) -> AudioStream:
	if streams.has(track):
		return streams[track]
	var s: AudioStream = null
	for folder in FOLDERS:
		var path: String = ProjectSettings.globalize_path(folder + track + ".ogg")
		if FileAccess.file_exists(path):
			var ogg := AudioStreamOggVorbis.load_from_file(path)
			if ogg:
				ogg.loop = true
				s = ogg
				break
	streams[track] = s
	return s

func play_track(track: String) -> void:
	want = track

func toggle() -> bool:
	enabled = not enabled
	return enabled

func _process(dt: float) -> void:
	var target := 1.0 if (enabled and want != "" and find(want) != null) else 0.0
	if current != want and fade_level <= 0.01:
		# the old track has faded out: swap
		current = want
		var st := find(current) if current != "" else null
		if st != null:
			player.stream = st
			player.play()
		else:
			player.stop()
	if current != want:
		target = 0.0
	fade_level = move_toward(fade_level, target, dt / FADE)
	player.volume_db = -80.0 if fade_level <= 0.001 else VOLUME_DB + linear_to_db(fade_level)
