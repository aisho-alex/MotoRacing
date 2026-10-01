extends SceneTree
## Dev tool: close-up of the procedural Skeleton3D rider, with pose/IK checks.
## env: BIKE=0..4 POSE=idle|punch|kick|crash OUT=path AZ=deg DIST=m
## Run under xvfb-run.

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
	var bike = root.find_child("Bike", true, false)
	if bike == null or bike.rider == null:
		push_error("no rider")
		quit(1)
		return
	var pose := OS.get_environment("POSE")
	if pose != "":
		if pose == "crash":
			bike._start_wipeout()
			await create_timer(0.55).timeout
		elif pose == "kick":
			bike.rider.attack(-1.0, "kick")
			await create_timer(0.16).timeout
		elif pose == "punch":
			bike.rider.attack(1.0, "punch")
			await create_timer(0.16).timeout

	var sk: Skeleton3D = bike.rider.get_node("Skeleton")
	for bn in ["Hand.L", "Hand.R", "Foot.L", "Foot.R"]:
		var i := sk.find_bone(bn)
		if i >= 0:
			print("BONE %-8s rider_local=%s" % [bn, sk.get_bone_global_pose(i).origin])

	var c: Vector3 = bike.rider.global_position
	var basis: Basis = bike.global_transform.basis.orthonormalized()
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.make_current()
	var az := deg_to_rad(float(OS.get_environment("AZ"))) if OS.get_environment("AZ") != "" else deg_to_rad(90.0)
	var dist := float(OS.get_environment("DIST")) if OS.get_environment("DIST") != "" else 2.4
	var elev := float(OS.get_environment("ELEV")) if OS.get_environment("ELEV") != "" else 1.05
	# offsets are in bike space: x = left(+), y = up, z = back(+); -Z is forward
	cam.global_position = c + basis * Vector3(sin(az) * dist, elev, cos(az) * dist)
	cam.look_at(c + basis * Vector3(0.0, 0.45, 0.0), Vector3.UP)
	cam.fov = 50
	await process_frame
	await process_frame
	await process_frame
	var out := OS.get_environment("OUT")
	if out.is_empty():
		out = "/tmp/opencode/rider_shot.png"
	root.get_texture().get_image().save_png(out)
	print("saved ", out)
	quit(0)
