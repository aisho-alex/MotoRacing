class_name HealthPickup
extends Area3D
## Green repair pack on the track. Driving over it restores part of the bike's
## health (player and AI both collect); the pack then hides for a while and
## respawns. Scarcity is the point: fewer packs than nitro bottles.

const AMOUNT := 30.0
const RESPAWN_TIME := 20.0
const BOB_HEIGHT := 0.14
const SPIN_SPEED := 1.1
const GLOW := Color(0.32, 1.0, 0.5)

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


## Restores the pack immediately (race restart).
func reset() -> void:
	_respawn = 0.0
	_set_active(true)


func _on_body_entered(body: Node3D) -> void:
	if _respawn > 0.0 or not body.has_method("add_health"):
		return
	body.call("add_health", AMOUNT)
	_respawn = RESPAWN_TIME
	_set_active(false)


func _set_active(active: bool) -> void:
	_visual.visible = active
	_shape.set_deferred("disabled", not active)


## A green cross (two bars) with an emissive, semi-transparent material so it
## reads as a pickup against the asphalt, day and night.
func _build_visual() -> Node3D:
	var root := Node3D.new()
	root.name = "HealthPack"
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.20, 0.65, 0.32, 0.92)
	mat.roughness = 0.28
	mat.emission_enabled = true
	mat.emission = GLOW
	mat.emission_energy_multiplier = 2.2
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	root.add_child(_bar(Vector3(0.30, 0.98, 0.30), Vector3(0.0, 0.72, 0.0), mat))
	root.add_child(_bar(Vector3(0.84, 0.30, 0.30), Vector3(0.0, 0.72, 0.0), mat))
	root.add_child(_make_glow())
	return root


func _bar(size: Vector3, pos: Vector3, material: StandardMaterial3D) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	return mi


## Soft additive halo so the pack pops against the asphalt, day and night.
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
	quad.size = Vector2(2.2, 2.2)
	quad.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = quad
	mi.position.y = 0.75
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi
