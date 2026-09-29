extends SceneTree
## Dev tool: renders preview screenshots of GLB files from a directory.
## DIR=/path/to/glbs OUT=/path/to/prefix
## Each *.glb gets a framed 3/4-view shot saved as OUT_<name>.png.

var _queue: Array[String] = []
var _out := "/tmp/opencode/asset"
var _done := false


func _process(_delta: float) -> bool:
	if _done:
		return false
	_done = true
	var dir := OS.get_environment("DIR")
	if dir.is_empty():
		dir = "/tmp/opencode/carpool/cars20/GLTF"
	var out := OS.get_environment("OUT")
	if not out.is_empty():
		_out = out
	var d := DirAccess.open(dir)
	if d == null:
		push_error("no dir %s" % dir)
		quit(1)
		return true
	for f in d.get_files():
		if f.to_lower().ends_with(".glb"):
			_queue.append(dir.path_join(f))
	_queue.sort()
	if _queue.is_empty():
		quit(0)
		return true
	_next()
	return false


func _next() -> void:
	if _queue.is_empty():
		quit(0)
		return
	var path: String = _queue.pop_front()
	var node := _load_glb(path)
	if node == null:
		push_warning("cannot load %s" % path)
		_next()
		return
	root.add_child(node)
	# compute world AABB
	var aabb := AABB()
	var first := true
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var mi3 := mi as MeshInstance3D
		var ab: AABB = mi3.global_transform * mi3.get_aabb()
		if first:
			aabb = ab
			first = false
		else:
			aabb = aabb.merge(ab)
	if first:
		aabb = AABB(Vector3(-1, 0, -1), Vector3(2, 1, 2))
	var center := aabb.get_center()
	var radius: float = maxf(aabb.size.length() * 0.5, 0.1)
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.make_current()
	var dirv := Vector3(1.0, 0.55, 1.0).normalized()
	cam.global_position = center + dirv * radius * 2.2
	cam.look_at(center, Vector3.UP)
	cam.near = 0.01
	cam.far = radius * 20.0
	var sun := DirectionalLight3D.new()
	root.add_child(sun)
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.light_energy = 1.2
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.22, 0.24, 0.27)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.8, 0.8, 0.85)
	e.ambient_light_energy = 0.7
	env.environment = e
	root.add_child(env)
	await process_frame
	await process_frame
	await process_frame
	var img := root.get_texture().get_image()
	var base := path.get_file().get_basename().replace(" ", "_")
	img.save_png("%s_%s.png" % [_out, base])
	print("shot %s (%d tris)" % [base, _count_tris(node)])
	for n in [cam, sun, env]:
		n.queue_free()
	node.queue_free()
	await process_frame
	await process_frame
	_next()


func _load_glb(path: String) -> Node3D:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_file(path, state)
	if err != OK:
		return null
	var node := doc.generate_scene(state)
	if node is Node3D:
		return node
	var holder := Node3D.new()
	holder.add_child(node)
	return holder


func _count_tris(node: Node) -> int:
	var t := 0
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var m: Mesh = (mi as MeshInstance3D).mesh
		if m != null:
			for s in m.get_surface_count():
				t += m.surface_get_arrays(s)[Mesh.ARRAY_INDEX].size() / 3 if m.surface_get_arrays(s)[Mesh.ARRAY_INDEX] != null else 0
	return t
