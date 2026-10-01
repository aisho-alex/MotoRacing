class_name AiDriver
extends RefCounted
## Track-following AI with bike avoidance: aims at a speed-scaled lookahead
## point on a personal corridor (line_offset) beside the centerline, brakes
## for curvature AND for bikes ahead, nitros on straights, and un-sticks
## itself after being blocked.

const STUCK_TIME := 1.4
const REVERSE_TIME := 1.3
const NITRO_MIN_RATIO := 0.5
const AHEAD_RANGE := 9.0
const AHEAD_HALF_WIDTH := 2.1
const DETOUR_TRIGGER := 1.1    # seconds blocked before committing to a pass
const OVERTAKE_TRIGGER := 0.7  # racing-speed overtake of a slower blocker
const OVERTAKE_GAP := 6.0      # m/s slower than our pace = worth passing
const DETOUR_TIME := 3.0
const DETOUR_OFFSET := 2.8

var track: TrackBuilder
var skill := 0.95       # 0..1, scales target speed
var speed_mult := 1.0   # extra pace from player upgrades (AI rubber-banding)
var base_speed_mult := 1.0  # pace before the dynamic rubber-band
var line_offset := 0.0  # personal corridor beside the centerline (meters)
var bikes: Array = []  # all racers, for avoidance / combat
var attack_side := 0.0           # set by decide_attack(): +1 right, -1 left
var attack_kind := ""            # "punch" / "kick" / "" (none)
var aggression := 0.45           # 0..1 chance to swing when an opponent is close
var chase: Node3D = null         # police: ride the chased rider's line

var _nearest := 0
var _stuck_time := 0.0
var _reverse_time := 0.0
var _block_timer := 0.0
var _detour_time := 0.0
var _detour_side := 1.0
var _center_hug := 0.0  # seconds of centerline preference after wall contact
var _stall_time := 0.0
var _wrong_time := 0.0
var _last_progress_i := 0
var _teleport_cooldown := 0.0
var _debug := false

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
	_debug = OS.get_environment("AI_DEBUG") != ""


## Full rescan of the nearest sample — call after any teleport (spawn, restart).
func resync(bike: RaceBike) -> void:
	_nearest = track.nearest_sample(bike.global_position)
	_stuck_time = 0.0
	_reverse_time = 0.0
	_block_timer = 0.0
	_detour_time = 0.0
	_center_hug = 0.0
	_stall_time = 0.0
	_wrong_time = 0.0
	_last_progress_i = _nearest


