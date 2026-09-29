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

var races_done := 0
var best_pos := 0  # 1 = win; 0 = no finished races yet


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


func record_result(finished: bool, pos: int) -> void:
	if not finished:
		return
	races_done += 1
	if best_pos == 0 or pos < best_pos:
		best_pos = pos
	_save_progress()


func cycle_car(dir: int) -> void:
	for _attempt in CAR_IDS.size():
		car_index = wrapi(car_index + dir, 0, CAR_IDS.size())
		if is_car_unlocked(CAR_IDS[car_index]):
			return


func cycle_track(dir: int) -> void:
	track_index = wrapi(track_index + dir, 0, TRACK_IDS.size())


func car_name() -> String:
	return car_def().display_name


func track_name() -> String:
	var def := track_def()
	if def.display_name != "":
		return def.display_name
	var id: String = TRACK_IDS[track_index]
	return id.split("_")[0].capitalize()


func car_def() -> CarDef:
	var path := "res://assets/data/cars/%s.tres" % CAR_IDS[car_index]
	if ResourceLoader.exists(path):
		var res := load(path) as CarDef
		if res != null:
			return res
	return CarDef.new()


func track_def() -> TrackDef:
	var path := "res://assets/data/tracks/%s.tres" % TRACK_IDS[track_index]
	if ResourceLoader.exists(path):
		var res := load(path) as TrackDef
		if res != null:
			return res
	return TrackDef.new()


func _load_progress() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	races_done = int(cfg.get_value("progress", "races_done", 0))
	best_pos = int(cfg.get_value("progress", "best_pos", 0))
	car_index = clampi(int(cfg.get_value("progress", "car_index", 0)), 0, CAR_IDS.size() - 1)
	track_index = clampi(int(cfg.get_value("progress", "track_index", 0)), 0, TRACK_IDS.size() - 1)


func _save_progress() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("progress", "races_done", races_done)
	cfg.set_value("progress", "best_pos", best_pos)
	cfg.set_value("progress", "car_index", car_index)
	cfg.set_value("progress", "track_index", track_index)
	cfg.save(SAVE_PATH)
