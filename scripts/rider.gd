class_name Rider
extends Node3D
## Procedural low-poly rider built on a real Skeleton3D rig. Bones are created
## in code (no external assets) with capsule/box meshes attached via
## BoneAttachment3D, so the whole pose is driven by bone transforms.
##
## The pose is composed every frame from:
##   * a per-style seated base pose (torso bend + head look-up),
##   * analytic two-bone IK that plants the hands on the handlebar and the feet
##     on the pegs (targets come from the BikeDef / bike style),
##   * additive dynamics: corner lean/head-turn, speed jitter, nitro tuck,
##   * Road Rash actions: a 3-phase punch/kick, a flinch and a crash flail.
##
## The skeleton ignores its rest transforms (poses are written directly), so the
## rest is only kept for a well-defined bind pose. Colors come from the BikeDef.

const SKIN := Color(0.82, 0.62, 0.48)
const VISOR := Color(0.05, 0.06, 0.09)
const BOOT := Color(0.09, 0.09, 0.10)

const ATTACK_TIME := 0.34
const HIT_TIME := 0.30

## Wipeout recovery timeline (seconds from crash()). Each boundary is the end of a
## phase: the rider is ejected, gets up, runs to the bike, lifts it upright and
## finally climbs back on. CRASH_TOTAL must match RaceBike.WIPEOUT_TIME.
const CRASH_EJECT_END := 0.80
const CRASH_GETUP_END := 1.35
const CRASH_RUN_END := 2.40
const CRASH_LIFT_END := 3.35
const CRASH_TOTAL := 4.20

## Rest skeleton: parent-relative bone origins (rider-local, origin at the
## pelvis, -Z forward). Listed parent-before-child; rest bases are identity.
const BONES := [
	{"name": "Hips", "parent": "", "pos": Vector3(0.0, 0.0, 0.0)},
	{"name": "Spine", "parent": "Hips", "pos": Vector3(0.0, 0.15, -0.03)},
	{"name": "Chest", "parent": "Spine", "pos": Vector3(0.0, 0.19, -0.06)},
	{"name": "Neck", "parent": "Chest", "pos": Vector3(0.0, 0.19, -0.08)},
	{"name": "Head", "parent": "Neck", "pos": Vector3(0.0, 0.09, -0.02)},
	{"name": "UpperArm.L", "parent": "Chest", "pos": Vector3(0.17, 0.13, -0.03)},
	{"name": "Forearm.L", "parent": "UpperArm.L", "pos": Vector3(0.0, -0.28, 0.0)},
	{"name": "Hand.L", "parent": "Forearm.L", "pos": Vector3(0.0, -0.26, 0.0)},
	{"name": "UpperArm.R", "parent": "Chest", "pos": Vector3(-0.17, 0.13, -0.03)},
	{"name": "Forearm.R", "parent": "UpperArm.R", "pos": Vector3(0.0, -0.28, 0.0)},
	{"name": "Hand.R", "parent": "Forearm.R", "pos": Vector3(0.0, -0.26, 0.0)},
	{"name": "Thigh.L", "parent": "Hips", "pos": Vector3(0.12, 0.0, -0.02)},
	{"name": "Calf.L", "parent": "Thigh.L", "pos": Vector3(0.0, -0.16, -0.29)},
	{"name": "Foot.L", "parent": "Calf.L", "pos": Vector3(0.0, -0.30, 0.09)},
	{"name": "Thigh.R", "parent": "Hips", "pos": Vector3(-0.12, 0.0, -0.02)},
	{"name": "Calf.R", "parent": "Thigh.R", "pos": Vector3(0.0, -0.16, -0.29)},
	{"name": "Foot.R", "parent": "Calf.R", "pos": Vector3(0.0, -0.30, 0.09)},
]

const TORSO := ["Hips", "Spine", "Chest", "Neck", "Head"]

