class_name Hud
extends CanvasLayer
## In-game UI: lap counter, timers, speed, countdown and finish screen.

var _lap_label: Label
var _pos_label: Label
var _police_label: Label
var _time_label: Label
var _best_label: Label
var _last_label: Label
var _speed_label: Label
var _nitro_gauge: NitroGauge
var _health_bar: ProgressBar
var _health_fill: StyleBoxFlat
var _center_big: Label
var _center_sub: Label
var _toast_label: Label
var _record_lap := -1.0
var _record_race := -1.0
var _toast_time := 0.0

static var _shared_font: Font = null
static var _font_lookup_done := false


## Racing font from assets/ui/fonts/ (ChakraPetch preferred); falls back to
## the engine default while the folder is empty.
static func _ui_font() -> Font:
	if _font_lookup_done:
		return _shared_font
	_font_lookup_done = true
	for font_name: String in ["ChakraPetch-Bold.ttf", "ChakraPetch-SemiBold.ttf", "ChakraPetch-Regular.ttf"]:
		var p := "res://assets/ui/fonts/" + font_name
		if ResourceLoader.exists(p):
			_shared_font = load(p) as Font
			return _shared_font
	var dir := DirAccess.open("res://assets/ui/fonts")
	if dir != null:
		for f in dir.get_files():
			if f.get_extension() in ["ttf", "otf"]:
				_shared_font = load("res://assets/ui/fonts/" + f) as Font
				break
	return _shared_font


func _ready() -> void:
	var stats := VBoxContainer.new()
	add_child(stats)
	stats.position = Vector2(18, 12)
	_lap_label = _make_label("LAP 1/3", 34)
	stats.add_child(_lap_label)
	_pos_label = _make_label("POS 1/4", 24)
	_pos_label.label_settings.font_color = Color(0.65, 0.9, 1.0)
	stats.add_child(_pos_label)
	_police_label = _make_label("POLICE!", 26)
	_police_label.label_settings.font_color = Color(1.0, 0.25, 0.2)
	_police_label.visible = false
	stats.add_child(_police_label)
	_time_label = _make_label("TIME 0:00.00", 22)
	stats.add_child(_time_label)
	_best_label = _make_label("BEST --:--.--", 22)
	_best_label.label_settings.font_color = Color(1.0, 0.85, 0.3)
	stats.add_child(_best_label)
	_last_label = _make_label("LAST --:--.--", 22)
	_last_label.label_settings.font_color = Color(0.8, 0.9, 1.0)
	stats.add_child(_last_label)

	var speed_box := VBoxContainer.new()
	add_child(speed_box)
	var health_caption := _make_label("HEALTH", 22)
	health_caption.label_settings.font_color = Color(1.0, 0.45, 0.42)
	speed_box.add_child(health_caption)
	_health_bar = ProgressBar.new()
	_health_bar.min_value = 0.0
	_health_bar.max_value = 1.0
	_health_bar.value = 1.0
	_health_bar.show_percentage = false
	_health_bar.custom_minimum_size = Vector2(320, 18)
	var hb_bg := StyleBoxFlat.new()
	hb_bg.bg_color = Color(1, 1, 1, 0.10)
	hb_bg.set_corner_radius_all(4)
	_health_bar.add_theme_stylebox_override("background", hb_bg)
	_health_fill = StyleBoxFlat.new()
	_health_fill.bg_color = Color(0.35, 0.82, 0.42)
	_health_fill.set_corner_radius_all(4)
	_health_bar.add_theme_stylebox_override("fill", _health_fill)
	speed_box.add_child(_health_bar)
	# Compact reward toast (near-miss) lives above the nitro gauge instead of
	# dead center, so a payout never blocks the view of the road.
	_toast_label = _make_label("", 30)
	_toast_label.label_settings.font_color = Color(1.0, 0.75, 0.25)
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.modulate.a = 0.0
	speed_box.add_child(_toast_label)
	var nitro_caption := _make_label("NITRO", 26)
	nitro_caption.label_settings.font_color = Color(1.0, 0.78, 0.28)
	speed_box.add_child(nitro_caption)
	_nitro_gauge = NitroGauge.new()
	_nitro_gauge.custom_minimum_size = Vector2(320, 28)
	speed_box.add_child(_nitro_gauge)
	_speed_label = _make_label("0 KM/H", 40)
	speed_box.add_child(_speed_label)
	# Pin the box to the bottom-left by its real (min) size once the children
	# exist, otherwise a bare anchor preset leaves it dangling off-screen.
	speed_box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT,
			Control.PRESET_MODE_MINSIZE, 16)

	var hint := _make_label("SHIFT — NITRO   Q/E — PUNCH   F — KICK   R — RESTART", 18)
	hint.label_settings.font_color = Color(1, 1, 1, 0.6)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(hint)
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT,
			Control.PRESET_MODE_MINSIZE, 14)

	var center := VBoxContainer.new()
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	_center_big = _make_label("", 84)
	_center_big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(_center_big)
	_center_sub = _make_label("", 32)
	_center_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(_center_sub)


