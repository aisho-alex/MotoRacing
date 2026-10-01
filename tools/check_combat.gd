extends SceneTree
## Dev tool: validates the Road Rash combat on RaceBike — punch/kick damage,
## side/range gating, attack cooldown, knockout -> wipeout -> remount, and the
## AI decide_attack hook. No rendering needed.
## Run: godot --headless --path . -s tools/check_combat.gd
##
## RaceBike and AiDriver reference each other (cyclic), so a standalone -s run
## must load them at runtime rather than preload them as consts.

var BikeScript
var DefScript
var DriverScript

var _deferred := true


func _initialize() -> void:
	_deferred = true


func _process(_delta: float) -> bool:
	if not _deferred:
		return true
	_deferred = false
	BikeScript = load("res://scripts/race_bike.gd")
	DefScript = load("res://scripts/bike_def.gd")
	DriverScript = load("res://scripts/ai_driver.gd")
	var failures := 0
	failures += _check_punch()
	failures += _check_side_gate()
	failures += _check_cooldown()
	failures += _check_knockout_and_remount()
	failures += _check_kick()
	failures += _check_crash_damage()
	failures += _check_rider_bump()
	failures += _check_ai_hook()
	failures += _check_ai_grudge()
	print("RESULT: %s" % ("PASS" if failures == 0 else "FAIL (%d)" % failures))
	quit(0 if failures == 0 else 1)
	return true


func _make_pair(gap: Vector3) -> Array:
	var a = BikeScript.new()
	a.def = DefScript.load_default()
	a.is_opponent = true
	root.add_child(a)
	a.global_position = Vector3(0.0, 1.0, 0.0)
	a.rotation = Vector3.ZERO
	var v = BikeScript.new()
	v.def = DefScript.load_default()
	v.is_opponent = true
	root.add_child(v)
	v.global_position = Vector3(0.0, 1.0, 0.0) + gap
	a.control_enabled = true
	v.control_enabled = true
	a.combat_targets = [v]
	v.combat_targets = [a]
	return [a, v]


func _check_punch() -> int:
	var p := _make_pair(Vector3(1.0, 0.0, 0.0))
	var a = p[0]
	var v = p[1]
	var before: float = v.health
	a._try_attack(1.0, "punch")
	var ok: bool = is_equal_approx(v.health, before - BikeScript.PUNCH_DAMAGE)
	if not ok:
		print("punch: expected damage %.1f, health %.1f -> %.1f" % [BikeScript.PUNCH_DAMAGE, before, v.health])
	_free_pair(p)
	return 0 if ok else 1


func _check_side_gate() -> int:
	var p := _make_pair(Vector3(1.0, 0.0, 0.0))
	var a = p[0]
	var v = p[1]
	var before: float = v.health
	a._try_attack(-1.0, "punch")  # swing left while the target is on the right
	var ok: bool = is_equal_approx(v.health, before)
	if not ok:
		print("side gate: target on the right took a left punch")
	_free_pair(p)
	return 0 if ok else 1


func _check_cooldown() -> int:
	var p := _make_pair(Vector3(1.0, 0.0, 0.0))
	var a = p[0]
	var v = p[1]
	var before: float = v.health
	a._try_attack(1.0, "punch")
	a._try_attack(1.0, "punch")  # same frame: must be blocked by the cooldown
	var ok: bool = is_equal_approx(v.health, before - BikeScript.PUNCH_DAMAGE)
	if not ok:
		print("cooldown: two punches landed in one cooldown window")
	_free_pair(p)
	return 0 if ok else 1


func _check_knockout_and_remount() -> int:
	var p := _make_pair(Vector3(1.0, 0.0, 0.0))
	var a = p[0]
	var v = p[1]
	var hits := 0
	while not v.wiped_out_now and hits < 100:
		a._attack_cooldown = 0.0
		a._try_attack(1.0, "punch")
		hits += 1
	var failures := 0
	if not v.wiped_out_now:
		print("knockout: victim survived %d punches" % hits)
		failures += 1
	v._update_wipeout(BikeScript.WIPEOUT_TIME + 0.1)
	if v.wiped_out_now:
		print("remount: still wiped out after the timer")
		failures += 1
	if not is_equal_approx(v.health, BikeScript.HEALTH_MAX):
		print("remount: health not restored (%.1f)" % v.health)
		failures += 1
	_free_pair(p)
	return failures


func _check_kick() -> int:
	var p := _make_pair(Vector3(0.6, 0.0, -1.6))  # ahead and slightly right
	var a = p[0]
	var v = p[1]
	var before: float = v.health
	a._try_attack(1.0, "kick")
	var ok: bool = is_equal_approx(v.health, before - BikeScript.KICK_DAMAGE)
	if not ok:
		print("kick: expected damage %.1f, health %.1f -> %.1f" % [BikeScript.KICK_DAMAGE, before, v.health])
	_free_pair(p)
	return 0 if ok else 1