## Per-style riding posture and fallback grip/peg points (bike-local). `bend` is
## the forward torso lean; `look` is the head counter-pitch (both radians).
const RIDER_STYLES := {
	"sport": {
		"bend": 0.58, "look": 0.52, "hump": true,
		"grip": Vector3(0.27, 1.15, -0.52), "peg": Vector3(0.21, 0.42, 0.05),
	},
	"super": {
		"bend": 0.66, "look": 0.60, "hump": true,
		"grip": Vector3(0.28, 1.14, -0.55), "peg": Vector3(0.23, 0.42, 0.02),
	},
	"scrambler": {
		"bend": 0.30, "look": 0.26, "hump": false,
		"grip": Vector3(0.30, 1.18, -0.46), "peg": Vector3(0.22, 0.40, 0.02),
	},
	"cruiser": {
		"bend": 0.12, "look": 0.14, "hump": false,
		"grip": Vector3(0.31, 1.12, -0.50), "peg": Vector3(0.26, 0.34, -0.02),
	},
}

var suit_color := Color(0.16, 0.18, 0.24)
var accent_color := Color(0.58, 0.61, 0.68)
var helmet_color := Color(0.86, 0.88, 0.92)

var _skeleton: Skeleton3D = null
var _idx := {}          # bone name -> index
var _rest := {}         # bone name -> parent-relative rest Transform3D
var _local := {}        # bone name -> current local Transform3D
var _glob := {}         # bone name -> rider-space global Transform3D
var _parent_name := {}  # bone name -> parent bone name ("" for the root)
var _style := RIDER_STYLES["sport"]

var _hand_target := {}  # "L"/"R" -> rider-local target Vector3
var _foot_target := {}  # "L"/"R" -> rider-local target Vector3
var _hand_base := {}    # unmodified targets (attack offsets start from these)
var _foot_base := {}

# animation state
var _time := 0.0
var _lean := 0.0
var _steer := 0.0
var _speed := 0.0
var _nitro := false
var _attack_side := 0.0
var _attack_kind := ""
var _attack_t := -1.0
var _crash_t := -1.0
var _hit_t := -1.0
var _crash_seed := 0.0
var _crash_side := 1.0
var _base_pos := Vector3.ZERO
## Public: current wipeout phase ("eject"/"getup"/"run"/"lift"/"mount" or "").
## RaceBike polls this to sync the bike's fall/rise with the rider's animation.
var crash_phase := ""


func setup(rider_col: Color, helmet_col: Color, def: BikeDef = null) -> void:
	suit_color = rider_col
	helmet_color = helmet_col
	if def != null:
		accent_color = def.rider_accent_color
	else:
		accent_color = rider_col.lightened(0.55).lerp(Color(0.85, 0.86, 0.9), 0.35)
	_style = RIDER_STYLES.get(def.style if def != null else "sport", RIDER_STYLES["sport"])
	_build_targets(def)
	_build()


## --- public API --------------------------------------------------------

## Lean/roll of the rider into corners (radians); also drives the head turn.
func set_lean(roll: float) -> void:
	_lean = roll


## Per-frame riding state from RaceBike: steering (-1..1), speed ratio (0..1)
## and whether nitro/boost is active.
func set_drive(steer: float, speed_ratio: float, nitro: bool) -> void:
	_steer = steer
	_speed = clampf(speed_ratio, 0.0, 1.0)
	_nitro = nitro


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


## Start a wipeout. `side` (+1 left / -1 right) is the direction the rider is
## thrown; 0 lets the rider pick one at random (used by dev tools).
func crash(side: float = 0.0) -> void:
	_crash_t = 0.0
	_attack_t = -1.0
	_hit_t = -1.0
	_crash_seed = randf() * TAU
	_crash_side = side if absf(side) > 0.01 else (1.0 if randf() < 0.5 else -1.0)
	crash_phase = "eject"
	rotation = Vector3.ZERO
	position = _base_pos


## Fraction of the wipeout recovery completed (0..1).
func crash_progress() -> float:
	if _crash_t < 0.0:
		return 0.0
	return clampf(_crash_t / CRASH_TOTAL, 0.0, 1.0)


func is_remounting() -> bool:
	return crash_phase == "lift" or crash_phase == "mount"


func recover() -> void:
	_crash_t = -1.0
	_hit_t = -1.0
	_attack_t = -1.0
	crash_phase = ""
	rotation = Vector3.ZERO
	position = _base_pos


