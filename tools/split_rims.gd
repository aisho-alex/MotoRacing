extends SceneTree
## Dev tool: splits rim geometry out of the baked body mesh into each corner
## wheel node, so car.gd's runtime wheel rotation spins the whole wheel.
## Only needed for models whose rims are baked into the body (DanielZ series).
## Run: GLB=path OUT=path godot -s tools/split_rims.gd


func _process(_delta: float) -> bool:
	_run()
	return false


func _is_corner(n: Node) -> bool:
	if n is MeshInstance3D:
		return false  # mesh nodes are wheel parts, not pivots
	var nm := n.name.to_lower()
	if not nm.contains("wheel") or nm.contains("steer"):
		return false
	for tag in ["_fl", "_fr", "_rl", "_rr", "_bl", "_br"]:
		if tag in nm:
			return true
	return false


func _run() -> void:
	var src := OS.get_environment("GLB")
	var dst := OS.get_environment("OUT")
	if src.is_empty() or dst.is_empty():
		push_error("GLB and OUT env required")
		quit(1)
		return
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(src, state) != OK:
		push_error("cannot load " + src)
		quit(1)
		return
	var model := doc.generate_scene(state)
	root.add_child(model)

	var corners: Array[Node3D] = []
	var stack: Array[Node] = [model]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is Node3D and _is_corner(n):
			corners.append(n)
	if corners.size() < 4:
		push_error("expected 4 corner wheel nodes, got %d" % corners.size())
		quit(1)
		return

	# hubs + pairing (nearest neighbor = same-axle partner)
	var hubs: Array[Vector3] = []
	for c in corners:
		hubs.append(c.global_transform.origin)
	var pair: Array[int] = []
	for i in hubs.size():
		var best_j := -1
		var best_d := INF
		for j in hubs.size():
			if j == i:
				continue
			var d := hubs[j].distance_to(hubs[i])
			if d < best_d:
				best_d = d
				best_j = j
		pair.append(best_j)

	# model center
	var model_aabb := AABB()
	var first := true
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var ab: AABB = (mi as Node3D).global_transform * (mi as MeshInstance3D).get_aabb()
		model_aabb = ab if first else model_aabb.merge(ab)
		first = false
	var model_center := model_aabb.get_center()

	# body meshes (not under a corner)
	var bodies: Array[MeshInstance3D] = []
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var under := false
		for c in corners:
			if c == mi or c.is_ancestor_of(mi):
				under = true
				break
		var mn2 := mi.name.to_lower()
		if not under and (mi as MeshInstance3D).mesh != null \
				and not (mn2.contains("caliper") or mn2.contains("brake")):
			bodies.append(mi)

	var moved_total := 0
	for mi in bodies:
		if not (mi.mesh is ArrayMesh):
			continue
		moved_total += _split_mesh(mi, corners, hubs, pair, model_center)
	print("moved faces: ", moved_total)

	if model.get_parent() != null:
		model.get_parent().remove_child(model)
	var out_doc := GLTFDocument.new()
	var out_state := GLTFState.new()
	if out_doc.append_from_scene(model, out_state) != OK:
		push_error("scene export failed")
		quit(1)
		return
	var bytes := out_doc.generate_buffer(out_state)
	var f := FileAccess.open(dst, FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()
	print("saved ", dst, " (", bytes.size() / 1024, " KB)")
	quit(0)


## Wheel owning this triangle: nearest hub by full distance, then disc test.
func _rim_target(c: Vector3, corners: Array[Node3D], hubs: Array[Vector3],
		pair: Array[int], model_center: Vector3) -> Node3D:
	var best_i := -1
	var best_d := INF
	for i in hubs.size():
		var d := hubs[i].distance_to(c)
		if d < best_d:
			best_d = d
			best_i = i
	if best_i < 0:
		return null
	var hub := hubs[best_i]
	var axle := hubs[pair[best_i]] - hub
	if axle.length() < 0.01:
		return null
	axle = axle.normalized()
	var v := c - hub
	var axial := v.dot(axle)
	var radial := (v - axle * axial).length()
	var outward := signf((hub - model_center).dot(axle))
	if outward == 0.0:
		outward = 1.0
	if radial <= 0.24 and axial * outward >= -0.08 and axial * outward <= 0.30:
		return corners[best_i]
	return null


func _split_mesh(mi: MeshInstance3D, corners: Array[Node3D], hubs: Array[Vector3],
		pair: Array[int], model_center: Vector3) -> int:
	var mesh := mi.mesh as ArrayMesh
	var moved_total := 0
	# per-corner SurfaceTools accumulating rim faces across all surfaces
	var tools := {}
	var mats := {}
	for s in mesh.get_surface_count():
		var mat := mesh.surface_get_material(s)
		var mdt := MeshDataTool.new()
		if mdt.create_from_surface(mesh, s) != OK:
			continue
		var xf := mi.global_transform
		var fmt := mdt.get_format()
		for fi in mdt.get_face_count():
			var a0 := mdt.get_vertex(mdt.get_face_vertex(fi, 0))
			var a1 := mdt.get_vertex(mdt.get_face_vertex(fi, 1))
			var a2 := mdt.get_vertex(mdt.get_face_vertex(fi, 2))
			var c: Vector3 = xf * ((a0 + a1 + a2) / 3.0)
			var target := _rim_target(c, corners, hubs, pair, model_center)
			if target == null:
				continue
			if not tools.has(target):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				tools[target] = st
				mats[target] = []
			var stc: SurfaceTool = tools[target]
			stc.set_material(mat)
			mats[target].append(mat)
			for k in 3:
				var vi := mdt.get_face_vertex(fi, k)
				stc.set_normal(mdt.get_vertex_normal(vi))
				if fmt & Mesh.ARRAY_FORMAT_TEX_UV:
					stc.set_uv(mdt.get_vertex_uv(vi))
				if fmt & Mesh.ARRAY_FORMAT_TEX_UV2:
					stc.set_uv2(mdt.get_vertex_uv2(vi))
				if fmt & Mesh.ARRAY_FORMAT_COLOR:
					stc.set_color(mdt.get_vertex_color(vi))
				var t := mdt.get_vertex_tangent(vi)
				stc.set_tangent(Plane(t.x, t.y, t.z, t.d))
				stc.add_vertex(mdt.get_vertex(vi))
			moved_total += 1
	# rebuild the body mesh without moved faces: simplest correct path is to
	# drop and re-add whole mesh only when nothing moved; otherwise rebuild
	# via per-surface keep tools — redo the loop once more tracking keeps
	if moved_total == 0:
		return 0
	_rebuild_body_without_rims(mi, corners, hubs, pair, model_center)
	for target in tools:
		var stc: SurfaceTool = tools[target]
		var move_mesh := stc.commit()
		if move_mesh == null:
			continue
		if move_mesh.get_surface_count() > 0 and mats[target].size() > 0:
			move_mesh.surface_set_material(0, mats[target][0])
		var rim := MeshInstance3D.new()
		rim.name = "rim"
		rim.mesh = move_mesh
		target.add_child(rim)
		rim.transform = (target as Node3D).global_transform.affine_inverse() * mi.global_transform
	return moved_total


## Rebuild mi.mesh keeping only non-rim faces (per surface, materials kept).
func _rebuild_body_without_rims(mi: MeshInstance3D, corners: Array[Node3D],
		hubs: Array[Vector3], pair: Array[int], model_center: Vector3) -> void:
	var mesh := mi.mesh as ArrayMesh
	var st_all := SurfaceTool.new()
	st_all.begin(Mesh.PRIMITIVE_TRIANGLES)
	for s in mesh.get_surface_count():
		var mat := mesh.surface_get_material(s)
		var mdt := MeshDataTool.new()
		if mdt.create_from_surface(mesh, s) != OK:
			continue
		var xf := mi.global_transform
		var fmt := mdt.get_format()
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var kept_any := false
		for fi in mdt.get_face_count():
			var a0 := mdt.get_vertex(mdt.get_face_vertex(fi, 0))
			var a1 := mdt.get_vertex(mdt.get_face_vertex(fi, 1))
			var a2 := mdt.get_vertex(mdt.get_face_vertex(fi, 2))
			var c: Vector3 = xf * ((a0 + a1 + a2) / 3.0)
			if _rim_target(c, corners, hubs, pair, model_center) != null:
				continue
			kept_any = true
			if mat != null:
				st.set_material(mat)
			for k in 3:
				var vi := mdt.get_face_vertex(fi, k)
				st.set_normal(mdt.get_vertex_normal(vi))
				if fmt & Mesh.ARRAY_FORMAT_TEX_UV:
					st.set_uv(mdt.get_vertex_uv(vi))
				if fmt & Mesh.ARRAY_FORMAT_TEX_UV2:
					st.set_uv2(mdt.get_vertex_uv2(vi))
				if fmt & Mesh.ARRAY_FORMAT_COLOR:
					st.set_color(mdt.get_vertex_color(vi))
				var t := mdt.get_vertex_tangent(vi)
				st.set_tangent(Plane(t.x, t.y, t.z, t.d))
				st.add_vertex(mdt.get_vertex(vi))
		if kept_any:
			st.set_material(mat)
			st_all.append_from(st.commit(), 0, Transform3D.IDENTITY)
	var combined := st_all.commit()
	if combined != null and combined.get_surface_count() > 0:
		mi.mesh = combined


## Append another mesh's surfaces into an existing rim MeshInstance3D,
## keeping world transforms consistent.
func _merge_mesh(rim: MeshInstance3D, add_mesh: Mesh, owner_corner: Node3D,
		mesh_world: Transform3D) -> void:
	var rel := owner_corner.global_transform.affine_inverse() * mesh_world
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.append_from(add_mesh, 0, rel)
	var base := rim.mesh
	var combined := SurfaceTool.new()
	combined.begin(Mesh.PRIMITIVE_TRIANGLES)
	combined.append_from(base, 0, Transform3D.IDENTITY)
	combined.append_from(add_mesh, 0, rel)
	var merged := combined.commit()
	if merged != null:
		if base.surface_get_material(0) != null:
			merged.surface_set_material(0, base.surface_get_material(0))
		rim.mesh = merged