## Returns (steer, throttle, want_nitro).
func drive(bike: RaceBike, delta: float) -> Vector3:
	_track_nearest(bike)
	var fwd := -bike.global_transform.basis.z
	var vf := bike.velocity.dot(fwd)

	# watchdog: progress must advance sample-to-sample; otherwise reset ahead.
	# This makes any kind of stall (wall grind, donut, jam) impossible.
	# Kept as an invisible last resort: 2s threshold, +8 samples, 3s cooldown.
	if _teleport_cooldown > 0.0:
		_teleport_cooldown -= delta
	if _nearest != _last_progress_i:
		_last_progress_i = _nearest
		_stall_time = 0.0
	elif bike.control_enabled and _teleport_cooldown <= 0.0:
		_stall_time += delta
	if _stall_time > 2.0:
		_stall_time = 0.0
		_teleport_cooldown = 3.0
		teleports += 1
		var n := track.sample_count()
		var i := (_nearest + 8) % n
		bike.reset_to(track.centerline[i] + track.side_vector(i) * line_offset,
			track.tangent_yaw(i))
		resync(bike)
		_center_hug = 1.0
		return Vector3.ZERO

	if bike.control_enabled and absf(vf) < 1.0:
		_stuck_time += delta
	else:
		_stuck_time = 0.0
	if _stuck_time > STUCK_TIME:
		_reverse_time = REVERSE_TIME
		_stuck_time = 0.0

	var avoid := _avoidance(bike)
	if _center_hug > 0.0:
		_center_hug -= delta

	# wrong way: facing against the track. Reversing would just lap the track
	# backwards, so after 1s of wrong-way snap the bike onto the line facing
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
			bike.reset_to(track.centerline[ri] + track.side_vector(ri) * line_offset,
				track.tangent_yaw(ri))
			resync(bike)
			_center_hug = 1.0
			return Vector3.ZERO
		if vf > 1.0:
			return Vector3(0.0, -1.0, false)  # brake before pivoting
		return Vector3(_steer_to_offset(bike, line_offset, 30), 0.6, false)
	_wrong_time = 0.0

	# pass a blocker that keeps us crawling (emergency) OR is much slower than
	# our own pace (racing overtake, do not just sit behind it)
	var blocked_now: bool = avoid.blocked and _reverse_time <= 0.0
	var must_pass: bool = blocked_now and vf < 3.0
	var want_pass: bool = blocked_now and _blocker_much_slower(bike, avoid)
	if must_pass or want_pass:
		_block_timer += delta
	else:
		_block_timer = maxf(_block_timer - 2.0 * delta, 0.0)
	var trigger := DETOUR_TRIGGER if must_pass else OVERTAKE_TRIGGER
	if _block_timer > trigger:
		_detour_time = DETOUR_TIME
		_detour_side = -avoid.blocker_side
		_block_timer = 0.0

	if _reverse_time > 0.0:
		frames_reverse += 1
		_reverse_time -= delta
		_center_hug = 1.5  # prefer the centerline for a bit after wall contact
		# back out while swinging the nose toward the track direction
		return Vector3(clampf(-_steer_to_offset(bike, 0.0, 25) - avoid.bias, -1.0, 1.0), -1.0, false)

	# arcade steering needs speed to turn: without motion, reverse first
	if _detour_time > 0.0:
		frames_detour += 1
		_detour_time -= delta
		if vf >= -0.5:
			return Vector3(_steer_to_offset(bike, DETOUR_OFFSET * _detour_side), 1.0, false)
		_reverse_time = maxf(_reverse_time, 0.7)
		return Vector3(-_steer_to_offset(bike, DETOUR_OFFSET * _detour_side), -1.0, false)

	var eff_offset := line_offset
	if _center_hug > 0.0:
		eff_offset = lerpf(line_offset, 0.0, 0.7)
	# Police pursuit: aim at the chased rider's line instead of our own corridor.
	if chase != null and is_instance_valid(chase):
		var cl: float = (chase.global_position - track.centerline[_nearest]).dot(track.side_vector(_nearest))
		eff_offset = clampf(cl, -3.5, 3.5)
	# hug the inside of an upcoming bend (racing line): keeps the bike off the
	# outer wall instead of drifting wide at the bend exit
	var bend := _bend_sign()
	if absf(bend) > 0.5 and _curvature_ahead() > 0.04:
		eff_offset = clampf(eff_offset + bend * 1.5, -3.5, 3.5)
	var steer := clampf(_steer_to_offset(bike, eff_offset, ahead_samples(vf)) + avoid.bias * 0.7, -1.0, 1.0)
	var lat_self := (bike.global_position - track.centerline[_nearest]).dot(track.side_vector(_nearest))
	# While lining up an overtake do not brake down to the blocker's pace.
	var slow_eff: float = avoid.slow
	if want_pass:
		slow_eff = maxf(slow_eff, 0.9)
	frames_normal += 1
	return Vector3(steer, _throttle(bike, vf, slow_eff, lat_self), _nitro(bike, vf, slow_eff))


## True when the bike blocking us ahead is clearly slower than our own pace,
## so we should overtake instead of matching its speed.
func _blocker_much_slower(bike: RaceBike, avoid: Dictionary) -> bool:
	var my_pace: float = bike.def.max_speed * skill * speed_mult
	return my_pace - float(avoid["blocker_speed"]) > OVERTAKE_GAP