func set_lap(current: int, total: int) -> void:
	_lap_label.text = "LAP %d/%d" % [current, total]


func set_position(pos: int, total: int) -> void:
	_pos_label.text = "POS %d/%d" % [pos, total]


func set_police(active: bool) -> void:
	if _police_label != null:
		_police_label.visible = active


func update_race_info(cur: float, best: float, last: float) -> void:
	# Before the first completed lap the BEST readout shows the stored track
	# record, so the player always races against a target.
	var shown_best := best if best >= 0.0 else _record_lap
	_time_label.text = "TIME %s" % fmt(cur)
	_best_label.text = "BEST %s" % fmt(shown_best)
	_last_label.text = "LAST %s" % fmt(last)


## Saved records for the current track/tier, shown while no local lap exists yet.
func set_record(record_lap: float, record_race: float) -> void:
	_record_lap = record_lap
	_record_race = record_race


## Short-lived reward toast (near-miss), shown above the nitro gauge so it
## never covers the center of the screen. Fades out at the end of its life.
func show_toast(text: String, color := Color.WHITE, sub := "", duration := 1.4) -> void:
	if _toast_label == null:
		return
	var full := text if sub.is_empty() else "%s  %s" % [text, sub]
	_toast_label.label_settings.font_color = color
	_toast_label.text = full
	_toast_label.modulate.a = 1.0
	_toast_time = duration


func _process(delta: float) -> void:
	if _toast_time > 0.0:
		_toast_time = maxf(_toast_time - delta, 0.0)
		if _toast_label != null:
			_toast_label.modulate.a = clampf(_toast_time / 0.4, 0.0, 1.0)
			if _toast_time <= 0.0:
				_toast_label.text = ""


func set_speed(kmh: float) -> void:
	_speed_label.text = "%d KM/H" % int(kmh)


func set_nitro(ratio: float, active: bool) -> void:
	_nitro_gauge.set_state(ratio, active)


func set_health(ratio: float) -> void:
	if _health_bar == null:
		return
	var r := clampf(ratio, 0.0, 1.0)
	_health_bar.value = r
	if _health_fill != null:
		if r > 0.5:
			_health_fill.bg_color = Color(0.35, 0.82, 0.42)
		elif r > 0.25:
			_health_fill.bg_color = Color(0.95, 0.78, 0.25)
		else:
			_health_fill.bg_color = Color(0.92, 0.25, 0.22)


## Big centered banner (wipeout / busted warnings).
func show_message(text: String, color := Color.WHITE, sub := "") -> void:
	_center_big.label_settings.font_color = color
	_center_big.text = text
	_center_sub.text = sub


func show_countdown(number: int) -> void:
	_center_big.label_settings.font_color = Color.WHITE
	_center_big.text = str(number)
	_center_sub.text = ""


func show_go() -> void:
	_center_big.label_settings.font_color = Color(0.4, 1.0, 0.45)
	_center_big.text = "GO!"
	_center_sub.text = ""


func clear_center() -> void:
	_center_big.text = ""
	_center_sub.text = ""


func show_finish(total: float, best: float, pos: int = 0, credits: int = 0, new_record: bool = false) -> void:
	_center_big.label_settings.font_color = Color(1.0, 0.85, 0.25)
	_center_big.text = "FINISH!"
	var sub := "RACE TIME %s    BEST LAP %s\nPress R to restart — returning to menu" % [fmt(total), fmt(best)]
	if pos > 0:
		sub = "POSITION %d/%d\n%s" % [pos, 4, sub]
	sub = "%s — %s\n%s" % [Game.track_name(), Game.tier_label(), sub]
	if new_record:
		sub = "NEW RECORD!\n%s" % sub
	if credits > 0:
		sub = "%s\n+%d CREDITS" % [sub, credits]
	_center_sub.text = sub


func reset_race() -> void:
	set_lap(1, 3)
	set_position(1, 4)
	update_race_info(0.0, -1.0, -1.0)
	set_speed(0.0)
	set_nitro(1.0, false)
	set_health(1.0)
	set_police(false)
	clear_center()
	_toast_time = 0.0
	if _toast_label != null:
		_toast_label.text = ""
		_toast_label.modulate.a = 0.0


static func fmt(t: float) -> String:
	if t < 0.0:
		return "--:--.--"
	var minutes := int(t) / 60
	var seconds := fmod(t, 60.0)
	return "%d:%05.2f" % [minutes, seconds]


func _make_label(text: String, font_size: int) -> Label:
	var l := Label.new()
	l.text = text
	var ls := LabelSettings.new()
	ls.font = _ui_font()
	ls.font_size = font_size
	ls.font_color = Color.WHITE
	ls.outline_size = int(font_size / 4.0)
	ls.outline_color = Color(0, 0, 0, 0.85)
	l.label_settings = ls
	return l
