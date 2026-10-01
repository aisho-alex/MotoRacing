class_name NitroPickup
extends Area3D
## Rotating nitro bottle on the track. Driving over it instantly refills part of
## the tank (player and AI both collect); the bottle then hides for a while and
## respawns.

const AMOUNT := 30.0
const RESPAWN_TIME := 15.0
const BOB_HEIGHT := 0.16
const SPIN_SPEED := 1.6
const GLOW := Color(1.0, 0.62, 0.16)

var _visual: Node3D
var _shape: CollisionShape3D
var _respawn := 0.0
var _base_y := 0.0
var _t := 0.0


func _ready() -> void:
	collision_layer = 0
	# watch the player (1) and the opponents (2), like the boost pads
	collision_mask = 3
	_base_y = position.y
	_visual = _build_visual()
	add_child(_visual)
	_shape = CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 1.1
	_shape.shape = sphere
	_shape.position.y = 0.6
	add_child(_shape)
	body_entered.connect(_on_body_entered)
	_t = randf() * TAU


func _process(delta: float) -> void:
	if _respawn > 0.0:
		_respawn = maxf(_respawn - delta, 0.0)
		if _respawn <= 0.0:
			_set_active(true)
		return
	_t += delta
	_visual.rotation.y += SPIN_SPEED * delta
	_visual.position.y = sin(_t * 2.0) * BOB_HEIGHT


## Restores the bottle immediately (race restart).
func reset() -> void:
	_respawn = 0.0
	_set_active(true)


func _on_body_entered(body: Node3D) -> void:
	if _respawn > 0.0 or not body.has_method("add_nitro"):
		return
	body.call("add_nitro", AMOUNT)
	_respawn = RESPAWN_TIME
	_set_active(false)


func _set_active(active: bool) -> void:
	_visual.visible = active
	_shape.set_deferred("disabled", not active)


func _build_visual() -> Node3D:
	var root := Node3D.new()
	root.name = "Bottle"
	var body_fill := StandardMaterial3D.new()
	body_fill.albedo_color = Color(0.28, 0.14, 0.03)
	body_fill.roughness = 0.22
	body_fill.metallic = 0.15
	body_fill.emission_enabled = true
	body_fill.emission = GLOW
	body_fill.emission_energy_multiplier = 2.6
	root.add_child(_cyl(0.28, 0.28, 0.9, 0.52, body_fill))
	root.add_child(_cyl(0.28, 0.13, 0.24, 1.09, body_fill))
	root.add_child(_cyl(0.11, 0.11, 0.26, 1.32, body_fill))
	var cap := StandardMaterial3D.new()
	cap.albedo_color = Color(0.9, 0.75, 0.2)
	cap.roughness = 0.35
	cap.emission_enabled = true
	cap.emission = Color(1.0, 0.75, 0.2)
	cap.emission_energy_multiplier = 1.2
	root.add_child(_cyl(0.15, 0.15, 0.14, 1.5, cap))
	root.add_child(_make_glow())
	return root


func _cyl(top: float, bottom: float, height: float, y: float,
		material: StandardMaterial3D) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = 16
	mesh.material = material
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position.y = y
	return mi


## Soft additive halo so the bottle pops against the asphalt, day and night.
func _make_glow() -> MeshInstance3D:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	grad.colors = PackedColorArray([
		Color(GLOW.r, GLOW.g, GLOW.b, 0.55),
		Color(GLOW.r, GLOW.g, GLOW.b, 0.18),
		Color(GLOW.r, GLOW.g, GLOW.b, 0.0),
	])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 128
	tex.height = 128
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_texture = tex
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var quad := QuadMesh.new()
	quad.size = Vector2(2.4, 2.4)
	quad.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = quad
	mi.position.y = 0.75
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi
