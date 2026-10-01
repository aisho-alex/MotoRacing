class_name RaceBike
extends CharacterBody3D
## Arcade-style bike: acceleration, braking/reverse, speed-sensitive steering
## and lateral grip. Tuning and visuals come from a BikeDef resource; wheels
## found in the model spin (front ones steer too) and liveries override the
## paint. Road Rash combat: side punches / kicks deplete health, knock a rider
## out (wipeout + remount); everything degrades gracefully without assets.

signal wiped_out(bike: RaceBike)
signal remounted(bike: RaceBike)

const OFFROAD_LIMIT := 1.5  # extra meters beyond road half width
const OPPONENT_HIDE_DISTANCE := 100.0
const OPPONENT_SHOW_DISTANCE := 82.0
## How long a boost pad ("ускорялка") keeps the bike at boosted speed (s).
const PAD_BOOST_TIME := 2.0

const HEALTH_MAX := 100.0
const PUNCH_DAMAGE := 13.0
const KICK_DAMAGE := 22.0
const ATTACK_COOLDOWN := 0.45
const WIPEOUT_TIME := Rider.CRASH_TOTAL  # canonical timeline lives in rider.gd
const CRASH_IMPACT_SPEED := 26.0  # hard hit above this speed = instant wipeout
const VEHICLE_HIT_SPEED := 10.0   # m/s into a traffic car / bike that starts hurting
const WALL_HIT_SPEED := 14.0      # m/s into a wall that starts hurting
const CRASH_HURT_COOLDOWN := 0.8

## Slipstream: tucking in behind another rider inside a narrow cone grants a
## small top-speed bump and faster nitro regen. Applies to every racer (player
## and AI), so the pack can chain drafts.
const DRAFT_RANGE := 16.0
const DRAFT_MIN_GAP := 3.0
const DRAFT_HALF_WIDTH := 2.2
const DRAFT_MIN_SPEED := 10.0
const DRAFT_MAX_MULT := 1.08
const DRAFT_SPOOL := 2.0
const DRAFT_REGEN_BONUS := 0.35
## Lateral grip multiplier while riding over an oil slick.
const OIL_GRIP_MULT := 0.32

var def: BikeDef
var road_half_width := 6.0
var night_lights := false
var driver: AiDriver = null  # when set, inputs come from AI instead of Input
var is_opponent := false     # opponents ghost through each other (arcade AI)
var is_traffic := false      # civilian car: hard crash object, not a racer

var control_enabled := false
var road_distance_fn := Callable()
var last_safe_transform := Transform3D.IDENTITY

var nitro := 0.0
var nitro_active := false
var _nitro_regen_timer := 0.0
var _boost_mult := 1.0
var _pad_boost_timer := 0.0
var _draft_mult := 1.0
var _drafting := false
var _exhaust: Array[GPUParticles3D] = []

var shield_time := 0.0   # seconds of immunity to combat hits (pickup)
var oil_time := 0.0      # seconds of reduced lateral grip after an oil slick

var _wheels: Array[Node3D] = []
var _front_wheels: Array[Node3D] = []
var _wheel_spin := 0.0
var _was_on_floor := true
var _impact_cooldown := 0.0
var _skid: AudioStreamPlayer3D = null
var _offroad_now := false

var _smoke: Array[GPUParticles3D] = []
var _dust: Array[GPUParticles3D] = []
var _sparks: GPUParticles3D = null

var rider: Rider = null          # seated rider (combat/animation in M2)
var player_skin: RiderSkinDef = null  # set on the player's bike by main.gd
var _tilt: Node3D = null         # visual lean/wheelie node (holds model + rider)
var _lean_roll := 0.0            # visual roll into corners (radians)
var _lean_pitch := 0.0           # visual wheelie under boost (radians)

var health := HEALTH_MAX
var wiped_out_now := false
var combat_targets: Array = []
var _attack_cooldown := 0.0
var _wipeout_timer := 0.0
var _wobble := 0.0
var _fall_side := -1.0           # which way the bike tips on a wipeout (+1 left, -1 right)
var _pre_slide_velocity := Vector3.ZERO
var _crash_hurt_cooldown := 0.0
var attacker: RaceBike = null      # last rider who hit us (AI grudge)
var grudge_timer := 0.0


