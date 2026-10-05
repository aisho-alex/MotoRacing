class_name UiKit
extends RefCounted
## Shared UI factories so the garage, menu and HUD render identical buttons and
## labels from a single source (font lookup, outline style, focus behaviour).

const ACCENT := Color(1.0, 0.85, 0.25)
const CYAN := Color(0.35, 0.78, 1.0)
const GREEN := Color(0.42, 0.90, 0.55)
const ORANGE := Color(1.0, 0.60, 0.22)
const PURPLE := Color(0.74, 0.56, 1.0)
const RED := Color(1.0, 0.42, 0.42)
const PINK := Color(1.0, 0.55, 0.78)
const INK := Color(0.05, 0.05, 0.08)
const DIM := Color(1, 1, 1, 0.5)

## Animated gradient backdrop shared by the menu and garage.
const BACKDROP_SHADER := """
shader_type canvas_item;
uniform vec3 top_color : source_color = vec3(0.05, 0.07, 0.14);
uniform vec3 bottom_color : source_color = vec3(0.12, 0.06, 0.18);
uniform vec3 accent : source_color = vec3(1.0, 0.85, 0.25);
void fragment() {
	vec2 uv = UV;
	vec3 col = mix(top_color, bottom_color, uv.y);
	float d = uv.x * 1.4 + uv.y * 0.8;
	float band = abs(fract(d * 2.5) - 0.5);
	col += accent * 0.045 * smoothstep(0.47, 0.50, band);
	float glow = distance(uv, vec2(0.84, 0.88));
	col += accent * 0.10 * smoothstep(0.78, 0.0, glow);
	float glow2 = distance(uv, vec2(0.14, 0.10));
	col += vec3(0.20, 0.45, 1.0) * 0.09 * smoothstep(0.72, 0.0, glow2);
	COLOR = vec4(col, 1.0);
}
"""

static var _shared_font: Font = null
static var _font_lookup_done := false


## Racing font from assets/ui/fonts/ (ChakraPetch preferred); falls back to the
## engine default while the folder is empty.
static func font() -> Font:
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


static func label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	var ls := LabelSettings.new()
	ls.font = font()
	ls.font_size = size
	ls.font_color = color
	ls.outline_size = int(size / 4.0)
	ls.outline_color = Color(0, 0, 0, 0.85)
	l.label_settings = ls
	return l


static func button(text: String, size: int) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", font())
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_hover_color", ACCENT)
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.25))
	return b


## Rounded panel background used across the menu and garage.
static func panel_style(bg: Color, border: Color, radius := 14, border_width := 1,
		margin := 14) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_width)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(margin)
	return s


## Button with a solid colored fill and dark label, used for primary actions
## (START RACE, BUY, EQUIP). `tint` is the base fill colour.
static func filled_button(text: String, size: int, tint: Color) -> Button:
	var b := button(text, size)
	b.add_theme_stylebox_override("normal", _btn_style(tint, tint.darkened(0.25)))
	b.add_theme_stylebox_override("hover", _btn_style(tint.lightened(0.14), tint.lightened(0.25)))
	b.add_theme_stylebox_override("pressed", _btn_style(tint.darkened(0.18), tint.darkened(0.3)))
	b.add_theme_stylebox_override("disabled", _btn_style(Color(tint.r, tint.g, tint.b, 0.22),
			Color(1, 1, 1, 0.10)))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", INK)
	b.add_theme_color_override("font_hover_color", INK)
	b.add_theme_color_override("font_pressed_color", INK)
	b.add_theme_color_override("font_disabled_color", Color(0, 0, 0, 0.35))
	return b


## Transparent button with a colored outline and label, for secondary actions
## (QUIT, CREDITS, BACK).
static func outline_button(text: String, size: int, tint: Color) -> Button:
	var b := button(text, size)
	b.add_theme_stylebox_override("normal", _btn_style(Color(1, 1, 1, 0.04), Color(tint.r, tint.g, tint.b, 0.6)))
	b.add_theme_stylebox_override("hover", _btn_style(Color(tint.r, tint.g, tint.b, 0.18), tint))
	b.add_theme_stylebox_override("pressed", _btn_style(Color(tint.r, tint.g, tint.b, 0.28), tint))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", tint)
	b.add_theme_color_override("font_hover_color", tint.lightened(0.2))
	return b


static func _btn_style(bg: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(2)
	s.set_corner_radius_all(10)
	s.content_margin_left = 18
	s.content_margin_right = 18
	s.content_margin_top = 4
	s.content_margin_bottom = 4
	return s


## Full-rect gradient backdrop; add as the first child of a Control screen.
static func backdrop() -> ColorRect:
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = BACKDROP_SHADER
	mat.shader = sh
	bg.material = mat
	return bg
