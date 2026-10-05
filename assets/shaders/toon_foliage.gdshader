shader_type spatial;
render_mode cull_disabled, specular_disabled, depth_draw_opaque;

// Foliage variant of the flat cel look (toon.gdshader): identical 3-tone
// half-lambert ramp and rim, but double-sided and alpha-scissored so leaf
// cards keep their cut-out silhouette. Bark that ships double-sided can use
// this too (its texture alpha is opaque, so nothing is discarded).

uniform vec4 albedo : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform bool use_texture = true;
uniform float alpha_scissor : hint_range(0.0, 1.0) = 0.35;
uniform float band_low : hint_range(0.0, 1.0) = 0.42;
uniform float band_mid : hint_range(0.0, 1.0) = 0.68;
uniform float shadow_level : hint_range(0.0, 1.0) = 0.5;
uniform float mid_level : hint_range(0.0, 1.0) = 0.8;
uniform float rim_strength : hint_range(0.0, 1.0) = 0.3;
uniform vec3 rim_color : source_color = vec3(1.0, 0.97, 0.9);

varying vec3 world_normal;


void vertex() {
	world_normal = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}


void fragment() {
	vec3 base = albedo.rgb;
	float alpha = albedo.a;
	if (use_texture) {
		vec4 c = texture(albedo_tex, UV);
		base *= c.rgb;
		alpha *= c.a;
	}
	ALBEDO = base;
	ALPHA = alpha;
	ALPHA_SCISSOR_THRESHOLD = alpha_scissor;
	ROUGHNESS = 0.9;
	METALLIC = 0.0;
}


void light() {
	float ndl = dot(normalize(NORMAL), normalize(LIGHT));
	float lit = ndl * 0.5 + 0.5;  // half-lambert: soft, flattering
	float w = max(fwidth(lit), 0.003);
	float l1 = smoothstep(band_low - w, band_low + w, lit);
	float l2 = smoothstep(band_mid - w, band_mid + w, lit);
	float level = mix(shadow_level, mid_level, l1);
	level = mix(level, 1.0, l2);
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * ATTENUATION * level;

	float rim = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 3.0);
	DIFFUSE_LIGHT += ALBEDO * rim_color * LIGHT_COLOR * ATTENUATION * rim * rim_strength
		* clamp(ndl + 0.4, 0.0, 1.0);
}
