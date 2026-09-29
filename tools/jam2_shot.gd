extends SceneTree
## Dev tool: top-down screenshot of the first-corner zone at ~14s game time.

var _setup_done := false
var _start_ms := 0
var _main: Node
var _game_time := 0.0


func _process(delta: float) -> bool:
	if not _setup_done:
		_setup_done = true
		var game := root.get_node_or_null("/root/Game")
		if game != null and OS.get_environment("TRACK") != "":
			game.track_index = int(OS.get_environment("TRACK"))
		_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
		root.add_child(_main)
		_start_ms = Time.get_ticks_msec()
		var cam := Camera3D.new()
		root.add_child(cam)
		cam.make_current()
		cam.global_position = Vector3(50, 85, -100)
		cam.look_at(Vector3(50, 0, -92), Vector3.FORWARD)
		cam.fov = 65
	_game_time += delta
	if _game_time >= 14.0:
		var img := root.get_texture().get_image()
		img.save_png("/tmp/opencode/jam3.png")
		print("saved /tmp/opencode/jam3.png t=", _game_time)
		return true
	return false