## Road Rash AI: swing at a bike that sits beside/ahead of us. Called every
## physics frame by RaceBike; the bike itself enforces the attack cooldown.
## Retaliation: a rider who just hit us becomes the priority target.
func decide_attack(bike: RaceBike, _delta: float) -> void:
	attack_side = 0.0
	attack_kind = ""
	if not bike.control_enabled or bike.wiped_out_now:
		return
	if bike.grudge_timer > 0.0 and is_instance_valid(bike.attacker) and not bike.attacker.wiped_out_now:
		var g: Vector3 = bike.global_transform.basis.inverse() * (bike.attacker.global_position - bike.global_position)
		if absf(g.z) < 3.0 and absf(g.x) < 2.4:
			attack_side = signf(g.x) if absf(g.x) > 0.05 else (1.0 if randf() < 0.5 else -1.0)
			attack_kind = "kick" if absf(g.z) < 1.5 and randf() < 0.4 else "punch"
			return
	for other in bikes:
		if other == bike or not is_instance_valid(other) or other.wiped_out_now:
			continue
		if not other.control_enabled:
			continue
		var local: Vector3 = bike.global_transform.basis.inverse() * (other.global_position - bike.global_position)
		if absf(local.z) < 2.2 and absf(local.x) < 1.8 and local.z < 0.7:
			# wheel-to-wheel: more eager to throw a hit
			var aggr: float = aggression
			if absf(local.x) < 1.0:
				aggr = minf(aggr + 0.25, 0.95)
			if randf() < aggr:
				attack_side = signf(local.x) if absf(local.x) > 0.05 else (1.0 if randf() < 0.5 else -1.0)
				attack_kind = "kick" if absf(local.z) < 1.3 and randf() < 0.35 else "punch"
			return


func ahead_samples(vf: float) -> int:
	var ahead := clampi(6 + int(absf(vf) * 0.3), 6, 14)
	if _curvature_ahead() > 0.06:
		ahead = mini(ahead, 8)  # short lookahead in bends: no chord-cutting
	return ahead


func _track_nearest(bike: RaceBike) -> void:
	_nearest = track.nearest_sample(bike.global_position, _nearest, 10)


## Bikes ahead IN OUR LANE slow us down and push the aim aside; ghosts in
## other corridors are ignored (they will pass through harmlessly).
## Additionally, any wall contact adds strong steering AWAY from the wall —
## otherwise a bike sliding along a wall keeps its aim parallel and grinds
## forever at crawl speed.
func _avoidance(bike: RaceBike) -> Dictionary:
	var slow := 1.0
	var bias := 0.0
	var blocked := false
	var blocker_side := 1.0
	var blocker_speed := 1e9
	var n := track.sample_count()
	var here := track.centerline[_nearest]
	var side := track.side_vector(_nearest)
	for other in bikes:
		if other == bike or not is_instance_valid(other):
			continue
		var to: Vector3 = other.global_position - bike.global_position
		var local: Vector3 = bike.global_transform.basis.inverse() * to
		if local.z > -AHEAD_RANGE and local.z < -0.5 and absf(local.x) < AHEAD_HALF_WIDTH:
			var other_lat: float = (other.global_position - here).dot(side)
			if absf(other_lat - line_offset) > 1.9:
				continue  # different lane
			var gap: float = -local.z
			slow = minf(slow, clampf((gap - 2.5) / (AHEAD_RANGE - 2.5), 0.0, 1.0))
			bias += -signf(local.x + 0.001) * 0.8
			if gap < 5.0:
				blocked = true
				blocker_side = signf(local.x + 0.001)
				blocker_speed = minf(blocker_speed, _forward_speed(other))
	# count wall contacts only: the ground is a StaticBody3D as well, so
	# require a contact normal that is not pointing up
	for k in bike.get_slide_collision_count():
		var col := bike.get_slide_collision(k)
		if col.get_collider() is StaticBody3D and col.get_normal().y < 0.7:
			wall_hits += 1
			break
	# drifting wide: steer back toward the centerline before the wall
	var lat_self := (bike.global_position - here).dot(side)
	if absf(lat_self) > bike.road_half_width - 1.2:
		bias += signf(lat_self) * 1.2
	return {"slow": slow, "bias": clampf(bias, -1.2, 1.2), "blocked": blocked,
		"blocker_side": blocker_side, "blocker_speed": blocker_speed}


## Forward speed (m/s) of another bike, for pass decisions.
func _forward_speed(other: RaceBike) -> float:
	return other.velocity.dot(-other.global_transform.basis.z)


