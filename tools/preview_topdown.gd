extends SceneTree
## Dev tool: top-down diagnostic screenshot focused on the road ribbon.

var _frames := 0
var _main: Node


func _initialize() -> void:
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 30:
		var t: Node3D = _main.get_node("Track")
		var road: MeshInstance3D = t.get_child(1)
		var m: StandardMaterial3D = road.mesh.surface_get_material(0)
		m.albedo_texture = null
		m.albedo_color = Color(1, 0, 0)
		m.normal_enabled = false
		m.ao_enabled = false
		m.roughness_texture = null
		m.metallic_texture = null
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		print("cull disabled test")
		for child in t.get_children():
			child.visible = child == road
		print("road visible=", road.visible, " in_tree=", road.is_visible_in_tree(),
			" pos=", road.global_position)
		var arrays := road.mesh.surface_get_arrays(0)
		var variant_meshes := {
			"full": arrays,
			"no_uv": (func(): 
				var a := arrays.duplicate()
				a[Mesh.ARRAY_TEX_UV] = null
				return a).call(),
			"no_normal": (func():
				var a := arrays.duplicate()
				a[Mesh.ARRAY_NORMAL] = null
				return a).call(),
			"pos_idx_only": (func():
				var a := arrays.duplicate()
				a[Mesh.ARRAY_NORMAL] = null
				a[Mesh.ARRAY_TEX_UV] = null
				return a).call(),
		}
		var y := 3.0
		for name in variant_meshes:
			var mi := MeshInstance3D.new()
			var am := ArrayMesh.new()
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, variant_meshes[name])
			var red := StandardMaterial3D.new()
			red.albedo_color = Color(1, 0, 0)
			red.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			am.surface_set_material(0, red)
			mi.mesh = am
			mi.position.y = y
			t.add_child(mi)
			print("variant ", name, " at y=", y)
			y += 0.5
		var cam := Camera3D.new()
		root.add_child(cam)
		cam.make_current()
		var c: Vector3 = t.centerline[0]
		cam.global_position = c + Vector3(0, 40, 0.01)
		cam.look_at(c, Vector3.FORWARD)
		cam.fov = 60
	if _frames >= 75:
		var img := root.get_texture().get_image()
		img.save_png("/tmp/opencode/topdown.png")
		print("saved /tmp/opencode/topdown.png")
		return true
	return false
