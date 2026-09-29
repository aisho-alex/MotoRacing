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
		cam.global_position = Vector3(30, 7, -100)
		cam.look_at(Vector3(90, 12, -85), Vector3.UP)
		cam.fov = 60
	if Time.get_ticks_msec() - _start_ms >= 4000:
		var img := root.get_texture().get_image()
		img.save_png("/tmp/opencode/buildings_close.png")
		print("saved")
		return true
	return false
