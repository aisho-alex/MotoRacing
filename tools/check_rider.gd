extends SceneTree
## Dev tool: validates the Skeleton3D rider rig headlessly — bones exist, the IK
## plants hands/feet on the BikeDef targets, and the combat API (attack / hit /
## crash / recover) runs without errors and returns to the base pose.
## Run: godot --headless --path . -s tools/check_rider.gd

var BikeScript
var DefScript

var _deferred := true


func _initialize() -> void:
	_deferred = true


func _process(_delta: float) -> bool:
	if not _deferred:
		return true
	_deferred = false
	BikeScript = load("res://scripts/race_bike.gd")
	DefScript = load("res://scripts/bike_def.gd")
	var failures := 0
	var ids := ["scrambler_01", "sport_01", "cruiser_01", "super_01", "cop_01"]
	for id in ids:
		failures += _check_bike(id)
	print("RESULT: %s" % ("PASS" if failures == 0 else "FAIL (%d)" % failures))
	quit(0 if failures == 0 else 1)
	return true


func _check_bike(id: String) -> int:
	var path := "res://assets/data/bikes/%s.tres" % id
	if not ResourceLoader.exists(path):
		print("%s: missing def" % id)
		return 1
	var bike = BikeScript.new()
	bike.def = load(path)
	root.add_child(bike)
	var failures := 0
	var rider = bike.rider
	if rider == null:
		print("%s: no rider" % id)
		bike.queue_free()
		return 1
	var sk: Skeleton3D = rider.get_node_or_null("Skeleton")
	if sk == null:
		print("%s: no Skeleton3D" % id)
		bike.queue_free()
		return 1
	for bone_name in ["Hips", "Spine", "Chest", "Neck", "Head",
			"UpperArm.L", "Forearm.L", "Hand.L", "UpperArm.R", "Forearm.R", "Hand.R",
			"Thigh.L", "Calf.L", "Foot.L", "Thigh.R", "Calf.R", "Foot.R"]:
		if sk.find_bone(bone_name) < 0:
			print("%s: missing bone %s" % [id, bone_name])
			failures += 1
	if failures > 0:
		bike.queue_free()
		return failures
	rider._update_pose()
	for side in ["L", "R"]:
		var hand: Vector3 = sk.get_bone_global_pose(sk.find_bone("Hand." + side)).origin
		var foot: Vector3 = sk.get_bone_global_pose(sk.find_bone("Foot." + side)).origin
		failures += _near(id, "Hand." + side, hand,
			_expected(rider, "UpperArm." + side, "Forearm." + side, "Hand." + side,
				rider._hand_target[side]))
		failures += _near(id, "Foot." + side, foot,
			_expected(rider, "Thigh." + side, "Calf." + side, "Foot." + side,
				rider._foot_target[side]))
	# combat API must not throw and must restore the base root transform
	rider.attack(1.0, "punch")
	rider._process(0.16)
	rider.attack(-1.0, "kick")
	rider._process(0.16)
	rider.hit()
	rider._process(0.05)
	rider.crash()
	rider._process(0.5)
	rider.recover()
	rider._process(0.01)
	if rider.position.distance_to(rider._base_pos) > 0.001 or rider.rotation.length() > 0.001:
		print("%s: recover did not reset the rider root" % id)
		failures += 1
	# wipeout recovery must run through every phase and return to the seat
	rider.crash(1.0)
	var seen := {}
	var moved := false
	var t := 0.0
	while t < 4.4:
		rider._process(1.0 / 60.0)
		t += 1.0 / 60.0
		if rider.crash_phase != "":
			seen[rider.crash_phase] = true
		if rider.position.distance_to(rider._base_pos) > 0.5:
			moved = true
	for phase in ["eject", "getup", "run", "lift", "mount"]:
		if not seen.has(phase):
			print("%s: wipeout never entered phase %s" % [id, phase])
			failures += 1
	if not moved:
		print("%s: wiped-out rider never left the seat" % id)
		failures += 1
	rider.recover()
	rider._process(0.01)
	if rider.position.distance_to(rider._base_pos) > 0.001 or rider.rotation.length() > 0.001:
		print("%s: recover after wipeout did not reset the rider root" % id)
		failures += 1
	bike.queue_free()
	return failures


func _near(id: String, bone: String, got: Vector3, want: Vector3) -> int:
	var d := got.distance_to(want)
	if d > 0.03:
		print("%s: %s IK off by %.3f (got %s want %s)" % [id, bone, d, got, want])
		return 1
	return 0


## Where the two-bone IK should land: the target when reachable, otherwise the
## full-extension point along the aim direction.
func _expected(rider, upper: String, lower: String, end: String, target: Vector3) -> Vector3:
	var parent: String = rider._parent_of(upper)
	var p0: Vector3 = rider._glob[parent] * rider._rest[upper].origin
	var l1: float = rider._rest[lower].origin.length()
	var l2: float = rider._rest[end].origin.length()
	var v := target - p0
	var d := v.length()
	if d <= l1 + l2 - 0.002:
		return target
	return p0 + v / d * (l1 + l2 - 0.002)
