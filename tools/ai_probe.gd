extends SceneTree
## AI diagnostic probe: race with the player parked, per-AI counters at
## game-time checkpoints. TRACK=0..3, TIME_SCALE, SOLO=n, PROBE_SECONDS.
## Metrics: metric (laps+progress), teleports (watchdog), wall_hits
## (contact frames), avg vf (m/s over the run).

var _setup_done := false
var _game_time := 0.0
var _next_check := 10.0
var _probe_seconds := 60.0
var _main: Node
var _crawl := false
var _crawl_f := 0.0
var _crawl_start := 0


func _process(delta: float) -> bool:
	if not _setup_done:
		_setup_done = true
		if OS.get_environment("TIME_SCALE") != "":
			Engine.time_scale = float(OS.get_environment("TIME_SCALE"))
		if OS.get_environment("PROBE_SECONDS") != "":
			_probe_seconds = float(OS.get_environment("PROBE_SECONDS"))
		_crawl = OS.get_environment("CRAWL") == "1"
		var game := root.get_node_or_null("/root/Game")
		if game != null and OS.get_environment("TRACK") != "":
			game.track_index = int(OS.get_environment("TRACK"))
		_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
		root.add_child(_main)
		if OS.get_environment("AUTO") == "1":
			var bike = _main.get("bike")
			var track2 = _main.get("track")
			var d = load("res://scripts/ai_driver.gd").new(track2, 1.0, 0.0)
			d.speed_mult = float(OS.get_environment("AUTO_PACE")) if OS.get_environment("AUTO_PACE") != "" else 1.2
			d.resync(bike)
			bike.driver = d
			bike.control_enabled = true
		return false
	_game_time += delta
	if _crawl:
		_crawl_player(delta)
	if _main != null:
		for r in _main.racers:
			if not r.player:
				r["vf_sum"] = r.get("vf_sum", 0.0) + r.bike.velocity.length() * delta
	if _game_time >= _next_check:
		_report()
		_next_check += 10.0
		if _next_check > _probe_seconds:
			return true
	return false


## CRAWL=1: teleport the parked player slowly along the centerline so the AI
## behind it has to overtake (the rivalry scenario under test).
func _crawl_player(_delta: float) -> void:
	if _main == null or _main.track == null:
		return
	var bike = _main.bike
	var n: int = _main.track.sample_count()
	if _crawl_start == 0:
		_crawl_start = 35  # ahead of the AI grid (samples 10/18/26)
	var i: int = (_crawl_start + int(_crawl_f)) % n
	bike.global_position = _main.track.centerline[i] + Vector3.UP * 0.6
	bike.rotation = Vector3(0.0, _main.track.tangent_yaw(i), 0.0)
	bike.velocity = -bike.global_transform.basis.z * 8.0
	_crawl_f += 8.0 / maxf(_main.track.sample_spacing(i), 0.5) * _delta


func _report() -> void:
	print("=== t=%.0fs" % _game_time)
	for r in _main.racers:
		var bike = r.bike
		var prog = r.progress
		if not r.player:
			prog.update()
		if r.player:
			print("%s pos=(%.0f,%.0f) vf=%5.1f metric=%.2f" % [bike.name,
				bike.global_position.x, bike.global_position.z, bike.velocity.length(),
				_main.tracker.progress_metric()])
		else:
			var drv = bike.driver
			print("%s vf=%5.1f metric=%.2f sm=%.2f tp=%d ws=%d wall=%d w/r/d/n=%d/%d/%d/%d i=%d y=%.1f avg=%.1f" % [
				bike.name, bike.velocity.length(), prog.progress_metric(), drv.speed_mult,
				drv.teleports, drv.wrong_snaps, drv.wall_hits,
				drv.frames_wrong, drv.frames_reverse, drv.frames_detour, drv.frames_normal,
				drv._nearest, bike.global_position.y,
				r.get("vf_sum", 0.0) / maxf(_game_time, 1.0)])
