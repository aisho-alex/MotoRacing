extends SceneTree
var _setup_done := false
var _start_ms := 0


func _process(_delta: float) -> bool:
	if not _setup_done:
		_setup_done = true
		var main = load("res://scenes/main.tscn").instantiate()
		root.add_child(main)
		_start_ms = Time.get_ticks_msec()
		var cam := Camera3D.new()
		root.add_child(cam)
		cam.make_current()
		cam.global_position = Vector3(20, 9, -95)
		cam.look_at(Vector3(95, 10, -80), Vector3.UP)
		cam.fov = 55
	if Time.get_ticks_msec() - _start_ms >= 4000:
		var img := root.get_texture().get_image()
		img.save_png("/tmp/opencode/closeup_building.png")
		print("saved")
		return true
	return false
