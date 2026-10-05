class_name TouchControls
extends CanvasLayer
## Virtual gamepad for mobile: an analog steering zone (left thumb), pedals on
## the right (throttle + brake), combat buttons in a row just above the zone and
## nitro stacked above the throttle pedal (right thumb reaches it without leaving
## the gas). Buttons drive the same Input actions as the keyboard with a
## multi-touch press map; steering injects an analog strength so Input.get_axis
## stays smooth. Hidden on desktop, shown for mobile exports (or FORCE_TOUCH=1);
## F4 toggles it on desktop for testing.

const ICON_DIR := "res://assets/ui/touch/"

# Right hand: pedals + nitro. Left hand: combat, laid out left-to-right.
const BUTTON_DEFS := [
	{"action": "accelerate", "icon": "pedal_gas", "right": true,
		"tint": Color(0.55, 1.0, 0.62)},
	{"action": "brake", "icon": "pedal_brake", "right": true,
		"tint": Color(1.0, 0.48, 0.42)},
	{"action": "nitro", "icon": "nitro", "right": true,
		"tint": Color(1.0, 0.66, 0.22)},
	{"action": "attack_left", "icon": "fist", "right": false,
		"tint": Color(0.85, 0.90, 1.0)},
	{"action": "attack_right", "icon": "fist", "right": false,
		"tint": Color(0.85, 0.90, 1.0), "flip": true},
	{"action": "kick", "icon": "boot", "right": false,
		"tint": Color(0.85, 0.90, 1.0)},
]

const STEER_DEADZONE := 0.06
const STEER_TRAVEL := 0.42  # fraction of zone half-width used for full lock


## Steering pad drawn as a rounded track with a knob plus edge chevrons.
class SteerZone extends Control:
	var value := 0.0
	var active := false
	var _style := StyleBoxFlat.new()

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_style.set_border_width_all(3)

	func set_value(v: float) -> void:
		value = v
		queue_redraw()

	func set_active(a: bool) -> void:
		active = a
		queue_redraw()

	func _draw() -> void:
		_style.bg_color = Color(1, 1, 1, 0.14 if active else 0.08)
		_style.border_color = Color(1, 1, 1, 0.42 if active else 0.22)
		_style.set_corner_radius_all(int(size.y * 0.5))
		draw_style_box(_style, Rect2(Vector2.ZERO, size))
		var cy := size.y * 0.5
		var cx := size.x * 0.5
		var travel := size.x * STEER_TRAVEL
		draw_line(Vector2(cx, size.y * 0.34), Vector2(cx, size.y * 0.66),
				Color(1, 1, 1, 0.18), 2.0)
		var kx := clampf(cx + value * travel, size.y * 0.3, size.x - size.y * 0.3)
		var kr := size.y * 0.2
		draw_circle(Vector2(kx, cy), kr, Color(1, 1, 1, 0.9 if active else 0.45))


var _buttons: Array[Dictionary] = []
var _steer_zone: SteerZone
var _chev_l: TextureRect
var _chev_r: TextureRect
var _steer_zone_rect := Rect2()
var _steer_index := -1
var _pointers := {}  # touch index -> action


## True when the on-screen pad should be used: a mobile export (or FORCE_TOUCH
## for dev/screenshots). DisplayServer.is_touchscreen_available() is unreliable
## here — it reports true even on headless/X11 — so gate on the export feature.
static func mobile_layout_active() -> bool:
	return OS.get_environment("FORCE_TOUCH") == "1" or OS.has_feature("mobile")


func _ready() -> void:
	layer = 10
	visible = mobile_layout_active()
	_steer_zone = SteerZone.new()
	add_child(_steer_zone)
	_chev_l = _make_chevron(true)
	_chev_r = _make_chevron(false)
	_steer_zone.add_child(_chev_l)
	_steer_zone.add_child(_chev_r)
	for def in BUTTON_DEFS:
		_buttons.append(_make_button(def))
	get_viewport().size_changed.connect(_layout)
	_layout()


func _make_chevron(point_left: bool) -> TextureRect:
	var chev := TextureRect.new()
	chev.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var path := "chevron_left" if point_left else "chevron_right"
	chev.texture = load(ICON_DIR + path + ".png")
	chev.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	chev.modulate = Color(1, 1, 1, 0.4)
	return chev


func _make_button(def: Dictionary) -> Dictionary:
	var node := Control.new()
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel := Panel.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.14)
	sb.border_color = Color(1, 1, 1, 0.32)
	sb.set_border_width_all(2)
	panel.add_theme_stylebox_override("panel", sb)
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	node.add_child(panel)
	var icon := TextureRect.new()
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.texture = load(ICON_DIR + String(def.icon) + ".png")
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.flip_h = bool(def.get("flip", false))
	icon.modulate = def.tint
	icon.set_anchors_preset(Control.PRESET_TOP_LEFT)
	node.add_child(icon)
	add_child(node)
	return {"action": def.action, "node": node, "panel": panel, "icon": icon}


