extends SceneTree
## Dev tool: boots the race and takes a 3/4 side close-up of the player bike.
## OUT=path WAIT_MS=ms

var _done := false


func _process(_delta: float) -> bool:
	if _done:
		return false
	_done = true
	_run()
	return false


func _run() -> void:
	var game := root.get_node_or_null("/root/Game")
	if game != null and OS.get_environment("BIKE") != "":
		game.bike_index = int(OS.get_environment("BIKE"))
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var wait := int(OS.get_environment("WAIT_MS")) if OS.get_environment("WAIT_MS") != "" else 2600
	await create_timer(wait / 1000.0).timeout
	var node_name := OS.get_environment("NODE")
	if node_name.is_empty():
		node_name = "Bike"
	var bike = root.find_child(node_name, true, false)
	if bike == null:
		push_error("no " + node_name)
		quit(1)
		return
	# optional combat/wipeout pose for inspection: POSE=punch|kick|crash|eject|getup|run|lift|mount
	var pose := OS.get_environment("POSE")
	if pose != "":
		var wipe_pose := {"crash": 0.7, "eject": 0.45, "getup": 1.05, "run": 1.9,
			"lift": 2.9, "mount": 3.7}
		if wipe_pose.has(pose):
			bike._start_wipeout()
			await create_timer(float(wipe_pose[pose])).timeout
		elif pose == "kick":
			bike.rider.attack(-1.0, "kick")
			await create_timer(0.16).timeout
		else:
			bike.rider.attack(1.0, "punch")
			await create_timer(0.16).timeout
	# report wheels
	var stack: Array[Node] = [bike]
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
	var c: Vector3 = bike.global_position
	cam.global_position = c + Vector3(4.0, 1.6, -3.2)
	cam.look_at(c + Vector3(0, 0.5, 0), Vector3.UP)
	cam.fov = 55
	await process_frame
	await process_frame
	await process_frame
	var out := OS.get_environment("OUT")
	if out.is_empty():
		out = "/tmp/opencode/bike_close.png"
	root.get_texture().get_image().save_png(out)
	print("saved ", out)
	quit(0)
