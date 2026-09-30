class_name AiDriver
extends RefCounted
## Track-following AI with car avoidance: aims at a speed-scaled lookahead
## point on a personal corridor (line_offset) beside the centerline, brakes
## for curvature AND for cars ahead, nitros on straights, and un-sticks
## itself after being blocked.

const STUCK_TIME := 1.4
const REVERSE_TIME := 1.3
const NITRO_MIN_RATIO := 0.5
const AHEAD_RANGE := 9.0
const AHEAD_HALF_WIDTH := 2.1
const DETOUR_TRIGGER := 1.1    # seconds blocked before committing to a pass
const DETOUR_TIME := 3.0
const DETOUR_OFFSET := 2.8

var track: TrackBuilder
var skill := 0.95       # 0..1, scales target speed
var speed_mult := 1.0   # extra pace from player upgrades (AI rubber-banding)
var line_offset := 0.0  # personal corridor beside the centerline (meters)
var cars: Array[RaceCar] = []  # all racers, for avoidance

var _nearest := 0
var _stuck_time := 0.0
var _reverse_time := 0.0
var _block_timer := 0.0
var _detour_time := 0.0
var _detour_side := 1.0
var _center_hug := 0.0  # seconds of centerline preference after wall contact
var _last_good_i := 0   # last sample where the car had real speed
var _stall_time := 0.0
var _wrong_time := 0.0
var _last_progress_i := 0
var _teleport_cooldown := 0.0

# diagnostics (see tools/ai_probe.gd)
var teleports := 0
var wall_hits := 0
var wrong_snaps := 0
var frames_wrong := 0
var frames_reverse := 0
var frames_detour := 0
var frames_normal := 0


func _init(track_ref: TrackBuilder, skill_mult: float = 0.95, offset: float = 0.0) -> void:
	track = track_ref
	skill = clampf(skill_mult, 0.7, 1.0)
	line_offset = offset


## Full rescan of the nearest sample — call after any teleport (spawn, restart).
func resync(car: RaceCar) -> void:
	var p := car.global_position
	var best := INF
	for i in track.sample_count():
		var d := track.centerline[i].distance_squared_to(p)
		if d < best:
			best = d
			_nearest = i
	_stuck_time = 0.0
	_reverse_time = 0.0
	_block_timer = 0.0
	_detour_time = 0.0
	_center_hug = 0.0
	_last_good_i = _nearest
	_stall_time = 0.0
	_wrong_time = 0.0
	_last_progress_i = _nearest


## Returns (steer, throttle, want_nitro).
func drive(car: RaceCar, delta: float) -> Vector3:
	_track_nearest(car)
	var fwd := -car.global_transform.basis.z
	var vf := car.velocity.dot(fwd)

	# watchdog: progress must advance sample-to-sample; otherwise reset ahead.
	# This makes any kind of stall (wall grind, donut, jam) impossible.
	# Kept as an invisible last resort: 2s threshold, +8 samples, 3s cooldown.
	if _teleport_cooldown > 0.0:
		_teleport_cooldown -= delta
	if vf > 5.0:
		_last_good_i = _nearest
	if _nearest != _last_progress_i:
		_last_progress_i = _nearest
		_stall_time = 0.0
	elif car.control_enabled and _teleport_cooldown <= 0.0:
		_stall_time += delta
	if _stall_time > 2.0:
		_stall_time = 0.0
		_teleport_cooldown = 3.0
		teleports += 1
		var n := track.sample_count()
		var i := (_nearest + 8) % n
		car.reset_to(track.centerline[i] + track.side_vector(i) * line_offset,
			track.tangent_yaw(i))
		resync(car)
		_center_hug = 1.0
		return Vector3.ZERO

	if car.control_enabled and absf(vf) < 1.0:
		_stuck_time += delta
	else:
		_stuck_time = 0.0
	if _stuck_time > STUCK_TIME:
		_reverse_time = REVERSE_TIME
		_stuck_time = 0.0

	var avoid := _avoidance(car)
	if _center_hug > 0.0:
		_center_hug -= delta

	# wrong way: facing against the track. Reversing would just lap the track
	# backwards, so after 1s of wrong-way snap the car onto the line facing
	# forward (deterministic, no swing dynamics to get stuck in).
	var tangent := track.tangents[_nearest]
	var facing := fwd.dot(tangent)
	if facing < -0.25:
		frames_wrong += 1
		_wrong_time += delta
		if _wrong_time > 1.0:
			_wrong_time = 0.0
			var rn := track.sample_count()
			var ri := (_nearest + 12) % rn
			wrong_snaps += 1
			car.reset_to(track.centerline[ri] + track.side_vector(ri) * line_offset,
				track.tangent_yaw(ri))
			resync(car)
			_center_hug = 1.0
			return Vector3.ZERO
		if vf > 1.0:
			return Vector3(0.0, -1.0, false)  # brake before pivoting
		return Vector3(clampf(_steer_to_offset(car, line_offset, 30), -1.0, 1.0), 0.6, false)
	_wrong_time = 0.0
	_last_progress_i = _nearest

	# committed pass around a blocker that keeps us crawling
	if avoid.blocked and vf < 3.0 and _reverse_time <= 0.0:
		_block_timer += delta
	else:
		_block_timer = maxf(_block_timer - 2.0 * delta, 0.0)
	if _block_timer > DETOUR_TRIGGER:
		_detour_time = DETOUR_TIME
		_detour_side = -avoid.blocker_side
		_block_timer = 0.0

	if _reverse_time > 0.0:
		frames_reverse += 1
		_reverse_time -= delta
		_center_hug = 1.5  # prefer the centerline for a bit after wall contact
		# back out while swinging the nose toward the track direction
		return Vector3(clampf(-_steer_to_offset(car, 0.0, 25) - avoid.bias, -1.0, 1.0), -1.0, false)

	# arcade steering needs speed to turn: without motion, reverse first
	if _detour_time > 0.0:
		frames_detour += 1
		_detour_time -= delta
		if vf >= -0.5:
			return Vector3(_steer_to_offset(car, 2.8 * _detour_side), 1.0, false)
		_reverse_time = maxf(_reverse_time, 0.7)
		return Vector3(-_steer_to_offset(car, 2.8 * _detour_side), -1.0, false)

	var eff_offset := line_offset
	if _center_hug > 0.0:
		eff_offset = lerpf(line_offset, 0.0, 0.7)
	# hug the inside of an upcoming bend (racing line): keeps the car off the
	# outer wall instead of drifting wide at the bend exit
	var bend := _bend_sign()
	if absf(bend) > 0.5 and _curvature_ahead() > 0.04:
		eff_offset = clampf(eff_offset + bend * 1.5, -3.5, 3.5)
	var steer := clampf(_steer_to_offset(car, eff_offset, ahead_samples(vf)) + avoid.bias * 0.7, -1.0, 1.0)
	var lat_self := (car.global_position - track.centerline[_nearest]).dot(track.side_vector(_nearest))
	frames_normal += 1
	return Vector3(steer, _throttle(car, vf, avoid.slow, lat_self), _nitro(car, vf, avoid.slow))


