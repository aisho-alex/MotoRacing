extends SceneTree
## Dev tool: exercises the credit/upgrade shop logic in Game (game_state.gd):
## rewards, unlock gating, affordability, leveling, tuned defs and save/load.
## The real progress.cfg is snapshotted and restored afterwards.
## Run: godot --headless --path . -s tools/check_shop.gd

const SAVE := "user://progress.cfg"
const CAR := "compact_01"

var _deferred := true


func _initialize() -> void:
	_deferred = true


func _process(_delta: float) -> bool:
	if not _deferred:
		return true
	_deferred = false
	var backup := _read(SAVE)
	var failures := 0
	var gs: Node = load("res://scripts/game_state.gd").new()
	root.add_child(gs)

	gs.races_done = 0
	gs.best_pos = 0
	gs.credits = 0
	gs.upgrades = {}

	failures += _check_unlock_gate(gs)
	failures += _check_reward(gs)
	failures += _check_affordability(gs)
	failures += _check_buy_and_tuned(gs)
	failures += _check_max(gs)

	_restore(SAVE, backup)
	print("RESULT: %s" % ("PASS" if failures == 0 else "FAIL (%d)" % failures))
	quit(0 if failures == 0 else 1)
	return true


func _check_unlock_gate(gs: Node) -> int:
	var failures := 0
	if gs.is_car_unlocked("sport_01"):
		print("sport should be locked before any race")
		failures += 1
	gs.credits = 99999
	if gs.buy_upgrade("sport_01", "engine"):
		print("locked car must not be upgradable")
		failures += 1
	if gs.upgrade_level("sport_01", "engine") != 0:
		print("locked car level changed")
		failures += 1
	return failures


func _check_reward(gs: Node) -> int:
	var failures := 0
	gs.credits = 0
	var earned: int = gs.record_result(true, 1)
	if earned != CarTuning.reward_for(1):
		print("reward mismatch: got %d" % earned)
		failures += 1
	if gs.credits != earned:
		print("credits not credited: %d" % gs.credits)
		failures += 1
	if not gs.is_car_unlocked("hyper_01"):
		print("win should unlock hyper")
		failures += 1
	return failures


func _check_affordability(gs: Node) -> int:
	var failures := 0
	var price: int = gs.upgrade_cost(CAR, "engine")
	if price != CarTuning.cost(CAR, 0):
		print("cost mismatch: %d" % price)
		failures += 1
	gs.credits = price - 1
	if gs.can_afford_upgrade(CAR, "engine"):
		print("should not afford with one credit short")
		failures += 1
	if gs.buy_upgrade(CAR, "engine"):
		print("buy must fail when credits are short")
		failures += 1
	gs.credits = price
	if not gs.can_afford_upgrade(CAR, "engine"):
		print("should afford with exact credits")
		failures += 1
	return failures


func _check_buy_and_tuned(gs: Node) -> int:
	var failures := 0
	gs.credits = 100000
	var base_speed: float = gs.car_def_by_id(CAR).max_speed
	var price: int = gs.upgrade_cost(CAR, "engine")
	var before: int = gs.credits
	if not gs.buy_upgrade(CAR, "engine"):
		print("valid buy failed")
		failures += 1
	if gs.credits != before - price:
		print("credits not deducted: %d -> %d" % [before, gs.credits])
		failures += 1
	if gs.upgrade_level(CAR, "engine") != 1:
		print("level not incremented")
		failures += 1
	var tuned_speed: float = gs.tuned_def_for(CAR).max_speed
	if tuned_speed <= base_speed:
		print("tuned def did not grow: %.2f -> %.2f" % [base_speed, tuned_speed])
		failures += 1
	if not is_equal_approx(gs.car_def_by_id(CAR).max_speed, base_speed):
		print("base def mutated")
		failures += 1
	return failures


func _check_max(gs: Node) -> int:
	var failures := 0
	gs.credits = 1000000
	while gs.upgrade_level(CAR, "tires") < CarTuning.MAX_LEVEL:
		if not gs.buy_upgrade(CAR, "tires"):
			print("buy to max failed")
			failures += 1
			break
	if gs.upgrade_cost(CAR, "tires") != -1:
		print("maxed cost should be -1")
		failures += 1
	if gs.buy_upgrade(CAR, "tires"):
		print("buy past max must fail")
		failures += 1
	return failures


func _read(path: String) -> PackedByteArray:
	if not FileAccess.file_exists(path):
		return PackedByteArray()
	return FileAccess.get_file_as_bytes(path)


func _restore(path: String, data: PackedByteArray) -> void:
	if data.is_empty():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		return
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_buffer(data)
