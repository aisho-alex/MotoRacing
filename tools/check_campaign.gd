extends SceneTree
## Dev tool: exercises the track campaign in Game (game_state.gd): the ladder
## unlock (podium opens the next track), per-track difficulty tiers, scaled
## rewards, AI pace scaling, save/load roundtrip and legacy-save defaults.
## The real progress.cfg is snapshotted and restored afterwards.
## Run: godot --headless --path . -s tools/check_campaign.gd

const SAVE := "user://progress.cfg"

var _deferred := true


func _initialize() -> void:
	_deferred = true


func _process(_delta: float) -> bool:
	if not _deferred:
		return true
	_deferred = false
	var backup := _read(SAVE)
	var failures := 0
	var gs := _fresh()
	failures += _check_initial(gs)
	failures += _check_ladder(gs)
	failures += _check_tiers(gs)
	failures += _check_reward_scale()
	failures += _check_ai_scale()
	failures += _check_roundtrip(gs)
	failures += _check_legacy_save()
	failures += _check_bosses()
	_restore(SAVE, backup)
	print("RESULT: %s" % ("PASS" if failures == 0 else "FAIL (%d)" % failures))
	quit(0 if failures == 0 else 1)
	return true


func _new_game() -> Node:
	var gs: Node = load("res://scripts/game_state.gd").new()
	root.add_child(gs)
	return gs


func _fresh() -> Node:
	var gs := _new_game()
	gs.races_done = 0
	gs.best_pos = 0
	gs.credits = 0
	gs.upgrades = {}
	gs.unlocked_tracks = 1
	gs.track_tiers = {}
	gs.track_index = 0
	gs.track_tier = 0
	gs.owned_bikes = []
	gs.bosses_beaten = {}
	return gs


func _check_initial(gs: Node) -> int:
	var failures := 0
	if not gs.is_track_unlocked(0) or gs.is_track_unlocked(1):
		print("only the first track should be unlocked")
		failures += 1
	if gs.unlocked_tier_count(0) != 1:
		print("a fresh track should have one tier")
		failures += 1
	return failures


func _check_ladder(gs: Node) -> int:
	var failures := 0
	gs.track_index = 0
	gs.track_tier = 0
	gs.record_result(true, 2)
	if not gs.is_track_unlocked(1):
		print("podium should unlock the next track")
		failures += 1
	if gs.unlocked_tier_count(0) < 2:
		print("podium should unlock the next tier")
		failures += 1
	gs.track_index = 1
	gs.track_tier = 0
	gs.record_result(true, 3)
	if gs.is_track_unlocked(2):
		print("no podium must not unlock the next track")
		failures += 1
	if gs.unlocked_tier_count(1) != 1:
		print("no podium must not unlock the next tier")
		failures += 1
	return failures


func _check_tiers(gs: Node) -> int:
	var failures := 0
	gs.track_index = 0
	if not gs.is_tier_unlocked(0, 1) or gs.is_tier_unlocked(0, 2):
		print("tier unlock state is wrong after a podium")
		failures += 1
	gs.track_tier = 1
	gs.record_result(true, 1)
	if gs.unlocked_tier_count(0) != BikeTuning.TRACK_TIERS:
		print("win should unlock the final tier")
		failures += 1
	gs.track_tier = BikeTuning.TRACK_TIERS - 1
	gs.record_result(true, 1)
	if gs.unlocked_tier_count(0) != BikeTuning.TRACK_TIERS:
		print("tiers must cap at the maximum")
		failures += 1
	var before: int = gs.track_tier
	gs.cycle_tier(1)
	if gs.track_tier != 0 or before != BikeTuning.TRACK_TIERS - 1:
		print("cycle_tier should wrap only over unlocked tiers")
		failures += 1
	return failures


func _check_reward_scale() -> int:
	var failures := 0
	if BikeTuning.track_reward(1, 0, 0) != BikeTuning.reward_for(1):
		print("base track reward should equal the flat reward")
		failures += 1
	var early := BikeTuning.track_reward(1, 0, 0)
	var mid := BikeTuning.track_reward(1, 5, 1)
	var late := BikeTuning.track_reward(1, 10, 2)
	if not (late > mid and mid > early):
		print("reward should grow with track and tier: %d %d %d" % [early, mid, late])
		failures += 1
	return failures


