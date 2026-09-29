class_name EngineAudio
extends Node
## Fake-RPM engine loop attached to a RaceCar. Plays
## assets/audio/engine/<engine_sound>/engine.ogg with pitch stepping through
## four "gears" by speed; silently does nothing while the sample is missing.

const PATH_TEMPLATE := "res://assets/audio/engine/%s/engine.ogg"
const GEARS := 4

var car: RaceCar

var _player: AudioStreamPlayer3D


func _ready() -> void:
	var path := PATH_TEMPLATE % car.def.engine_sound
	if not ResourceLoader.exists(path):
		set_process(false)
		return
	_player = AudioStreamPlayer3D.new()
	_player.stream = load(path) as AudioStream
	RaceCar._set_ogg_loop(_player.stream)
	_player.bus = "Engine"
	_player.unit_size = 14.0
	_player.max_db = 3.0
	add_child(_player)
	_player.play()


func _process(_delta: float) -> void:
	var fwd := -car.global_transform.basis.z
	var ratio := clampf(car.velocity.dot(fwd) / car.def.max_speed, 0.0, 1.0)
	var gear_pos := ratio * GEARS
	var local := gear_pos - floorf(gear_pos)  # 0..1 inside the current gear
	_player.pitch_scale = 0.75 + local * 0.9 + ratio * 0.2
	_player.volume_db = lerpf(-8.0, 0.0, clampf(local + ratio * 0.4, 0.0, 1.0))
