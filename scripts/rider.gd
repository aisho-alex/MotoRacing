class_name Rider
extends Node3D
## Procedural low-poly rider seated on a bike. Arms and legs hang off pivot
## nodes (shoulders / hips) so poses — punch, kick, crash — animate by rotating
## a pivot, no mesh rebuilding. Colors come from the BikeDef; no external
## assets are required.

const SKIN := Color(0.82, 0.62, 0.48)
const VISOR := Color(0.06, 0.07, 0.10)
const BOOT := Color(0.10, 0.10, 0.11)

const ATTACK_TIME := 0.34

# Joint positions in rider-local space (origin at the pelvis, -Z forward).
const PELVIS := Vector3(0.0, 0.0, 0.0)
const TORSO_TOP := Vector3(0.0, 0.50, -0.10)
const HEAD := Vector3(0.0, 0.70, -0.16)
const SHOULDER := Vector3(0.19, 0.52, -0.15)
const ELBOW := Vector3(0.32, 0.34, -0.40)
const HAND := Vector3(0.28, 0.46, -0.58)
const HIP := Vector3(0.13, -0.02, 0.02)
const KNEE := Vector3(0.24, -0.14, -0.28)
const FOOT := Vector3(0.26, -0.46, -0.08)

var suit_color := Color(0.16, 0.18, 0.24)
var helmet_color := Color(0.86, 0.88, 0.92)

var _shoulder := {}   # side -> shoulder pivot Node3D
var _hip := {}        # side -> hip pivot Node3D
var _base_pos := Vector3.ZERO

var _lean := 0.0
var _attack_side := 0.0
var _attack_kind := ""
var _attack_t := -1.0
var _crash_t := -1.0
var _hit_t := -1.0


func setup(rider_col: Color, helmet_col: Color) -> void:
	suit_color = rider_col
	helmet_color = helmet_col
	_build()


func _build() -> void:
	var suit := _mat(suit_color, 0.55)
	var helmet := _mat(helmet_color, 0.25)
	var skin := _mat(SKIN, 0.7)
	var visor := _mat(VISOR, 0.15)
	var boot := _mat(BOOT, 0.6)

	# pelvis + torso
	_box(Vector3(0.30, 0.20, 0.30), PELVIS + Vector3(0.0, 0.04, 0.0), suit)
	_segment(PELVIS + Vector3(0.0, 0.10, 0.0), TORSO_TOP, 0.11, suit)

	# head / helmet
	var hm := MeshInstance3D.new()
	var helm := SphereMesh.new()
	helm.radius = 0.135
	helm.height = 0.27
	helm.radial_segments = 12
	helm.rings = 8
	helm.material = helmet
	hm.mesh = helm
	hm.position = HEAD
	add_child(hm)
	var vm := MeshInstance3D.new()
	var visor_mesh := BoxMesh.new()
	visor_mesh.size = Vector3(0.20, 0.09, 0.06)
	visor_mesh.material = visor
	vm.mesh = visor_mesh
	vm.position = HEAD + Vector3(0.0, 0.0, -0.11)
	add_child(vm)

	for side in [1.0, -1.0]:
		var sh := Node3D.new()
		sh.name = "Shoulder%s" % ("L" if side > 0.0 else "R")
		sh.position = _side(SHOULDER, side)
		add_child(sh)
		_seg_child(sh, Vector3.ZERO, _side(ELBOW - SHOULDER, side), 0.055, suit)
		var el := Node3D.new()
		el.name = "Elbow"
		el.position = _side(ELBOW - SHOULDER, side)
		sh.add_child(el)
		_seg_child(el, Vector3.ZERO, _side(HAND - ELBOW, side), 0.05, suit)
		_sphere_child(el, _side(HAND - ELBOW, side), 0.062, skin)
		_shoulder[side] = sh

		var hip := Node3D.new()
		hip.name = "Hip%s" % ("L" if side > 0.0 else "R")
		hip.position = _side(HIP, side)
		add_child(hip)
		_seg_child(hip, Vector3.ZERO, _side(KNEE - HIP, side), 0.075, suit)
		var kn := Node3D.new()
		kn.name = "Knee"
		kn.position = _side(KNEE - HIP, side)
		hip.add_child(kn)
		_seg_child(kn, Vector3.ZERO, _side(FOOT - KNEE, side), 0.06, suit)
		_box_child(kn, Vector3(0.10, 0.09, 0.20), _side(FOOT - KNEE, side) + Vector3(0.0, -0.02, -0.02), boot)
		_hip[side] = hip

	_base_pos = position


