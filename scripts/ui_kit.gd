class_name UiKit
extends RefCounted
## Shared UI factories so the garage, menu and HUD render identical buttons and
## labels from a single source (font lookup, outline style, focus behaviour).

const ACCENT := Color(1.0, 0.85, 0.25)

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
