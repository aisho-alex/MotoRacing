class_name BikeVisuals
extends RefCounted
## Builds a low-poly motorcycle (and its seated Rider) from primitives. The two
## wheels are ordinary "wheel_front"/"wheel_rear" nodes so race_bike.gd's
## existing spin/steer pipeline picks them up unchanged. Silhouette and colors
## come from the BikeDef; an optional GLB in BikeDef.model_path overrides this.

const WHEELBASE := 1.46
const HEADLIGHT := Color(1.0, 0.96, 0.80)

## Per-style proportions. z is +/- the track direction (-Z is forward).
const STYLES := {
	"scrambler": {
		"wheel_r": 0.35, "rear_w": 0.13, "seat_h": 0.84, "tank": Vector3(0.32, 0.26, 0.56),
		"bar_h": 1.28, "bar_z": -0.42, "fairing": false, "screen": false, "rear_wide": 1.0,
	},
	"sport": {
		"wheel_r": 0.32, "rear_w": 0.16, "seat_h": 0.86, "tank": Vector3(0.36, 0.24, 0.60),
		"bar_h": 1.18, "bar_z": -0.52, "fairing": true, "screen": true, "rear_wide": 1.3,
	},
	"cruiser": {
		"wheel_r": 0.33, "rear_w": 0.15, "seat_h": 0.74, "tank": Vector3(0.38, 0.28, 0.66),
		"bar_h": 1.14, "bar_z": -0.50, "fairing": false, "screen": false, "rear_wide": 1.1,
	},
	"super": {
		"wheel_r": 0.33, "rear_w": 0.20, "seat_h": 0.84, "tank": Vector3(0.40, 0.26, 0.64),
		"bar_h": 1.16, "bar_z": -0.54, "fairing": true, "screen": true, "rear_wide": 1.6,
	},
}


## Returns a "Model" holder with the bike and rider. Empty when the style is
## unknown (falls back to "sport").
static func build(def: BikeDef) -> Node3D:
	var cfg: Dictionary = STYLES.get(def.style, STYLES["sport"])
	var holder := Node3D.new()
	holder.name = "Model"
	_build_wheels(holder, def, cfg)
	_build_body(holder, def, cfg)
	return holder


## Seat position for the procedural rider, per style (bike-local, -Z forward).
static func procedural_rider_mount(def: BikeDef) -> Vector3:
	var cfg: Dictionary = STYLES.get(def.style, STYLES["sport"])
	return Vector3(0.0, cfg["seat_h"] + 0.06, 0.14)


static func _build_wheels(holder: Node3D, def: BikeDef, cfg: Dictionary) -> void:
	var r: float = cfg["wheel_r"]
	var zf := -WHEELBASE * 0.5
	var zr := WHEELBASE * 0.5
	_wheel(holder, "wheel_front", Vector3(0.0, r, zf), r, cfg["rear_w"] * 0.85)
	_wheel(holder, "wheel_rear", Vector3(0.0, r, zr), r, cfg["rear_w"] * cfg["rear_wide"])


static func _wheel(holder: Node3D, name: String, pos: Vector3, r: float, width: float) -> void:
	var w := Node3D.new()
	w.name = name
	w.position = pos

	var tire := CylinderMesh.new()
	tire.top_radius = r
	tire.bottom_radius = r
	tire.height = width
	tire.radial_segments = 16
	tire.rings = 1
	tire.material = _mat(Color(0.045, 0.045, 0.05), 0.95, 0.0)
	var tm := MeshInstance3D.new()
	tm.mesh = tire
	tm.basis = Basis(Vector3(0.0, 0.0, 1.0), PI * 0.5)
	w.add_child(tm)

	var rim := CylinderMesh.new()
	rim.top_radius = r * 0.58
	rim.bottom_radius = r * 0.58
	rim.height = width * 1.06
	rim.radial_segments = 12
	rim.rings = 1
	rim.material = _mat(Color(0.74, 0.76, 0.80), 0.28, 0.85)
	var rm := MeshInstance3D.new()
	rm.mesh = rim
	rm.basis = Basis(Vector3(0.0, 0.0, 1.0), PI * 0.5)
	w.add_child(rm)

	var hub := CylinderMesh.new()
	hub.top_radius = r * 0.18
	hub.bottom_radius = r * 0.18
	hub.height = width * 1.2
	hub.radial_segments = 8
	hub.material = _mat(Color(0.2, 0.2, 0.22), 0.4, 0.7)
	var hm := MeshInstance3D.new()
	hm.mesh = hub
	hm.basis = Basis(Vector3(0.0, 0.0, 1.0), PI * 0.5)
	w.add_child(hm)

	holder.add_child(w)


