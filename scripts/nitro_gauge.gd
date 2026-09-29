class_name NitroGauge
extends Control
## Segmented NITRO gauge for the HUD. Drawn manually so the tank reads clearly
## at a glance: chunky bright segments, a glowing frame while the boost is on
## and a soft pulse once the tank is full.

const SEGMENTS := 10
const PAD := 4.0
const GAP := 2.0

const C_FILL := Color(1.0, 0.55, 0.1)
const C_FILL_ACTIVE := Color(1.0, 0.85, 0.25)
const C_FILL_LOW := Color(0.6, 0.3, 0.07)
const C_FILL_FULL := Color(1.0, 0.72, 0.18)
const C_FRAME := Color(1.0, 1.0, 1.0, 0.30)
const C_GLOW := Color(1.0, 0.78, 0.25, 0.95)
const C_SEG_BG := Color(0.02, 0.02, 0.03, 0.78)

var _ratio := 1.0
var _active := false
var _pulse := 0.0

var _frame: StyleBoxFlat
var _seg_bg: StyleBoxFlat
var _seg_fill: StyleBoxFlat
var _glow: StyleBoxFlat


func _ready() -> void:
	custom_minimum_size = Vector2(320, 28)
	_frame = StyleBoxFlat.new()
	_frame.bg_color = Color(0.0, 0.0, 0.0, 0.55)
	_frame.set_corner_radius_all(6)
	_frame.set_border_width_all(2)
	_frame.border_color = C_FRAME
	_seg_bg = StyleBoxFlat.new()
	_seg_bg.bg_color = C_SEG_BG
	_seg_bg.set_corner_radius_all(3)
	_seg_fill = StyleBoxFlat.new()
	_seg_fill.bg_color = C_FILL
	_seg_fill.set_corner_radius_all(3)
	_glow = StyleBoxFlat.new()
	_glow.draw_center = false
	_glow.set_border_width_all(3)
	_glow.border_color = C_GLOW
	_glow.set_corner_radius_all(7)


func set_state(ratio: float, active: bool) -> void:
	_ratio = clampf(ratio, 0.0, 1.0)
	_active = active


func _process(delta: float) -> void:
	_pulse = wrapf(_pulse + delta * 3.4, 0.0, TAU)
	if _active:
		_seg_fill.bg_color = C_FILL_ACTIVE
	elif _ratio < 0.15:
		_seg_fill.bg_color = C_FILL_LOW
	elif _ratio >= 0.995:
		_seg_fill.bg_color = C_FILL_FULL.lerp(C_FILL_ACTIVE, 0.5 + 0.5 * sin(_pulse))
	else:
		_seg_fill.bg_color = C_FILL
	queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_style_box(_frame, r)
	var inner := Rect2(Vector2(PAD, PAD), size - Vector2(PAD, PAD) * 2.0)
	var seg_w := (inner.size.x - GAP * float(SEGMENTS - 1)) / float(SEGMENTS)
	var filled := _ratio * float(SEGMENTS)
	for i in SEGMENTS:
		var amount := clampf(filled - float(i), 0.0, 1.0)
		var cell := Rect2(
			Vector2(inner.position.x + float(i) * (seg_w + GAP), inner.position.y),
			Vector2(seg_w, inner.size.y)
		)
		draw_style_box(_seg_bg, cell)
		if amount <= 0.0:
			continue
		var fill := cell
		fill.position.x = cell.position.x + cell.size.x * (1.0 - amount)
		fill.size.x = cell.size.x * amount
		draw_style_box(_seg_fill, fill)
	if _active:
		draw_style_box(_glow, r)
