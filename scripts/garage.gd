extends Control
## Garage: spend credits on per-bike upgrades (engine / tires / nitro). Keyboard
## (arrows, Enter, Esc) and mouse both work. Locked bikes can be browsed but not
## upgraded. Up to three levels per part; stat bars preview the next level.

const Ui := preload("res://scripts/ui_kit.gd")
const ACCENT := Ui.ACCENT
const DIM := Color(1, 1, 1, 0.45)
const STAT_ROWS := [
	{"part": "engine", "label": "SPEED", "prop": "max_speed"},
	{"part": "engine", "label": "ACCEL", "prop": "accel"},
	{"part": "tires", "label": "GRIP", "prop": "grip"},
	{"part": "tires", "label": "STEERING", "prop": "steer_rate"},
	{"part": "nitro", "label": "NITRO", "prop": "nitro_max"},
]
const BAR_REF := 1.65  # full bar = base stat * BAR_REF (~maxed range plus margin)

const SECTION_PARTS := 0
const SECTION_SKIN := 1

var bike_pos := 0
var part_pos := 0
var skin_pos := 0
var section := SECTION_PARTS  # which panel the arrows/Enter drive (Tab toggles)

var _bike_label: Label
var _credits_label: Label
var _hint_label: Label
var _stat_rows: Array = []   # {bar: ProgressBar, value: Label}
var _part_rows: Array = []   # {level: Label, pips: ProgressBar, cost: Label, buy: Button, label: Label}
var _skin_label: Label
var _skin_cost: Label
var _skin_buy: Button
var _skin_hint: Label
var _skin_swatches: Array = []  # ColorRect chips: suit, accent, helmet


func _ready() -> void:
	bike_pos = Game.bike_index
	skin_pos = maxi(Game.SKIN_IDS.find(Game.current_skin_id()), 0)
	_build_ui()
	_refresh()


func _bike_id() -> String:
	return Game.BIKE_IDS[bike_pos]


func _part() -> String:
	return BikeTuning.PARTS[part_pos]


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.07, 0.11)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 6)
	box.offset_left = 220
	box.offset_right = -220
	box.offset_top = 8
	box.offset_bottom = -8
	add_child(box)

	var header := HBoxContainer.new()
	header.add_child(_label("GARAGE", 40, ACCENT))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	_credits_label = _label("", 30, Color.WHITE)
	header.add_child(_credits_label)
	box.add_child(header)

	box.add_child(_bike_row())

	var stats_panel := PanelContainer.new()
	stats_panel.add_theme_stylebox_override("panel", _panel_style())
	var stats := VBoxContainer.new()
	stats.add_theme_constant_override("separation", 2)
	stats.add_child(_label("PERFORMANCE", 18, DIM))
	for row in STAT_ROWS:
		stats.add_child(_stat_row(row))
	stats_panel.add_child(stats)
	box.add_child(stats_panel)

	var parts_panel := PanelContainer.new()
	parts_panel.add_theme_stylebox_override("panel", _panel_style())
	var parts := VBoxContainer.new()
	parts.add_theme_constant_override("separation", 4)
	parts.add_child(_label("UPGRADES", 18, DIM))
	for i in BikeTuning.PARTS.size():
		parts.add_child(_part_row(i))
	parts_panel.add_child(parts)
	box.add_child(parts_panel)

	box.add_child(_skin_panel())

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 16)
	_hint_label = _label("", 16, DIM)
	_hint_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	footer.add_child(_hint_label)
	var back := _button("BACK", 22)
	back.pressed.connect(_go_back)
	back.size_flags_horizontal = Control.SIZE_SHRINK_END
	footer.add_child(back)
	box.add_child(footer)


func _bike_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 24)
	row.add_child(_label("BIKE", 32, DIM))
	var prev := _button("<", 32)
	prev.pressed.connect(_cycle_bike.bind(-1))
	row.add_child(prev)
	_bike_label = _label("", 30, Color.WHITE)
	_bike_label.custom_minimum_size = Vector2(320, 0)
	_bike_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(_bike_label)
	var next := _button(">", 32)
	next.pressed.connect(_cycle_bike.bind(1))
	row.add_child(next)
	return row


