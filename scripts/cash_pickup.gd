class_name CashPickup
extends "res://scripts/track_pickup.gd"
## Money bag on the track. Only the player collects it; driving over it adds
## credits straight to the campaign wallet (a coin toast fires in the HUD).

signal collected(amount: int)

const AMOUNT := 75
const RESPAWN_TIME := 25.0
const BOB_HEIGHT := 0.16
const SPIN_SPEED := 1.8
const GLOW := Color(1.0, 0.85, 0.25)


func bob_height() -> float:
	return BOB_HEIGHT


func spin_speed() -> float:
	return SPIN_SPEED


func respawn_time() -> float:
	return RESPAWN_TIME


func glow_color() -> Color:
	return GLOW


func _try_apply(body: Node3D) -> bool:
	if not body.has_method("is_player_racer") or not body.is_player_racer():
		return false
	var game := get_node_or_null("/root/Game")
	if game != null:
		game.add_credits(AMOUNT)
	collected.emit(AMOUNT)
	return true


## A squat green pouch with a golden tie and a soft glow.
func _build_visual() -> Node3D:
	var root := Node3D.new()
	root.name = "CashBag"
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.24, 0.5, 0.2, 0.96)
	mat.roughness = 0.5
	mat.emission_enabled = true
	mat.emission = GLOW
	mat.emission_energy_multiplier = 1.6
	var bag := SphereMesh.new()
	bag.radius = 0.36
	bag.height = 0.78
	bag.radial_segments = 16
	bag.rings = 8
	bag.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = bag
	mi.position.y = 0.48
	root.add_child(mi)
	var tie_mat := StandardMaterial3D.new()
	tie_mat.albedo_color = Color(0.9, 0.72, 0.2)
	tie_mat.roughness = 0.35
	tie_mat.emission_enabled = true
	tie_mat.emission = Color(1.0, 0.8, 0.3)
	tie_mat.emission_energy_multiplier = 1.4
	var tie := CylinderMesh.new()
	tie.top_radius = 0.13
	tie.bottom_radius = 0.2
	tie.height = 0.22
	tie.material = tie_mat
	var tm := MeshInstance3D.new()
	tm.mesh = tie
	tm.position.y = 0.9
	root.add_child(tm)
	root.add_child(_make_glow(2.4))
	return root