func _ready() -> void:
	if def == null:
		def = BikeDef.load_default()
	nitro = def.nitro_max
	_build_visuals()
	_build_lights()
	_build_exhaust()
	_build_vfx()
	_add_engine_audio()
	_add_skid_audio()
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = def.collision_size
	col.shape = box
	col.position.y = box.size.y * 0.5
	add_child(col)
	up_direction = Vector3.UP
	floor_snap_length = 0.5
	# opponents ignore each other physically (avoids AI pile-ups), but still
	# interact with the player, walls and ground
	collision_layer = 2 if is_opponent else 1
	collision_mask = 1 if is_opponent else 3


func _process(_delta: float) -> void:
	if is_opponent:
		_update_distance_visibility()


func _update_distance_visibility() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var dist := global_position.distance_to(cam.global_position)
	if visible:
		if dist > OPPONENT_HIDE_DISTANCE:
			visible = false
	elif dist < OPPONENT_SHOW_DISTANCE:
		visible = true


func _physics_process(delta: float) -> void:
	var steer := 0.0
	var throttle := 0.0
	var want_nitro := false
	if control_enabled:
		if driver != null:
			var c := driver.drive(self, delta)
			steer = c.x
			throttle = c.y
			want_nitro = c.z
			driver.decide_attack(self, delta)
			if driver.attack_kind != "":
				_try_attack(driver.attack_side, driver.attack_kind)
		else:
			steer = Input.get_axis("steer_left", "steer_right")
			throttle = Input.get_axis("brake", "accelerate")
			want_nitro = Input.is_action_pressed("nitro")
			if Input.is_action_pressed("attack_left"):
				_try_attack(-1.0, "punch")
			if Input.is_action_pressed("attack_right"):
				_try_attack(1.0, "punch")
			if Input.is_action_pressed("kick"):
				_try_attack(signf(steer) if absf(steer) > 0.1 else 1.0, "kick")
	if wiped_out_now:
		steer = 0.0
		throttle = 0.0
		want_nitro = false

	_attack_cooldown = maxf(_attack_cooldown - delta, 0.0)
	_crash_hurt_cooldown = maxf(_crash_hurt_cooldown - delta, 0.0)
	shield_time = maxf(shield_time - delta, 0.0)
	oil_time = maxf(oil_time - delta, 0.0)
	grudge_timer = maxf(grudge_timer - delta, 0.0)
	_wobble = move_toward(_wobble, 0.0, 6.0 * delta)
	rotation.y += _wobble * delta
	_update_wipeout(delta)

	var fwd := -global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var right := global_transform.basis.x
	right.y = 0.0
	right = right.normalized()
	var vf := velocity.dot(fwd)
	var vl := velocity.dot(right)

	# --- steering (stronger at low speed, reversed while driving backwards)
	var turn := steer * def.steer_authority(vf) * signf(vf)
	rotation.y -= turn * delta
	fwd = -global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	right = global_transform.basis.x
	right.y = 0.0
	right = right.normalized()

	# --- nitro boost
	_update_nitro(delta, want_nitro and throttle > 0.0 and vf > -0.5)
	_set_exhaust(nitro_active or _pad_boost_timer > 0.0)

	# --- slipstream (also feeds the nitro tank a little)
	_update_draft(delta, vf)

	# --- longitudinal control
	if throttle > 0.0:
		var target_speed := def.max_speed * _boost_mult * _draft_mult
		var accel := def.accel * (def.nitro_accel_mult if nitro_active or _pad_boost_timer > 0.0 else 1.0)
		vf = move_toward(vf, target_speed, accel * throttle * delta)
	elif throttle < 0.0:
		if vf > 0.5:
			vf = move_toward(vf, 0.0, def.brake * delta)
		else:
			vf = move_toward(vf, -def.reverse_max, def.reverse_accel * delta)
	vf -= vf * def.drag * delta
	vf = move_toward(vf, 0.0, def.roll_resistance * delta)
	if wiped_out_now:
		vf = move_toward(vf, 0.0, 14.0 * delta)
		vl = move_toward(vl, 0.0, 14.0 * delta)

	# --- lateral grip / off-road
	var offroad := is_offroad()
	_offroad_now = offroad
	if offroad:
		vf -= vf * def.offroad_drag * delta
		vl *= exp(-def.offroad_grip * _grip_multiplier() * delta)
	else:
		vl *= exp(-def.grip * _grip_multiplier() * delta)

	if is_on_floor():
		var fn := get_floor_normal()
		if fn.y > 0.001 and fn.y < 0.995:
			# On a slope: keep the climb speed as vertical velocity so the
			# bike keeps its momentum over crests instead of dropping.
			velocity.y = -vf * Vector3(fn.x, 0.0, fn.z).dot(fwd) / fn.y
		else:
			velocity.y = -0.5
	else:
		velocity.y -= 28.0 * delta

	velocity = fwd * vf + right * vl + Vector3.UP * velocity.y
	if driver != null:
		driver.lane_pull(self, delta)
	_pre_slide_velocity = velocity
	move_and_slide()
	_update_lean(delta, steer, velocity.dot(-global_transform.basis.z))
	_update_wheels(delta, steer)
	_slide_audio(delta)

	if global_position.y < -8.0:
		respawn()