# --- build -------------------------------------------------------------

func _build_targets(def: BikeDef) -> void:
	var style_name := def.style if def != null else "sport"
	var cfg: Dictionary = RIDER_STYLES.get(style_name, RIDER_STYLES["sport"])
	var mount: Vector3 = def.rider_mount if def != null else Vector3(0.0, 0.80, 0.06)
	var grip: Vector3 = cfg["grip"]
	var peg: Vector3 = cfg["peg"]
	if def != null and def.handlebar_local != Vector3.ZERO:
		grip = def.handlebar_local
	if def != null and def.peg_local != Vector3.ZERO:
		peg = def.peg_local
	grip -= mount
	peg -= mount
	_hand_base = {"L": Vector3(grip.x, grip.y, grip.z), "R": Vector3(-grip.x, grip.y, grip.z)}
	_foot_base = {"L": Vector3(peg.x, peg.y, peg.z), "R": Vector3(-peg.x, peg.y, peg.z)}
	_hand_target = {"L": _hand_base["L"], "R": _hand_base["R"]}
	_foot_target = {"L": _foot_base["L"], "R": _foot_base["R"]}


func _build() -> void:
	_skeleton = Skeleton3D.new()
	_skeleton.name = "Skeleton"
	add_child(_skeleton)
	_base_pos = position
	for b in BONES:
		var name: String = b["name"]
		_idx[name] = _skeleton.get_bone_count()
		_skeleton.add_bone(name)
		_rest[name] = Transform3D(Basis.IDENTITY, b["pos"])
		_local[name] = _rest[name]
		_glob[name] = _rest[name]
		_parent_name[name] = b["parent"]
	for b in BONES:
		var parent: String = b["parent"]
		if parent != "":
			_skeleton.set_bone_parent(_idx[b["name"]], _idx[parent])
			_skeleton.set_bone_rest(_idx[b["name"]], _rest[b["name"]])
	_build_meshes()


func _build_meshes() -> void:
	var suit := _mat(suit_color, 0.55)
	var accent := _mat(accent_color, 0.45)
	var helmet := _mat(helmet_color, 0.22)
	var visor := _mat(VISOR, 0.12)
	var glove := _mat(suit_color.darkened(0.25), 0.5)
	var boot := _mat(BOOT, 0.6)

	_attach("Hips", _box_mesh(Vector3(0.28, 0.21, 0.25), suit), Vector3(0.0, 0.0, 0.0))
	_attach("Spine", _box_mesh(Vector3(0.29, 0.24, 0.25), suit), Vector3(0.0, 0.06, 0.0))
	_attach("Chest", _box_mesh(Vector3(0.31, 0.27, 0.27), suit), Vector3(0.0, 0.05, 0.0))
	_attach("Chest", _box_mesh(Vector3(0.32, 0.055, 0.275), accent), Vector3(0.0, 0.02, 0.0))

	# head + full-face helmet (chin bar + visor band)
	_attach("Neck", _cap_mesh(0.058, 0.10, suit), Vector3(0.0, 0.03, 0.0))
	_attach("Head", _sphere_mesh(0.125, helmet), Vector3(0.0, 0.095, 0.0))
	_attach("Head", _box_mesh(Vector3(0.155, 0.10, 0.12), helmet), Vector3(0.0, 0.025, -0.045))
	_attach("Head", _box_mesh(Vector3(0.19, 0.055, 0.035), visor), Vector3(0.0, 0.082, -0.10))
	_attach("Head", _box_mesh(Vector3(0.05, 0.018, 0.19), accent), Vector3(0.0, 0.185, -0.01))

	if _style["hump"]:
		_attach("Chest", _box_mesh(Vector3(0.24, 0.16, 0.15), suit), Vector3(0.0, 0.12, 0.14))

	for side_name: String in ["L", "R"]:
		var side := 1.0 if side_name == "L" else -1.0
		var upper := "UpperArm." + side_name
		var fore := "Forearm." + side_name
		var hand := "Hand." + side_name
		var thigh := "Thigh." + side_name
		var calf := "Calf." + side_name
		var foot := "Foot." + side_name
		_attach(upper, _sphere_mesh(0.082, suit), Vector3(side * 0.01, 0.015, 0.0))
		_attach_segment(upper, fore, 0.063, suit)
		_attach(fore, _sphere_mesh(0.06, suit), Vector3.ZERO)
		_attach_segment(fore, hand, 0.054, accent)
		_attach(hand, _sphere_mesh(0.06, glove), Vector3.ZERO)
		_attach(thigh, _sphere_mesh(0.088, suit), Vector3(side * 0.01, 0.0, 0.0))
		_attach_segment(thigh, calf, 0.082, suit)
		_attach(calf, _sphere_mesh(0.074, suit), Vector3.ZERO)
		_attach_segment(calf, foot, 0.070, accent)
		_attach(calf, _box_mesh(Vector3(0.10, 0.10, 0.12), suit), Vector3(0.0, 0.02, -0.05))
		_attach(foot, _sphere_mesh(0.058, boot), Vector3(0.0, 0.0, 0.0))
		_attach(foot, _box_mesh(Vector3(0.11, 0.10, 0.23), boot), Vector3(0.0, -0.02, -0.03))