func _check_ai_scale() -> int:
	var failures := 0
	if not is_equal_approx(BikeTuning.track_ai_scale(0, 0), 1.0):
		print("first track, first tier should not boost AI")
		failures += 1
	if not (BikeTuning.track_ai_scale(10, 2) > BikeTuning.track_ai_scale(5, 1)
			and BikeTuning.track_ai_scale(5, 1) > BikeTuning.track_ai_scale(0, 0)):
		print("track AI scale should grow with position and tier")
		failures += 1
	var gs := _fresh()
	gs.unlocked_tracks = 3
	gs.track_tiers = {"city_01": 3}
	gs.track_index = 0
	gs.track_tier = 0
	var base: float = gs.ai_speed_scale()
	gs.track_tier = 2
	if gs.ai_speed_scale() <= base:
		print("Game.ai_speed_scale should grow with the tier")
		failures += 1
	gs.track_index = 2
	gs.track_tier = 0
	if gs.ai_speed_scale() <= base:
		print("Game.ai_speed_scale should grow with the ladder position")
		failures += 1
	return failures


func _check_roundtrip(gs: Node) -> int:
	var failures := 0
	gs.track_index = 0
	gs.track_tier = 1
	gs.unlocked_tracks = 2
	gs.credits = 1234
	gs.upgrades = {"scrambler_01": {"engine": 2, "tires": 0, "nitro": 1}}
	gs.owned_bikes = ["boss_atlas"]
	gs.bosses_beaten = {"canyon_01": true}
	gs._save_progress()
	var loaded := _new_game()
	if loaded.unlocked_tracks != 2 or loaded.track_tier != 1 or loaded.credits != 1234:
		print("roundtrip lost progress: u=%d t=%d c=%d" % [loaded.unlocked_tracks, loaded.track_tier, loaded.credits])
		failures += 1
	if loaded.upgrade_level("scrambler_01", "engine") != 2:
		print("roundtrip lost upgrades")
		failures += 1
	if loaded.unlocked_tier_count(0) != BikeTuning.TRACK_TIERS:
		print("roundtrip lost track tiers")
		failures += 1
	if not ("boss_atlas" in loaded.owned_bikes):
		print("roundtrip lost owned bikes")
		failures += 1
	if not loaded.boss_beaten("canyon_01"):
		print("roundtrip lost beaten bosses")
		failures += 1
	return failures


func _check_legacy_save() -> int:
	var failures := 0
	var cfg := ConfigFile.new()
	cfg.set_value("progress", "races_done", 5)
	cfg.set_value("progress", "best_pos", 1)
	cfg.set_value("progress", "credits", 900)
	cfg.save(SAVE)
	var loaded := _new_game()
	if loaded.unlocked_tracks != 1:
		print("legacy save should start the campaign at track 1")
		failures += 1
	if loaded.unlocked_tier_count(0) != 1:
		print("legacy save should start tracks at tier 1")
		failures += 1
	if loaded.credits != 900:
		print("legacy save credits not loaded")
		failures += 1
	return failures


func _check_bosses() -> int:
	var failures := 0
	var gs := _fresh()
	for track_id in Bosses.DATA:
		if not (track_id in gs.TRACK_IDS):
			print("boss track missing from ladder: %s" % track_id)
			failures += 1
		var boss: Dictionary = Bosses.for_track(track_id)
		var bike_id := String(boss["bike"])
		if not ResourceLoader.exists("res://assets/data/bikes/%s.tres" % bike_id):
			print("boss bike def missing: %s" % bike_id)
			failures += 1
		elif not gs.is_shop_bike(bike_id):
			print("boss bike must be purchasable: %s" % bike_id)
			failures += 1
	if not Bosses.for_track("city_01").is_empty():
		print("city_01 should not have a boss")
		failures += 1
	var boss: Dictionary = Bosses.for_track("canyon_01")
	if boss.is_empty():
		print("canyon_01 should have a boss")
		return failures + 1
	# one-time bonus
	var bonus := int(boss["bonus"])
	gs.credits = 0
	if gs.beat_boss("canyon_01", bonus) != bonus or gs.credits != bonus:
		print("boss bonus not awarded")
		failures += 1
	if gs.beat_boss("canyon_01", bonus) != 0 or gs.credits != bonus:
		print("boss bonus must be one-time")
		failures += 1
	# shop bike purchase
	var bike_id := String(boss["bike"])
	var price: int = gs.bike_price(bike_id)
	if price <= 0 or gs.is_bike_unlocked(bike_id):
		print("shop bike should be locked and priced")
		failures += 1
	gs.credits = price - 1
	if gs.buy_bike(bike_id):
		print("buy_bike must fail when credits are short")
		failures += 1
	gs.credits = price
	if not gs.buy_bike(bike_id) or not gs.is_bike_unlocked(bike_id) or gs.credits != 0:
		print("buy_bike failed to purchase the bike")
		failures += 1
	if gs.buy_bike(bike_id):
		print("buy_bike must not sell the same bike twice")
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
