class_name PoliceManager
extends Node
## Road Rash police: after a delay a cop bike joins the race and hunts the
## player. If the player is slow while the cop is close, they are BUSTED (race
## over, no prize). Knocking the cop down pays a small bonus; the cop remounts
## and resumes the chase.

signal busted
signal cop_down(bonus: int)

const SPAWN_DELAY := 18.0
const BUST_SPEED := 6.0      # m/s; below this near a cop counts as "caught"
const BUST_TIME := 2.5
const BUST_RANGE := 7.5
const COP_BONUS := 150
const COP_DEF_PATH := "res://assets/data/bikes/cop_01.tres"
const FLASH_TIME := 0.3

var track: TrackBuilder
var player: RaceBike
var racers: Array = []       # rider bikes (player + AI), for the cop's combat
var cop: RaceBike = null

var active := false
var _elapsed := 0.0
var _spawned := false
var _bust_timer := 0.0
var _hunt := false
var _flash_t := 0.0
var _flash_on := false
var _light: OmniLight3D = null
var _strobes: Array[MeshInstance3D] = []


func setup(track_ref: TrackBuilder, player_ref: RaceBike, racers_ref: Array) -> void:
	track = track_ref
	player = player_ref
	racers = racers_ref


func start() -> void:
	active = true
	_elapsed = 0.0
	_spawned = false
	_bust_timer = 0.0
	_hunt = false


func stop() -> void:
	active = false
	_hunt = false


## Remove the cop (restart): the next start() spawns a fresh one.
func clear() -> void:
	active = false
	_hunt = false
	_spawned = false
	_elapsed = 0.0
	_bust_timer = 0.0
	if cop != null and is_instance_valid(cop):
		cop.queue_free()
	cop = null
	_light = null
	_strobes.clear()


func is_hunting() -> bool:
	return _hunt and cop != null and is_instance_valid(cop)


## Spawn delay, overridable for dev/testing via the POLICE_DELAY env var.
func _spawn_delay() -> float:
	var e := OS.get_environment("POLICE_DELAY")
	return float(e) if e != "" else SPAWN_DELAY


func _process(delta: float) -> void:
	if not active:
		return
	_elapsed += delta
	if not _spawned and _elapsed >= _spawn_delay():
		_spawn()
	_flash(delta)
	if cop == null or not is_instance_valid(cop):
		return
	_hunt = true
	if player == null or not is_instance_valid(player):
		return
	var dist := cop.global_position.distance_to(player.global_position)
	var caught := dist < BUST_RANGE and player.velocity.length() < BUST_SPEED
	if caught:
		_bust_timer += delta
		if _bust_timer >= BUST_TIME:
			_bust_timer = 0.0
			active = false
			_hunt = false
			busted.emit()
	else:
		_bust_timer = maxf(_bust_timer - delta, 0.0)


func _spawn() -> void:
	_spawned = true
	var def: BikeDef = null
	if ResourceLoader.exists(COP_DEF_PATH):
		def = load(COP_DEF_PATH) as BikeDef
	if def == null:
		def = BikeDef.load_default()
	var n := track.sample_count()
	var back := ((_player_index() - 14) % n + n) % n
	cop = RaceBike.new()
	cop.name = "Police"
	cop.def = def
	cop.is_opponent = true
	cop.night_lights = track.def.night_racing
	cop.road_half_width = track.def.road_half_width
	add_child(cop)
	var pos := track.centerline[back] + track.side_vector(back) * 2.0
	var yaw := track.tangent_yaw(back)
	cop.reset_to(pos, yaw)
	var driver := AiDriver.new(track, 1.0, 2.0)
	driver.speed_mult = 1.18
	driver.aggression = 0.95
	driver.chase = player
	var all := racers.duplicate()
	all.append(cop)
	driver.bikes = all
	driver.resync(cop)
	cop.driver = driver
	cop.combat_targets = all
	cop.control_enabled = true
	cop.wiped_out.connect(_on_cop_wiped)
	_build_strobes(cop)


func _player_index() -> int:
	var best := INF
	var idx := 0
	var p := player.global_position
	for i in track.sample_count():
		var d := track.centerline[i].distance_squared_to(p)
		if d < best:
			best = d
			idx = i
	return idx


func _build_strobes(host: RaceBike) -> void:
	_light = OmniLight3D.new()
	_light.position = Vector3(0.0, 1.45, 0.15)
	_light.omni_range = 11.0
	_light.light_energy = 2.2
	_light.shadow_enabled = false
	host.add_child(_light)
	for x in [-0.14, 0.14]:
		var m := SphereMesh.new()
		m.radius = 0.08
		m.height = 0.16
		m.radial_segments = 8
		m.rings = 5
		var mat := StandardMaterial3D.new()
		mat.emission_enabled = true
		mat.emission_energy_multiplier = 5.0
		m.material = mat
		var mi := MeshInstance3D.new()
		mi.mesh = m
		mi.position = Vector3(x, 1.5, 0.15)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		host.add_child(mi)
		_strobes.append(mi)


func _flash(delta: float) -> void:
	if _light == null:
		return
	_flash_t += delta
	if _flash_t >= FLASH_TIME:
		_flash_t = 0.0
		_flash_on = not _flash_on
	var col := Color(0.25, 0.35, 1.0) if _flash_on else Color(1.0, 0.12, 0.10)
	_light.light_color = col
	for i in _strobes.size():
		var mat := (_strobes[i].mesh as SphereMesh).material as StandardMaterial3D
		if mat != null:
			mat.albedo_color = col
			mat.emission = col


func _on_cop_wiped(_bike: RaceBike) -> void:
	cop_down.emit(COP_BONUS)
