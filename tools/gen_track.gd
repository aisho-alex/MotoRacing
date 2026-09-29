extends SceneTree
## Dev tool: seeded race-track layout generator + validator.
##
## Builds closed Catmull-Rom loops (control points in a .tres TrackDef), checks
## them against the same geometry rules the game relies on (self-clearance,
## corner radius, straight runs for boost pads) and renders a contact sheet so a
## human can pick a layout. Selected seeds are then emitted as real .tres files.
##
## Run:
##   godot --headless --path . -s tools/gen_track.gd -- mode=calibrate
##   godot --headless --path . -s tools/gen_track.gd -- mode=sheet biome=coast count=12 seed=100
##   godot --headless --path . -s tools/gen_track.gd -- mode=emit biome=coast seed=104 id=coast_02 display="Coast II"

const SUBDIV := 26  # must mirror TrackBuilder.SUBDIV
const PAD_COUNT := 5
const PAD_STRAIGHT_DOT := 0.995
const PAD_STRAIGHT_LAG := 8
const PAD_MIN_INDEX := 60
const PAD_START_GAP := 70
## Samples of arc separation under which two centerline points count as
## neighbours (same corner/straight) rather than a potential crossing.
## ~1.7 control points: wider than one SUBDIV corner but below a 2-point bend.
const NEIGHBOUR_SAMPLES := 44
const CELL := 420
const COLS := 4
const OUT_DIR := "/tmp/opencode"
const TRACK_DIR := "res://assets/data/tracks"

# Acceptance thresholds, tuned by `mode=calibrate` against the shipped tracks
# (their tightest section clearance is ~49 m, tightest corner ~25 m, laps
# 1220-1947 m, 3-7 boost-pad straights).
const GAP_MIN := 40.0        # min centerline distance between non-adjacent parts
const RADIUS_MIN := 22.0     # min corner radius (m)
const LAP_MIN := 1000.0      # lap length lower bound (m)
const LAP_MAX := 2400.0      # lap length upper bound (m)
const PADS_REQUIRED := 3     # straight stretches usable as boost pads

var _done := false


func _initialize() -> void:
	var args := _parse_args(OS.get_cmdline_user_args())
	match args.get("mode", "calibrate"):
		"calibrate":
			_calibrate()
		"sheet":
			_sheet(args)
		"emit":
			_emit(args)
		_:
			push_error("mode must be calibrate|sheet|emit")
	_done = true


func _process(_delta: float) -> bool:
	if _done:
		quit(0)
	return _done


func _parse_args(argv: PackedStringArray) -> Dictionary:
	var out := {}
	for a in argv:
		var eq := a.find("=")
		if eq > 0:
			out[a.substr(0, eq)] = a.substr(eq + 1)
	return out


# ---------------------------------------------------------------- calibration

func _calibrate() -> void:
	print("existing tracks (gap measured at several neighbour windows):")
	for id in ["city_01", "desert_01", "alpine_01", "coast_01"]:
		var td := load("%s/%s.tres" % [TRACK_DIR, id]) as TrackDef
		var m := _metrics(td)
		var g40 := _gap(td, 40)
		var g90 := _gap(td, 90)
		var g140 := _gap(td, 140)
		print("  %-11s len=%6.0f  gap40=%6.1f gap90=%6.1f gap140=%6.1f  minR=%6.1f  pads=%d  pts=%d" % [
			id, m.length, g40, g90, g140, m.radius, m.pads, td.control_points.size()])


## Min centerline distance between sections at least `window` samples apart.
func _gap(td: TrackDef, window: int) -> float:
	var tb := TrackBuilder.new()
	tb.def = td
	tb._sample_centerline()
	var c := tb.centerline
	var n := c.size()
	var gap := INF
	for i in n:
		for j in n:
			var d := absi(i - j)
			if mini(d, n - d) <= window:
				continue
			gap = minf(gap, c[i].distance_to(c[j]))
	tb.free()
	return gap


# ------------------------------------------------------------------ generation

