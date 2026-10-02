extends SceneTree
## Dev tool: close-up of a cartoon streetlight (pole/head/lens/halo).
## env: BIKE=0..9 WAIT_MS=2600 DIST=4 ELEV=1.5 OUT=path
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
	var lights = root.find_child("StreetLights", true, false)
	if lights == null:
		push_error("no StreetLights")
		quit(1)
		return
	# The lens is the emissive mesh; frame the first one above head height.
	var target: MeshInstance3D = null
	for c in lights.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		var mat := mi.material_override
		if mat == null and mi.mesh is BoxMesh:
			mat = (mi.mesh as BoxMesh).material
		if mat is StandardMaterial3D and (mat as StandardMaterial3D).emission_enabled \
				and mi.global_position.y > 5.0:
			target = mi
			break
	if target == null:
		push_error("no lamp lens found")
		quit(1)
		return
	var p := target.global_position
	var dist := float(OS.get_environment("DIST")) if OS.get_environment("DIST") != "" else 4.0
	var elev := float(OS.get_environment("ELEV")) if OS.get_environment("ELEV") != "" else 1.5
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.make_current()
	cam.global_position = p + Vector3(dist, elev, dist)
	cam.look_at(p, Vector3.UP)
	cam.fov = 45
	await process_frame
	await process_frame
	await process_frame
	var out := OS.get_environment("OUT")
	if out.is_empty():
		out = "/tmp/opencode/streetlight_shot.png"
	root.get_texture().get_image().save_png(out)
	print("saved ", out, " at ", p)
	quit(0)
