extends SceneTree
## Dev tool: verifies traffic car orientation. A traffic car is a RaceBike, so
## its hull must travel along the bike's forward axis (-Z); a wrong BikeDef
## model_yaw leaves the GLB model lying across the road ("driving sideways").
## For every BikeDef in assets/data/traffic this applies model_yaw exactly like
## RaceBike._build_visuals and checks that the body's long horizontal axis ends
## up along Z.
## Run: godot --headless --path . -s tools/check_traffic_orient.gd

const TRAFFIC_DIR := "res://assets/data/traffic"
const MIN_ASPECT := 1.15  # length must clearly dominate width

var _deferred := true


func _initialize() -> void:
	_deferred = true


func _process(_delta: float) -> bool:
	if _deferred:
		_deferred = false
		var failures := 0
		for id in _discover():
			if _check(id) != 0:
				failures += 1
		print("RESULT: %s" % ("PASS" if failures == 0 else "FAIL (%d)" % failures))
		quit(0 if failures == 0 else 1)
	return true


func _discover() -> PackedStringArray:
	var ids: PackedStringArray = []
	var da := DirAccess.open(TRAFFIC_DIR)
	if da == null:
		return ids
	for f in da.get_files():
		if f.get_extension() == "tres":
			ids.append(f.get_basename())
	ids.sort()
	return ids


func _check(id: String) -> int:
	var def := load("%s/%s.tres" % [TRAFFIC_DIR, id]) as BikeDef
	if def == null:
		print("%s: FAIL — cannot load BikeDef" % id)
		return 1
	if def.model_path == "" or not ResourceLoader.exists(def.model_path):
		print("%s: FAIL — model missing (%s)" % [id, def.model_path])
		return 1
	var scene := load(def.model_path) as PackedScene
	if scene == null:
		print("%s: FAIL — not a PackedScene (%s)" % [id, def.model_path])
		return 1
	var holder := Node3D.new()
	holder.rotation.y = def.model_yaw
	holder.scale = Vector3.ONE * def.model_scale
	holder.add_child(scene.instantiate())
	root.add_child(holder)

	var xs := PackedFloat32Array()
	var zs := PackedFloat32Array()
	var stack: Array[Node] = [holder]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			var mesh: Mesh = mi.mesh
			if mesh == null:
				continue
			var xf := mi.global_transform
			for s in mesh.get_surface_count():
				var arr := mesh.surface_get_arrays(s)
				var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
				if verts == null:
					continue
				for v in verts:
					var w: Vector3 = xf * v
					xs.append(w.x)
					zs.append(w.z)
	holder.queue_free()

	if xs.is_empty():
		print("%s: FAIL — no geometry" % id)
		return 1
	xs.sort()
	zs.sort()
	var x_span := _span(xs)
	var z_span := _span(zs)
	var ok := z_span > x_span * MIN_ASPECT
	print("%s: yaw=%.4f len_z=%.2f width_x=%.2f ratio=%.2f — %s"
		% [id, def.model_yaw, z_span, x_span, z_span / maxf(x_span, 0.001),
			"ok" if ok else "SIDEWAYS"])
	if not ok:
		return 1
	return 0


## Robust span (2%..98%) so a handful of stray vertices cannot fake the axis.
func _span(values: PackedFloat32Array) -> float:
	var n := values.size()
	var lo := values[int(n * 0.02)]
	var hi := values[int(n * 0.98)]
	return hi - lo
