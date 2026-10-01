extends Node
## Autoload "Audio": asset-guarded playback of UI sounds, music and 3D one-shots.
## Every helper silently no-ops while the audio file is missing, so the game
## runs unchanged as assets/ is being filled in (see docs/assets.md).

const BASE := "res://assets/audio/"

var _cache := {}
var _music: AudioStreamPlayer
var _music_name := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	add_child(_music)


func _exit_tree() -> void:
	if _music != null:
		AudioServer.lock()
		_music.stop()
		_music.stream = null
		_music.free()
		_music = null
		AudioServer.unlock()
	_cache.clear()


## Cached stream lookup relative to assets/audio/; null when absent.
func stream(rel: String) -> AudioStream:
	if not _cache.has(rel):
		var path := BASE + rel + ".ogg"
		_cache[rel] = load(path) as AudioStream if ResourceLoader.exists(path) else null
	return _cache[rel]


func play_ui(sound: String, volume_db := 0.0) -> void:
	_play_2d("ui/" + sound, "SFX", volume_db)


func play_music(track_name: String) -> void:
	if _music_name == track_name:
		return
	_music_name = track_name
	var s := stream("music/" + track_name)
	if s == null:
		_music.stop()
		return
	_music.stream = s
	_music.play()


## Positional one-shot (impacts etc.) placed in the current scene.
func play_at(rel: String, pos: Vector3, volume_db := 0.0) -> void:
	var s := stream(rel)
	if s == null:
		return
	var scene := get_tree().current_scene
	if scene == null:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = s
	p.bus = "SFX"
	p.volume_db = volume_db
	p.unit_size = 14.0
	scene.add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	p.play()


func _play_2d(rel: String, bus: String, volume_db: float) -> void:
	var s := stream(rel)
	if s == null:
		return
	var p := AudioStreamPlayer.new()
	p.stream = s
	p.bus = bus
	p.volume_db = volume_db
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()
