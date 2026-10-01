class_name ShieldPickup
extends "res://scripts/track_pickup.gd"
## Cyan energy cell on the track. Driving over it grants a short shield that
## absorbs combat hits (punches/kicks); crashes still hurt. Player and AI can
## both use it.

const DURATION := 8.0
const RESPAWN_TIME := 24.0
const BOB_HEIGHT := 0.15
const SPIN_SPEED := 1.3
const GLOW := Color(0.35, 0.8, 1.0)


func bob_height() -> float:
	return BOB_HEIGHT


func spin_speed() -> float:
	return SPIN_SPEED


func respawn_time() -> float:
	return RESPAWN_TIME


func glow_color() -> Color:
	return GLOW


func _try_apply(body: Node3D) -> bool:
	if not body.has_method("add_shield"):
		return false
	body.call("add_shield", DURATION)
	return true


## A translucent hexagonal ring around a bright core — reads as a bubble shield.
func _build_visual() -> Node3D:
	var root := Node3D.new()
	root.name = "Shield"
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.72, 0.95, 0.55)
	mat.roughness = 0.15
	mat.metallic = 0.2
	mat.emission_enabled = true
	mat.emission = GLOW
	mat.emission_energy_multiplier = 2.4
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var prism := PrismMesh.new()
	prism.size = Vector3(0.62, 0.34, 0.62)
	prism.material = mat
	var pi := MeshInstance3D.new()
	pi.mesh = prism
	pi.position.y = 0.66
	root.add_child(pi)
	var core_mat := StandardMaterial3D.new()
	core_mat.albedo_color = Color(0.85, 0.97, 1.0)
	core_mat.emission_enabled = true
	core_mat.emission = Color(0.7, 0.95, 1.0)
	core_mat.emission_energy_multiplier = 4.0
	var core := SphereMesh.new()
	core.radius = 0.18
	core.height = 0.36
	core.material = core_mat
	var ci := MeshInstance3D.new()
	ci.mesh = core
	ci.position.y = 0.66
	root.add_child(ci)
	root.add_child(_make_glow(2.6))
	return root
