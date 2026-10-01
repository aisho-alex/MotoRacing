class_name BikeDef
extends Resource
## Data-driven bike description: procedural silhouette/colors, dimensions,
## physics stats and nitro. An optional GLB (model_path) overrides the
## procedural look; when it is empty the bike is assembled from primitives by
## scripts/bike_visuals.gd with a seated rider on top.
## A default instance is a safe fallback when a .tres definition is missing.

const DEFAULT_PATH := "res://assets/data/bikes/sport_01.tres"

@export var id := "sport_01"
@export var display_name := "Sport 600"

@export_group("Visuals")
## Procedural silhouette: "scrambler", "sport", "cruiser" or "super".
@export var style := "sport"
@export var body_color := Color(0.80, 0.14, 0.11)
@export var accent_color := Color(0.10, 0.10, 0.12)
@export var rider_color := Color(0.16, 0.18, 0.24)
@export var rider_accent_color := Color(0.58, 0.61, 0.68)
@export var helmet_color := Color(0.86, 0.88, 0.92)
## Visual lean into corners, degrees (0 disables).
@export var lean_max := 30.0
## Optional GLB override; when empty the procedural bike is built instead.
@export var model_path := ""
@export var model_scale := 1.0
@export var model_yaw := PI      # rotate the GLB so its forward becomes -Z
@export var model_y_offset := 0.0
## Seated procedural rider mount (bike-local xyz); used with a GLB body.
@export var rider_mount := Vector3(0.0, 0.80, 0.06)
@export var rider_scale := 1.0
## Bike-local handlebar grip / footpeg points the rider's IK reaches for.
## Vector3.ZERO keeps the per-style default from scripts/rider.gd.
@export var handlebar_local := Vector3.ZERO
@export var peg_local := Vector3.ZERO
@export var collision_size := Vector3(0.85, 1.05, 2.35)
@export var wheel_radius := 0.33
@export var livery_dir := ""
@export var livery_count := 0    # livery_0.webp .. livery_{n-1}.webp
@export var livery_index := 0    # which livery this bike uses

@export_group("Audio")
@export var engine_sound := "sport"  # assets/audio/engine/<engine_sound>/engine.ogg

@export_group("Physics")
@export var max_speed := 36.0
@export var reverse_max := 9.0
@export var accel := 20.0
@export var brake := 32.0
@export var reverse_accel := 8.0
@export var drag := 0.35
@export var roll_resistance := 2.0
@export var grip := 8.0
@export var offroad_grip := 2.8
@export var offroad_drag := 2.2
@export var steer_rate := 2.1
## Yaw-authority curve shared by the bike physics and the AI's pure pursuit:
## steering effect saturates over STEER_SPEED_REF m/s and eases off with speed.
const STEER_SPEED_REF := 7.0
const STEER_HIGH_SPEED_DAMP := 0.45

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


## Yaw authority (turn rate per unit steer) at the given forward speed. Kept in
## one place so the player physics and the AI controller cannot drift apart.
func steer_authority(speed: float) -> float:
	var s := absf(speed)
	return steer_rate \
		* clampf(s / STEER_SPEED_REF, 0.0, 1.0) \
		* (1.0 - STEER_HIGH_SPEED_DAMP * clampf(s / maxf(max_speed, 1.0), 0.0, 1.0))


static func load_default() -> BikeDef:
	if ResourceLoader.exists(DEFAULT_PATH):
		var res := load(DEFAULT_PATH) as BikeDef
		if res != null:
			return res
	return BikeDef.new()
