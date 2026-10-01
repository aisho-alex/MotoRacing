extends Node
## Autoload "Game": bike/track selection, savefile progression and unlocks.

const BIKE_IDS := ["scrambler_01", "sport_01", "cruiser_01", "super_01"]
## Pre-motorcycle car ids, position-for-position with BIKE_IDS; used only to
## migrate an old savefile's upgrade levels.
const LEGACY_CAR_IDS := ["compact_01", "sport_01", "muscle_01", "hyper_01"]
const TRACK_IDS := [
	"city_01", "desert_01", "alpine_01", "coast_01",
	"city_02", "desert_02", "alpine_02", "coast_02",
	"canyon_01", "sakura_01", "volcano_01",
]
const SAVE_PATH := "user://progress.cfg"

var bike_index := 0
var track_index := 0
var track_tier := 0  # 0-based difficulty level on the selected track

var races_done := 0
var best_pos := 0  # 1 = win; 0 = no finished races yet
var credits := 0
var upgrades := {}  # bike_id -> {engine, tires, nitro}
var unlocked_tracks := 1  # ladder prefix: tracks [0, unlocked_tracks) are open
var track_tiers := {}  # track_id -> number of unlocked difficulty tiers (1..3)
var records := {}  # "track_id:tier" -> {"lap": best_lap, "race": best_race} (-1 = unset)


func _ready() -> void:
	_load_progress()


## Unlocks: Scrambler is free; Sport after finishing any race; Cruiser after a
## podium (2nd or better); Superbike after winning a race.
func is_bike_unlocked(bike_id: String) -> bool:
	match bike_id:
		"sport_01":
			return races_done >= 1
		"cruiser_01":
			return best_pos > 0 and best_pos <= 2
		"super_01":
			return best_pos == 1
	return true


func lock_hint(bike_id: String) -> String:
	var name := bike_def_by_id(bike_id).display_name
	match bike_id:
		"sport_01":
			return "%s — finish a race to unlock" % name
		"cruiser_01":
			return "%s — finish 2nd or better to unlock" % name
		"super_01":
			return "%s — win a race to unlock" % name
	return ""


## Records the finish, rewards credits (scaled by campaign position and level)
## and opens the next track / difficulty level on a podium. Returns the amount
## earned (0 when the race was not finished).
func record_result(finished: bool, pos: int) -> int:
	if not finished:
		return 0
	races_done += 1
	if best_pos == 0 or pos < best_pos:
		best_pos = pos
	var earned := BikeTuning.track_reward(pos, track_index, track_tier)
	credits += earned
	if pos > 0 and pos <= 2:
		_unlock_after_podium()
	_save_progress()
	return earned


## Adds credits outside the race reward (e.g. knocking a cop down) and saves.
func add_credits(amount: int) -> void:
	credits += maxi(amount, 0)
	_save_progress()


func _unlock_after_podium() -> void:
	var id: String = TRACK_IDS[track_index]
	var unlocked := unlocked_tier_count(track_index)
	track_tiers[id] = mini(maxi(unlocked, track_tier + 2), BikeTuning.TRACK_TIERS)
	if track_index + 1 >= unlocked_tracks and track_index + 1 < TRACK_IDS.size():
		unlocked_tracks = track_index + 2


func cycle_bike(dir: int) -> void:
	for _attempt in BIKE_IDS.size():
		bike_index = wrapi(bike_index + dir, 0, BIKE_IDS.size())
		if is_bike_unlocked(BIKE_IDS[bike_index]):
			return


## Ladder campaign: track 0 is always open; a podium (top-2) opens the next
## track. Each track also has TRACK_TIERS difficulty levels, level N+1 opens
## after a podium at level N of the same track.
func is_track_unlocked(index: int) -> bool:
	return index >= 0 and index < unlocked_tracks


func unlocked_tier_count(track_index_ref: int) -> int:
	if track_index_ref < 0 or track_index_ref >= TRACK_IDS.size():
		return 1
	return clampi(int(track_tiers.get(TRACK_IDS[track_index_ref], 1)), 1, BikeTuning.TRACK_TIERS)


func is_tier_unlocked(track_index_ref: int, tier: int) -> bool:
	return tier >= 0 and tier < unlocked_tier_count(track_index_ref)


func track_lock_hint(index: int) -> String:
	if index <= 0 or index >= TRACK_IDS.size():
		return ""
	if index == unlocked_tracks:
		return "%s — podium on %s to unlock" % [track_name_at(index), track_name_at(index - 1)]
	return "%s — locked" % track_name_at(index)