func is_offroad() -> bool:
	if road_distance_fn.is_valid():
		return road_distance_fn.call(global_position) > (road_half_width + OFFROAD_LIMIT)
	return false


## --- Road Rash combat ----------------------------------------------------

## side: +1 right, -1 left. kind: "punch" or "kick". No-op while cooling down.
func _try_attack(side: float, kind: String) -> void:
	if _attack_cooldown > 0.0 or wiped_out_now or not control_enabled:
		return
	_attack_cooldown = ATTACK_COOLDOWN
	if rider != null:
		rider.attack(side, kind)
	Audio.play_at("impacts/hit_light", global_position, -3.0)
	var target := _find_attack_target(side, kind)
	if target != null:
		target.take_hit(KICK_DAMAGE if kind == "kick" else PUNCH_DAMAGE, global_position, self)


## A combat/draft target that is valid, not us, and upright. Shared by the
## attack scan and the slipstream scan so both agree on what counts as a target.
func _live_target(t: RaceBike) -> bool:
	return t != self and is_instance_valid(t) and not t.wiped_out_now


func _find_attack_target(side: float, kind: String) -> RaceBike:
	var best: RaceBike = null
	var best_d := INF
	for t in combat_targets:
		if not _live_target(t):
			continue
		var local: Vector3 = global_transform.basis.inverse() * (t.global_position - global_position)
		var ok := false
		if kind == "kick":
			ok = local.z < 0.4 and local.z > -2.6 and absf(local.x) < 1.3
		else:
			ok = absf(local.z) < 2.4 and local.z < 0.7 and absf(local.x) < 1.7 \
				and signf(local.x) == signf(side)
		if ok:
			var d: float = local.length()
			if d < best_d:
				best_d = d
				best = t
	return best


## Damage from a hit; depleted health starts a wipeout.
func take_hit(damage: float, from_pos: Vector3, from: RaceBike = null) -> void:
	if wiped_out_now or not control_enabled or shield_time > 0.0:
		return
	health = maxf(health - damage, 0.0)
	var local: Vector3 = global_transform.basis.inverse() * (from_pos - global_position)
	_wobble += signf(local.x if absf(local.x) > 0.05 else randf_range(-1.0, 1.0)) * 2.6
	if from != null:
		attacker = from           # remembered for AI grudge/retaliation
		grudge_timer = 4.0
	if rider != null:
		rider.hit()
	if health <= 0.0:
		_start_wipeout()


## Direct crash damage (collisions), no combat wobble. `source` is the collided
## traffic car or null for a static wall; `impact` is the closing speed into the
## surface (m/s). Rival bikes never reach here — see `_resolve_impact`.
func apply_crash_impact(source: RaceBike, impact: float) -> void:
	if wiped_out_now or not control_enabled or _crash_hurt_cooldown > 0.0:
		return
	var damage := 0.0
	if source != null:
		if impact < VEHICLE_HIT_SPEED:
			return
		damage = minf(12.0 + impact * 1.6, 40.0)
	else:
		if impact < WALL_HIT_SPEED:
			return
		damage = clampf((impact - WALL_HIT_SPEED) * 1.2, 6.0, 25.0)
	_crash_hurt_cooldown = CRASH_HURT_COOLDOWN
	health = maxf(health - damage, 0.0)
	if rider != null:
		rider.hit()
	if health <= 0.0:
		_start_wipeout()


## Classifies a hard slide contact. `other` is the collided RaceBike or null for
## a static wall; `impact` is the closing speed (m/s). Rider-on-rider contact is
## a shove with no health loss; traffic cars and walls deal crash damage.
func _resolve_impact(other: RaceBike, normal: Vector3, impact: float) -> void:
	if other != null and not other.is_traffic:
		_apply_bump(other, normal, impact)
		return
	apply_crash_impact(other, impact)
	if impact > CRASH_IMPACT_SPEED and control_enabled and not wiped_out_now:
		_start_wipeout()


