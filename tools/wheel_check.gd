extends SceneTree
## Dev tool: verifies car.gd wheel math offline. Loads a car body.glb, applies
## the same spin/steer transform as RaceCar._update_wheels with configurable
## angles, and screenshots a closeup of the front-left wheel.
## GLB=res://assets/cars/sport_01/body.glb SPIN=120 STEER=25 OUT=/tmp/x.png

func _process(_delta: float) -> bool:
	_run()
	return false


func _run() -> void:
	var path := OS.get_environment("GLB")
	if path.is_empty():
		path = "res://assets/cars/sport_01/body.glb"
	var spin := deg_to_rad(float(OS.get_environment("SPIN")) if OS.get_environment("SPIN") != "" else 0.0)
	var steer := deg_to_rad(float(OS.get_environment("STEER")) if OS.get_environment("STEER") != "" else 0.0)
	var out := OS.get_environment("OUT")
	if out.is_empty():
		out = "/tmp/opencode/wheel_check.png"

	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_file(path, state)
	if err != OK:
		push_error("load fail %s" % err)
		quit(1)
		return
	var model := doc.generate_scene(state)
	var holder := Node3D.new()
	# same convention as RaceCar: model_yaw aligns model forward with -Z
	var yaw := float(OS.get_environment("YAW")) if OS.get_environment("YAW") != "" else PI
	holder.rotation.y = yaw
	holder.add_child(model)
	root.add_child(holder)

	# find corner wheels like car.gd does
	var wheels: Array[Node3D] = []
	var fronts: Array[Node3D] = []
	var stack: Array[Node] = [model]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is Node3D and n.name.to_lower().contains("wheel"):
			wheels.append(n)
			var l := n.name.to_lower()
			if l.ends_with("fl") or l.ends_with("fr") or l.contains("front"):
				fronts.append(n)
	if wheels.is_empty():
		push_error("no wheels found")
		quit(1)
		return

	if OS.get_environment("NOBODY") == "1":
		for mi in model.find_children("*", "MeshInstance3D", true, false):
			var under := false
			for c in wheels:
				if c == mi or c.is_ancestor_of(mi):
					under = true
					break
			if not under:
				(mi as MeshInstance3D).visible = false
	# same scheme as RaceCar._update_wheels: rebuild each wheel into a clean
	# hub frame (car orientation + hub translation), compensate children,
	# then apply spin/steer as pure rotations around car right/up axes
	var hinv := holder.global_transform.affine_inverse()
	var hubs: Array[Vector3] = []
	for w in wheels:
		var w3 := w as Node3D
		var hub_rel := hinv * w3.global_transform.origin
		var old_world := w3.global_transform
		w3.global_transform = holder.global_transform * Transform3D(Basis.IDENTITY, hub_rel)
		var new_local_inv := w3.transform.affine_inverse()
		for c in w3.get_children():
			if c is Node3D:
				(c as Node3D).transform = new_local_inv * old_world * (c as Node3D).transform
		hubs.append(hub_rel)
	for i in wheels.size():
		var steer_angle := steer if wheels[i] in fronts else 0.0
		var rot := Basis(Quaternion(Vector3.UP, steer_angle) * Quaternion(Vector3.RIGHT, spin))
		(wheels[i] as Node3D).global_transform = holder.global_transform * Transform3D(rot, hubs[i])

	# frame the front-left wheel
	var target: Node3D = fronts[0] if fronts.size() > 0 else wheels[0]
	var center: Vector3 = target.global_transform.origin
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.make_current()
	var dist := 1.4 if OS.get_environment("NOBODY") == "1" else 2.4
	cam.global_position = center + Vector3(dist, 0.15, 0.0)
	cam.look_at(center, Vector3.UP)
	cam.near = 0.05
	var sun := DirectionalLight3D.new()
	root.add_child(sun)
	sun.rotation_degrees = Vector3(-45, -140, 0)
	sun.light_energy = 1.3
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.2, 0.22, 0.25)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.85, 0.85, 0.9)
	e.ambient_light_energy = 0.8
	env.environment = e
	root.add_child(env)
	await process_frame
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png(out)
	print("saved ", out, " wheels=", wheels.size(), " fronts=", fronts.size())
	quit(0)
