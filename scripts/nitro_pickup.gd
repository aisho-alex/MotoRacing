class_name NitroPickup
extends "res://scripts/track_pickup.gd"
## Rotating nitro bottle on the track. Driving over it instantly refills part of
## the tank (player and AI both collect); the bottle then hides for a while and
## respawns.

const AMOUNT := 30.0
const RESPAWN_TIME := 15.0
const BOB_HEIGHT := 0.16
const SPIN_SPEED := 1.6
const GLOW := Color(1.0, 0.62, 0.16)


func bob_height() -> float:
	return BOB_HEIGHT


func spin_speed() -> float:
	return SPIN_SPEED


func respawn_time() -> float:
	return RESPAWN_TIME


func glow_color() -> Color:
	return GLOW


func _try_apply(body: Node3D) -> bool:
	if not body.has_method("add_nitro"):
		return false
	body.call("add_nitro", AMOUNT)
	return true


func _build_visual() -> Node3D:
	var root := Node3D.new()
	root.name = "Bottle"
	var body_fill := StandardMaterial3D.new()
	body_fill.albedo_color = Color(0.28, 0.14, 0.03)
	body_fill.roughness = 0.22
	body_fill.metallic = 0.15
	body_fill.emission_enabled = true
	body_fill.emission = GLOW
	body_fill.emission_energy_multiplier = 2.6
	root.add_child(_cyl(0.28, 0.28, 0.9, 0.52, body_fill))
	root.add_child(_cyl(0.28, 0.13, 0.24, 1.09, body_fill))
	root.add_child(_cyl(0.11, 0.11, 0.26, 1.32, body_fill))
	var cap := StandardMaterial3D.new()
	cap.albedo_color = Color(0.9, 0.75, 0.2)
	cap.roughness = 0.35
	cap.emission_enabled = true
	cap.emission = Color(1.0, 0.75, 0.2)
	cap.emission_energy_multiplier = 1.2
	root.add_child(_cyl(0.15, 0.15, 0.14, 1.5, cap))
	root.add_child(_make_glow(2.4))
	return root


func _cyl(top: float, bottom: float, height: float, y: float,
		material: StandardMaterial3D) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = 16
	mesh.material = material
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position.y = y
	return mi
