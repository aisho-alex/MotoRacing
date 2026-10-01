class_name RacerProgress
extends RefCounted
## Lightweight per-bike progress along the track (nearest sample + lap count),
## used for live race positions of AI opponents.

const WINDOW := 30

var bike: RaceBike
var track: TrackBuilder
var laps := 0

var _nearest := 0
var _prog := 0.0
var _passed_half := false


func reset() -> void:
	var p := _flat(bike.global_position)
	var best := INF
	var best_i := 0
	for i in track.sample_count():
		var d := _flat(track.centerline[i]).distance_squared_to(p)
		if d < best:
			best = d
			best_i = i
	_nearest = best_i
	_prog = float(best_i) / float(track.sample_count())
	_passed_half = false
	laps = 0


func progress_metric() -> float:
	return float(laps) + _prog


func update() -> void:
	var p := _flat(bike.global_position)
	var n := track.sample_count()
	var best := INF
	var best_i := _nearest
	for k in range(-WINDOW, WINDOW + 1):
		var i := (_nearest + k + n) % n
		var d := _flat(track.centerline[i]).distance_squared_to(p)
		if d < best:
			best = d
			best_i = i
	_nearest = best_i
	var new_prog := float(best_i) / float(n)
	# Same anti-cut rule as LapTracker: a lap only counts if the rider actually
	# passed the far half of the track, so teleports / corner cuts cannot farm it.
	if new_prog > 0.4 and new_prog < 0.6:
		_passed_half = true
	if _prog > 0.8 and new_prog < 0.2:
		if _passed_half:
			laps += 1
		_passed_half = false
	elif _prog < 0.2 and new_prog > 0.8 and laps > 0:
		laps -= 1
		_passed_half = false
	_prog = new_prog


static func _flat(p: Vector3) -> Vector2:
	return Vector2(p.x, p.z)
