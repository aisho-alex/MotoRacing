class_name TrafficCone
extends "res://scripts/track_pickup.gd"
## Road-work cone at the edge of the racing line. Hitting it at speed costs a
## little health and knocks it aside (it respawns a while later). Not a wipeout
## hazard on its own — traffic and walls remain the hard ones.

const DAMAGE := 5.0
const MIN_SPEED := 6.0
const RESPAWN_TIME := 12.0
const GLOW := Color(1.0, 0.45, 0.1)


func bob_height() -> float:
	return 0.0


func spin_speed() -> float:
	return 0.0


func respawn_time() -> float:
	return RESPAWN_TIME


func glow_color() -> Color:
	return GLOW


func _try_apply(body: Node3D) -> bool:
	if "is_traffic" in body and body.is_traffic:
		return false
	if not body.has_method("take_hit"):
		return false
	if body.velocity.length() < MIN_SPEED:
		return false
	body.take_hit(DAMAGE, global_position)
	return true


## Orange cone with a reflective white band on a dark base.
func _build_visual() -> Node3D:
	var root := Node3D.new()
	root.name = "Cone"
	var orange := StandardMaterial3D.new()
	orange.albedo_color = Color(0.95, 0.42, 0.08)
	orange.roughness = 0.5
	orange.emission_enabled = true
	orange.emission = GLOW
	orange.emission_energy_multiplier = 0.9
	var cone := CylinderMesh.new()
	cone.top_radius = 0.06
	cone.bottom_radius = 0.30
	cone.height = 0.72
	cone.radial_segments = 12
	cone.material = orange
	var ci := MeshInstance3D.new()
	ci.mesh = cone
	ci.position.y = 0.4
	root.add_child(ci)
	var base := CylinderMesh.new()
	base.top_radius = 0.34
	base.bottom_radius = 0.36
	base.height = 0.08
	base.radial_segments = 12
	base.material = orange
	var bi := MeshInstance3D.new()
	bi.mesh = base
	bi.position.y = 0.04
	root.add_child(bi)
	var band_mat := StandardMaterial3D.new()
	band_mat.albedo_color = Color(0.95, 0.95, 0.92)
	band_mat.roughness = 0.3
	band_mat.emission_enabled = true
	band_mat.emission = Color(0.9, 0.9, 0.9)
	band_mat.emission_energy_multiplier = 0.8
	var band := CylinderMesh.new()
	band.top_radius = 0.19
	band.bottom_radius = 0.22
	band.height = 0.12
	band.radial_segments = 12
	band.material = band_mat
	var bi2 := MeshInstance3D.new()
	bi2.mesh = band
	bi2.position.y = 0.42
	root.add_child(bi2)
	return root