# --- animation ---------------------------------------------------------

func _process(delta: float) -> void:
	_time += delta
	if _attack_t >= 0.0:
		_attack_t += delta
		if _attack_t >= ATTACK_TIME:
			_attack_t = -1.0
	if _hit_t >= 0.0:
		_hit_t += delta
		if _hit_t >= HIT_TIME:
			_hit_t = -1.0
	if _crash_t >= 0.0:
		_crash_t += delta
		_apply_crash_motion()
	_update_pose()


## Drive the root transform through the wipeout sequence: a ballistic ejection,
## getting up, a run back to the bike, bracing to lift it and climbing on.
func _apply_crash_motion() -> void:
	var t: float = _crash_t
	var side := _crash_side
	var landing: Vector3 = _base_pos + Vector3(side * 1.25, -0.16, 0.18)
	var beside: Vector3 = _base_pos + Vector3(side * 0.52, -0.18, 0.02)
	if t < CRASH_EJECT_END:
		var p: float = t / CRASH_EJECT_END
		var e: float = p * p * (3.0 - 2.0 * p)
		var arc: float = 4.0 * p * (1.0 - p)
		position = _base_pos.lerp(landing, e) + Vector3.UP * (0.55 * arc)
		rotation = Vector3(0.35 * arc, 0.0, -side * TAU * e)
		crash_phase = "eject"
	elif t < CRASH_GETUP_END:
		var p: float = (t - CRASH_EJECT_END) / (CRASH_GETUP_END - CRASH_EJECT_END)
		var e: float = p * p * (3.0 - 2.0 * p)
		position = landing
		rotation = Vector3(lerpf(0.45, 0.0, e), 0.0, lerp_angle(-side * TAU, 0.0, e))
		crash_phase = "getup"
	elif t < CRASH_RUN_END:
		var p: float = (t - CRASH_GETUP_END) / (CRASH_RUN_END - CRASH_GETUP_END)
		var e: float = p * p * (3.0 - 2.0 * p)
		position = landing.lerp(beside, e) + Vector3.UP * absf(sin(t * 13.0)) * 0.04
		rotation = Vector3.ZERO
		crash_phase = "run"
	elif t < CRASH_LIFT_END:
		var p: float = (t - CRASH_RUN_END) / (CRASH_LIFT_END - CRASH_RUN_END)
		var e: float = 1.0 - (1.0 - p) * (1.0 - p)
		position = beside
		rotation = Vector3(0.0, -side * 0.28 * e, 0.0)
		crash_phase = "lift"
	else:
		var p: float = clampf((t - CRASH_LIFT_END) / (CRASH_TOTAL - CRASH_LIFT_END), 0.0, 1.0)
		var e: float = p * p * (3.0 - 2.0 * p)
		position = beside.lerp(_base_pos, e) + Vector3.UP * (0.30 * 4.0 * p * (1.0 - p))
		rotation = Vector3(0.0, -side * 0.28 * (1.0 - e), 0.0)
		crash_phase = "mount"