func ahead_samples(vf: float) -> int:
	var ahead := clampi(6 + int(absf(vf) * 0.3), 6, 14)
	if _curvature_ahead() > 0.06:
		ahead = mini(ahead, 8)  # short lookahead in bends: no chord-cutting
	return ahead


func _track_nearest(car: RaceCar) -> void:
	var n := track.sample_count()
	var pos := car.global_position
	var best := INF
	for k in range(-10, 11):
		var i := (_nearest + k + n) % n
		var d := track.centerline[i].distance_squared_to(pos)
		if d < best:
			best = d
			_nearest = i


## Cars ahead IN OUR LANE slow us down and push the aim aside; ghosts in
## other corridors are ignored (they will pass through harmlessly).
## Additionally, any wall contact adds strong steering AWAY from the wall —
## otherwise a car sliding along a wall keeps its aim parallel and grinds
## forever at crawl speed.
func _avoidance(car: RaceCar) -> Dictionary:
	var slow := 1.0
	var bias := 0.0
	var blocked := false
	var blocker_side := 1.0
	var n := track.sample_count()
	var here := track.centerline[_nearest]
	var side := track.side_vector(_nearest)
	for other in cars:
		if other == car or not is_instance_valid(other):
			continue
		var to := other.global_position - car.global_position
		var local := car.global_transform.basis.inverse() * to
		if local.z > -AHEAD_RANGE and local.z < -0.5 and absf(local.x) < AHEAD_HALF_WIDTH:
			var other_lat := (other.global_position - here).dot(side)
			if absf(other_lat - line_offset) > 1.9:
				continue  # different lane
			var gap := -local.z
			slow = minf(slow, clampf((gap - 2.5) / (AHEAD_RANGE - 2.5), 0.0, 1.0))
			bias += -signf(local.x + 0.001) * 0.8
			if gap < 5.0:
				blocked = true
				blocker_side = signf(local.x + 0.001)
	# count wall contacts only: the ground is a StaticBody3D as well, so
	# require a contact normal that is not pointing up
	for k in car.get_slide_collision_count():
		var col := car.get_slide_collision(k)
		if col.get_collider() is StaticBody3D and col.get_normal().y < 0.7:
			wall_hits += 1
			break
	# drifting wide: steer back toward the centerline before the wall
	var lat_self := (car.global_position - here).dot(side)
	if absf(lat_self) > car.road_half_width - 1.2:
		bias += signf(lat_self) * 1.2
	return {"slow": slow, "bias": clampf(bias, -1.2, 1.2), "blocked": blocked, "blocker_side": blocker_side}


