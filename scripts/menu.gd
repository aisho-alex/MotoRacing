extends Control
## Main menu: bike and track pickers plus start/quit. Keyboard (arrows, Enter,
## Esc) and mouse both work.

const Ui := preload("res://scripts/ui_kit.gd")

var _bike_label: Label
var _track_label: Label
var _tier_label: Label
var _rec_label: Label
var _hint_label: Label
var _bank_label: Label
var _credits_panel: PanelContainer


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

Full license texts: assets/*/*/*.license"""


func _ready() -> void:
	Audio.play_music("menu")
	_build_ui()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.07, 0.11)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 18)
	box.offset_left = 240
	box.offset_right = -240
	add_child(box)

	var title := _label("SIMPLE RACING", 72, Color(1.0, 0.85, 0.25))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	box.add_child(_spacer(10))

	_bike_label = _label("", 36, Color.WHITE)
	_track_label = _label("", 36, Color.WHITE)
	_tier_label = _label("", 36, Color.WHITE)
	box.add_child(_picker_row("BIKE", _bike_label, _on_bike_prev, _on_bike_next))
	box.add_child(_picker_row("TRACK", _track_label, _on_track_prev, _on_track_next))
	box.add_child(_picker_row("LEVEL", _tier_label, _on_tier_prev, _on_tier_next))
	_rec_label = _label("", 22, Color(0.55, 0.85, 1.0, 0.9))
	box.add_child(_rec_label)
	_hint_label = _label("", 22, Color(1, 1, 1, 0.45))
	box.add_child(_hint_label)
	_bank_label = _label("", 24, Color(1.0, 0.85, 0.25, 0.9))
	box.add_child(_bank_label)

	box.add_child(_spacer(24))

	var start := _button("START RACE", 44)
	start.pressed.connect(_start_race)
	box.add_child(start)

	var garage := _button("GARAGE", 28)
	garage.pressed.connect(_open_garage)
	box.add_child(garage)

	var quit := _button("QUIT", 26)
	quit.pressed.connect(_on_quit)
	box.add_child(quit)

	var credits := _button("CREDITS", 22)
	credits.pressed.connect(_toggle_credits)
	box.add_child(credits)

	_build_credits_panel()
	_refresh()


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


func _on_quit() -> void:
	get_tree().quit()


func _build_credits_panel() -> void:
	_credits_panel = PanelContainer.new()
	_credits_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_credits_panel.visible = false
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.05, 0.09, 0.96)
	style.border_color = Color(1.0, 0.85, 0.25, 0.6)
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.set_content_margin_all(28)
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
	var close := _button("BACK", 26)
	close.pressed.connect(_toggle_credits)
	close.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	close.offset_left = -160
	close.offset_top = -80
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
	_rec_label.text = Game.record_hint(Game.track_index, Game.track_tier)
	_hint_label.text = _first_lock_hint()
	_bank_label.text = "%d CREDITS  —  G garage · Q/E level" % Game.credits


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


func _picker_row(caption: String, value_label: Label, on_prev: Callable, on_next: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 24)
	row.add_child(_label(caption, 32, Color(1, 1, 1, 0.55)))
	var prev := _button("<", 32)
	prev.pressed.connect(on_prev)
	row.add_child(prev)
	value_label.custom_minimum_size = Vector2(320, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(value_label)
	var next := _button(">", 32)
	next.pressed.connect(on_next)
	row.add_child(next)
	return row


func _label(text: String, size: int, color: Color) -> Label:
	return Ui.label(text, size, color)


func _button(text: String, size: int) -> Button:
	return Ui.button(text, size)


func _spacer(px: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, px)
	return c
