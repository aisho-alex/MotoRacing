extends Node
## Autoload "Game": car/track selection, savefile progression and unlocks.

const CAR_IDS := ["compact_01", "sport_01", "muscle_01", "hyper_01"]
const TRACK_IDS := [
	"city_01", "desert_01", "alpine_01", "coast_01",
	"city_02", "desert_02", "alpine_02", "coast_02",
	"canyon_01", "sakura_01", "volcano_01",
]
const SAVE_PATH := "user://progress.cfg"

var car_index := 0
var track_index := 0
var track_tier := 0  # 0-based difficulty level on the selected track

var races_done := 0
var best_pos := 0  # 1 = win; 0 = no finished races yet
var credits := 0
var upgrades := {}  # car_id -> {engine, tires, nitro}
var unlocked_tracks := 1  # ladder prefix: tracks [0, unlocked_tracks) are open
var track_tiers := {}  # track_id -> number of unlocked difficulty tiers (1..3)


func _ready() -> void:
	_load_progress()


## Unlocks: compact is free; sport after finishing any race; muscle after a
## podium (2nd or better); hyper after winning a race.
func is_car_unlocked(car_id: String) -> bool:
	match car_id:
		"sport_01":
			return races_done >= 1
		"muscle_01":
			return best_pos > 0 and best_pos <= 2
		"hyper_01":
			return best_pos == 1
	return true


func lock_hint(car_id: String) -> String:
	match car_id:
		"sport_01":
			return "Sport 01 — finish a race to unlock"
		"muscle_01":
			return "Muscle 01 — finish 2nd or better to unlock"
		"hyper_01":
			return "Hyper 01 — win a race to unlock"
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
	var earned := CarTuning.track_reward(pos, track_index, track_tier)
	credits += earned
	if pos > 0 and pos <= 2:
		_unlock_after_podium()
	_save_progress()
	return earned


func _unlock_after_podium() -> void:
	var id: String = TRACK_IDS[track_index]
	var unlocked := unlocked_tier_count(track_index)
	track_tiers[id] = mini(maxi(unlocked, track_tier + 2), CarTuning.TRACK_TIERS)
	if track_index + 1 >= unlocked_tracks and track_index + 1 < TRACK_IDS.size():
		unlocked_tracks = track_index + 2


func cycle_car(dir: int) -> void:
	for _attempt in CAR_IDS.size():
		car_index = wrapi(car_index + dir, 0, CAR_IDS.size())
		if is_car_unlocked(CAR_IDS[car_index]):
			return


## Ladder campaign: track 0 is always open; a podium (top-2) opens the next
## track. Each track also has TRACK_TIERS difficulty levels, level N+1 opens
## after a podium at level N of the same track.
func is_track_unlocked(index: int) -> bool:
	return index >= 0 and index < unlocked_tracks


func unlocked_tier_count(track_index_ref: int) -> int:
	if track_index_ref < 0 or track_index_ref >= TRACK_IDS.size():
		return 1
	return clampi(int(track_tiers.get(TRACK_IDS[track_index_ref], 1)), 1, CarTuning.TRACK_TIERS)


func is_tier_unlocked(track_index_ref: int, tier: int) -> bool:
	return tier >= 0 and tier < unlocked_tier_count(track_index_ref)


func track_lock_hint(index: int) -> String:
	if index <= 0 or index >= TRACK_IDS.size():
		return ""
	if index == unlocked_tracks:
		return "%s — podium on %s to unlock" % [track_name_at(index), track_name_at(index - 1)]
	return "%s — locked" % track_name_at(index)


func tier_label(tier: int = -1) -> String:
	var t := track_tier if tier < 0 else tier
	return "LEVEL %d/%d" % [t + 1, CarTuning.TRACK_TIERS]


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


func car_name() -> String:
	return car_def().display_name


func track_name() -> String:
	return track_name_at(track_index)


func track_name_at(index: int) -> String:
	var def := track_def_at(index)
	if def.display_name != "":
		return def.display_name
	var id: String = TRACK_IDS[index]
	return id.split("_")[0].capitalize()


func car_def() -> CarDef:
	return car_def_by_id(current_car_id())


func car_def_by_id(car_id: String) -> CarDef:
	var path := "res://assets/data/cars/%s.tres" % car_id
	if ResourceLoader.exists(path):
		var res := load(path) as CarDef
		if res != null:
			return res
	return CarDef.new()