static func _build_body(holder: Node3D, def: BikeDef, cfg: Dictionary) -> void:
	var r: float = cfg["wheel_r"]
	var seat_h: float = cfg["seat_h"]
	var body := _mat(def.body_color, 0.32, 0.45)
	var accent := _mat(def.accent_color, 0.35, 0.5)
	var engine := _mat(Color(0.12, 0.12, 0.13), 0.4, 0.7)
	var chrome := _mat(Color(0.84, 0.86, 0.90), 0.15, 1.0)
	var zf := -WHEELBASE * 0.5
	var zr := WHEELBASE * 0.5

	# engine block + frame spine
	_box(holder, Vector3(0.30, 0.30, 0.42), Vector3(0.0, r + 0.18, -0.02), engine)
	_seg(holder, Vector3(0.0, seat_h - 0.04, 0.16), Vector3(0.0, seat_h + 0.02, -0.30), 0.045, body)
	_seg(holder, Vector3(0.0, r + 0.10, 0.06), Vector3(0.0, seat_h - 0.06, 0.18), 0.05, accent)

	# swingarm + rear shock
	_seg(holder, Vector3(0.09, r + 0.06, 0.10), Vector3(0.09, r, zr), 0.035, engine)
	_seg(holder, Vector3(-0.09, r + 0.06, 0.10), Vector3(-0.09, r, zr), 0.035, engine)
	_seg(holder, Vector3(0.0, r + 0.10, 0.06), Vector3(0.0, seat_h - 0.10, 0.20), 0.03, chrome)

	# front forks + steering
	_seg(holder, Vector3(0.075, seat_h - 0.06, -0.24), Vector3(0.075, r, zf), 0.028, chrome)
	_seg(holder, Vector3(-0.075, seat_h - 0.06, -0.24), Vector3(-0.075, r, zf), 0.028, chrome)

	# tank, seat, tail
	var tank: Vector3 = cfg["tank"]
	_box(holder, tank, Vector3(0.0, seat_h + 0.06, -0.10), body)
	_box(holder, Vector3(0.30, 0.10, 0.42), Vector3(0.0, seat_h + 0.01, 0.18), accent)
	_box(holder, Vector3(0.26, 0.12, 0.30), Vector3(0.0, seat_h + 0.08, 0.42), body)
	_box(holder, Vector3(0.20, 0.10, 0.10), Vector3(0.0, seat_h + 0.05, 0.58), _mat(Color(0.85, 0.10, 0.08), 0.4, 0.2))

	# fenders
	var ff := BoxMesh.new()
	ff.size = Vector3(0.12, 0.06, 0.36)
	ff.material = body
	var fm := MeshInstance3D.new()
	fm.mesh = ff
	fm.position = Vector3(0.0, r + 0.20, zf - 0.02)
	holder.add_child(fm)
	var rf := BoxMesh.new()
	rf.size = Vector3(0.16, 0.06, 0.30)
	rf.material = accent
	var rm := MeshInstance3D.new()
	rm.mesh = rf
	rm.position = Vector3(0.0, r + 0.22, zr + 0.04)
	holder.add_child(rm)

	# handlebar
	var bar := CylinderMesh.new()
	bar.top_radius = 0.022
	bar.bottom_radius = 0.022
	bar.height = 0.62
	bar.radial_segments = 8
	bar.material = chrome
	var bm := MeshInstance3D.new()
	bm.mesh = bar
	bm.position = Vector3(0.0, cfg["bar_h"], cfg["bar_z"])
	bm.basis = Basis(Vector3(0.0, 0.0, 1.0), PI * 0.5)
	holder.add_child(bm)

	if cfg["fairing"]:
		_box(holder, Vector3(0.30, 0.30, 0.26), Vector3(0.0, seat_h + 0.02, -0.42), body)
		_box(holder, Vector3(0.22, 0.16, 0.16), Vector3(0.0, seat_h + 0.20, -0.40), body)
	if cfg["screen"]:
		var scr := BoxMesh.new()
		scr.size = Vector3(0.24, 0.16, 0.02)
		scr.material = _mat(Color(0.35, 0.45, 0.60), 0.15, 0.2)
		var sm := MeshInstance3D.new()
		sm.mesh = scr
		sm.position = Vector3(0.0, cfg["bar_h"] + 0.12, cfg["bar_z"] - 0.04)
		holder.add_child(sm)

	# headlight
	var hl := _mat(HEADLIGHT, 0.2, 0.1)
	hl.emission_enabled = true
	hl.emission = HEADLIGHT
	hl.emission_energy_multiplier = 1.6
	var light := SphereMesh.new()
	light.radius = 0.09
	light.height = 0.18
	light.radial_segments = 10
	light.rings = 6
	light.material = hl
	var lm := MeshInstance3D.new()
	lm.mesh = light
	lm.position = Vector3(0.0, seat_h - 0.02, -WHEELBASE * 0.5 - 0.26)
	holder.add_child(lm)

	# exhaust
	_seg(holder, Vector3(0.14, r + 0.10, -0.10), Vector3(0.16, r + 0.14, zr + 0.06), 0.045, chrome)
	_seg(holder, Vector3(0.16, r + 0.14, zr + 0.06), Vector3(0.20, r + 0.16, zr + 0.34), 0.055, chrome)

	# footpegs
	for s in [1.0, -1.0]:
		var peg := CylinderMesh.new()
		peg.top_radius = 0.02
		peg.bottom_radius = 0.02
		peg.height = 0.12
		peg.radial_segments = 6
		peg.material = chrome
		var pm := MeshInstance3D.new()
		pm.mesh = peg
		pm.position = Vector3(s * 0.24, r + 0.06, 0.10)
		pm.basis = Basis(Vector3(0.0, 0.0, 1.0), PI * 0.5)
		holder.add_child(pm)


static func _mat(c: Color, rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


static func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var m := BoxMesh.new()
	m.size = size
	m.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.position = pos
	parent.add_child(mi)
	return mi


static func _seg(parent: Node3D, a: Vector3, b: Vector3, r: float, mat: Material) -> MeshInstance3D:
	var dir := b - a
	var dist := dir.length()
	var m := CylinderMesh.new()
	m.top_radius = r
	m.bottom_radius = r
	m.height = maxf(dist, r * 2.0)
	m.radial_segments = 8
	m.rings = 1
	m.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.position = (a + b) * 0.5
	if dist > 0.0001:
		mi.basis = Basis(Quaternion(Vector3.UP, dir.normalized()))
	parent.add_child(mi)
	return mi