func _stat_row(row: Dictionary) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 18)
	var name := _label(row["label"], 20, Color.WHITE)
	name.custom_minimum_size = Vector2(180, 0)
	h.add_child(name)
	var bar := _bar(0.0, Color(0.35, 0.75, 1.0))
	bar.custom_minimum_size = Vector2(420, 14)
	h.add_child(bar)
	var value := _label("", 20, DIM)
	value.custom_minimum_size = Vector2(220, 0)
	h.add_child(value)
	_stat_rows.append({"bar": bar, "value": value})
	return h


func _part_row(index: int) -> HBoxContainer:
	var part: String = BikeTuning.PARTS[index]
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 18)
	var name := _label(BikeTuning.PART_LABELS[part], 22, Color.WHITE)
	name.custom_minimum_size = Vector2(180, 0)
	h.add_child(name)
	var level := _label("", 20, Color.WHITE)
	level.custom_minimum_size = Vector2(90, 0)
	h.add_child(level)
	var pips := _bar(0.0, ACCENT)
	pips.max_value = BikeTuning.MAX_LEVEL
	pips.custom_minimum_size = Vector2(150, 14)
	h.add_child(pips)
	var cost := _label("", 20, DIM)
	cost.custom_minimum_size = Vector2(150, 0)
	cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(cost)
	var buy := _button("BUY", 22)
	buy.custom_minimum_size = Vector2(130, 0)
	buy.pressed.connect(_buy_selected.bind(index))
	h.add_child(buy)
	_part_rows.append({"name": name, "level": level, "pips": pips, "cost": cost, "buy": buy})
	return h


func _skin_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style())
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.add_child(_label("RIDER SKIN", 18, DIM))

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 24)
	var prev := _button("<", 28)
	prev.pressed.connect(_cycle_skin.bind(-1))
	row.add_child(prev)
	_skin_label = _label("", 26, Color.WHITE)
	_skin_label.custom_minimum_size = Vector2(360, 0)
	_skin_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(_skin_label)
	var next := _button(">", 28)
	next.pressed.connect(_cycle_skin.bind(1))
	row.add_child(next)
	v.add_child(row)

	var srow := HBoxContainer.new()
	srow.alignment = BoxContainer.ALIGNMENT_CENTER
	srow.add_theme_constant_override("separation", 14)
	for chip_name: String in ["SUIT", "ACCENT", "HELMET"]:
		var chip := ColorRect.new()
		chip.custom_minimum_size = Vector2(110, 26)
		srow.add_child(chip)
		srow.add_child(_label(chip_name, 18, DIM))
		_skin_swatches.append(chip)
	v.add_child(srow)

	var brow := HBoxContainer.new()
	brow.alignment = BoxContainer.ALIGNMENT_CENTER
	brow.add_theme_constant_override("separation", 18)
	_skin_cost = _label("", 20, DIM)
	brow.add_child(_skin_cost)
	_skin_buy = _button("EQUIP", 22)
	_skin_buy.custom_minimum_size = Vector2(150, 0)
	_skin_buy.pressed.connect(_buy_or_equip_skin)
	brow.add_child(_skin_buy)
	v.add_child(brow)

	_skin_hint = _label("", 15, DIM)
	_skin_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_skin_hint)
	panel.add_child(v)
	return panel


func _refresh() -> void:
	var id := _bike_id()
	var unlocked := Game.is_bike_unlocked(id)
	var for_sale := Game.is_shop_bike(id) and not unlocked
	_credits_label.text = "%d CR" % Game.credits

	var def_name := Game.bike_def_by_id(id).display_name
	if for_sale:
		_bike_label.text = "%s   [%d CR]" % [def_name, Game.bike_price(id)]
	else:
		_bike_label.text = "%s%s" % [def_name, "" if unlocked else "  [LOCKED]"]

	var base := Game.bike_def_by_id(id)
	var tuned := Game.tuned_def_for(id)
	for i in STAT_ROWS.size():
		var row: Dictionary = STAT_ROWS[i]
		var widgets: Dictionary = _stat_rows[i]
		var current := float(tuned.get(row["prop"]))
		var base_val := float(base.get(row["prop"]))
		widgets["bar"].value = clampf(current / (base_val * BAR_REF), 0.0, 1.0)
		var text := "%.1f" % current
		var part := String(row["part"])
		if unlocked and part == _part() and Game.upgrade_level(id, part) < BikeTuning.MAX_LEVEL:
			var next := _preview_def(base, id, part)
			text += "  ->  %.1f" % float(next.get(row["prop"]))
		widgets["value"].text = text

	for i in BikeTuning.PARTS.size():
		if for_sale:
			_refresh_shop_row(i, id)
		else:
			_refresh_part_row(i, id, unlocked)

	_refresh_skin()
	_hint_label.text = _hint_text(unlocked, for_sale)


