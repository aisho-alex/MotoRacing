extends SceneTree
## Dev tool: frames a city lot (mall/skate/plaza/court/parking) built by
## TrackBuilder, hiding the street wall so the new infill is visible.
## TRACK=city_01 LOT_INDEX=0 OUT=/tmp/opencode/lot_shot.png

var _frames := 0
var _track: TrackBuilder
var _center := Vector3.ZERO
var _road_dir := Vector3.FORWARD


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 1:
		_build()
	elif _frames == 120:
		var img := root.get_texture().get_image()
		var out := OS.get_environment("OUT")
		if out.is_empty():
			out = "/tmp/opencode/lot_shot.png"
		img.save_png(out)
		print("saved ", out)
		quit(0)
		return true
	return false


func _build() -> void:
	var id := OS.get_environment("TRACK")
	if id.is_empty():
		id = "city_01"
	var res := load("res://assets/data/tracks/%s.tres" % id) as TrackDef
	if res == null:
		push_error("cannot load track %s" % id)
		quit(1)
		return
	_track = TrackBuilder.new()
	_track.name = "Track"
	_track.def = res
	root.add_child(_track)
	_track.build()
	if OS.get_environment("HIDE_WALL") != "0":
		for nm in ["StreetFront", "Skyline"]:
			var n := _track.find_child(nm, true, false)
			if n != null:
				n.visible = false
	var lots: Array[Node] = []
	_collect(_track, lots)
	print("lots=", lots.size())
	for l in lots:
		print("  ", l.name, " @ ", (l as Node3D).global_position.round())
	if lots.is_empty():
		quit(1)
		return
	var li := int(OS.get_environment("LOT_INDEX")) if OS.get_environment("LOT_INDEX") != "" else 0
	var lot := lots[clampi(li, 0, lots.size() - 1)] as Node3D
	_center = _lot_center(lot)
	var nearest := _track.nearest_sample(_center)
	var to_road := _track.centerline[nearest] - _center
	to_road.y = 0.0
	_road_dir = to_road.normalized() if to_road.length() > 0.01 else Vector3.FORWARD
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.make_current()
	cam.global_position = _center - _road_dir * 24.0 + Vector3.UP * 17.0
	cam.look_at(_center + Vector3.UP * 3.0, Vector3.UP)
	cam.near = 0.1
	cam.far = 400.0
	cam.fov = 55.0
	var sun := DirectionalLight3D.new()
	root.add_child(sun)
	sun.rotation_degrees = Vector3(-52, -35, 0)
	sun.light_energy = 1.25
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.68, 0.85)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.85, 0.88, 0.95)
	e.ambient_light_energy = 0.75
	env.environment = e
	root.add_child(env)


func _collect(node: Node, out: Array[Node]) -> void:
	for c in node.get_children():
		if c is Node3D and c.name.begins_with("Lot"):
			out.append(c)
		_collect(c, out)


func _lot_center(lot: Node3D) -> Vector3:
	var box := AABB()
	var first := true
	for mi in lot.find_children("*", "MeshInstance3D", true, false):
		var ab: AABB = (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
		if first:
			box = ab
			first = false
		else:
			box = box.merge(ab)
	if first:
		return lot.global_position
	return box.get_center()
