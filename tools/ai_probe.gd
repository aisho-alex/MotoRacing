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


func _process(delta: float) -> bool:
	if not _setup_done:
		_setup_done = true
		if OS.get_environment("TIME_SCALE") != "":
			Engine.time_scale = float(OS.get_environment("TIME_SCALE"))
		if OS.get_environment("PROBE_SECONDS") != "":
			_probe_seconds = float(OS.get_environment("PROBE_SECONDS"))
		var game := root.get_node_or_null("/root/Game")
		if game != null and OS.get_environment("TRACK") != "":
			game.track_index = int(OS.get_environment("TRACK"))
		_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
		root.add_child(_main)
		return false
	_game_time += delta
	if _main != null:
		for r in _main.racers:
			if not r.player:
				r["vf_sum"] = r.get("vf_sum", 0.0) + r.car.velocity.length() * delta
	if _game_time >= _next_check:
		_report()
		_next_check += 10.0
		if _next_check > _probe_seconds:
			return true
	return false


func _report() -> void:
	print("=== t=%.0fs" % _game_time)
	for r in _main.racers:
		var car = r.car
		var prog = r.progress
		if not r.player:
			prog.update()
		if r.player:
			print("%s pos=(%.0f,%.0f) vf=%5.1f" % [car.name,
				car.global_position.x, car.global_position.z, car.velocity.length()])
		else:
			var drv = car.driver
			print("%s vf=%5.1f metric=%.2f tp=%d ws=%d wall=%d w/r/d/n=%d/%d/%d/%d i=%d y=%.1f avg=%.1f" % [
				car.name, car.velocity.length(), prog.progress_metric(),
				drv.teleports, drv.wrong_snaps, drv.wall_hits,
				drv.frames_wrong, drv.frames_reverse, drv.frames_detour, drv.frames_normal,
				drv._nearest, car.global_position.y,
				r.get("vf_sum", 0.0) / maxf(_game_time, 1.0)])