## Rider-on-rider shove: the struck bike wobbles and is nudged along the contact
## normal, the rammer sheds a little speed. Nobody loses health (that is what
## punch/kick are for).
func _apply_bump(other: RaceBike, normal: Vector3, impact: float) -> void:
	if other == null or not is_instance_valid(other):
		return
	var away := -normal
	away.y = 0.0
	if away.length() < 0.01:
		return
	away = away.normalized()
	var side := other.global_transform.basis.x.dot(away)
	var wobble := signf(side if absf(side) > 0.05 else 1.0)
	other._wobble += wobble * minf(impact * 0.1, 2.4)
	other.velocity += away * minf(impact * 0.25, 6.0)
	velocity -= away * minf(impact * 0.15, 4.0)


func _start_wipeout() -> void:
	if wiped_out_now:
		return
	wiped_out_now = true
	_wipeout_timer = WIPEOUT_TIME
	_wobble = 0.0
	velocity *= 0.5
	_fall_side = 1.0 if randf() < 0.5 else -1.0
	if rider != null:
		_detach_rider()
		rider.crash(_fall_side)
	Audio.play_at("impacts/landing", global_position, 2.0)
	wiped_out.emit(self)


func _update_wipeout(delta: float) -> void:
	if not wiped_out_now:
		return
	_wipeout_timer -= delta
	if _tilt != null:
		# The bike tips over during the ejection and is pulled back upright while
		# the rider braces and lifts it.
		var rising: bool = rider != null and rider.is_remounting()
		var target: float = 0.0 if rising else _fall_side * 1.45
		_lean_roll = move_toward(_lean_roll, target, (1.9 if rising else 3.2) * delta)
		_tilt.rotation.z = _lean_roll
	if _wipeout_timer <= 0.0:
		_remount()


func _detach_rider() -> void:
	_reparent_rider(self)


func _attach_rider() -> void:
	_reparent_rider(_tilt)


func _reparent_rider(to: Node) -> void:
	var g := rider.global_transform
	var parent := rider.get_parent()
	if parent != null:
		parent.remove_child(rider)
	to.add_child(rider)
	rider.global_transform = g


func _remount() -> void:
	wiped_out_now = false
	health = HEALTH_MAX
	_attack_cooldown = ATTACK_COOLDOWN
	_lean_roll = 0.0
	if _tilt != null:
		_tilt.rotation.z = 0.0
	if rider != null:
		rider.recover()
		_attach_rider()
	Audio.play_at("ui/unlock", global_position, 0.0)
	remounted.emit(self)


## Visual-only lean into corners and a wheelie under boost. Purely cosmetic:
## physics still uses the upright body. Applies to both procedural and GLB bikes.
func _update_lean(delta: float, steer: float, vf: float) -> void:
	if _tilt == null or wiped_out_now:
		return
	var speed_ratio := clampf(absf(vf) / maxf(def.max_speed, 1.0), 0.0, 1.0)
	var grip := clampf(absf(vf) / 4.0, 0.0, 1.0)
	var roll_target := -steer * deg_to_rad(def.lean_max) * speed_ratio * grip
	var pitch_target := deg_to_rad(6.0) if (nitro_active or _pad_boost_timer > 0.0) else 0.0
	_lean_roll = lerpf(_lean_roll, roll_target, 1.0 - exp(-9.0 * delta))
	_lean_pitch = lerpf(_lean_pitch, pitch_target, 1.0 - exp(-4.0 * delta))
	_tilt.rotation.x = _lean_pitch
	_tilt.rotation.z = _lean_roll
	if rider != null:
		rider.set_lean(_lean_roll)
		rider.set_drive(steer, speed_ratio, nitro_active or _pad_boost_timer > 0.0)


func speed_kmh() -> float:
	return velocity.length() * 3.6


func nitro_ratio() -> float:
	return clampf(nitro / def.nitro_max, 0.0, 1.0)


func is_nitro_active() -> bool:
	return nitro_active


## Called by a boost pad Area3D when the bike passes over it. Reuses the nitro
## speed multiplier pipeline, so the exhaust flares and the bike settles back to
## normal speed with the same spool-down.
func apply_pad_boost() -> void:
	if not control_enabled:
		return
	_pad_boost_timer = maxf(_pad_boost_timer, PAD_BOOST_TIME)
	if not is_opponent:
		Audio.play_at("ui/unlock", global_position, -9.0)