## Rider skin panel: browse the catalog, live-equip owned skins and buy the
## shop ones. Locked progression skins show their unlock hint.
func _refresh_skin() -> void:
	var id: String = Game.SKIN_IDS[skin_pos]
	var def := Game.skin_def_by_id(id)
	var unlocked := Game.is_skin_unlocked(id)
	var for_sale := Game.skin_price(id) >= 0 and not unlocked
	var bike := Game.bike_def_by_id(_bike_id())

	var title := def.display_name
	if for_sale:
		title += "   [%d CR]" % Game.skin_price(id)
	elif not unlocked:
		title += "   [LOCKED]"
	_skin_label.text = title
	_skin_label.label_settings.font_color = ACCENT if section == SECTION_SKIN else Color.WHITE

	var suit := def.suit_color if def.overrides(def.suit_color) else bike.rider_color
	var accent := def.accent_color if def.overrides(def.accent_color) else bike.rider_accent_color
	var helmet := def.helmet_color if def.overrides(def.helmet_color) else bike.helmet_color
	_skin_swatches[0].color = suit
	_skin_swatches[1].color = accent
	_skin_swatches[2].color = helmet

	if for_sale:
		_skin_cost.text = "%d CR" % Game.skin_price(id)
		_skin_cost.label_settings.font_color = ACCENT if Game.credits >= Game.skin_price(id) else DIM
		_skin_buy.text = "BUY"
		_skin_buy.disabled = not Game.can_afford_skin(id)
		_skin_hint.text = "Enter: buy for %d CR" % Game.skin_price(id)
	elif not unlocked:
		_skin_cost.text = "LOCKED"
		_skin_cost.label_settings.font_color = DIM
		_skin_buy.text = "--"
		_skin_buy.disabled = true
		_skin_hint.text = Game.skin_lock_hint(id)
	else:
		var equipped := Game.current_skin_id() == id
		_skin_cost.text = "SELECTED" if equipped else "OWNED"
		_skin_cost.label_settings.font_color = ACCENT if equipped else DIM
		_skin_buy.text = "EQUIPPED" if equipped else "EQUIP"
		_skin_buy.disabled = equipped
		_skin_hint.text = def.display_name + ("  ·  DECAL" if def.has_decals() else "")


## Shop bike rows double as the "buy the bike" button: they show the price
## instead of upgrade levels until the machine is owned.
func _refresh_shop_row(index: int, id: String) -> void:
	var widgets: Dictionary = _part_rows[index]
	var price := Game.bike_price(id)
	widgets["name"].label_settings.font_color = ACCENT if index == part_pos else Color.WHITE
	widgets["level"].text = "--"
	widgets["pips"].value = 0
	widgets["cost"].text = "%d CR" % price
	widgets["cost"].label_settings.font_color = ACCENT if Game.credits >= price else DIM
	widgets["buy"].text = "BUY BIKE"
	widgets["buy"].disabled = Game.credits < price


func _refresh_part_row(index: int, id: String, unlocked: bool) -> void:
	var part: String = BikeTuning.PARTS[index]
	var widgets: Dictionary = _part_rows[index]
	var level := Game.upgrade_level(id, part)
	var selected := index == part_pos
	widgets["name"].label_settings.font_color = ACCENT if selected else Color.WHITE
	widgets["level"].text = "LV %d/%d" % [level, BikeTuning.MAX_LEVEL]
	widgets["pips"].value = level
	var maxed := level >= BikeTuning.MAX_LEVEL
	if not unlocked:
		widgets["cost"].text = "LOCKED"
		widgets["buy"].text = "--"
		widgets["buy"].disabled = true
		return
	if maxed:
		widgets["cost"].text = "MAXED"
		widgets["buy"].text = "MAX"
		widgets["buy"].disabled = true
		return
	var price := Game.upgrade_cost(id, part)
	widgets["cost"].text = "%d CR" % price
	widgets["cost"].label_settings.font_color = ACCENT if Game.credits >= price else DIM
	widgets["buy"].text = "BUY"
	widgets["buy"].disabled = Game.credits < price


