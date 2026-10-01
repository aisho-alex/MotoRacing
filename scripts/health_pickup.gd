class_name HealthPickup
extends "res://scripts/track_pickup.gd"
## Green repair pack on the track. Driving over it restores part of the bike's
## health (player and AI both collect); the pack then hides for a while and
## respawns. Scarcity is the point: fewer packs than nitro bottles.

const AMOUNT := 30.0
const RESPAWN_TIME := 20.0
const BOB_HEIGHT := 0.14
const SPIN_SPEED := 1.1
const GLOW := Color(0.32, 1.0, 0.5)


func bob_height() -> float:
	return BOB_HEIGHT


func spin_speed() -> float:
	return SPIN_SPEED


func respawn_time() -> float:
	return RESPAWN_TIME


func glow_color() -> Color:
	return GLOW


func _try_apply(body: Node3D) -> bool:
	if not body.has_method("add_health"):
		return false
	body.call("add_health", AMOUNT)
	return true


## A green cross (two bars) with an emissive, semi-transparent material so it
## reads as a pickup against the asphalt, day and night.
func _build_visual() -> Node3D:
	var root := Node3D.new()
	root.name = "HealthPack"
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.20, 0.65, 0.32, 0.92)
	mat.roughness = 0.28
	mat.emission_enabled = true
	mat.emission = GLOW
	mat.emission_energy_multiplier = 2.2
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	root.add_child(_bar(Vector3(0.30, 0.98, 0.30), Vector3(0.0, 0.72, 0.0), mat))
	root.add_child(_bar(Vector3(0.84, 0.30, 0.30), Vector3(0.0, 0.72, 0.0), mat))
	root.add_child(_make_glow(2.2))
	return root


func _bar(size: Vector3, pos: Vector3, material: StandardMaterial3D) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	return mi
