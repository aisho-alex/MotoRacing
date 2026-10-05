extends Control
## Main menu: a colourful two-column screen. Left column holds the bike / track
## / level / quality pickers and the actions, right column previews the selected
## track (procedural mini-map) and bike (livery chips + stat bars). Keyboard
## (arrows, Enter, Q/E, G, Esc) and mouse both work.

const Ui := preload("res://scripts/ui_kit.gd")
const ACCENT := Ui.ACCENT
const CYAN := Ui.CYAN
const GREEN := Ui.GREEN
const ORANGE := Ui.ORANGE
const PURPLE := Ui.PURPLE
const RED := Ui.RED
const DIM := Color(1, 1, 1, 0.5)

## Biome -> preview tint (matches the world palettes).
const BIOME_COLORS := {
	"city": Color(0.45, 0.78, 1.0),
	"desert": Color(1.0, 0.72, 0.32),
	"alpine": Color(0.62, 0.90, 1.0),
	"coast": Color(0.35, 0.92, 0.86),
	"canyon": Color(1.0, 0.52, 0.30),
	"sakura": Color(1.0, 0.62, 0.82),
	"volcano": Color(1.0, 0.40, 0.26),
}

## Preview stat bars: base def field, tint and full-bar reference value.
const STAT_ROWS := [
	{"label": "SPEED", "prop": "max_speed", "color": Color(1.0, 0.60, 0.22), "ref": 46.0},
	{"label": "ACCEL", "prop": "accel", "color": Color(0.42, 0.90, 0.55), "ref": 32.0},
	{"label": "GRIP", "prop": "grip", "color": Color(0.35, 0.78, 1.0), "ref": 13.0},
	{"label": "NITRO", "prop": "nitro_max", "color": Color(0.74, 0.56, 1.0), "ref": 150.0},
]

var _bike_label: Label
var _track_label: Label
var _tier_label: Label
var _quality_label: Label
var _rec_label: Label
var _hint_label: Label
var _bank_label: Label
var _credits_panel: PanelContainer

var _preview_panel: PanelContainer
var _map: TrackMap
var _track_caption: Label
var _bike_caption: Label
var _chip_rects: Array = []
var _stat_bars: Array = []


const CREDITS_TEXT := """[b]MOTORCYCLES & RIDERS — Sketchfab, CC-BY 4.0[/b]
DIRT BIKE OFF ROAD BIKE LOW POLY — nabeelashrafphotography
Honda CB 750 F Super Sport 1970 — Alex.Ka.
Motorcycle Fallout — milinam2002
HCR2 Superbike — oakar258
Low Poly Motorcycle 001 — roh3d
Yz250 — EmanuelRestrepoV
night rod — EmanuelRestrepoV
Piggo Electric - Motorbike — Rayzngames
Yamaha 500 custom motorbike — Alexios_Apokauko
Rider: procedural low-poly (built in-engine)

[b]TRAFFIC CARS — Sketchfab, CC-BY 4.0[/b]
Shvan '92 · Illinois '90 Taxi · Fairheaven SW '84 — DanielZhabotinsk
BMW E46 1998 · BMW E30 1985 · De Tomaso P72 2020 — roh3d
Moped, motorcycle. — lexpartizan
City Bus (РоАЗ-5236) — grox777

[b]CITY BUILDINGS[/b]
NeonTown (bank, bar, pharmacy, restaurant, store) — bnishna · CC0 · OpenGameArt
Apartment Complex · Old Apartment · Large Building — jimbogies · CC-BY · Sketchfab
Brooklyn Street Row — B0rn2D13 · CC-BY · Sketchfab
Chicago Buildings — 99.Miles · CC-BY · Sketchfab
Game Ready City Buildings — mireubay1 · CC-BY · Sketchfab
Low Poly Building — roh3d · CC-BY · Sketchfab
Lowpoly Urban House — AspectStudio · CC-BY · Sketchfab

[b]CITY LOTS (mall · skatepark · fountain)[/b]
Low rise department store — aitortilla01 · CC-BY · Sketchfab
Skatepark Rails & Ramps — maxkeeley · CC-BY · Sketchfab
Fountain — local.yany · CC-BY · Sketchfab
Cel textures — generated (SwarmUI Z-Image Turbo)

[b]STREET TREES — Sketchfab, CC-BY 4.0[/b]
Linden — Asia Matusik
Oak · Beech · Birch — evolveduk

Full license texts: assets/*/*/*.license"""


func _ready() -> void:
	Audio.play_music("menu")
	_build_ui()