## Aim at the sample `ahead` samples forward, offset sideways by `off` meters.
## Pure pursuit as a curvature command: k = 2*sin(alpha)/distance needs the
## yaw rate speed*k, and dividing by the car's real yaw authority keeps the
## controller from over-gaining — a fixed angle*gain diverges at low speed and
## spins the car onto the wrong way.
func _steer_to_offset(car: RaceCar, off: float, ahead: int = 6) -> float:
	var n := track.sample_count()
	var aim := (_nearest + ahead) % n
	var target := track.centerline[aim] + track.side_vector(aim) * off
	var to := target - car.global_position
	to.y = 0.0
	var dist := maxf(to.length(), 0.5)
	var local := car.global_transform.basis.inverse() * to
	var curvature := 2.0 * sin(atan2(local.x, -local.z)) / dist
	var speed := absf(car.velocity.dot(-car.global_transform.basis.z))
	var authority := car.def.steer_rate \
		* clampf(speed / 7.0, 0.1, 1.0) \
		* (1.0 - 0.45 * clampf(speed / car.def.max_speed, 0.0, 1.0))
	return clampf(speed * curvature / maxf(authority, 0.05), -1.0, 1.0)


## Arcade magnetism: when roughly facing forward and not in a recovery
## maneuver, pull the body toward the lane center and damp lateral velocity.
## Keeps opponents off the walls regardless of steering dynamics.
func lane_pull(car: RaceCar, delta: float) -> void:
	if _reverse_time > 0.0 or _wrong_time > 0.0:
		return
	var here := track.centerline[_nearest]
	var side := track.side_vector(_nearest)
	var fwd := -car.global_transform.basis.z
	if fwd.dot(track.tangents[_nearest]) < 0.4:
		return
	# the corridor the car is actually aiming at: the detour lane while
	# passing a blocker, its personal lane otherwise
	var corridor := line_offset
	if _detour_time > 0.0:
		corridor = DETOUR_OFFSET * _detour_side
	var err := (car.global_position - here).dot(side) - corridor
	if absf(err) < 0.2 or absf(err) > 7.0:
		return
	var vlat := car.velocity.dot(side)
	car.velocity -= side * (vlat * clampf(delta * 6.0, 0.0, 1.0))
	# pull harder the further off-corridor the car is, so one wedged against
	# a wall always works its way back onto the road
	var gain := 1.0 + clampf((absf(err) - 2.0) / 3.0, 0.0, 1.0) * 1.2
	car.global_position -= side * (err * gain * delta)


func _curvature_ahead() -> float:
	var n := track.sample_count()
	var worst := 0.0
	for k in [10, 20, 30]:
		var dot := track.tangents[_nearest].dot(track.tangents[(_nearest + k) % n])
		worst = maxf(worst, clampf(1.0 - dot, 0.0, 1.0))
	return worst


## Bend direction: +1 when the upcoming turn goes toward the car's left
## (+side_vector), -1 for a right turn, ~0 on a straight.
func _bend_sign() -> float:
	var n := track.sample_count()
	var t0: Vector3 = track.tangents[_nearest]
	var t1: Vector3 = track.tangents[(_nearest + 12) % n]
	return signf(t0.cross(t1).y)


## Corner speed limit from the estimated bend radius: the tangent angle over
## k samples gives R = spacing*k/angle, and v stays within sqrt(lat_acc * R).
func _corner_speed(car: RaceCar) -> float:
	var n := track.sample_count()
	var k := 12
	var t0: Vector3 = track.tangents[_nearest]
	var t1: Vector3 = track.tangents[(_nearest + k) % n]
	var ang := t0.angle_to(t1)
	if ang < 0.08:
		return car.def.max_speed
	var radius := track.sample_spacing(_nearest) * float(k) / maxf(ang, 0.05)
	return sqrt(14.0 * radius)


func _throttle(car: RaceCar, vf: float, slow: float, lat: float = 0.0) -> float:
	var target_speed := minf(car.def.max_speed * skill * speed_mult, _corner_speed(car))
	target_speed *= lerpf(0.15, 1.0, slow)
	if absf(lat) > car.road_half_width - 2.0:
		target_speed *= 0.7  # near a wall: leave steering margin
	if OS.get_environment("AI_DEBUG") != "" and car.name == "AI2":
		print("THR vf=", vf, " slow=", slow, " target=", target_speed,
			" near=", _nearest, " cars=", cars.size())
	if vf < target_speed:
		return 1.0
	return clampf((target_speed - vf) / 4.0, -1.0, 0.0)


func _nitro(car: RaceCar, vf: float, slow: float) -> bool:
	return slow > 0.99 \
		and _curvature_ahead() < 0.02 \
		and vf > car.def.max_speed * 0.55 \
		and car.nitro_ratio() > NITRO_MIN_RATIO
