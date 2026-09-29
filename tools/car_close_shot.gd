extends SceneTree
## Dev tool: boots the race and takes a 3/4 side close-up of the player car.
## OUT=path WAIT_MS=ms

var _done := false


func _process(_delta: float) -> bool:
	if _done:
		return false
	_done = true
	_run()
	return false


func _run() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var wait := int(OS.get_environment("WAIT_MS")) if OS.get_environment("WAIT_MS") != "" else 2600
	await create_timer(wait / 1000.0).timeout
	var car = root.find_child("Car", true, false)
	if car == null:
		push_error("no Car")
		quit(1)
		return
	# report wheels
	var stack: Array[Node] = [car]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is Node3D and n.name.to_lower().contains("wheel"):
			var w := n as Node3D
			print("WHEEL ", w.name, " global=", w.global_transform.origin,
				" scale=", w.global_transform.basis.get_scale())
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.make_current()
	var c: Vector3 = car.global_position
	cam.global_position = c + Vector3(4.0, 1.6, -3.2)
	cam.look_at(c + Vector3(0, 0.5, 0), Vector3.UP)
	cam.fov = 55
	await process_frame
	await process_frame
	await process_frame
	var out := OS.get_environment("OUT")
	if out.is_empty():
		out = "/tmp/opencode/car_close.png"
	root.get_texture().get_image().save_png(out)
	print("saved ", out)
	quit(0)