func _build_ui() -> void:
	add_child(Ui.backdrop())

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 44)
	margin.add_theme_constant_override("margin_right", 44)
	margin.add_theme_constant_override("margin_top", 30)
	margin.add_theme_constant_override("margin_bottom", 30)
	add_child(margin)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 30)
	margin.add_child(columns)
	columns.add_child(_left_column())
	columns.add_child(_right_column())

	_build_credits_panel()
	_refresh()


func _left_column() -> VBoxContainer:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_stretch_ratio = 1.05
	col.add_theme_constant_override("separation", 9)

	var title_row := HBoxContainer.new()
	title_row.alignment = BoxContainer.ALIGNMENT_CENTER
	title_row.add_theme_constant_override("separation", 16)
	title_row.add_child(_label("SIMPLE", 56, Color.WHITE))
	title_row.add_child(_label("RACING", 56, ACCENT))
	col.add_child(title_row)

	var line_row := HBoxContainer.new()
	line_row.alignment = BoxContainer.ALIGNMENT_CENTER
	var line := ColorRect.new()
	line.color = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.85)
	line.custom_minimum_size = Vector2(260, 5)
	line_row.add_child(line)
	col.add_child(line_row)

	col.add_child(_spacer(6))

	_bike_label = _label("", 28, Color.WHITE)
	_track_label = _label("", 28, Color.WHITE)
	_tier_label = _label("", 28, Color.WHITE)
	_quality_label = _label("", 28, Color.WHITE)
	col.add_child(_picker_card("BIKE", ORANGE, _bike_label, _on_bike_prev, _on_bike_next))
	col.add_child(_picker_card("TRACK", CYAN, _track_label, _on_track_prev, _on_track_next))
	col.add_child(_picker_card("LEVEL", GREEN, _tier_label, _on_tier_prev, _on_tier_next))
	col.add_child(_picker_card("QUALITY", PURPLE, _quality_label, _on_quality_prev, _on_quality_next))

	col.add_child(_spacer(4))

	_rec_label = _label("", 22, CYAN)
	col.add_child(_rec_label)
	_hint_label = _label("", 20, DIM)
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_hint_label)

	var grow := Control.new()
	grow.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(grow)

	var start := Ui.filled_button("START RACE", 38, ACCENT)
	start.custom_minimum_size = Vector2(0, 62)
	start.pressed.connect(_start_race)
	col.add_child(start)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	var garage := Ui.filled_button("GARAGE", 24, CYAN)
	garage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	garage.pressed.connect(_open_garage)
	actions.add_child(garage)
	var quit := Ui.outline_button("QUIT", 24, RED)
	quit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quit.pressed.connect(_on_quit)
	actions.add_child(quit)
	var credits := Ui.outline_button("CREDITS", 24, Color(0.85, 0.88, 0.95))
	credits.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	credits.pressed.connect(_toggle_credits)
	actions.add_child(credits)
	col.add_child(actions)

	var controls := _label("← → bike   ↑ ↓ track   Q/E level   G garage   Enter start   Esc quit",
			15, Color(1, 1, 1, 0.38))
	controls.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(controls)
	return col


func _right_column() -> PanelContainer:
	_preview_panel = PanelContainer.new()
	_preview_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview_panel.size_flags_stretch_ratio = 0.95
	_preview_panel.add_theme_stylebox_override("panel", Ui.panel_style(
			Color(0.06, 0.07, 0.12, 0.82), Color(1, 1, 1, 0.12), 16, 2, 16))

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)

	var track_header := HBoxContainer.new()
	track_header.add_child(_label("TRACK PREVIEW", 18, DIM))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	track_header.add_child(spacer)
	_track_caption = _label("", 22, CYAN)
	track_header.add_child(_track_caption)
	v.add_child(track_header)

	_map = TrackMap.new()
	_map.custom_minimum_size = Vector2(0, 230)
	_map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_map)

	v.add_child(_divider())
	v.add_child(_label("YOUR BIKE", 18, DIM))
	_bike_caption = _label("", 26, Color.WHITE)
	v.add_child(_bike_caption)

	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 22)
	chips.add_child(_chip("BODY"))
	chips.add_child(_chip("TRIM"))
	chips.add_child(_chip("HELMET"))
	v.add_child(chips)

	for row in STAT_ROWS:
		v.add_child(_stat_row(row))

	var grow := Control.new()
	grow.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(grow)

	_bank_label = _label("", 26, ACCENT)
	_bank_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.add_child(_bank_label)

	_preview_panel.add_child(v)
	return _preview_panel