func track_def() -> TrackDef:
	return track_def_at(track_index)


func track_def_at(index: int) -> TrackDef:
	var path := "res://assets/data/tracks/%s.tres" % TRACK_IDS[index]
	if ResourceLoader.exists(path):
		var res := load(path) as TrackDef
		if res != null:
			return res
	return TrackDef.new()


func current_car_id() -> String:
	return CAR_IDS[car_index]


## Upgrade levels for a car, always a sanitized {engine, tires, nitro} dict.
func upgrade_levels(car_id: String) -> Dictionary:
	if not upgrades.has(car_id):
		upgrades[car_id] = CarTuning.empty_levels()
	return CarTuning.sanitize(upgrades[car_id])


func upgrade_level(car_id: String, part: String) -> int:
	return int(upgrade_levels(car_id).get(part, 0))


func upgrade_cost(car_id: String, part: String) -> int:
	return CarTuning.cost(car_id, upgrade_level(car_id, part))


func can_afford_upgrade(car_id: String, part: String) -> bool:
	var price := upgrade_cost(car_id, part)
	return price >= 0 and credits >= price


func buy_upgrade(car_id: String, part: String) -> bool:
	if not is_car_unlocked(car_id):
		return false
	var price := upgrade_cost(car_id, part)
	if price < 0 or credits < price:
		return false
	credits -= price
	var levels := upgrade_levels(car_id)
	levels[part] = int(levels[part]) + 1
	upgrades[car_id] = levels
	_save_progress()
	return true


func total_upgrade_levels(car_id: String) -> int:
	return CarTuning.total_levels(upgrade_levels(car_id))


## Base def with the car's upgrades applied — used for the player's car only.
func player_car_def() -> CarDef:
	return tuned_def_for(current_car_id())


func tuned_def_for(car_id: String) -> CarDef:
	return CarTuning.apply(car_def_by_id(car_id), upgrade_levels(car_id))


## Opponent speed multiplier: upgrades keep races competitive as the garage is
## filled in; campaign position and difficulty level make later races harder.
func ai_speed_scale() -> float:
	return (
		CarTuning.ai_speed_scale(total_upgrade_levels(current_car_id()))
		* CarTuning.track_ai_scale(track_index, track_tier)
	)


func _load_progress() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	races_done = int(cfg.get_value("progress", "races_done", 0))
	best_pos = int(cfg.get_value("progress", "best_pos", 0))
	credits = int(cfg.get_value("progress", "credits", 0))
	car_index = clampi(int(cfg.get_value("progress", "car_index", 0)), 0, CAR_IDS.size() - 1)
	track_index = clampi(int(cfg.get_value("progress", "track_index", 0)), 0, TRACK_IDS.size() - 1)
	upgrades = {}
	for id in CAR_IDS:
		var saved: Variant = cfg.get_value("upgrades", id, {})
		upgrades[id] = CarTuning.sanitize(saved if saved is Dictionary else {})
	unlocked_tracks = clampi(int(cfg.get_value("progress", "unlocked_tracks", 1)), 1, TRACK_IDS.size())
	track_tiers = {}
	for id in TRACK_IDS:
		track_tiers[id] = clampi(int(cfg.get_value("tracks", id, 1)), 1, CarTuning.TRACK_TIERS)
	track_index = clampi(track_index, 0, unlocked_tracks - 1)
	track_tier = clampi(int(cfg.get_value("progress", "track_tier", 0)), 0, unlocked_tier_count(track_index) - 1)


func _save_progress() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("progress", "races_done", races_done)
	cfg.set_value("progress", "best_pos", best_pos)
	cfg.set_value("progress", "credits", credits)
	cfg.set_value("progress", "car_index", car_index)
	cfg.set_value("progress", "track_index", track_index)
	cfg.set_value("progress", "track_tier", track_tier)
	cfg.set_value("progress", "unlocked_tracks", unlocked_tracks)
	for id in CAR_IDS:
		cfg.set_value("upgrades", id, upgrade_levels(id))
	for id in TRACK_IDS:
		cfg.set_value("tracks", id, int(track_tiers.get(id, 1)))
	cfg.save(SAVE_PATH)