func _check_crash_damage() -> int:
	var p := _make_pair(Vector3(1.0, 0.0, 0.0))
	var a = p[0]
	var v = p[1]
	a.is_traffic = true
	var failures := 0
	# vehicle hit at 20 m/s -> clampf(12 + 20*1.6, 10, 40) = 40 damage
	v.apply_crash_impact(a, 20.0)
	var expected := clampf(12.0 + 20.0 * 1.6, 10.0, 40.0)
	if not is_equal_approx(v.health, BikeScript.HEALTH_MAX - expected):
		print("crash vehicle: expected %.1f, health %.1f" % [BikeScript.HEALTH_MAX - expected, v.health])
		failures += 1
	# second hit inside the hurt cooldown must not stack
	var hp: float = v.health
	v.apply_crash_impact(a, 20.0)
	if not is_equal_approx(v.health, hp):
		print("crash cooldown: damage stacked in one window")
		failures += 1
	# soft wall tap below the threshold does nothing
	var hp2: float = v.health
	v._crash_hurt_cooldown = 0.0
	v.apply_crash_impact(null, 10.0)
	if not is_equal_approx(v.health, hp2):
		print("crash wall: soft tap should not hurt (%.1f -> %.1f)" % [hp2, v.health])
		failures += 1
	# repeated hard hits eventually knock the rider out
	var hits := 0
	while not v.wiped_out_now and hits < 50:
		v._crash_hurt_cooldown = 0.0
		v.apply_crash_impact(a, 30.0)
		hits += 1
	if not v.wiped_out_now:
		print("crash KO: rider survived %d hits" % hits)
		failures += 1
	_free_pair(p)
	return failures


func _check_rider_bump() -> int:
	var p := _make_pair(Vector3(0.0, 0.0, -2.0))  # v is ahead of a
	var a = p[0]
	var v = p[1]
	var failures := 0
	var hp: float = v.health
	var vz: float = v.velocity.z
	a._resolve_impact(v, Vector3(0.0, 0.0, 1.0), 8.0)
	if not is_equal_approx(v.health, hp):
		print("bump: rider-on-rider dealt damage")
		failures += 1
	if is_zero_approx(v._wobble):
		print("bump: victim was not wobbled")
		failures += 1
	if v.velocity.z >= vz:
		print("bump: victim was not nudged forward")
		failures += 1
	# even a very hard rear-end must not wipe either rider out
	a._resolve_impact(v, Vector3(0.0, 0.0, 1.0), 40.0)
	if a.wiped_out_now or v.wiped_out_now:
		print("bump: bike contact wiped a rider out")
		failures += 1
	_free_pair(p)
	return failures


func _check_ai_hook() -> int:
	var p := _make_pair(Vector3(1.0, 0.0, 0.0))
	var a = p[0]
	var v = p[1]
	var d = DriverScript.new(null, 1.0, 0.0)
	d.bikes = [a, v]
	d.aggression = 1.0
	d.decide_attack(a, 0.1)
	var ok: bool = d.attack_kind != "" and absf(d.attack_side) > 0.01
	if not ok:
		print("ai hook: decide_attack returned kind='%s' side=%.2f" % [d.attack_kind, d.attack_side])
	_free_pair(p)
	return 0 if ok else 1


func _check_ai_grudge() -> int:
	var p := _make_pair(Vector3(1.0, 0.0, 0.0))
	var a = p[0]
	var v = p[1]
	var failures := 0
	# taking a hit records the attacker on the victim
	v.take_hit(BikeScript.PUNCH_DAMAGE, a.global_position, a)
	if v.attacker != a or v.grudge_timer <= 0.0:
		print("grudge: attacker not recorded (timer=%.2f)" % v.grudge_timer)
		failures += 1
	# with zero aggression, only the grudge path should produce an attack
	var d = DriverScript.new(null, 1.0, 0.0)
	d.bikes = [a, v]
	d.aggression = 0.0
	a.grudge_timer = 4.0
	a.attacker = v
	a.global_position = v.global_position - Vector3(2.0, 0.0, 0.0)  # v is to our right
	d.decide_attack(a, 0.1)
	if d.attack_kind == "" or d.attack_side <= 0.0:
		print("grudge: no retaliation (kind='%s' side=%.2f)" % [d.attack_kind, d.attack_side])
		failures += 1
	_free_pair(p)
	return failures


func _free_pair(p: Array) -> void:
	for n in p:
		(n as Node).queue_free()
