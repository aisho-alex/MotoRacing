class_name TrafficManager
extends Node
## Road Rash traffic: slow civilian cars share the road with the riders. They
## are RaceBike instances with a GLB body and a low-speed lane driver; the
## player collides with them (a fast hit = wipeout). Spawned ahead along the
## track and recycled once the player leaves them far behind.

const DEF_IDS := ["traffic_sedan", "traffic_taxi", "traffic_van", "traffic_wagon1", "traffic_wagon2"]
const COUNT := 10
const SPAWN_MIN_AHEAD := 45.0
const SPAWN_MAX_AHEAD := 230.0
const KEEP_DISTANCE := 300.0
const LANES := [-2.7, 2.7]
const SPEED_MULT := 0.35

var track: TrackBuilder
var player: RaceBike
var cars: Array = []

var _rng := RandomNumberGenerator.new()
var _active := false
var _timer := 0.0


func setup(track_ref: TrackBuilder, player_ref: RaceBike) -> void:
	track = track_ref
	player = player_ref


func start() -> void:
	_active = true
	_rng.randomize()
	_timer = 0.0
	_maintain(true)


func stop() -> void:
	_active = false


func clear() -> void:
	for c in cars:
		if is_instance_valid(c):
			c.queue_free()
	cars.clear()


func _process(delta: float) -> void:
	if not _active:
		return
	_timer -= delta
	if _timer <= 0.0:
		_timer = 0.5
		_maintain(false)


func _maintain(initial: bool) -> void:
	# recycle cars the player has left far behind
	var kept: Array = []
	for c in cars:
		if not is_instance_valid(c):
			continue
		if c.global_position.distance_to(player.global_position) > KEEP_DISTANCE:
			c.queue_free()
		else:
			kept.append(c)
	cars = kept
	while cars.size() < COUNT:
		if not _spawn_one():
			break
	if initial:
		pass


func _spawn_one() -> bool:
	var n := track.sample_count()
	var pi := _player_index()
	for _attempt in 8:
		var ahead := _rng.randf_range(SPAWN_MIN_AHEAD, SPAWN_MAX_AHEAD)
		var steps := maxi(int(ahead / maxf(track.sample_spacing(pi), 0.5)), 6)
		var idx := (pi + steps) % n
		var lane: float = LANES[_rng.randi() % LANES.size()]
		var pos := track.centerline[idx] + track.side_vector(idx) * lane
		if pos.distance_to(player.global_position) < SPAWN_MIN_AHEAD:
			continue
		var def_id: String = DEF_IDS[_rng.randi() % DEF_IDS.size()]
		var path := "res://assets/data/traffic/%s.tres" % def_id
		if not ResourceLoader.exists(path):
			continue
		var def := load(path) as BikeDef
		if def == null:
			continue
		var car := RaceBike.new()
		car.name = "Traffic"
		car.def = def
		car.is_opponent = true
		car.road_half_width = track.def.road_half_width
		add_child(car)
		car.reset_to(pos, track.tangent_yaw(idx))
		var driver := AiDriver.new(track, 0.8, lane)
		driver.speed_mult = SPEED_MULT
		driver.aggression = 0.0
		driver.resync(car)
		car.driver = driver
		car.control_enabled = true
		cars.append(car)
		return true
	return false


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