## Aim at the sample `ahead` samples forward, offset sideways by `off` meters.
## Pure pursuit as a curvature command: k = 2*sin(alpha)/distance needs the
## yaw rate speed*k, and dividing by the bike's real yaw authority keeps the
## controller from over-gaining — a fixed angle*gain diverges at low speed and
## spins the bike onto the wrong way.
func _steer_to_offset(bike: RaceBike, off: float, ahead: int = 6) -> float:
	var n := track.sample_count()
	var aim := (_nearest + ahead) % n
	var target := track.centerline[aim] + track.side_vector(aim) * off
	var to := target - bike.global_position
	to.y = 0.0
	var dist := maxf(to.length(), 0.5)
	var local := bike.global_transform.basis.inverse() * to
	var curvature := 2.0 * sin(atan2(local.x, -local.z)) / dist
	var speed := absf(bike.velocity.dot(-bike.global_transform.basis.z))
	# Same yaw-authority curve as the bike physics, with a small floor so the
	# controller does not blow up at a standstill.
	var authority: float = maxf(bike.def.steer_authority(speed), bike.def.steer_rate * 0.1)
	return clampf(speed * curvature / maxf(authority, 0.05), -1.0, 1.0)


## Arcade magnetism: when roughly facing forward and not in a recovery
## maneuver, pull the body toward the lane center and damp lateral velocity.
## Keeps opponents off the walls regardless of steering dynamics.
func lane_pull(bike: RaceBike, delta: float) -> void:
	if _reverse_time > 0.0 or _wrong_time > 0.0:
		return
	var here := track.centerline[_nearest]
	var side := track.side_vector(_nearest)
	var fwd := -bike.global_transform.basis.z
	if fwd.dot(track.tangents[_nearest]) < 0.4:
		return
	# the corridor the bike is actually aiming at: the detour lane while
	# passing a blocker, its personal lane otherwise
	var corridor := line_offset
	if _detour_time > 0.0:
		corridor = DETOUR_OFFSET * _detour_side
	var err := (bike.global_position - here).dot(side) - corridor
	if absf(err) < 0.2 or absf(err) > 7.0:
		return
	var vlat := bike.velocity.dot(side)
	bike.velocity -= side * (vlat * clampf(delta * 6.0, 0.0, 1.0))
	# pull harder the further off-corridor the bike is, so one wedged against
	# a wall always works its way back onto the road
	var gain := 1.0 + clampf((absf(err) - 2.0) / 3.0, 0.0, 1.0) * 1.2
	bike.global_position -= side * (err * gain * delta)


func _curvature_ahead() -> float:
	var n := track.sample_count()
	var worst := 0.0
	for k in [10, 20, 30]:
		var dot := track.tangents[_nearest].dot(track.tangents[(_nearest + k) % n])
		worst = maxf(worst, clampf(1.0 - dot, 0.0, 1.0))
	return worst


## Bend direction: +1 when the upcoming turn goes toward the bike's left
## (+side_vector), -1 for a right turn, ~0 on a straight.
func _bend_sign() -> float:
	var n := track.sample_count()
	var t0: Vector3 = track.tangents[_nearest]
	var t1: Vector3 = track.tangents[(_nearest + 12) % n]
	return signf(t0.cross(t1).y)


## Corner speed limit from the estimated bend radius: the tangent angle over
## k samples gives R = spacing*k/angle, and v stays within sqrt(lat_acc * R).
func _corner_speed(bike: RaceBike) -> float:
	var n := track.sample_count()
	var k := 12
	var t0: Vector3 = track.tangents[_nearest]
	var t1: Vector3 = track.tangents[(_nearest + k) % n]
	var ang := t0.angle_to(t1)
	if ang < 0.08:
		return bike.def.max_speed
	var radius := track.sample_spacing(_nearest) * float(k) / maxf(ang, 0.05)
	return sqrt(14.0 * radius)


func _throttle(bike: RaceBike, vf: float, slow: float, lat: float = 0.0) -> float:
	var target_speed := minf(bike.def.max_speed * skill * speed_mult, _corner_speed(bike))
	target_speed *= lerpf(0.15, 1.0, slow)
	if absf(lat) > bike.road_half_width - 2.0:
		target_speed *= 0.7  # near a wall: leave steering margin
	if _debug and bike.name == "AI2":
		print("THR vf=", vf, " slow=", slow, " target=", target_speed,
			" near=", _nearest, " bikes=", bikes.size())
	if vf < target_speed:
		return 1.0
	return clampf((target_speed - vf) / 4.0, -1.0, 0.0)


func _nitro(bike: RaceBike, vf: float, slow: float) -> bool:
	return slow > 0.99 \
		and _curvature_ahead() < 0.02 \
		and vf > bike.def.max_speed * 0.55 \
		and bike.nitro_ratio() > NITRO_MIN_RATIO