## Called by a nitro pickup ("бутылочка") when the bike drives over it: instantly
## refills part of the tank, never above the maximum.
func add_nitro(amount: float) -> void:
	if not control_enabled:
		return
	nitro = clampf(nitro + amount, 0.0, def.nitro_max)
	if not is_opponent:
		Audio.play_at("ui/unlock", global_position, -6.0)


## Called by a health pickup ("аптечка") when the bike drives over it: restores
## part of the health pool, never above the maximum. A wipeout already in
## progress is not cancelled — it only heals the bike for the remount.
func add_health(amount: float) -> void:
	if not control_enabled:
		return
	health = clampf(health + amount, 0.0, HEALTH_MAX)
	if not is_opponent:
		Audio.play_at("ui/unlock", global_position, -3.0)


## Called by a shield pickup: temporary immunity to combat hits (punches/kicks).
## Crash damage from walls and traffic still applies.
func add_shield(duration: float) -> void:
	if not control_enabled:
		return
	shield_time = maxf(shield_time, duration)
	if not is_opponent:
		Audio.play_at("ui/unlock", global_position, -3.0)


func has_shield() -> bool:
	return shield_time > 0.0


## True for the human rider's bike (not an AI opponent and not civilian traffic).
func is_player_racer() -> bool:
	return not is_opponent and not is_traffic


## Called by an oil slick: temporarily loses lateral grip.
func apply_oil(duration: float) -> void:
	if not control_enabled:
		return
	oil_time = maxf(oil_time, duration)


func _grip_multiplier() -> float:
	return OIL_GRIP_MULT if oil_time > 0.0 else 1.0


func _update_nitro(delta: float, request: bool) -> void:
	if not control_enabled:
		nitro = def.nitro_max
		nitro_active = false
		_boost_mult = 1.0
		_nitro_regen_timer = 0.0
		_pad_boost_timer = 0.0
		_draft_mult = 1.0
		return
	_pad_boost_timer = maxf(_pad_boost_timer - delta, 0.0)
	nitro_active = request and nitro > 0.0
	if nitro_active:
		nitro = maxf(nitro - def.nitro_burn * delta, 0.0)
		_nitro_regen_timer = def.nitro_regen_delay
	else:
		_nitro_regen_timer = maxf(_nitro_regen_timer - delta, 0.0)
		if _nitro_regen_timer <= 0.0:
			var rate := def.nitro_regen * (1.0 + (DRAFT_REGEN_BONUS if _drafting else 0.0))
			nitro = move_toward(nitro, def.nitro_max, rate * delta)
	var boost_target := def.nitro_speed_mult if (nitro_active or _pad_boost_timer > 0.0) else 1.0
	if boost_target > 1.0:
		_boost_mult = move_toward(_boost_mult, boost_target, def.nitro_spool_up * delta)
	else:
		_boost_mult = move_toward(_boost_mult, 1.0, def.nitro_spool_down * delta)


## True while tucked behind another rider: raises the speed cap and boosts nitro
## regen. Traffic cars are not draft targets (that is what near-miss is for).
func _update_draft(delta: float, vf: float) -> void:
	var found := false
	if control_enabled and not wiped_out_now and vf > 2.0 and not _offroad_now:
		for t in combat_targets:
			if not _live_target(t):
				continue
			if t.velocity.length() < DRAFT_MIN_SPEED:
				continue
			var local: Vector3 = global_transform.basis.inverse() * (t.global_position - global_position)
			if local.z > -DRAFT_MIN_GAP or local.z < -DRAFT_RANGE:
				continue
			if absf(local.x) > DRAFT_HALF_WIDTH:
				continue
			found = true
			break
	_drafting = found
	_draft_mult = move_toward(_draft_mult, DRAFT_MAX_MULT if found else 1.0, DRAFT_SPOOL * delta)


func _set_exhaust(active: bool) -> void:
	for p in _exhaust:
		p.emitting = active


func reset_to(pos: Vector3, yaw: float) -> void:
	global_position = pos + Vector3.UP * 0.6
	rotation = Vector3(0.0, yaw, 0.0)
	velocity = Vector3.ZERO
	shield_time = 0.0
	oil_time = 0.0


func respawn() -> void:
	global_transform = last_safe_transform
	velocity = Vector3.ZERO