func _process(delta: float) -> void:
	if _crash_t >= 0.0:
		_crash_t += delta
		var t := clampf(_crash_t / 0.6, 0.0, 1.0)
		rotation.z = -t * 1.5
		position.y = _base_pos.y - t * 0.35
		return
	if _hit_t >= 0.0:
		_hit_t += delta
		var ht := clampf(_hit_t / 0.3, 0.0, 1.0)
		rotation.x = sin(ht * PI) * 0.28
		if _hit_t > 0.3:
			_hit_t = -1.0
			rotation.x = 0.0
	if _attack_t >= 0.0:
		_attack_t += delta
		var p := _attack_t / ATTACK_TIME
		var amount := sin(clampf(p, 0.0, 1.0) * PI)
		_pose_attack(amount)
		if p >= 1.0:
			_attack_t = -1.0
			_pose_attack(0.0)


## Lean/roll of the whole rider (radians), used when cornering.
func set_lean(roll: float) -> void:
	_lean = roll
	if _crash_t < 0.0:
		rotation.z = _lean


## side: +1 left, -1 right. kind: "punch" or "kick".
func attack(side: float, kind: String = "punch") -> void:
	if _crash_t >= 0.0:
		return
	_attack_side = side
	_attack_kind = kind
	_attack_t = 0.0


func hit() -> void:
	if _crash_t < 0.0:
		_hit_t = 0.0


func crash() -> void:
	_crash_t = 0.0
	_attack_t = -1.0


func recover() -> void:
	_crash_t = -1.0
	_hit_t = -1.0
	rotation = Vector3.ZERO
	position = _base_pos
	for side in _shoulder:
		_shoulder[side].rotation = Vector3.ZERO
	for side in _hip:
		_hip[side].rotation = Vector3.ZERO


func _pose_attack(amount: float) -> void:
	var s := _attack_side
	if _attack_kind == "kick":
		for side in _hip:
			var kick := amount if is_equal_approx(side, s) else 0.0
			_hip[side].rotation = Vector3(-1.1 * kick, 0.0, 0.0)
		for side in _shoulder:
			_shoulder[side].rotation = Vector3.ZERO
	else:
		for side in _shoulder:
			var punch := amount if is_equal_approx(side, s) else 0.0
			_shoulder[side].rotation = Vector3(-0.35 * punch, 0.0, -side * 1.35 * punch)
		for side in _hip:
			_hip[side].rotation = Vector3.ZERO


func _side(p: Vector3, side: float) -> Vector3:
	return Vector3(p.x * side, p.y, p.z)


func _sphere_child(parent: Node3D, pos: Vector3, r: float, mat: Material) -> MeshInstance3D:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = 10
	m.rings = 6
	m.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.position = pos
	parent.add_child(mi)
	return mi


func _box(size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	return _box_child(self, size, pos, mat)


func _box_child(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var m := BoxMesh.new()
	m.size = size
	m.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.position = pos
	parent.add_child(mi)
	return mi


func _segment(a: Vector3, b: Vector3, r: float, mat: Material) -> MeshInstance3D:
	return _seg_child(self, a, b, r, mat)


func _seg_child(parent: Node3D, a: Vector3, b: Vector3, r: float, mat: Material) -> MeshInstance3D:
	var dir := b - a
	var dist := dir.length()
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = maxf(dist, r * 2.0)
	m.radial_segments = 8
	m.rings = 3
	m.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.position = (a + b) * 0.5
	if dist > 0.0001:
		mi.basis = Basis(Quaternion(Vector3.UP, dir.normalized()))
	parent.add_child(mi)
	return mi


func _mat(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m
