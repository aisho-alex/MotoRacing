extends SceneTree
## Dev tool: builds every track headless and verifies that no building
## (regular or skyline) reaches into the road. Prints the worst footprint
## corner distance to the centerline per track.
## Run: godot --headless --path . -s tools/check_buildings.gd

const TRACKS_DIR := "res://assets/data/tracks"
const MARGIN := 0.5  # slack above road_half_width

var _deferred := true


func _initialize() -> void:
	_deferred = true


## Every TrackDef in the tracks folder, so new tracks are validated automatically.
func _discover_tracks() -> PackedStringArray:
	var ids: PackedStringArray = []
	var da := DirAccess.open(TRACKS_DIR)
	if da == null:
		return ids
	for f in da.get_files():
		if f.get_extension() == "tres":
			ids.append(f.get_basename())
	ids.sort()
	return ids


func _process(_delta: float) -> bool:
	if _deferred:
		_deferred = false
		var failures := 0
		for id in _discover_tracks():
			if _check_track(id) != 0:
				failures += 1
		print("RESULT: %s" % ("PASS" if failures == 0 else "FAIL (%d)" % failures))
		quit(0 if failures == 0 else 1)
	return true


func _check_track(id: String) -> int:
	var res := load("res://assets/data/tracks/%s.tres" % id) as TrackDef
	if res == null:
		print("%s: FAIL — cannot load TrackDef" % id)
		return 1
	var track := TrackBuilder.new()
	track.name = "Track"
	track.def = res
	root.add_child(track)
	track.build()
	var buildings := track.find_child("Buildings", true, false)
	var placed := 0
	var front_row := 0
	var skyline_boxes := 0
	var worst := INF
	var worst_at := Vector3.ZERO
	var worst_name := ""
	var worst_debug := ""
	if buildings != null:
		for child in buildings.get_children():
			if child.name == "Skyline":
				skyline_boxes = track.skyline_transforms.size()
				for xf in track.skyline_transforms:
					var aabb: AABB = xf * AABB(Vector3(-0.5, -0.5, -0.5), Vector3.ONE)
					for corner in _footprint_corners(aabb):
						var d := track.min_distance_to_track(corner)
						if d < worst:
							worst = d
							worst_at = corner
							worst_name = "Skyline@%v reach=%.1f" % [xf.origin, xf.basis.get_scale().x * 0.5]
				continue
			if child.name == "StreetFront":
				for side_root in child.get_children():
					front_row += side_root.get_child_count()
				placed += front_row
			else:
				placed += 1
			for mesh in child.find_children("*", "MeshInstance3D", true, false):
				var aabb: AABB = mesh.global_transform * mesh.get_aabb()
				for corner in _footprint_corners(aabb):
					var d := track.min_distance_to_track(corner)
					if d < worst:
						worst = d
						worst_at = corner
						worst_name = "%s>%s" % [child.name, mesh.name]
						worst_debug = _describe_building(mesh)
	var limit := res.road_half_width + MARGIN
	var ok := worst >= limit
	print("%s: buildings=%d front_row=%d skyline=%d | worst corner %.1f m from centerline (limit %.1f) -> %s at %v [%s]%s" % [
			id, placed, front_row, skyline_boxes, worst, limit, "OK" if ok else "ON ROAD", worst_at, worst_name, worst_debug])
	root.remove_child(track)
	track.free()
	return 0 if ok else 1


func _describe_building(mesh: Node) -> String:
	var n := mesh
	var root: Node = null
	while n != null:
		if n.has_meta("kit_footprint"):
			root = n
			break
		n = n.get_parent()
	if root == null:
		return ""
	var r := root as Node3D
	return " root=" + str(r.global_position) + " rot=" + str(r.rotation.y) \
			+ " scale=" + str(r.scale.x) + " fp=" + str(r.get_meta("kit_footprint")) \
			+ " mesh_aabb=" + str((mesh as MeshInstance3D).get_aabb())


func _footprint_corners(aabb: AABB) -> Array:
	var y := aabb.position.y
	return [
		Vector3(aabb.position.x, y, aabb.position.z),
		Vector3(aabb.end.x, y, aabb.position.z),
		Vector3(aabb.position.x, y, aabb.end.z),
		Vector3(aabb.end.x, y, aabb.end.z),
	]
