class_name ToonMaterial
extends RefCounted
## Shared factory for the flat cel-shaded look of the actors (rider, bikes,
## traffic). Wraps assets/shaders/toon.gdshader plus an optional inverse-hull
## outline (assets/shaders/toon_outline.gdshader) used as `next_pass`.

const TOON := preload("res://assets/shaders/toon.gdshader")
const FOLIAGE := preload("res://assets/shaders/toon_foliage.gdshader")
const OUTLINE := preload("res://assets/shaders/toon_outline.gdshader")

const OUTLINE_COLOR := Color(0.04, 0.04, 0.06)
const OUTLINE_WIDTH_BODY := 0.02
const OUTLINE_WIDTH_LIMB := 0.009


## Toon material for a flat colour, optionally multiplied by a texture.
## `triplanar` projects the texture in world space (box mapping) instead of
## using the mesh UVs — needed for kit models whose atlas does not match a
## tiled generated facade/ground texture. `tri_scale` is 1 / texture period (m).
static func make(color: Color, tex: Texture2D = null, outline_width: float = -1.0,
		triplanar: bool = false, tri_scale: float = 0.1) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = TOON
	m.set_shader_parameter("albedo", color)
	m.set_shader_parameter("use_texture", tex != null)
	m.set_shader_parameter("triplanar", triplanar)
	m.set_shader_parameter("tri_scale", tri_scale)
	if tex != null:
		m.set_shader_parameter("albedo_tex", tex)
	if outline_width > 0.0:
		m.next_pass = outline_pass(outline_width)
	return m


## Converts an imported PBR material (GLB) into its toon counterpart.
static func from_base(base: BaseMaterial3D, outline_width: float = -1.0,
		triplanar: bool = false, tri_scale: float = 0.1) -> ShaderMaterial:
	if base == null:
		return make(Color.WHITE, null, outline_width, triplanar, tri_scale)
	return make(base.albedo_color, base.albedo_texture, outline_width, triplanar, tri_scale)


## Double-sided, alpha-scissored toon material for foliage/bark cards. Use for
## imported materials whose leaves carry alpha (transparency != DISABLED) or
## that are flagged double-sided.
static func make_leaf(color: Color, tex: Texture2D = null,
		alpha_scissor: float = 0.35) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = FOLIAGE
	m.set_shader_parameter("albedo", color)
	m.set_shader_parameter("use_texture", tex != null)
	m.set_shader_parameter("alpha_scissor", alpha_scissor)
	if tex != null:
		m.set_shader_parameter("albedo_tex", tex)
	return m


static func outline_pass(width: float) -> ShaderMaterial:
	var o := ShaderMaterial.new()
	o.shader = OUTLINE
	o.set_shader_parameter("outline_color", OUTLINE_COLOR)
	o.set_shader_parameter("outline_width", width)
	return o