func _segment_p(a: float, b: float) -> float:
	return clampf((_crash_t - a) / maxf(b - a, 0.001), 0.0, 1.0)


func _smooth(p: float) -> float:
	return p * p * (3.0 - 2.0 * p)


func _update_pose() -> void:
	for b in BONES:
		_local[b["name"]] = _rest[b["name"]]
	var attack := _attack_weights()
	_apply_torso(attack)
	_apply_targets(attack)
	_fk_torso()
	if _crash_t < 0.0:
		_ik_arm("L", 1.0)
		_ik_arm("R", -1.0)
		_ik_leg("L", 1.0)
		_ik_leg("R", -1.0)
	else:
		_apply_crash_pose()
	for b in BONES:
		var name: String = b["name"]
		var t: Transform3D = _local[name]
		_skeleton.set_bone_pose_position(_idx[name], t.origin)
		_skeleton.set_bone_pose_rotation(_idx[name], t.basis)


## Punch/kick envelope: returns {wind, strike} in 0..1.
func _attack_weights() -> Dictionary:
	if _attack_t < 0.0:
		return {"wind": 0.0, "strike": 0.0}
	var p: float = _attack_t / ATTACK_TIME
	if p < 0.28:
		var q: float = p / 0.28
		return {"wind": sin(q * PI * 0.5), "strike": 0.0}
	if p < 0.55:
		var q: float = (p - 0.28) / 0.27
		return {"wind": 1.0 - q, "strike": sin(q * PI)}
	var q2: float = (p - 0.55) / 0.45
	return {"wind": 0.0, "strike": (1.0 - q2) * 0.0}


func _apply_torso(attack: Dictionary) -> void:
	var bend: float = _style["bend"]
	var look: float = _style["look"]
	# nitro/speed tuck adds a touch more forward lean
	bend += (0.10 if _nitro else 0.0) + _speed * 0.06
	var wind: float = attack["wind"]
	var strike: float = attack["strike"]
	var side := _attack_side
	var yaw := side * (strike * 0.55 - wind * 0.30)
	var roll := _lean * 0.35 - side * strike * 0.14
	var jitter := (sin(_time * 37.0) + sin(_time * 23.0 + 1.3)) * 0.5 * _speed * 0.012
	# hit flinch: sharp pitch-back plus a roll away
	var flinch := 0.0
	if _hit_t >= 0.0:
		flinch = sin(clampf(_hit_t / HIT_TIME, 0.0, 1.0) * PI)
	_set_rot("Spine", Vector3(bend * 0.45 + jitter, yaw * 0.35, roll * 0.5 + jitter))
	_set_rot("Chest", Vector3(bend * 0.55 - flinch * 0.30, yaw, roll * 0.5))
	_set_rot("Neck", Vector3(-bend * 0.25 + flinch * 0.15, yaw * 0.2, 0.0))
	var head_yaw := -_steer * 0.30 * (0.4 + _speed) + yaw * 0.25
	_set_rot("Head", Vector3(look - bend * 0.15 + flinch * 0.2, head_yaw, roll * 0.4))


func _apply_targets(attack: Dictionary) -> void:
	var wind: float = attack["wind"]
	var strike: float = attack["strike"]
	for side_name: String in ["L", "R"]:
		var side := 1.0 if side_name == "L" else -1.0
		_hand_target[side_name] = _hand_base[side_name]
		_foot_target[side_name] = _foot_base[side_name]
		if _attack_t < 0.0 or not is_equal_approx(side, _attack_side):
			continue
		if _attack_kind == "kick":
			_foot_target[side_name] += Vector3(0.0, 0.03, 0.10) * wind
			_foot_target[side_name] += Vector3(side * 0.80, 0.45, -0.35) * strike
		else:
			_hand_target[side_name] += Vector3(-side * 0.12, 0.02, 0.15) * wind
			_hand_target[side_name] += Vector3(side * 0.85, 0.16, 0.0) * strike


func _fk_torso() -> void:
	for name in TORSO:
		var parent := _parent_of(name)
		_glob[name] = (_glob[parent] if parent != "" else Transform3D.IDENTITY) * _local[name]


