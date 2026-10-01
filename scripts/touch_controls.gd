class_name TouchControls
extends CanvasLayer
## Virtual gamepad for mobile: multi-touch hold buttons that drive the same
## Input actions as the keyboard. Hidden unless a touchscreen is present;
## F4 toggles it on desktop for testing.

const BUTTON_DEFS := [
	{"action": "steer_left", "label": "<", "left": true, "offset": Vector2(24, -170), "size": Vector2(130, 130)},
	{"action": "steer_right", "label": ">", "left": true, "offset": Vector2(174, -170), "size": Vector2(130, 130)},
	{"action": "attack_left", "label": "PL", "left": true, "offset": Vector2(70, -320), "size": Vector2(120, 120)},
	{"action": "attack_right", "label": "PR", "left": true, "offset": Vector2(210, -320), "size": Vector2(120, 120)},
	{"action": "brake", "label": "v", "left": false, "offset": Vector2(-310, -170), "size": Vector2(130, 130)},
	{"action": "accelerate", "label": "^", "left": false, "offset": Vector2(-164, -170), "size": Vector2(130, 130)},
	{"action": "nitro", "label": "N", "left": false, "offset": Vector2(-310, -316), "size": Vector2(130, 130)},
	{"action": "kick", "label": "K", "left": false, "offset": Vector2(-164, -316), "size": Vector2(130, 130)},
]

var _rects: Array[Rect2] = []
var _pointers := {}  # touch index -> action


func _ready() -> void:
	layer = 10
	visible = DisplayServer.is_touchscreen_available()
	var font := Hud._ui_font()
	for def in BUTTON_DEFS:
		var btn := Control.new()
		btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var size: Vector2 = def.size
		var panel := Panel.new()
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(1, 1, 1, 0.14)
		sb.set_corner_radius_all(int(size.x / 2.0))
		sb.border_color = Color(1, 1, 1, 0.35)
		sb.set_border_width_all(2)
		panel.add_theme_stylebox_override("panel", sb)
		panel.set_anchors_preset(Control.PRESET_FULL_RECT)
		btn.add_child(panel)
		var lbl := Label.new()
		lbl.text = def.label
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ls := LabelSettings.new()
		ls.font = font
		ls.font_size = int(size.y * 0.45)
		ls.font_color = Color(1, 1, 1, 0.85)
		ls.outline_size = 8
		ls.outline_color = Color(0, 0, 0, 0.6)
		lbl.label_settings = ls
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
		btn.add_child(lbl)
		btn.size = size
		var ax := 0.0 if def.left else 1.0
		btn.anchor_left = ax
		btn.anchor_right = ax
		btn.anchor_top = 1.0
		btn.anchor_bottom = 1.0
		btn.offset_left = def.offset.x
		btn.offset_right = def.offset.x + size.x
		btn.offset_top = def.offset.y
		btn.offset_bottom = def.offset.y + size.y
		add_child(btn)

	_rects.resize(BUTTON_DEFS.size())
	_update_rects()


func _update_rects() -> void:
	var vs := get_viewport().get_visible_rect().size
	for i in BUTTON_DEFS.size():
		var def: Dictionary = BUTTON_DEFS[i]
		var org := Vector2.ZERO
		org.x = 0.0 if def.left else vs.x
		org.y = vs.y
		_rects[i] = Rect2(org + def.offset, def.size)


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
			var action := _action_at(event.position)
			if action != "":
				_pointers[event.index] = action
				Input.action_press(action)
		elif _pointers.has(event.index):
			Input.action_release(_pointers[event.index])
			_pointers.erase(event.index)


func _exit_tree() -> void:
	_release_all()


func _release_all() -> void:
	for action in _pointers.values():
		Input.action_release(action)
	_pointers.clear()


func _action_at(p: Vector2) -> String:
	_update_rects()
	for i in _rects.size():
		if _rects[i].has_point(p):
			return BUTTON_DEFS[i].action
	return ""