func _build_lights() -> void:
	if not night_lights:
		return
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.13
	head_mesh.height = 0.26
	head_mesh.radial_segments = 12
	head_mesh.rings = 6
	var head_mat := StandardMaterial3D.new()
	head_mat.albedo_color = Color(0.72, 0.84, 1.0)
	head_mat.emission_enabled = true
	head_mat.emission = Color(0.68, 0.82, 1.0)
	head_mat.emission_energy_multiplier = 4.5
	head_mesh.material = head_mat
	var tail_mesh := SphereMesh.new()
	tail_mesh.radius = 0.11
	tail_mesh.height = 0.22
	tail_mesh.radial_segments = 10
	tail_mesh.rings = 5
	var tail_mat := StandardMaterial3D.new()
	tail_mat.albedo_color = Color(1.0, 0.025, 0.01)
	tail_mat.emission_enabled = true
	tail_mat.emission = Color(1.0, 0.018, 0.006)
	tail_mat.emission_energy_multiplier = 3.5
	tail_mesh.material = tail_mat
	if not is_opponent:
		var light := SpotLight3D.new()
		light.position = Vector3(0.0, 0.80, -1.15)
		light.light_color = Color(0.68, 0.82, 1.0)
		light.light_energy = 1.2
		light.light_specular = 0.5
		light.spot_range = 34.0
		light.spot_angle = 25.0
		light.spot_angle_attenuation = 1.0
		light.shadow_enabled = false
		light.light_volumetric_fog_energy = 0.12
		add_child(light)
	var head := MeshInstance3D.new()
	head.mesh = head_mesh
	head.position = Vector3(0.0, 0.72, -1.02)
	head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(head)
	var tail := MeshInstance3D.new()
	tail.mesh = tail_mesh
	tail.position = Vector3(0.0, 0.70, 0.96)
	tail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(tail)


func _build_visuals() -> void:
	# Everything hangs off a tilt node so lean/wheelie/crash rotate the whole
	# bike (GLB or procedural) around the bike-space axes, independent of the
	# model's own yaw.
	_tilt = Node3D.new()
	_tilt.name = "Tilt"
	add_child(_tilt)

	var holder: Node3D = null
	if def.model_path != "" and ResourceLoader.exists(def.model_path):
		var scene := load(def.model_path) as PackedScene
		if scene != null:
			var model := scene.instantiate() as Node3D
			if model != null:
				holder = Node3D.new()
				holder.name = "Model"
				holder.position.y = def.model_y_offset
				holder.rotation.y = def.model_yaw
				holder.scale = Vector3.ONE * def.model_scale
				holder.add_child(model)
				_tilt.add_child(holder)
				_collect_wheels(model)
				_apply_livery(model)
	if holder == null:
		if def.model_path != "":
			push_warning("Bike model missing/not a PackedScene: %s" % def.model_path)
		holder = BikeVisuals.build(def)
		_tilt.add_child(holder)
		_collect_wheels(holder)

	# Seated procedural rider on top of either body. Wide traffic (cars, buses)
	# gets no rider — only two-wheeled traffic (motorcycles) does.
	var two_wheeler := not is_traffic or def.collision_size.x < 1.3
	if two_wheeler:
		var mount: Vector3 = def.rider_mount
		if def.model_path == "":
			mount = BikeVisuals.procedural_rider_mount(def)
		rider = Rider.new()
		rider.name = "Rider"
		rider.position = mount
		rider.scale = Vector3.ONE * def.rider_scale
		rider.setup(def.rider_color, def.helmet_color, def, _resolve_skin())
		_tilt.add_child(rider)


## The player's chosen global skin wins for their own bike; AI keep the plain
## per-bike colors unless the machine names a skin (bosses).
func _resolve_skin() -> RiderSkinDef:
	if player_skin != null:
		return player_skin
	if def.rider_skin_id != "":
		var gs := get_node_or_null("/root/Game")
		if gs != null:
			return gs.skin_def_by_id(def.rider_skin_id)
	return null


## Wheels are any Node3D whose name contains "wheel"; front wheels are those
## whose name ends with fl/fr or contains "front". Each wheel node is rebuilt
## into a clean hub frame (bike orientation + hub translation only; children
## are compensated so the visual stays identical), which lets spin/steer be
## applied as pure rotations around the bike's right/up axes with no shear
## from arbitrary model-internal node scales/rotations.
func _collect_wheels(root: Node) -> void:
	var inv := global_transform.affine_inverse()
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is Node3D and n.name.to_lower().contains("wheel"):
			var lname := n.name.to_lower()
			if lname.contains("steer") or lname.contains("handle"):
				continue
			var w := n as Node3D
			var old_world := w.global_transform
			var hub_rel := inv * old_world.origin
			# clean hub frame in bike space: bike orientation + hub translation
			w.global_transform = global_transform * Transform3D(Basis.IDENTITY, hub_rel)
			# keep children visually identical: their new local transform is
			# relative to the wheel's NEW global transform
			var new_world_inv := w.global_transform.affine_inverse()
			for c in w.get_children():
				if c is Node3D:
					(c as Node3D).transform = new_world_inv * old_world * (c as Node3D).transform
			w.set_meta("hub_rel", hub_rel)
			_wheels.append(w)
			if lname.ends_with("fl") or lname.ends_with("fr") or lname.contains("front"):
				_front_wheels.append(w)