func _ik_arm(side_name: String, side: float) -> void:
	var parent_glob: Transform3D = _glob["Chest"]
	var upper_off: Vector3 = _rest["UpperArm." + side_name].origin
	var lower_off: Vector3 = _rest["Forearm." + side_name].origin
	var end_off: Vector3 = _rest["Hand." + side_name].origin
	var p0: Vector3 = parent_glob * upper_off
	var pole := p0 + Vector3(side * 0.34, -0.46, 0.10)
	var res := _ik_two(parent_glob, upper_off, lower_off, end_off, _hand_target[side_name], pole)
	_local["UpperArm." + side_name] = res[0]
	_local["Forearm." + side_name] = res[1]


func _ik_leg(side_name: String, side: float) -> void:
	var parent_glob: Transform3D = _glob["Hips"]
	var upper_off: Vector3 = _rest["Thigh." + side_name].origin
	var lower_off: Vector3 = _rest["Calf." + side_name].origin
	var end_off: Vector3 = _rest["Foot." + side_name].origin
	var p0: Vector3 = parent_glob * upper_off
	var pole := p0 + Vector3(side * 0.28, -0.15, -0.60)
	var res := _ik_two(parent_glob, upper_off, lower_off, end_off, _foot_target[side_name], pole)
	_local["Thigh." + side_name] = res[0]
	_local["Calf." + side_name] = res[1]


## Crash flail: the bike is already tipping over (Tilt), the rider tumbles with
## it and the limbs thrash with decaying amplitude.
func _flail() -> void:
	var t: float = _crash_t
	var amp: float = clampf(exp(-t * 0.55), 0.0, 1.0)
	var s := _crash_seed
	_set_rot("Spine", Vector3(-0.45 * amp, sin(t * 9.0 + s) * 0.35 * amp, 0.30 * amp))
	_set_rot("Chest", Vector3(-0.35 * amp, sin(t * 7.0 + s + 1.0) * 0.30 * amp, 0.25 * amp))
	_set_rot("Neck", Vector3(0.35 * amp, 0.0, 0.0))
	_set_rot("Head", Vector3(0.30 * amp, sin(t * 11.0) * 0.30 * amp, 0.0))
	for side_name: String in ["L", "R"]:
		var side := 1.0 if side_name == "L" else -1.0
		var ph := t * 10.0 + (0.0 if side > 0.0 else 2.1) + s
		_set_rot("UpperArm." + side_name, Vector3(sin(ph) * 0.9 * amp - 0.4 * amp, 0.0, side * (0.5 + 0.8 * amp)))
		_set_rot("Forearm." + side_name, Vector3(-0.9 * amp, 0.0, 0.0))
		_set_rot("Thigh." + side_name, Vector3(-0.5 * amp + sin(ph * 1.3) * 0.6 * amp, 0.0, side * 0.2 * amp))
		_set_rot("Calf." + side_name, Vector3(-1.1 * amp, 0.0, 0.0))


## Wipeout pose dispatcher: runs after `_apply_crash_motion` set the root, and
## writes only the bones for the current phase.
func _apply_crash_pose() -> void:
	match crash_phase:
		"eject":
			_flail()
		"getup":
			_pose_getup()
		"run":
			_pose_run()
		"lift":
			_pose_lift()
		"mount":
			_pose_mount()
		_:
			_flail()


## Stand up after the tumble: the torso swings from face-down to upright while
## the feet slide from behind the hips to under them.
func _pose_getup() -> void:
	var e := _smooth(_segment_p(CRASH_EJECT_END, CRASH_GETUP_END))
	_set_rot("Spine", Vector3(lerpf(-0.90, 0.06, e), 0.0, 0.0))
	_set_rot("Chest", Vector3(lerpf(-0.70, 0.04, e), 0.0, 0.0))
	_set_rot("Neck", Vector3(lerpf(0.50, -0.04, e), 0.0, 0.0))
	_set_rot("Head", Vector3(lerpf(0.40, 0.0, e), 0.0, 0.0))
	for side_name in ["L", "R"]:
		var side := 1.0 if side_name == "L" else -1.0
		_set_rot("UpperArm." + side_name, Vector3(lerpf(-0.70, 0.0, e), 0.0, side * lerpf(0.80, 0.12, e)))
		_set_rot("Forearm." + side_name, Vector3(lerpf(-1.00, 0.20, e), 0.0, 0.0))
	_fk_torso()
	for side_name in ["L", "R"]:
		var side := 1.0 if side_name == "L" else -1.0
		_foot_target[side_name] = Vector3(side * 0.13, lerpf(-0.40, -0.58, e), lerpf(0.16, -0.03, e))
		_ik_leg(side_name, side)


