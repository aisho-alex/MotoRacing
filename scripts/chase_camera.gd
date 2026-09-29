class_name ChaseCamera
extends Camera3D
## Smooth follow camera that trails behind the car; FOV widens with speed.

var target: Node3D

var _dist := 8.5
var _height := 4.2
var _look_height := 1.4
var _pos_smoothing := 5.5

var _nitro_kick := 0.0
var _dist_push := 0.0
var _roll := 0.0
var _time := 0.0
var _speed_streaks: GPUParticles3D
var _speed_streak_material: StandardMaterial3D


func _ready() -> void:
	_build_speed_streaks()


func _physics_process(delta: float) -> void:
	if target == null:
		return
	_time += delta
	var spd := 0.0
	var lateral_speed := 0.0
	var boosting := false
	var max_spd := 32.0
	if target is RaceCar:
		spd = target.velocity.length()
		lateral_speed = target.velocity.dot(target.global_transform.basis.x)
		boosting = target.is_nitro_active()
		max_spd = target.def.max_speed
	var speed_ratio := clampf(spd / maxf(max_spd, 1.0), 0.0, 1.0)
	_nitro_kick = lerpf(_nitro_kick, 10.0 if boosting else 0.0, 1.0 - exp(-4.5 * delta))
	_dist_push = lerpf(_dist_push, 1.35 if boosting else 0.0, 1.0 - exp(-3.0 * delta))

	var fwd: Vector3 = -target.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length_squared() < 0.0001:
		fwd = Vector3.BACK
	fwd = fwd.normalized()
	var right := target.global_transform.basis.x
	right.y = 0.0
	if right.length_squared() > 0.0001:
		right = right.normalized()
	var speed_height := lerpf(_height, 3.72, speed_ratio) - (0.18 if boosting else 0.0)
	var goal := target.global_position - fwd * (_dist + _dist_push) + Vector3.UP * speed_height
	var shake := maxf(speed_ratio - 0.58, 0.0) * 0.018 + (0.045 if boosting else 0.0)
	goal += right * sin(_time * 47.0) * shake
	goal += Vector3.UP * cos(_time * 39.0) * shake * 0.55
	goal = _resolve_occlusion(goal)
	global_position = global_position.lerp(goal, 1.0 - exp(-_pos_smoothing * delta))
	var look_target := target.global_position + Vector3.UP * (_look_height + speed_ratio * 0.18)
	look_target += fwd * lerpf(1.5, 7.5, speed_ratio)
	look_at(look_target, Vector3.UP)
	var roll_goal := clampf(-lateral_speed * 0.012, -0.065, 0.065)
	if boosting:
		roll_goal += sin(_time * 31.0) * 0.006
	_roll = lerpf(_roll, roll_goal, 1.0 - exp(-5.0 * delta))
	rotation.z = _roll
	var fov_goal := 60.0 + 18.0 * speed_ratio + _nitro_kick
	fov = lerpf(fov, fov_goal, 1.0 - exp(-3.2 * delta))
	if _speed_streaks != null:
		_speed_streaks.emitting = speed_ratio > 0.48 or boosting
		var intensity := clampf((speed_ratio - 0.42) * 1.8 + (0.65 if boosting else 0.0), 0.0, 1.0)
		_speed_streak_material.albedo_color.a = 0.03 + intensity * 0.16
		_speed_streak_material.emission_energy_multiplier = 0.45 + intensity * 1.15


func _resolve_occlusion(goal: Vector3) -> Vector3:
	var anchor := target.global_position + Vector3.UP * 1.2
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(anchor, goal, 4)
	var hit := space.intersect_ray(query)
	if not hit.has("position"):
		return goal
	var safe := (hit.position as Vector3) + (hit.normal as Vector3) * 0.65
	if safe.distance_to(anchor) < 2.8:
		safe = anchor + (goal - anchor).normalized() * 2.8
	return safe


func _build_speed_streaks() -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.018, 0.018, 1.7)
	_speed_streak_material = StandardMaterial3D.new()
	_speed_streak_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_speed_streak_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_speed_streak_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_speed_streak_material.albedo_color = Color(0.38, 0.72, 1.0, 0.08)
	_speed_streak_material.emission_enabled = true
	_speed_streak_material.emission = Color(0.22, 0.58, 1.0)
	_speed_streak_material.emission_energy_multiplier = 0.8
	mesh.material = _speed_streak_material
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0.0, 0.0, 1.0)
	pm.spread = 2.0
	pm.initial_velocity_min = 12.0
	pm.initial_velocity_max = 20.0
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.45
	pm.scale_max = 0.95
	pm.color = Color(0.38, 0.72, 1.0, 0.20)
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(4.6, 2.5, 0.30)
	_speed_streaks = GPUParticles3D.new()
	_speed_streaks.name = "SpeedStreaks"
	_speed_streaks.position = Vector3(0.0, 0.0, -10.0)
	_speed_streaks.amount = 26
	_speed_streaks.lifetime = 0.20
	_speed_streaks.local_coords = false
	_speed_streaks.emitting = false
	_speed_streaks.visibility_aabb = AABB(Vector3(-10.0, -7.0, -16.0), Vector3(20.0, 14.0, 32.0))
	_speed_streaks.process_material = pm
	_speed_streaks.draw_pass_1 = mesh
	add_child(_speed_streaks)


func snap_behind(car: RaceCar) -> void:
	target = car
	var fwd: Vector3 = -car.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	global_position = car.global_position - fwd * _dist + Vector3.UP * _height
	look_at(car.global_position + Vector3.UP * _look_height + fwd * 1.5, Vector3.UP)
	fov = 60.0
	_roll = 0.0
	rotation.z = 0.0
