class_name CarDef
extends Resource
## Data-driven car description: model, dimensions, physics stats and nitro.
## Drop-in assets live under res://assets/cars/<id>/ (see docs/assets.md).
## A default instance mirrors the original hardcoded car.gd constants, so the
## game runs unchanged before real .tres definitions exist.

const DEFAULT_PATH := "res://assets/data/cars/sport_01.tres"

@export var id := "sport_01"
@export var display_name := "Sport 01"

@export_group("Visuals")
@export var model_path := "res://assets/car.glb"
@export var model_scale := 4.3   # GLB is ~1 unit long; car is ~4.3 m
@export var model_yaw := PI      # GLB faces +Z, car drives along -Z
@export var model_y_offset := 0.76
@export var collision_size := Vector3(1.9, 1.0, 4.3)
@export var wheel_radius := 0.33
@export var livery_dir := "res://assets/cars/sport_01"
@export var livery_count := 0    # livery_0.webp .. livery_{n-1}.webp
@export var livery_index := 0    # which livery this car uses

@export_group("Audio")
@export var engine_sound := "sport"  # assets/audio/engine/<engine_sound>/engine.ogg

@export_group("Physics")
@export var max_speed := 32.0
@export var reverse_max := 10.0
@export var accel := 15.0
@export var brake := 30.0
@export var reverse_accel := 9.0
@export var drag := 0.35
@export var roll_resistance := 2.0
@export var grip := 9.0
@export var offroad_grip := 3.5
@export var offroad_drag := 1.8
@export var steer_rate := 1.9

@export_group("Nitro")
@export var nitro_max := 100.0
@export var nitro_burn := 40.0
@export var nitro_regen := 12.0
@export var nitro_regen_delay := 1.0
@export var nitro_accel_mult := 2.2
@export var nitro_speed_mult := 1.45
@export var nitro_spool_up := 2.5
@export var nitro_spool_down := 2.0


func livery_path(index: int) -> String:
	return "%s/livery_%d.webp" % [livery_dir, index]


static func load_default() -> CarDef:
	if ResourceLoader.exists(DEFAULT_PATH):
		var res := load(DEFAULT_PATH) as CarDef
		if res != null:
			return res
	return CarDef.new()