func _picker_card(caption: String, tint: Color, value_label: Label,
		on_prev: Callable, on_next: Callable) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Ui.panel_style(
			Color(1, 1, 1, 0.05), Color(tint.r, tint.g, tint.b, 0.45), 12, 1, 8))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)

	var cap := _label(caption, 24, tint)
	cap.custom_minimum_size = Vector2(130, 0)
	cap.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(cap)

	var prev := Ui.filled_button("<", 24, tint)
	prev.custom_minimum_size = Vector2(56, 0)
	prev.pressed.connect(on_prev)
	row.add_child(prev)

	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(value_label)

	var next := Ui.filled_button(">", 24, tint)
	next.custom_minimum_size = Vector2(56, 0)
	next.pressed.connect(on_next)
	row.add_child(next)

	panel.add_child(row)
	return panel


func _chip(caption: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	var rect := ColorRect.new()
	rect.custom_minimum_size = Vector2(60, 22)
	h.add_child(rect)
	h.add_child(_label(caption, 15, DIM))
	_chip_rects.append(rect)
	return h


func _stat_row(row: Dictionary) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	var name := _label(row["label"], 17, Color.WHITE)
	name.custom_minimum_size = Vector2(84, 0)
	h.add_child(name)
	var bar := _bar(row["color"])
	bar.custom_minimum_size = Vector2(0, 12)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(bar)
	var value := _label("", 17, DIM)
	value.custom_minimum_size = Vector2(56, 0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(value)
	_stat_bars.append({"bar": bar, "value": value})
	return h


func _bar(fill: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.show_percentage = false
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(1, 1, 1, 0.12)
	bg.set_corner_radius_all(5)
	bar.add_theme_stylebox_override("background", bg)
	var f := StyleBoxFlat.new()
	f.bg_color = fill
	f.set_corner_radius_all(5)
	bar.add_theme_stylebox_override("fill", f)
	return bar


func _divider() -> ColorRect:
	var line := ColorRect.new()
	line.color = Color(1, 1, 1, 0.12)
	line.custom_minimum_size = Vector2(0, 1)
	return line


func _on_bike_prev() -> void:
	Game.cycle_bike(-1)
	_refresh()


func _on_bike_next() -> void:
	Game.cycle_bike(1)
	_refresh()


func _on_track_prev() -> void:
	Game.cycle_track(-1)
	_refresh()


func _on_track_next() -> void:
	Game.cycle_track(1)
	_refresh()


func _on_tier_prev() -> void:
	Game.cycle_tier(-1)
	_refresh()


func _on_tier_next() -> void:
	Game.cycle_tier(1)
	_refresh()


func _on_quality_prev() -> void:
	Game.cycle_quality(-1)
	_refresh()


func _on_quality_next() -> void:
	Game.cycle_quality(1)
	_refresh()


func _on_quit() -> void:
	get_tree().quit()


func _build_credits_panel() -> void:
	_credits_panel = PanelContainer.new()
	_credits_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_credits_panel.visible = false
	var style := Ui.panel_style(Color(0.04, 0.05, 0.09, 0.97), Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.6),
			14, 2, 28)
	_credits_panel.add_theme_stylebox_override("panel", style)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_credits_panel.add_child(scroll)
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.fit_content = true
	text.text = CREDITS_TEXT
	text.add_theme_font_override("normal_font", Hud._ui_font())
	text.add_theme_font_override("bold_font", Hud._ui_font())
	text.add_theme_font_size_override("normal_font_size", 22)
	text.add_theme_font_size_override("bold_font_size", 26)
	text.add_theme_color_override("default_color", Color(0.92, 0.93, 0.96))
	scroll.add_child(text)
	var close := Ui.outline_button("BACK", 26, ACCENT)
	close.pressed.connect(_toggle_credits)
	close.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	close.offset_left = -180
	close.offset_top = -84
	close.offset_right = -28
	close.offset_bottom = -28
	_credits_panel.add_child(close)
	add_child(_credits_panel)


func _toggle_credits() -> void:
	Audio.play_ui("click")
	_credits_panel.visible = not _credits_panel.visible


func _refresh() -> void:
	_bike_label.text = Game.bike_name()
	_track_label.text = Game.track_name()
	_tier_label.text = Game.tier_label()
	_quality_label.text = Game.quality_label()
	_rec_label.text = Game.record_hint(Game.track_index, Game.track_tier)
	_hint_label.text = _first_lock_hint()
	_bank_label.text = "%d CREDITS" % Game.credits
	_refresh_preview()


func _refresh_preview() -> void:
	var tdef := Game.track_def()
	var tint: Color = BIOME_COLORS.get(tdef.biome, CYAN)
	_map.set_control_points(tdef.control_points, tint)
	_preview_panel.add_theme_stylebox_override("panel", Ui.panel_style(
			Color(0.06, 0.07, 0.12, 0.82), Color(tint.r, tint.g, tint.b, 0.5), 16, 2, 16))
	_track_caption.text = Game.track_name()
	_track_caption.label_settings.font_color = tint

	var base := Game.bike_def()
	_bike_caption.text = base.display_name
	_chip_rects[0].color = base.body_color
	_chip_rects[1].color = base.accent_color
	_chip_rects[2].color = base.helmet_color

	var tuned := Game.tuned_def_for(Game.current_bike_id())
	for i in STAT_ROWS.size():
		var row: Dictionary = STAT_ROWS[i]
		var widgets: Dictionary = _stat_bars[i]
		var value := float(tuned.get(row["prop"]))
		widgets["bar"].value = clampf(value / float(row["ref"]), 0.0, 1.0)
		widgets["value"].text = "%.0f" % value


func _first_lock_hint() -> String:
	if Game.unlocked_tracks < Game.TRACK_IDS.size():
		return Game.track_lock_hint(Game.unlocked_tracks)
	for id in Game.BIKE_IDS:
		if not Game.is_bike_unlocked(id):
			return Game.lock_hint(id)
	return ""


func _start_race() -> void:
	Audio.play_ui("click")
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _open_garage() -> void:
	Audio.play_ui("click")
	get_tree().change_scene_to_file("res://scenes/garage.tscn")


func _unhandled_input(event: InputEvent) -> void:
	if _credits_panel.visible:
		if event.is_action_pressed("ui_cancel") or event.is_action_pressed("ui_accept"):
			_toggle_credits()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_G:
		_open_garage()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_Q:
		Game.cycle_tier(-1)
		_refresh()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_E:
		Game.cycle_tier(1)
		_refresh()
	elif event.is_action_pressed("ui_accept"):
		_start_race()
	elif event.is_action_pressed("ui_cancel"):
		get_tree().quit()
	elif event.is_action_pressed("ui_left"):
		Game.cycle_bike(-1)
		_refresh()
	elif event.is_action_pressed("ui_right"):
		Game.cycle_bike(1)
		_refresh()
	elif event.is_action_pressed("ui_up"):
		Game.cycle_track(-1)
		_refresh()
	elif event.is_action_pressed("ui_down"):
		Game.cycle_track(1)
		_refresh()


func _label(text: String, size: int, color: Color) -> Label:
	return Ui.label(text, size, color)


func _spacer(px: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, px)
	return c


## Procedural top-down track outline drawn from the track's control points.
class TrackMap extends Control:
	var pts := PackedVector2Array()
	var line_color := Color(0.35, 0.78, 1.0)
	var bg_color := Color(0.02, 0.03, 0.06, 0.55)

	func _ready() -> void:
		clip_contents = true
		resized.connect(queue_redraw)

	func set_control_points(cp: PackedVector3Array, tint: Color) -> void:
		line_color = tint
		pts = sample(cp)
		queue_redraw()

	func _draw() -> void:
		var r := get_rect()
		draw_rect(Rect2(Vector2.ZERO, r.size), bg_color)
		if pts.size() < 3:
			return
		var mn := pts[0]
		var mx := pts[0]
		for p in pts:
			mn = mn.min(p)
			mx = mx.max(p)
		var span := mx - mn
		var pad := 18.0
		var avail := Vector2(maxf(r.size.x - pad * 2.0, 1.0), maxf(r.size.y - pad * 2.0, 1.0))
		var scale := minf(avail.x / maxf(span.x, 1.0), avail.y / maxf(span.y, 1.0))
		var off := (r.size - span * scale) * 0.5 - mn * scale
		var fitted := PackedVector2Array()
		for p in pts:
			fitted.append(p * scale + off)
		draw_polyline(fitted, Color(line_color.r, line_color.g, line_color.b, 0.16), 16.0, true)
		draw_polyline(fitted, line_color.darkened(0.5), 9.0, true)
		draw_polyline(fitted, line_color, 4.5, true)
		draw_polyline(fitted, line_color.lightened(0.55), 1.6, true)
		draw_circle(fitted[0], 7.0, Color.WHITE)
		draw_circle(fitted[0], 3.5, line_color)

	static func sample(cp: PackedVector3Array) -> PackedVector2Array:
		var out := PackedVector2Array()
		var k := cp.size()
		if k < 2:
			return out
		const SUB := 12
		for i in k:
			var p0 := cp[(i - 1 + k) % k]
			var p1 := cp[i]
			var p2 := cp[(i + 1) % k]
			var p3 := cp[(i + 2) % k]
			for j in SUB:
				out.append(_catmull(p0, p1, p2, p3, float(j) / float(SUB)))
		out.append(out[0])
		return out

	static func _catmull(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector2:
		var t2 := t * t
		var t3 := t2 * t
		var v := 0.5 * (
			(2.0 * p1)
			+ (-p0 + p2) * t
			+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
			+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)
		return Vector2(v.x, v.z)