## Recomputes the whole pad from viewport-relative units: one source of truth
## for both the visuals and the hit rects, so buttons stay finger-sized on any
## DPI (fixed 130px circles shrank to ~12% of the screen on 1080p phones).
func _layout() -> void:
	var vs := get_viewport().get_visible_rect().size
	var w := vs.x
	var h := vs.y
	var m := clampf(h * 0.024, 12.0, 36.0)
	var gap := clampf(h * 0.02, 8.0, 26.0)
	var d_gas := clampf(h * 0.235, 116.0, 240.0)
	var d_brake := clampf(h * 0.190, 92.0, 200.0)
	var d_nitro := clampf(h * 0.150, 76.0, 172.0)
	var d_atk := clampf(h * 0.125, 64.0, 144.0)
	var zh := clampf(h * 0.38, 190.0, 440.0)
	var zw := clampf(w * 0.34, 300.0, 900.0)

	var zone_rect := Rect2(m, h - m - zh, zw, zh)
	_steer_zone_rect = zone_rect
	_steer_zone.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_steer_zone.position = zone_rect.position
	_steer_zone.size = zone_rect.size
	var chev := zone_rect.size.y * 0.36
	_chev_l.size = Vector2(chev, chev)
	_chev_l.position = Vector2(zone_rect.size.y * 0.18, (zone_rect.size.y - chev) * 0.5)
	_chev_r.size = Vector2(chev, chev)
	_chev_r.position = Vector2(zone_rect.size.x - zone_rect.size.y * 0.18 - chev,
			(zone_rect.size.y - chev) * 0.5)
	_steer_zone.queue_redraw()

	var row_base := zone_rect.position.y - gap
	# Combat buttons keep their original slots (the row starts where nitro used
	# to sit) so they don't creep toward the centre of the screen / camera.
	var left_x := m + d_nitro + gap
	var sizes := {"attack_left": d_atk, "attack_right": d_atk, "kick": d_atk}
	var gas_rect := Rect2(w - m - d_gas, h - m - d_gas, d_gas, d_gas)
	var brake_rect := Rect2(gas_rect.position.x - gap - d_brake,
			h - m - d_brake, d_brake, d_brake)
	# Nitro sits directly above the throttle pedal: the right thumb rides the
	# gas and pivots up to the nitro without giving up throttle.
	var nitro_rect := Rect2(gas_rect.get_center().x - d_nitro * 0.5,
			gas_rect.position.y - gap - d_nitro, d_nitro, d_nitro)
	for b in _buttons:
		var action: String = b.action
		var rect: Rect2
		match action:
			"accelerate":
				rect = gas_rect
			"brake":
				rect = brake_rect
			"nitro":
				rect = nitro_rect
			_:
				var d: float = sizes[action]
				rect = Rect2(left_x, row_base - d, d, d)
				left_x += d + gap
		b.rect = rect
		_place(b.node, rect)
		b.panel.get_theme_stylebox("panel").set_corner_radius_all(int(rect.size.x / 2.0))
		var inset := rect.size.x * 0.16
		b.icon.position = Vector2(inset, inset)
		b.icon.size = rect.size - Vector2(inset, inset) * 2.0


func _place(node: Control, rect: Rect2) -> void:
	node.set_anchors_preset(Control.PRESET_TOP_LEFT)
	node.position = rect.position
	node.size = rect.size


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_F4:
		visible = not visible
		if not visible:
			_release_all()
		return
	if not visible:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_press(event.index, event.position)
		else:
			_release(event.index)
	elif event is InputEventScreenDrag:
		if event.index == _steer_index:
			_update_steer(event.position)


func _press(index: int, p: Vector2) -> void:
	if _steer_zone_rect.has_point(p):
		_steer_index = index
		_steer_zone.set_active(true)
		_update_steer(p)
		return
	for b in _buttons:
		if (b.rect as Rect2).has_point(p):
			_pointers[index] = b.action
			Input.action_press(b.action)
			b.node.scale = Vector2(0.92, 0.92)
			b.node.pivot_offset = (b.rect as Rect2).size * 0.5
			return


func _release(index: int) -> void:
	if index == _steer_index:
		_steer_index = -1
		_steer_zone.set_active(false)
		_steer_zone.set_value(0.0)
		Input.action_release("steer_left")
		Input.action_release("steer_right")
		return
	if _pointers.has(index):
		var action: String = _pointers[index]
		Input.action_release(action)
		_pointers.erase(index)
		for b in _buttons:
			if b.action == action:
				b.node.scale = Vector2.ONE
				break


func _update_steer(p: Vector2) -> void:
	var center := _steer_zone_rect.position.x + _steer_zone_rect.size.x * 0.5
	var travel := _steer_zone_rect.size.x * STEER_TRAVEL
	var v := clampf((p.x - center) / travel, -1.0, 1.0)
	if absf(v) < STEER_DEADZONE:
		v = 0.0
	_steer_zone.set_value(v)
	Input.action_press("steer_right", maxf(v, 0.0))
	Input.action_press("steer_left", maxf(-v, 0.0))


func _exit_tree() -> void:
	_release_all()


func _release_all() -> void:
	for action in _pointers.values():
		Input.action_release(action)
	_pointers.clear()
	_steer_index = -1
	Input.action_release("steer_left")
	Input.action_release("steer_right")
	if _steer_zone != null:
		_steer_zone.set_active(false)
		_steer_zone.set_value(0.0)
