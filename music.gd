extends Node
# Background music. Plays looping .ogg files from audio/_local/ (hub.ogg, duel.ogg) if they exist, and stays silent if not.
# That folder is git-ignored on purpose: anything committed to audio/ must be original or rights-cleared (see audio/README.md).
# Anyone cloning the repo plays audio/music/ (cleared tracks) instead; your _local/ files override it on your machine.
# M toggles the music (remembered in the save).

const FOLDERS := ["res://audio/_local/", "res://audio/music/"]   # your private tracks win; everyone else gets the public set
const VOLUME_DB := -9.0
const FADE := 0.7

var player := AudioStreamPlayer.new()
var sting_player := AudioStreamPlayer.new()
var duck := 0.0         # 0..1, how far the background track is turned down under a sting
var streams := {}       # track name -> AudioStream or null (cached lookups)
var want := ""          # track that should be playing
var current := ""
var enabled := true
var fade_level := 0.0   # 0..1

func _ready() -> void:
	player.volume_db = -80.0
	add_child(player)
	sting_player.volume_db = -4.0
	add_child(sting_player)

# Optional loops.json beside the tracks: {"title": 3.75} means "when title loops, jump back to 3.75 s, not 0" (a track whose
# first play has a clean intro that the repeats should skip). Tracks not listed loop from the start.
func loop_offset(folder: String, track: String) -> float:
	var path := ProjectSettings.globalize_path(folder + "loops.json")
	if FileAccess.file_exists(path):
		var d = JSON.parse_string(FileAccess.get_file_as_string(path))
		if d is Dictionary:
			return float(d.get(track, 0.0))
	return 0.0

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
				ogg.loop_offset = loop_offset(folder, track)
				s = ogg
				break
	streams[track] = s
	return s

# A one-shot jingle (victory.ogg ...). The background track ducks while it plays. Returns its length in seconds (0 if missing).
func play_sting(track: String) -> float:
	if not enabled:
		return 0.0
	var st := find(track)
	if st == null:
		return 0.0
	var one := (st as AudioStreamOggVorbis).duplicate() as AudioStreamOggVorbis
	one.loop = false
	sting_player.stream = one
	sting_player.play()
	want = ""          # the background music fades out for a jingle (it comes back when the screen changes)
	return one.get_length()

func sting_length(track: String) -> float:
	var st := find(track)
	return 0.0 if st == null else st.get_length()

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
	duck = move_toward(duck, 1.0 if sting_player.playing else 0.0, dt / 0.25)
	fade_level = move_toward(fade_level, target, dt / FADE)
	player.volume_db = -80.0 if fade_level <= 0.001 else VOLUME_DB + linear_to_db(fade_level) - 14.0 * duck