func tier_label() -> String:
	return "LEVEL %d/%d" % [track_tier + 1, BikeTuning.TRACK_TIERS]


## --- Track records (best lap / full-race time per track + difficulty tier) ---

## Stored best lap on a track/tier, or -1.0 when none is set yet.
func best_lap_at(track_index_ref: int, tier: int) -> float:
	return float(_record_at(track_index_ref, tier).get("lap", -1.0))


## Stored best full-race time (all laps) on a track/tier, or -1.0 when none.
func best_race_at(track_index_ref: int, tier: int) -> float:
	return float(_record_at(track_index_ref, tier).get("race", -1.0))


## Records a lap time; returns true when it beats the stored best. Persists.
func record_lap(track_index_ref: int, tier: int, lap_time: float) -> bool:
	return _record_best(track_index_ref, tier, "lap", lap_time)


## Records a full-race time; returns true when it beats the stored best. Persists.
func record_race(track_index_ref: int, tier: int, race_time: float) -> bool:
	return _record_best(track_index_ref, tier, "race", race_time)


func _record_best(track_index_ref: int, tier: int, field: String, value: float) -> bool:
	if value <= 0.0 or _record_key(track_index_ref, tier) == "":
		return false
	var rec := _record_at(track_index_ref, tier)
	var prev := float(rec.get(field, -1.0))
	if prev > 0.0 and value >= prev:
		return false
	rec[field] = value
	_store_record(track_index_ref, tier, rec)
	return true


## One-line record summary for the menu (or "no record" when both are unset).
func record_hint(track_index_ref: int, tier: int) -> String:
	var lap := best_lap_at(track_index_ref, tier)
	var race := best_race_at(track_index_ref, tier)
	if lap <= 0.0 and race <= 0.0:
		return "no record"
	return "REC  LAP %s · RACE %s" % [Hud.fmt(lap), Hud.fmt(race)]


func _record_at(track_index_ref: int, tier: int) -> Dictionary:
	var key := _record_key(track_index_ref, tier)
	if key == "":
		return {}
	return records.get(key, {})


func _record_key(track_index_ref: int, tier: int) -> String:
	if track_index_ref < 0 or track_index_ref >= TRACK_IDS.size():
		return ""
	if tier < 0 or tier >= BikeTuning.TRACK_TIERS:
		return ""
	return "%s:%d" % [TRACK_IDS[track_index_ref], tier]


func _store_record(track_index_ref: int, tier: int, rec: Dictionary) -> void:
	records[_record_key(track_index_ref, tier)] = rec
	_save_progress()


func cycle_track(dir: int) -> void:
	if unlocked_tracks <= 1:
		return
	track_index = wrapi(track_index + dir, 0, unlocked_tracks)
	track_tier = 0


func cycle_tier(dir: int) -> void:
	var count := unlocked_tier_count(track_index)
	if count <= 1:
		return
	track_tier = wrapi(track_tier + dir, 0, count)


func bike_name() -> String:
	return bike_def().display_name


func track_name() -> String:
	return track_name_at(track_index)


func track_name_at(index: int) -> String:
	var def := track_def_at(index)
	if def.display_name != "":
		return def.display_name
	var id: String = TRACK_IDS[index]
	return id.split("_")[0].capitalize()


func bike_def() -> BikeDef:
	return bike_def_by_id(current_bike_id())


func bike_def_by_id(bike_id: String) -> BikeDef:
	var path := "res://assets/data/bikes/%s.tres" % bike_id
	if ResourceLoader.exists(path):
		var res := load(path) as BikeDef
		if res != null:
			return res
	return BikeDef.new()


func track_def() -> TrackDef:
	return track_def_at(track_index)


func track_def_at(index: int) -> TrackDef:
	var path := "res://assets/data/tracks/%s.tres" % TRACK_IDS[index]
	if ResourceLoader.exists(path):
		var res := load(path) as TrackDef
		if res != null:
			return res
	return TrackDef.new()


func current_bike_id() -> String:
	return BIKE_IDS[bike_index]


## Upgrade levels for a bike, always a sanitized {engine, tires, nitro} dict.
func upgrade_levels(bike_id: String) -> Dictionary:
	if not upgrades.has(bike_id):
		upgrades[bike_id] = BikeTuning.empty_levels()
	return BikeTuning.sanitize(upgrades[bike_id])


func upgrade_level(bike_id: String, part: String) -> int:
	return int(upgrade_levels(bike_id).get(part, 0))


func upgrade_cost(bike_id: String, part: String) -> int:
	return BikeTuning.cost(bike_id, upgrade_level(bike_id, part))