func _update_wheels(delta: float, steer: float) -> void:
	if _wheels.is_empty():
		return
	var fwd := -global_transform.basis.z
	var vf := velocity.dot(fwd)
	_wheel_spin = wrapf(
		_wheel_spin + vf / maxf(def.wheel_radius, 0.05) * delta,
		-TAU, TAU
	)
	var lean := Basis.from_euler(Vector3(_lean_pitch, 0.0, _lean_roll))
	var visual := global_transform.basis * lean
	for w in _wheels:
		var steer_angle := -steer * 0.45 if w in _front_wheels else 0.0
		var hub_rel: Vector3 = w.get_meta("hub_rel")
		var rot := Basis(Quaternion(Vector3.UP, steer_angle) * Quaternion(Vector3.RIGHT, _wheel_spin))
		w.global_transform = Transform3D(visual * rot, global_position + visual * hub_rel)


## Livery 0 replaces the albedo of every mesh in the model; shared
## normal/ORM maps from the bike folder are used when present.
func _apply_livery(root: Node) -> void:
	if def.livery_count <= 0:
		return
	var albedo := load(def.livery_path(def.livery_index)) as Texture2D
	if albedo == null:
		push_warning("Livery not found: %s" % def.livery_path(def.livery_index))
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = albedo
	var normal := _load_tex("%s/normal.png" % def.livery_dir)
	if normal != null:
		mat.normal_enabled = true
		mat.normal_texture = normal
	var orm := _load_tex("%s/orm.png" % def.livery_dir)
	if orm != null:
		mat.ao_enabled = true
		mat.ao_texture = orm
		mat.roughness_texture = orm
		mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
		mat.metallic_texture = orm
		mat.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
		mat.roughness = 1.0
		mat.metallic = 1.0
	for mi in _find_mesh_instances(root):
		mi.material_override = mat


## One-shot sounds for wall hits and hard landings; silent while the samples
## are missing. Impacts trigger only on hard, fresh collisions.
func _slide_audio(delta: float) -> void:
	_impact_cooldown = maxf(_impact_cooldown - delta, 0.0)
	var landed := is_on_floor() and not _was_on_floor
	_was_on_floor = is_on_floor()
	if landed and absf(velocity.y) > 2.0:
		Audio.play_at("impacts/landing", global_position, -6.0)
	_update_skid(delta)
	if _impact_cooldown > 0.0:
		return
	for k in get_slide_collision_count():
		var col := get_slide_collision(k)
		var normal := col.get_normal()
		if normal.y > 0.7:
			continue  # floor/ramp, not a crash
		var other := col.get_collider() as RaceBike
		# Closing speed: bikes travel together, so a gentle touch at racing pace
		# must not read as a head-on crash. Static walls have no velocity.
		var rel := _pre_slide_velocity
		if other != null:
			rel -= other.velocity
		var impact := absf(rel.dot(normal))
		if impact > 6.0:
			Audio.play_at("impacts/hit_light", global_position)
			if _sparks != null:
				_sparks.restart()
				_sparks.emitting = true
			_impact_cooldown = 0.4
			_resolve_impact(other, normal, impact)
			break


## Tire skid loop: volume follows lateral slip while on the road.
func _update_skid(delta: float) -> void:
	if _skid == null:
		return
	var right := global_transform.basis.x
	var slip := absf(velocity.dot(right))
	var slipping := is_on_floor() and not is_offroad() and slip > 4.0 and velocity.length() > 4.0
	var goal := -60.0
	if slipping:
		goal = -18.0 + clampf((slip - 4.0) / 6.0, 0.0, 1.0) * 14.0
	_skid.volume_db = lerpf(_skid.volume_db, goal, 1.0 - exp(-10.0 * delta))
	for p in _smoke:
		p.emitting = slipping
	var dusty := _offroad_now and is_on_floor() and velocity.length() > 5.0
	for p in _dust:
		p.emitting = dusty