## Run back to the bike: planted fore/aft leg stride (IK) plus opposite arm swing.
func _pose_run() -> void:
	var t := _crash_t
	_set_rot("Spine", Vector3(0.12 + 0.05 * sin(t * 13.0), 0.0, 0.0))
	_set_rot("Chest", Vector3(0.10, 0.0, 0.0))
	_set_rot("Neck", Vector3(-0.05, 0.0, 0.0))
	_set_rot("Head", Vector3(0.05, 0.0, 0.0))
	for side_name in ["L", "R"]:
		var side := 1.0 if side_name == "L" else -1.0
		var ph := t * 13.0 + (0.0 if side > 0.0 else PI)
		var swing := sin(ph)
		_set_rot("UpperArm." + side_name, Vector3(0.55 * swing, 0.0, side * 0.14))
		_set_rot("Forearm." + side_name, Vector3(0.95, 0.0, 0.0))
	_fk_torso()
	for side_name in ["L", "R"]:
		var side := 1.0 if side_name == "L" else -1.0
		var ph := t * 13.0 + (0.0 if side > 0.0 else PI)
		var s := sin(ph)
		var lift := maxf(0.0, -cos(ph)) * 0.10
		_foot_target[side_name] = Vector3(side * 0.12, -0.58 + lift, -0.42 * s)
		_ik_leg(side_name, side)


## Brace against the fallen bike and pull it upright: the arms reach for the bar
## and rise as the bike comes up.
func _pose_lift() -> void:
	var e := _smooth(_segment_p(CRASH_RUN_END, CRASH_LIFT_END))
	_set_rot("Spine", Vector3(lerpf(0.48, 0.16, e), 0.0, 0.0))
	_set_rot("Chest", Vector3(lerpf(0.52, 0.20, e), 0.0, 0.0))
	_set_rot("Neck", Vector3(-0.08, 0.0, 0.0))
	_set_rot("Head", Vector3(0.12, 0.0, 0.0))
	_fk_torso()
	for side_name in ["L", "R"]:
		var side := 1.0 if side_name == "L" else -1.0
		_foot_target[side_name] = Vector3(side * 0.15, -0.58, -0.06)
		_hand_target[side_name] = Vector3(side * 0.13, lerpf(-0.12, 0.52, e), lerpf(-0.50, -0.46, e))
	_ik_arm("L", 1.0)
	_ik_arm("R", -1.0)
	_ik_leg("L", 1.0)
	_ik_leg("R", -1.0)


## Climb back on: targets blend from the standing/lift pose to the seated grip
## and peg, with a small hop over the bike.
func _pose_mount() -> void:
	var e := _smooth(_segment_p(CRASH_LIFT_END, CRASH_TOTAL))
	var bend: float = _style["bend"]
	var look: float = _style["look"]
	_set_rot("Spine", Vector3(lerpf(0.16, bend * 0.45, e), 0.0, 0.0))
	_set_rot("Chest", Vector3(lerpf(0.20, bend * 0.55, e), 0.0, 0.0))
	_set_rot("Neck", Vector3(lerpf(-0.08, -bend * 0.25, e), 0.0, 0.0))
	_set_rot("Head", Vector3(lerpf(0.12, look - bend * 0.15, e), 0.0, 0.0))
	_fk_torso()
	for side_name in ["L", "R"]:
		var side := 1.0 if side_name == "L" else -1.0
		var stand_foot := Vector3(side * 0.12, -0.58, -0.03)
		_foot_target[side_name] = stand_foot.lerp(_foot_base[side_name], e) + Vector3.UP * (0.28 * sin(e * PI))
		var lift_hand := Vector3(side * 0.13, 0.52, -0.46)
		_hand_target[side_name] = lift_hand.lerp(_hand_base[side_name], e)
	_ik_arm("L", 1.0)
	_ik_arm("R", -1.0)
	_ik_leg("L", 1.0)
	_ik_leg("R", -1.0)


