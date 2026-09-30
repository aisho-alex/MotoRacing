extends SceneTree
## Dev tool: renders traffic cars with their BikeDef.model_yaw applied and a
## red arrow pointing to -Z (the direction a correctly oriented car faces).
## Top view: arrow up = forward. Usage:
##   xvfb-run godot --path . -s tools/car_orient_shot.gd
## Also respects CAR_ID to shoot a single model.

var _started := false


func _process(_d: float) -> bool:
	if not _started:
		_started = true
		_run()
	return false


func _run() -> void:
	var only := OS.get_environment("CAR_ID")
	var ids := ["traffic_sedan", "traffic_taxi", "traffic_van", "traffic_wagon1", "traffic_wagon2"]
	if only != "":
		ids = [only]
	for id in ids:
		await _shoot(id)
	quit(0)


func _shoot(id: String) -> void:
	var def := load("res://assets/data/traffic/%s.tres" % id) as BikeDef
	if def == null:
		push_error("no def %s" % id)
		return
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(def.model_path, state) != OK:
		push_error("load fail %s" % def.model_path)
		return
	var model := doc.generate_scene(state)
	var holder := Node3D.new()
	holder.name = "Model"
	holder.rotation.y = def.model_yaw
	holder.scale = Vector3.ONE * def.model_scale
	holder.add_child(model)
	root.add_child(holder)

	var aabb := AABB()
	var first := true
	for n in holder.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var ab: AABB = mi.global_transform * mi.get_aabb()
		aabb = ab if first else aabb.merge(ab)
		first = false
	var c := aabb.get_center()
	var reach: float = maxf(aabb.size.z * 0.5 + 1.2, 2.0)

	# red arrow in WORLD space: always points to -Z (the forward a correct
	# orientation must face). Drawn above the car so the top view shows it.
	var shaft := BoxMesh.new()
	shaft.size = Vector3(0.1, 0.05, reach)
	shaft.material = _mat()
	var sm := MeshInstance3D.new()
	sm.mesh = shaft
	sm.position = Vector3(0, aabb.size.y + 0.6, -reach * 0.5)
	sm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(sm)
	var tip := SphereMesh.new()
	tip.radius = 0.18
	tip.height = 0.36
	tip.material = _mat()
	var tm := MeshInstance3D.new()
	tm.mesh = tip
	tm.position = Vector3(0, aabb.size.y + 0.6, -reach)
	root.add_child(tm)

	var cam := Camera3D.new()
	root.add_child(cam)
	cam.make_current()
	cam.global_position = c + Vector3(0, reach * 3.0, 0.001)
	cam.look_at(c, Vector3.FORWARD)
	cam.fov = 60
	var front_cam := Camera3D.new()
	root.add_child(front_cam)
	front_cam.global_position = c + Vector3(0, aabb.size.y * 0.8 + 0.8, -reach * 2.2)
	front_cam.look_at(c, Vector3.UP)
	front_cam.fov = 55
	var sun := DirectionalLight3D.new()
	root.add_child(sun)
	sun.rotation_degrees = Vector3(-70, -30, 0)
	sun.light_energy = 1.4
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.16, 0.17, 0.2)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.9, 0.9, 0.95)
	e.ambient_light_energy = 1.0
	env.environment = e
	root.add_child(env)
	await process_frame
	await process_frame
	await process_frame
	var path := "/tmp/opencode/orient_%s.png" % id
	root.get_texture().get_image().save_png(path)
	front_cam.make_current()
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png("/tmp/opencode/orient_%s_front.png" % id)
	print("shot %s yaw=%.4f pos=%s saved %s" % [id, def.model_yaw, str(c.round()), path])
	for n in [cam, front_cam, sun, env, holder]:
		n.queue_free()
	await process_frame


func _mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.95, 0.1, 0.1)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m
