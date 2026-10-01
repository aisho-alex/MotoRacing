class_name OilSlick
extends Area3D
## Dark glossy puddle on the asphalt. Riding over it drops lateral grip for a
## few seconds (a slide, not a crash). Persistent for the whole race; traffic
## ignores it.

const RADIUS := 1.7
const DURATION := 3.5


func _ready() -> void:
	collision_layer = 0
	collision_mask = 3  # player + opponents
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = RADIUS
	cyl.height = 0.6
	shape.shape = cyl
	shape.position.y = 0.3
	add_child(shape)
	add_child(_build_visual())
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if "is_traffic" in body and body.is_traffic:
		return
	if body.has_method("apply_oil"):
		body.call("apply_oil", DURATION)


## One broad puddle plus two smaller blotches so the patch reads organically.
func _build_visual() -> Node3D:
	var root := Node3D.new()
	root.name = "OilSlick"
	root.add_child(_blotch(Vector3.ZERO, RADIUS))
	root.add_child(_blotch(Vector3(1.1, 0.0, 0.6), RADIUS * 0.55))
	root.add_child(_blotch(Vector3(-0.9, 0.0, -0.7), RADIUS * 0.45))
	return root


func _blotch(offset: Vector3, radius: float) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius * 0.92
	mesh.height = 0.03
	mesh.radial_segments = 20
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.035, 0.035, 0.045, 0.92)
	mat.roughness = 0.12
	mat.metallic = 0.55
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = offset + Vector3.UP * 0.025
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi
