extends SceneTree
## Dev tool: screenshot of the start-area jam ~12s into a race.

var _setup_done := false
var _start_ms := 0
var _main: Node


func _process(_delta: float) -> bool:
	if not _setup_done:
		_setup_done = true
		var game := root.get_node_or_null("/root/Game")
		if game != null and OS.get_environment("TRACK") != "":
			game.track_index = int(OS.get_environment("TRACK"))
		_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
		root.add_child(_main)
		_start_ms = Time.get_ticks_msec()
		return false
	if Time.get_ticks_msec() - _start_ms >= 12000:
		var cam := Camera3D.new()
		root.add_child(cam)
		cam.make_current()
		cam.global_position = Vector3(-20, 50, -98)
		cam.look_at(Vector3(-15, 0, -95), Vector3.FORWARD)
		cam.fov = 55
		var img := root.get_texture().get_image()
		img.save_png("/tmp/opencode/jam_shot.png")
		print("saved /tmp/opencode/jam_shot.png")
		return true
	return false
