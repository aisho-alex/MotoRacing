class_name TrackPickup
extends Area3D
## Shared base for track pickups (nitro bottle / health pack): spin + bob,
## contact detection that ignores traffic, timed respawn and an additive glow
## halo. Subclasses provide the visual, the applied effect and the tuning
## values through the small overridable hooks below.

const BOB_SPEED := 2.0

var _visual: Node3D
var _shape: CollisionShape3D
var _respawn := 0.0
var _t := 0.0


func _ready() -> void:
	collision_layer = 0
	# watch the player (1) and the opponents (2), like the boost pads
	collision_mask = 3
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
	_visual.rotation.y += spin_speed() * delta
	_visual.position.y = sin(_t * BOB_SPEED) * bob_height()


## Restores the pickup immediately (race restart).
func reset() -> void:
	_respawn = 0.0
	_set_active(true)


func _on_body_entered(body: Node3D) -> void:
	if _respawn > 0.0:
		return
	if "is_traffic" in body and body.is_traffic:
		return
	if not _try_apply(body):
		return
	_respawn = respawn_time()
	_set_active(false)


func _set_active(active: bool) -> void:
	_visual.visible = active
	_shape.set_deferred("disabled", not active)


## Soft additive halo so the pickup pops against the asphalt, day and night.
func _make_glow(quad_size: float) -> MeshInstance3D:
	var glow := glow_color()
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	grad.colors = PackedColorArray([
		Color(glow.r, glow.g, glow.b, 0.55),
		Color(glow.r, glow.g, glow.b, 0.18),
		Color(glow.r, glow.g, glow.b, 0.0),
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
	quad.size = Vector2(quad_size, quad_size)
	quad.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = quad
	mi.position.y = 0.75
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


# --- hooks for subclasses ------------------------------------------------

func _build_visual() -> Node3D:
	return Node3D.new()


func _try_apply(_body: Node3D) -> bool:
	return false


func bob_height() -> float:
	return 0.15


func spin_speed() -> float:
	return 1.4


func respawn_time() -> float:
	return 15.0


func glow_color() -> Color:
	return Color.WHITE