func can_afford_upgrade(bike_id: String, part: String) -> bool:
	var price := upgrade_cost(bike_id, part)
	return price >= 0 and credits >= price


func buy_upgrade(bike_id: String, part: String) -> bool:
	if not is_bike_unlocked(bike_id):
		return false
	if not can_afford_upgrade(bike_id, part):
		return false
	var price := upgrade_cost(bike_id, part)
	credits -= price
	var levels := upgrade_levels(bike_id)
	levels[part] = int(levels[part]) + 1
	upgrades[bike_id] = levels
	_save_progress()
	return true


func total_upgrade_levels(bike_id: String) -> int:
	return BikeTuning.total_levels(upgrade_levels(bike_id))


## Base def with the bike's upgrades applied — used for the player's bike only.
func player_bike_def() -> BikeDef:
	return tuned_def_for(current_bike_id())


func tuned_def_for(bike_id: String) -> BikeDef:
	return BikeTuning.apply(bike_def_by_id(bike_id), upgrade_levels(bike_id))


## Opponent speed multiplier: upgrades keep races competitive as the garage is
## filled in; campaign position and difficulty level make later races harder.
func ai_speed_scale() -> float:
	return (
		BikeTuning.ai_speed_scale(total_upgrade_levels(current_bike_id()))
		* BikeTuning.track_ai_scale(track_index, track_tier)
	)


func _load_progress() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	races_done = int(cfg.get_value("progress", "races_done", 0))
	best_pos = int(cfg.get_value("progress", "best_pos", 0))
	credits = int(cfg.get_value("progress", "credits", 0))
	bike_index = clampi(int(cfg.get_value("progress", "bike_index",
		cfg.get_value("progress", "car_index", 0))), 0, BIKE_IDS.size() - 1)
	track_index = clampi(int(cfg.get_value("progress", "track_index", 0)), 0, TRACK_IDS.size() - 1)
	upgrades = {}
	for i in BIKE_IDS.size():
		var id: String = BIKE_IDS[i]
		var saved: Variant = cfg.get_value("upgrades", id, {})
		# migrate upgrades saved under the pre-bike car ids
		if (not (saved is Dictionary) or (saved as Dictionary).is_empty()) and i < LEGACY_CAR_IDS.size():
			var legacy: Variant = cfg.get_value("upgrades", LEGACY_CAR_IDS[i], {})
			if legacy is Dictionary and not (legacy as Dictionary).is_empty():
				saved = legacy
		upgrades[id] = BikeTuning.sanitize(saved if saved is Dictionary else {})
	unlocked_tracks = clampi(int(cfg.get_value("progress", "unlocked_tracks", 1)), 1, TRACK_IDS.size())
	track_tiers = {}
	for id in TRACK_IDS:
		track_tiers[id] = clampi(int(cfg.get_value("tracks", id, 1)), 1, BikeTuning.TRACK_TIERS)
	records = {}
	for id in TRACK_IDS:
		for t in BikeTuning.TRACK_TIERS:
			var key := "%s:%d" % [id, t]
			var saved_rec: Variant = cfg.get_value("records", key, {})
			if not (saved_rec is Dictionary) or (saved_rec as Dictionary).is_empty():
				continue
			var lap := float((saved_rec as Dictionary).get("lap", -1.0))
			var race := float((saved_rec as Dictionary).get("race", -1.0))
			if lap > 0.0 or race > 0.0:
				records[key] = {
					"lap": lap if lap > 0.0 else -1.0,
					"race": race if race > 0.0 else -1.0,
				}
	track_index = clampi(track_index, 0, unlocked_tracks - 1)
	track_tier = clampi(int(cfg.get_value("progress", "track_tier", 0)), 0, unlocked_tier_count(track_index) - 1)


func _save_progress() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("progress", "races_done", races_done)
	cfg.set_value("progress", "best_pos", best_pos)
	cfg.set_value("progress", "credits", credits)
	cfg.set_value("progress", "bike_index", bike_index)
	cfg.set_value("progress", "track_index", track_index)
	cfg.set_value("progress", "track_tier", track_tier)
	cfg.set_value("progress", "unlocked_tracks", unlocked_tracks)
	for id in BIKE_IDS:
		cfg.set_value("upgrades", id, upgrade_levels(id))
	for id in TRACK_IDS:
		cfg.set_value("tracks", id, int(track_tiers.get(id, 1)))
	for key in records:
		cfg.set_value("records", key, records[key])
	cfg.save(SAVE_PATH)
