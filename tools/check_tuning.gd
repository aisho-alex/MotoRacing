extends SceneTree
## Dev tool: validates the car upgrade balance tables (CarTuning): stat
## multipliers grow monotonically with level, the base CarDef is never mutated,
## and costs/rewards/AI scaling behave as designed.
## Run: godot --headless --path . -s tools/check_tuning.gd

const CAR_ID := "sport_01"
const BASE_STATS := [
	"max_speed", "accel", "grip", "steer_rate", "offroad_grip",
	"nitro_max", "nitro_regen", "nitro_speed_mult",
]

var _deferred := true


func _initialize() -> void:
	_deferred = true


func _process(_delta: float) -> bool:
	if not _deferred:
		return true
	_deferred = false
	var failures := 0
	failures += _check_monotonic()
	failures += _check_base_untouched()
	failures += _check_costs()
	failures += _check_rewards()
	failures += _check_ai_scale()
	failures += _check_sanitize()
	print("RESULT: %s" % ("PASS" if failures == 0 else "FAIL (%d)" % failures))
	quit(0 if failures == 0 else 1)
	return true


func _check_monotonic() -> int:
	var def := CarDef.load_default()
	var failures := 0
	for part in CarTuning.PARTS:
		var prev := CarTuning.apply(def, {part: 0})
		for level in range(1, CarTuning.MAX_LEVEL + 1):
			var tuned := CarTuning.apply(def, {part: level})
			for prop in CarTuning.PART_MULTS[part]:
				var before := float(prev.get(prop))
				var after := float(tuned.get(prop))
				if after <= before:
					print("%s lvl%d: %s did not grow (%.3f -> %.3f)" % [part, level, prop, before, after])
					failures += 1
			prev = tuned
	return failures


func _check_base_untouched() -> int:
	var def := CarDef.load_default()
	var before := {}
	for prop in BASE_STATS:
		before[prop] = float(def.get(prop))
	CarTuning.apply(def, {"engine": 3, "tires": 3, "nitro": 3})
	var failures := 0
	for prop in BASE_STATS:
		if not is_equal_approx(float(def.get(prop)), before[prop]):
			print("base CarDef mutated: %s (%.3f -> %.3f)" % [prop, before[prop], float(def.get(prop))])
			failures += 1
	return failures


func _check_costs() -> int:
	var failures := 0
	for level in range(1, CarTuning.MAX_LEVEL):
		var low := CarTuning.cost(CAR_ID, level - 1)
		var high := CarTuning.cost(CAR_ID, level)
		if high <= low:
			print("cost not increasing: lvl%d=%d lvl%d=%d" % [level, low, level + 1, high])
			failures += 1
	if CarTuning.cost(CAR_ID, CarTuning.MAX_LEVEL) != -1:
		print("maxed part should cost -1")
		failures += 1
	if CarTuning.cost("hyper_01", 0) <= CarTuning.cost("compact_01", 0):
		print("hyper should cost more than compact")
		failures += 1
	return failures


func _check_rewards() -> int:
	var failures := 0
	var last := 1 << 30
	for pos in range(1, 5):
		var reward := CarTuning.reward_for(pos)
		if reward <= 0 or reward > last:
			print("reward not decreasing at pos %d: %d" % [pos, reward])
			failures += 1
		last = reward
	if CarTuning.reward_for(99) != CarTuning.REWARD_DEFAULT:
		print("unknown position should give the default reward")
		failures += 1
	return failures


func _check_ai_scale() -> int:
	var failures := 0
	if not is_equal_approx(CarTuning.ai_speed_scale(0), 1.0):
		print("ai scale at 0 levels should be 1.0")
		failures += 1
	if CarTuning.ai_speed_scale(9) <= CarTuning.ai_speed_scale(0):
		print("ai scale should grow with total levels")
		failures += 1
	return failures


func _check_sanitize() -> int:
	var failures := 0
	var clean := CarTuning.sanitize({"engine": 99, "tires": -3})
	if clean.get("engine") != CarTuning.MAX_LEVEL or clean.get("tires") != 0 or clean.get("nitro") != 0:
		print("sanitize failed: %s" % [clean])
		failures += 1
	return failures
