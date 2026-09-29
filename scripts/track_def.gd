class_name TrackDef
extends Resource
## Data-driven track: centerline spline, road metrics and biome asset paths.
## Drop-in environment assets live under res://assets/environments/<biome>/
## (see docs/assets.md). Defaults mirror the original track_builder.gd track.

const DEFAULT_PATH := "res://assets/data/tracks/city_01.tres"

@export var id := "city_01"
@export var display_name := ""
@export var biome := "city"
@export var control_points := PackedVector3Array([
	Vector3(-150, 0, -270),
	Vector3(-20, 0, -270),
	Vector3(110, 0, -270),
	Vector3(200, 0, -270),
	Vector3(255, 0, -245),
	Vector3(272, 0, -190),
	Vector3(272, 0, -100),
	Vector3(272, 0, 10),
	Vector3(272, 0, 120),
	Vector3(258, 0, 200),
	Vector3(205, 0, 248),
	Vector3(120, 0, 248),
	Vector3(40, 0, 262),
	Vector3(-40, 0, 248),
	Vector3(-120, 0, 248),
	Vector3(-210, 0, 232),
	Vector3(-252, 0, 185),
	Vector3(-252, 0, 100),
	Vector3(-252, 0, -10),
	Vector3(-252, 0, -120),
	Vector3(-252, 0, -195),
	Vector3(-235, 0, -248),
	Vector3(-195, 0, -266),
])

@export_group("Road")
@export var road_half_width := 7.5
@export var wall_height := 1.1
@export var road_tile_length := 8.0     # meters covered by one road texture tile
@export var terrain_tile_size := 6.0    # meters covered by one terrain texture tile

@export_group("Decor")
@export var decor_seed := 20260914
@export var prop_count := 72
@export var building_count := 14
@export var prop_min_lateral := 12.0
@export var prop_max_lateral := 46.0
@export var building_min_lateral := 20.0
@export var building_max_lateral := 52.0
@export var building_min_gap := 24.0
@export var night_racing := false
@export var wet_road := false
@export var urban_canyon := false
@export var streetlight_spacing := 0
@export var skyline_count := 0


func env_dir() -> String:
	return "res://assets/environments/%s" % biome


func road_albedo_path() -> String:
	return env_dir() + "/road/asphalt_albedo.webp"


func road_normal_path() -> String:
	return env_dir() + "/road/asphalt_normal.png"


func road_orm_path() -> String:
	return env_dir() + "/road/asphalt_orm.png"


func terrain_albedo_path() -> String:
	return env_dir() + "/terrain/surface_albedo.webp"


func terrain_normal_path() -> String:
	return env_dir() + "/terrain/surface_normal.png"


func terrain_orm_path() -> String:
	return env_dir() + "/terrain/surface_orm.png"


func sky_path() -> String:
	return env_dir() + "/sky.hdr"


func facade_albedo_path(suffix: String) -> String:
	return env_dir() + "/facade_%s.webp" % suffix


func facade_night_albedo_path(suffix: String) -> String:
	return env_dir() + "/facade_%s_night.webp" % suffix


func facade_normal_path(suffix: String) -> String:
	return env_dir() + "/facade_%s_normal.png" % suffix


func facade_orm_path(suffix: String) -> String:
	return env_dir() + "/facade_%s_orm.png" % suffix


func facade_emission_path(suffix: String) -> String:
	return env_dir() + "/facade_%s_emission.webp" % suffix


static func load_default() -> TrackDef:
	if ResourceLoader.exists(DEFAULT_PATH):
		var res := load(DEFAULT_PATH) as TrackDef
		if res != null:
			return res
	return TrackDef.new()