func _set_rot(name: String, euler: Vector3) -> void:
	_local[name] = Transform3D(Basis.from_euler(euler), _rest[name].origin)


func _parent_of(name: String) -> String:
	return _parent_name.get(name, "")


## Analytic two-bone IK. `parent_glob` is the upper bone's parent frame in rider
## space; *_off are the rest offsets (upper from parent, lower from upper, end
## from lower). Returns [upper_local, lower_local].
func _ik_two(parent_glob: Transform3D, upper_off: Vector3, lower_off: Vector3,
		end_off: Vector3, target: Vector3, pole: Vector3) -> Array:
	var p0: Vector3 = parent_glob * upper_off
	var l1 := lower_off.length()
	var l2 := end_off.length()
	var to_target := target - p0
	var d := clampf(to_target.length(), 0.02, l1 + l2 - 0.002)
	var u := to_target.normalized()
	var cos_a := clampf((l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d), -1.0, 1.0)
	var a := acos(cos_a)
	var perp := (pole - p0) - u * (pole - p0).dot(u)
	if perp.length_squared() < 1e-6:
		perp = Vector3(0.0, -1.0, 0.0).cross(u)
		if perp.length_squared() < 1e-6:
			perp = Vector3(1.0, 0.0, 0.0)
	perp = perp.normalized()
	var upper_dir := (u * cos(a) + perp * sin(a)).normalized()
	var joint: Vector3 = p0 + upper_dir * l1
	var lower_dir := (target - joint).normalized()
	var up_basis := _bone_basis(parent_glob.basis, lower_off.normalized(), upper_dir)
	var upper_glob_basis := parent_glob.basis * up_basis
	var lo_basis := _bone_basis(upper_glob_basis, end_off.normalized(), lower_dir)
	return [Transform3D(up_basis, upper_off), Transform3D(lo_basis, lower_off)]


## Basis B so that parent_basis * B maps `from_dir` (bone-local) to `to_dir`.
func _bone_basis(parent_basis: Basis, from_dir: Vector3, to_dir: Vector3) -> Basis:
	var to := (parent_basis.inverse() * to_dir).normalized()
	return Basis(Quaternion(from_dir, to))


# --- mesh helpers ------------------------------------------------------

func _attach(bone: String, mesh: Mesh, offset: Vector3) -> MeshInstance3D:
	return _attach_t(bone, mesh, Transform3D(Basis.IDENTITY, offset))


func _attach_segment(bone: String, child: String, radius: float, mat: Material) -> MeshInstance3D:
	var off: Vector3 = _rest[child].origin
	var dist := off.length()
	var mesh := _cap_mesh(radius, dist, mat)
	var t := Transform3D(Basis(Quaternion(Vector3.UP, off.normalized())), off * 0.5)
	return _attach_t(bone, mesh, t)


func _attach_t(bone: String, mesh: Mesh, t: Transform3D) -> MeshInstance3D:
	var ba: BoneAttachment3D = null
	for c in _skeleton.get_children():
		if c is BoneAttachment3D and (c as BoneAttachment3D).bone_name == bone:
			ba = c
			break
	if ba == null:
		ba = BoneAttachment3D.new()
		ba.name = "Attach_" + bone
		ba.bone_name = bone
		_skeleton.add_child(ba)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.transform = t
	ba.add_child(mi)
	return mi


func _cap_mesh(radius: float, height: float, mat: Material) -> CapsuleMesh:
	var m := CapsuleMesh.new()
	m.radius = radius
	m.height = maxf(height, radius * 2.0)
	m.radial_segments = 10
	m.rings = 3
	m.material = mat
	return m


func _box_mesh(size: Vector3, mat: Material) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	m.material = mat
	return m


func _sphere_mesh(radius: float, mat: Material) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0
	m.radial_segments = 12
	m.rings = 8
	m.material = mat
	return m


func _mat(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m