## Builds one candidate layout from `seed` as a closed radial loop with a few
## snapped straight runs. Returns {points: PackedVector3Array, seed: int}.
func _make_layout(seed: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var n := rng.randi_range(16, 22)
	var base_r := rng.randf_range(170.0, 245.0)
	var max_freq := 3 if n <= 18 else 4
	var terms := rng.randi_range(2, 3)
	var freqs: Array[int] = []
	var amps: Array[float] = []
	var phases: Array[float] = []
	for _i in terms:
		freqs.append(rng.randi_range(2, max_freq))
		amps.append(rng.randf_range(0.05, 0.15))
		phases.append(rng.randf() * TAU)
	var sx := rng.randf_range(0.85, 1.18)
	var sz := rng.randf_range(0.85, 1.18)
	var rot := rng.randf() * TAU
	var pts := PackedVector3Array()
	for k in n:
		var th := TAU * float(k) / float(n)
		var r := 1.0
		for i in terms:
			r += amps[i] * sin(freqs[i] * th + phases[i])
		var x := r * base_r * cos(th) * sx
		var z := r * base_r * sin(th) * sz
		pts.append(Vector3(x * cos(rot) - z * sin(rot), 0.0, x * sin(rot) + z * cos(rot)))
	var runs := _snap_straights(rng, pts)
	_rotate_to_start(pts, runs)
	return {"points": pts, "seed": seed}


## Replaces 2-4 runs of 4-6 consecutive control points by a straight chord.
## Catmull-Rom draws a truly straight segment only when 4 neighbours are
## collinear, so runs are at least 4 points long.
func _snap_straights(rng: RandomNumberGenerator, pts: PackedVector3Array) -> Array:
	var n := pts.size()
	var runs: Array = []
	var used := {}
	for _r in rng.randi_range(2, 4):
		var length := mini(rng.randi_range(4, 6), n - 2)
		var start := rng.randi_range(0, n - 1)
		var idxs: Array[int] = []
		var ok := true
		for t in length:
			var i := (start + t) % n
			if used.has(i):
				ok = false
				break
			idxs.append(i)
		if not ok:
			continue
		for i in idxs:
			used[i] = true
		var a: Vector3 = pts[idxs[0]]
		var b: Vector3 = pts[idxs[length - 1]]
		if a.distance_to(b) < 1.0:
			continue
		for t in length:
			var p := a.lerp(b, float(t) / float(length - 1))
			pts[idxs[t]] = Vector3(p.x, 0.0, p.z)
		runs.append(idxs)
	return runs


## Rotates the loop so the first control point starts the longest straight,
## keeping the start/finish line on a clean, pad-friendly stretch.
func _rotate_to_start(pts: PackedVector3Array, runs: Array) -> void:
	if runs.is_empty():
		return
	var best: Array = runs[0]
	for r in runs:
		if r.size() > best.size():
			best = r
	var off: int = best[0]
	var n := pts.size()
	var out := PackedVector3Array()
	for k in n:
		out.append(pts[(off + k) % n])
	for k in n:
		pts[k] = out[k]


# ------------------------------------------------------------------- metrics

## Samples the candidate's centerline with the engine's own code and reports
## clearance, tightest corner, straight-run count and lap length.
func _metrics(td: TrackDef) -> Dictionary:
	var tb := TrackBuilder.new()
	tb.def = td
	tb._sample_centerline()
	var c := tb.centerline
	var n := c.size()
	var hw := td.road_half_width
	var length := tb._arc[n - 1] + c[n - 1].distance_to(c[0])

	var gap := INF
	for i in n:
		for j in n:
			var d := absi(i - j)
			if mini(d, n - d) <= NEIGHBOUR_SAMPLES:
				continue
			var dist := c[i].distance_to(c[j])
			if dist < gap:
				gap = dist

	var radius := INF
	for i in n:
		var a := c[(i - 1 + n) % n]
		var b := c[i]
		var cc := c[(i + 1) % n]
		var ab := a.distance_to(b)
		var bc := b.distance_to(cc)
		var ca := cc.distance_to(a)
		var area := 0.5 * absf((b.x - a.x) * (cc.z - a.z) - (cc.x - a.x) * (b.z - a.z))
		if area > 0.0001:
			radius = minf(radius, ab * bc * ca / (4.0 * area))

	var pads := 0
	var last := -1000
	for i in n:
		if i < PAD_MIN_INDEX or i > n - 12:
			continue
		var t0 := tb.tangents[(i - PAD_STRAIGHT_LAG + n) % n]
		var t1 := tb.tangents[(i + PAD_STRAIGHT_LAG) % n]
		if t0.dot(t1) <= PAD_STRAIGHT_DOT:
			continue
		if i - last < PAD_START_GAP:
			continue
		pads += 1
		last = i

	tb.free()
	return {"length": length, "gap": gap, "radius": radius, "pads": pads}


func _passes(td: TrackDef, m: Dictionary) -> bool:
	return m.gap >= GAP_MIN and m.radius >= RADIUS_MIN \
			and m.length >= LAP_MIN and m.length <= LAP_MAX and m.pads >= PADS_REQUIRED


# ---------------------------------------------------------------------- sheet

func _sheet(args: Dictionary) -> void:
	var biome: String = args.get("biome", "coast")
	var count := int(args.get("count", "12"))
	var base_seed := int(args.get("seed", "1000"))
	var template := _load_template(biome, args.get("template", ""))

	var layouts: Array = []
	var lines: Array[String] = []
	for k in count:
		var seed := base_seed + k
		var layout := _make_layout(seed)
		var td := _def_from_layout(template, layout.points, "%s_cand" % biome, "", biome)
		var m := _metrics(td)
		var ok := _passes(td, m)
		layouts.append({"pts": layout.points, "metrics": m, "ok": ok, "seed": seed})
		lines.append("cell %d,%d  idx=%2d seed=%d  %s  len=%6.0f gap=%6.1f minR=%6.1f pads=%d pts=%d" % [
			k / COLS, k % COLS, k, seed, "PASS" if ok else "fail",
			m.length, m.gap, m.radius, m.pads, layout.points.size()])

	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var path := "%s/track_sheet_%s.png" % [OUT_DIR, biome]
	_render_sheet(layouts, path)
	var txt := "%s/track_sheet_%s.txt" % [OUT_DIR, biome]
	var f := FileAccess.open(txt, FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	print("sheet: %s" % path)
	print("metrics: %s" % txt)
	for l in lines:
		print("  " + l)


## Decor donor for a layout: explicit `template=<id>` beats the biome's own
## `_01` track; a brand-new biome with neither falls back to TrackDef defaults.
func _load_template(biome: String, override: String) -> TrackDef:
	if override != "":
		return load("%s/%s.tres" % [TRACK_DIR, override]) as TrackDef
	var path := "%s/%s_01.tres" % [TRACK_DIR, biome]
	if ResourceLoader.exists(path):
		return load(path) as TrackDef
	return TrackDef.new()


func _def_from_layout(template: TrackDef, pts: PackedVector3Array, id: String,
		display: String, biome: String) -> TrackDef:
	var td := TrackDef.new()
	td.id = id
	td.display_name = display
	td.biome = biome
	td.control_points = pts
	td.road_half_width = template.road_half_width
	td.wall_height = template.wall_height
	td.road_tile_length = template.road_tile_length
	td.terrain_tile_size = template.terrain_tile_size
	td.decor_seed = template.decor_seed
	td.prop_count = template.prop_count
	td.building_count = template.building_count
	td.prop_min_lateral = template.prop_min_lateral
	td.prop_max_lateral = template.prop_max_lateral
	td.building_min_lateral = template.building_min_lateral
	td.building_max_lateral = template.building_max_lateral
	td.building_min_gap = template.building_min_gap
	td.night_racing = template.night_racing
	td.wet_road = template.wet_road
	td.urban_canyon = template.urban_canyon
	td.streetlight_spacing = template.streetlight_spacing
	td.skyline_count = template.skyline_count
	return td


func _render_sheet(layouts: Array, path: String) -> void:
	var rows := int(ceil(float(layouts.size()) / float(COLS)))
	var img := Image.create(COLS * CELL, maxi(rows, 1) * CELL, false, Image.FORMAT_RGB8)
	img.fill(Color(0.05, 0.055, 0.07))
	for k in layouts.size():
		var origin := Vector2i((k % COLS) * CELL, (k / COLS) * CELL)
		var entry: Dictionary = layouts[k]
		var color := Color(0.25, 0.85, 0.4) if entry.ok else Color(0.72, 0.18, 0.20)
		_draw_loop(img, origin, entry.pts, color)
		_draw_marker(img, origin, entry.pts)
	img.save_png(path)


func _draw_marker(img: Image, origin: Vector2i, pts: PackedVector3Array) -> void:
	var p := _to_px(origin, pts, pts[0])
	img.fill_rect(Rect2i(p - Vector2i(8, 8), Vector2i(16, 16)), Color(1.0, 0.85, 0.2))


func _draw_loop(img: Image, origin: Vector2i, pts: PackedVector3Array, color: Color) -> void:
	if pts.is_empty():
		return
	var n := pts.size()
	for i in n:
		_draw_thick_segment(img, _to_px(origin, pts, pts[i]),
				_to_px(origin, pts, pts[(i + 1) % n]), color)


## Fits the loop's bounding box into the cell and maps a world point to pixels.
func _to_px(origin: Vector2i, pts: PackedVector3Array, p: Vector3) -> Vector2i:
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for q in pts:
		mn.x = minf(mn.x, q.x)
		mn.y = minf(mn.y, q.z)
		mx.x = maxf(mx.x, q.x)
		mx.y = maxf(mx.y, q.z)
	var extent := maxf(maxf(mx.x - mn.x, mx.y - mn.y), 1.0)
	var scale := (float(CELL) - 48.0) / extent
	var center := (mn + mx) * 0.5
	return Vector2i(
		origin.x + CELL / 2 + int((p.x - center.x) * scale),
		origin.y + CELL / 2 + int((p.z - center.y) * scale))


func _draw_thick_segment(img: Image, a: Vector2i, b: Vector2i, color: Color) -> void:
	var steps := maxi(absi(b.x - a.x), absi(b.y - a.y))
	if steps == 0:
		return
	for s in steps + 1:
		var t := float(s) / float(steps)
		var p := Vector2(a).lerp(Vector2(b), t)
		img.fill_rect(Rect2i(Vector2i(p) - Vector2i(2, 2), Vector2i(5, 5)), color)


# ----------------------------------------------------------------------- emit

func _emit(args: Dictionary) -> void:
	var biome: String = args.get("biome", "coast")
	var seed := int(args.get("seed", "1000"))
	var id: String = args.get("id", "%s_02" % biome)
	var display: String = args.get("display", "")
	var template := _load_template(biome, args.get("template", ""))
	var layout := _make_layout(seed)
	var td := _def_from_layout(template, layout.points, id, display, biome)
	var m := _metrics(td)
	print("emit %s seed=%d len=%.0f gap=%.1f minR=%.1f pads=%d pass=%s" % [
		id, seed, m.length, m.gap, m.radius, m.pads, str(_passes(td, m))])
	var path := "%s/%s.tres" % [TRACK_DIR, id]
	_write_tres(td, path)
	print("saved %s" % path)


## Writes a TrackDef in the same hand-maintained .tres style as the shipped
## tracks: load_steps, the shared script id and explicit biome, with only the
## non-default decor fields present.
func _write_tres(td: TrackDef, path: String) -> void:
	var d := TrackDef.new()
	var lines: Array[String] = [
		'[gd_resource type="Resource" script_class="TrackDef" load_steps=2 format=3]',
		"",
		'[ext_resource type="Script" path="res://scripts/track_def.gd" id="1_tdef"]',
		"",
		"[resource]",
		'script = ExtResource("1_tdef")',
		'id = "%s"' % td.id,
		'display_name = "%s"' % td.display_name,
		'biome = "%s"' % td.biome,
		"control_points = PackedVector3Array(%s)" % _pack_points(td.control_points),
	]
	_add_field(lines, "road_half_width", td.road_half_width, d.road_half_width)
	_add_field(lines, "wall_height", td.wall_height, d.wall_height)
	_add_field(lines, "road_tile_length", td.road_tile_length, d.road_tile_length)
	_add_field(lines, "terrain_tile_size", td.terrain_tile_size, d.terrain_tile_size)
	_add_field(lines, "decor_seed", td.decor_seed, d.decor_seed)
	_add_field(lines, "prop_count", td.prop_count, d.prop_count)
	_add_field(lines, "building_count", td.building_count, d.building_count)
	_add_field(lines, "prop_min_lateral", td.prop_min_lateral, d.prop_min_lateral)
	_add_field(lines, "prop_max_lateral", td.prop_max_lateral, d.prop_max_lateral)
	_add_field(lines, "building_min_lateral", td.building_min_lateral, d.building_min_lateral)
	_add_field(lines, "building_max_lateral", td.building_max_lateral, d.building_max_lateral)
	_add_field(lines, "building_min_gap", td.building_min_gap, d.building_min_gap)
	_add_field(lines, "night_racing", td.night_racing, d.night_racing)
	_add_field(lines, "wet_road", td.wet_road, d.wet_road)
	_add_field(lines, "urban_canyon", td.urban_canyon, d.urban_canyon)
	_add_field(lines, "streetlight_spacing", td.streetlight_spacing, d.streetlight_spacing)
	_add_field(lines, "skyline_count", td.skyline_count, d.skyline_count)
	lines.append("")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("\n".join(lines))
	f.close()


func _add_field(lines: Array[String], key: String, value, default) -> void:
	if value == default:
		return
	if value is bool:
		lines.append("%s = %s" % [key, "true" if value else "false"])
	elif value is int:
		lines.append("%s = %d" % [key, value])
	else:
		var s := String.num(value, 3)
		lines.append("%s = %s" % [key, s if s.contains(".") else s + ".0"])


func _pack_points(pts: PackedVector3Array) -> String:
	var parts: PackedStringArray = []
	for p in pts:
		parts.append("%s, %s, %s" % [_fmt(p.x), _fmt(p.y), _fmt(p.z)])
	return ", ".join(parts)


func _fmt(v: float) -> String:
	var r := roundf(v)
	if absf(v - r) < 0.001:
		return str(int(r))
	return String.num(v, 2)
