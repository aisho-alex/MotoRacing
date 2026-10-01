class_name LapTracker
extends Node
## Tracks the bike's progress along the track centerline, counts laps,
## measures lap times and detects backwards crossing / cutting.

signal lap_changed(current_lap: int, total_laps: int)
signal lap_finished(lap_time: float, best_time: float)
signal race_finished(total_time: float)

const TOTAL_LAPS := 3
const SEARCH_WINDOW := 30
## Respawn points are only stored while the bike is this close to the road edge
## (slightly wider than RaceBike.OFFROAD_LIMIT so a brief excursion does not
## leave a stale respawn point behind).
const SAFE_ROAD_MARGIN := 2.0

var track: TrackBuilder
var bike: RaceBike

var racing := false
var finished := false
var laps_done := 0
var lap_time := 0.0
var total_time := 0.0
var best_lap := -1.0
var last_lap := -1.0

var _passed_half := false
var _last_progress := 0.0
var _last_index := 0


func setup(track_ref: TrackBuilder, bike_ref: RaceBike) -> void:
	track = track_ref
	bike = bike_ref
	_full_rescan()


func start_race() -> void:
	racing = true


func reset() -> void:
	racing = false
	finished = false
	laps_done = 0
	lap_time = 0.0
	total_time = 0.0
	best_lap = -1.0
	last_lap = -1.0
	_passed_half = false
	_full_rescan()
	lap_changed.emit(1, TOTAL_LAPS)


func current_lap() -> int:
	return clampi(laps_done + 1, 1, TOTAL_LAPS)


## Live race position metric: laps done + fraction of the lap.
func progress_metric() -> float:
	if track == null:
		return 0.0
	return float(laps_done) + float(_last_index) / float(track.sample_count())


func _physics_process(delta: float) -> void:
	if track == null or bike == null:
		return
	_update_nearest()
	if racing and not finished:
		lap_time += delta
		total_time += delta

	var prog := float(_last_index) / float(track.sample_count())
	if prog > 0.4 and prog < 0.6:
		_passed_half = true
	if _last_progress > 0.8 and prog < 0.2:
		if _passed_half and racing and not finished:
			_cross_finish_line()
		_passed_half = false
	elif _last_progress < 0.2 and prog > 0.8:
		_passed_half = false
	_last_progress = prog


func road_distance_to(p: Vector3) -> float:
	var pp := Vector2(p.x, p.z)
	var best := INF
	var n := track.sample_count()
	for k in range(-SEARCH_WINDOW, SEARCH_WINDOW + 1):
		var i := (_last_index + k + n) % n
		var d := _flat(track.centerline[i]).distance_squared_to(pp)
		if d < best:
			best = d
	return sqrt(best)


static func _flat(p: Vector3) -> Vector2:
	return Vector2(p.x, p.z)


func _update_nearest() -> void:
	var p := _flat(bike.global_position)
	var n := track.sample_count()
	var best := INF
	var best_i := _last_index
	for k in range(-SEARCH_WINDOW, SEARCH_WINDOW + 1):
		var i := (_last_index + k + n) % n
		var d := _flat(track.centerline[i]).distance_squared_to(p)
		if d < best:
			best = d
			best_i = i
	if best > 625.0:  # bike is far from the expected window: full scan
		best_i = _full_rescan()
		best = _flat(track.centerline[best_i]).distance_squared_to(p)
	_last_index = best_i
	if best < (track.def.road_half_width + SAFE_ROAD_MARGIN) * (track.def.road_half_width + SAFE_ROAD_MARGIN):
		var yaw := track.tangent_yaw(best_i)
		var xf := Transform3D(Basis(Vector3.UP, yaw), track.centerline[best_i] + Vector3.UP * 0.6)
		bike.last_safe_transform = xf


func _full_rescan() -> int:
	var p := _flat(bike.global_position)
	var best := INF
	var best_i := 0
	for i in track.sample_count():
		var d := _flat(track.centerline[i]).distance_squared_to(p)
		if d < best:
			best = d
			best_i = i
	_last_index = best_i
	_last_progress = float(best_i) / float(track.sample_count())
	return best_i


func _cross_finish_line() -> void:
	last_lap = lap_time
	if best_lap < 0.0 or lap_time < best_lap:
		best_lap = lap_time
	lap_time = 0.0
	laps_done += 1
	lap_finished.emit(last_lap, best_lap)
	if laps_done >= TOTAL_LAPS:
		finished = true
		racing = false
		race_finished.emit(total_time)
	else:
		lap_changed.emit(current_lap(), TOTAL_LAPS)