func _preview_def(base: BikeDef, id: String, part: String) -> BikeDef:
	var levels := Game.upgrade_levels(id)
	levels[part] = int(levels[part]) + 1
	return BikeTuning.apply(base, levels)


func _hint_text(unlocked: bool, for_sale: bool = false) -> String:
	if for_sale:
		var price := Game.bike_price(_bike_id())
		if Game.credits >= price:
			return "Enter: buy this bike for %d CR" % price
		return "Need %d CR to buy this bike" % price
	if not unlocked:
		return Game.lock_hint(_bike_id())
	return "Arrows: bike / upgrade / skin    Tab: panel    Enter: buy    Esc: menu"


func _cycle_bike(dir: int) -> void:
	bike_pos = wrapi(bike_pos + dir, 0, Game.BIKE_IDS.size())
	part_pos = 0
	Audio.play_ui("click")
	_refresh()


func _cycle_part(dir: int) -> void:
	part_pos = wrapi(part_pos + dir, 0, BikeTuning.PARTS.size())
	Audio.play_ui("click")
	_refresh()


func _cycle_skin(dir: int) -> void:
	section = SECTION_SKIN
	skin_pos = wrapi(skin_pos + dir, 0, Game.SKIN_IDS.size())
	var id: String = Game.SKIN_IDS[skin_pos]
	if Game.is_skin_unlocked(id):
		Game.select_skin(id)
	Audio.play_ui("click")
	_refresh()


func _buy_or_equip_skin() -> void:
	section = SECTION_SKIN
	var id: String = Game.SKIN_IDS[skin_pos]
	if Game.is_skin_unlocked(id):
		Audio.play_ui("unlock" if Game.select_skin(id) else "click")
	elif Game.buy_skin(id):
		Audio.play_ui("unlock")
	else:
		Audio.play_ui("click")
	_refresh()


func _buy_selected(index: int = -1) -> void:
	if index >= 0:
		part_pos = index
	var id := _bike_id()
	if Game.is_shop_bike(id) and not Game.is_bike_unlocked(id):
		if Game.buy_bike(id):
			Audio.play_ui("unlock")
		else:
			Audio.play_ui("click")
		_refresh()
		return
	if not Game.is_bike_unlocked(id):
		Audio.play_ui("click")
		return
	if Game.buy_upgrade(id, _part()):
		Audio.play_ui("unlock")
	else:
		Audio.play_ui("click")
	_refresh()


func _go_back() -> void:
	Audio.play_ui("click")
	get_tree().change_scene_to_file("res://scenes/menu.tscn")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_go_back()
	elif event.is_action_pressed("ui_focus_next"):
		section = SECTION_SKIN if section == SECTION_PARTS else SECTION_PARTS
		Audio.play_ui("click")
		_refresh()
	elif event.is_action_pressed("ui_left"):
		if section == SECTION_SKIN:
			_cycle_skin(-1)
		else:
			_cycle_bike(-1)
	elif event.is_action_pressed("ui_right"):
		if section == SECTION_SKIN:
			_cycle_skin(1)
		else:
			_cycle_bike(1)
	elif event.is_action_pressed("ui_up"):
		if section == SECTION_SKIN:
			_cycle_skin(-1)
		else:
			_cycle_part(-1)
	elif event.is_action_pressed("ui_down"):
		if section == SECTION_SKIN:
			_cycle_skin(1)
		else:
			_cycle_part(1)
	elif event.is_action_pressed("ui_accept"):
		if section == SECTION_SKIN:
			_buy_or_equip_skin()
		else:
			_buy_selected()


func _bar(value: float, fill: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.value = value
	bar.show_percentage = false
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(1, 1, 1, 0.10)
	bg_style.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("background", bg_style)
	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = fill
	fill_style.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("fill", fill_style)
	return bar


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.11, 0.16, 0.9)
	style.border_color = Color(1, 1, 1, 0.08)
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(6)
	return style


func _label(text: String, size: int, color: Color) -> Label:
	return Ui.label(text, size, color)


func _button(text: String, size: int) -> Button:
	return Ui.button(text, size)