func _add_skid_audio() -> void:
	var path := "res://assets/audio/tires/skid.ogg"
	if not ResourceLoader.exists(path):
		return
	_skid = AudioStreamPlayer3D.new()
	_skid.stream = load(path)
	_set_ogg_loop(_skid.stream)
	_skid.bus = "SFX"
	_skid.unit_size = 14.0
	_skid.max_db = 0.0
	add_child(_skid)
	_skid.play()


static func _set_ogg_loop(stream: AudioStream) -> void:
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true


## Tire smoke (drifting), offroad dust and wall-impact sparks.
func _build_vfx() -> void:
	var puff := QuadMesh.new()
	puff.size = Vector2(0.55, 0.55)
	var puff_mat := StandardMaterial3D.new()
	puff_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	puff_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	puff_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	puff_mat.albedo_color = Color(0.8, 0.8, 0.83, 0.35)
	puff.material = puff_mat

	var dust_mat := puff_mat.duplicate() as StandardMaterial3D
	dust_mat.albedo_color = Color(0.66, 0.56, 0.40, 0.40)
	var dust_mesh := puff.duplicate() as QuadMesh
	dust_mesh.material = dust_mat

	var spark := QuadMesh.new()
	spark.size = Vector2(0.14, 0.14)
	var spark_mat := StandardMaterial3D.new()
	spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	spark_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	spark_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	spark_mat.albedo_color = Color(1.0, 0.75, 0.25, 0.9)
	spark.material = spark_mat

	_smoke.append(_make_vfx_node(puff, Vector3(0.0, 0.25, 0.72), Color(0.7, 0.7, 0.72, 0.5),
		14, 0.7, Vector3(0, 1.4, 0)))
	_dust.append(_make_vfx_node(dust_mesh, Vector3(0.0, 0.25, 0.72), Color(0.62, 0.52, 0.38, 0.55),
		12, 0.8, Vector3(0, 1.8, 0)))

	var up := Vector3.UP
	_sparks = GPUParticles3D.new()
	_sparks.name = "Sparks"
	_sparks.position = Vector3(0, 0.3, -0.95)
	_sparks.amount = 16
	_sparks.lifetime = 0.4
	_sparks.one_shot = true
	_sparks.explosiveness = 1.0
	_sparks.local_coords = false
	_sparks.emitting = false
	var spm := ParticleProcessMaterial.new()
	spm.direction = Vector3(0, 0.6, -1)
	spm.spread = 55.0
	spm.initial_velocity_min = 5.0
	spm.initial_velocity_max = 10.0
	spm.gravity = Vector3(0, -22, 0)
	spm.scale_min = 0.5
	spm.scale_max = 1.0
	spm.color = Color(1.0, 0.72, 0.25)
	_sparks.process_material = spm
	_sparks.draw_pass_1 = spark
	add_child(_sparks)


func _make_vfx_node(mesh: Mesh, pos: Vector3, color: Color, amount: int,
		lifetime: float, gravity: Vector3) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.position = pos
	p.amount = amount
	p.lifetime = lifetime
	p.local_coords = false
	p.emitting = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 25.0
	pm.initial_velocity_min = 0.6
	pm.initial_velocity_max = 1.6
	pm.gravity = gravity
	pm.scale_min = 0.6
	pm.scale_max = 1.3
	pm.color = color
	p.process_material = pm
	p.draw_pass_1 = mesh
	add_child(p)
	return p


func _add_engine_audio() -> void:
	var eng := EngineAudio.new()
	eng.name = "EngineAudio"
	eng.bike = self
	add_child(eng)


func _build_exhaust() -> void:
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.4, 0.4)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_color = Color(1.0, 0.6, 0.15, 0.85)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.55, 0.1)
	mat.emission_energy_multiplier = 4.0
	mesh.material = mat

	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0.0, 0.0, 1.0)
	pm.spread = 12.0
	pm.initial_velocity_min = 7.0
	pm.initial_velocity_max = 13.0
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.5
	pm.scale_max = 1.1
	pm.color = Color(1.0, 0.6, 0.2, 0.9)

	var p := GPUParticles3D.new()
	p.name = "Exhaust"
	p.position = Vector3(0.18, 0.44, 1.05)
	p.amount = 32
	p.lifetime = 0.5
	p.local_coords = false
	p.emitting = false
	p.process_material = pm
	p.draw_pass_1 = mesh
	add_child(p)
	_exhaust.append(p)


static func _load_tex(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null


static func _find_mesh_instances(root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			out.append(n)
		for c in n.get_children():
			stack.append(c)
	return out
