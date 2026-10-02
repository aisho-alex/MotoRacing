shader_type spatial;
render_mode cull_back, specular_disabled;

// Flat cel look for the arcade actors (rider, bikes, traffic): a 3-tone
// half-lambert ramp plus a soft rim, no specular. Colours stay data-driven
// through `albedo`; an optional texture multiplies it (bike liveries).

uniform vec4 albedo : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform bool use_texture = false;
// World-space box projection for tiled facade/ground textures on kit models
// whose own UV atlas does not match the generated texture (lots/buildings).
uniform bool triplanar = false;
uniform float tri_scale : hint_range(0.001, 1.0) = 0.1;
uniform float band_low : hint_range(0.0, 1.0) = 0.42;
uniform float band_mid : hint_range(0.0, 1.0) = 0.68;
uniform float shadow_level : hint_range(0.0, 1.0) = 0.5;
uniform float mid_level : hint_range(0.0, 1.0) = 0.8;
uniform float rim_strength : hint_range(0.0, 1.0) = 0.3;
uniform vec3 rim_color : source_color = vec3(1.0, 0.97, 0.9);

varying vec3 world_pos;
varying vec3 world_normal;


void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}


void fragment() {
	vec3 base = albedo.rgb;
	if (use_texture) {
		if (triplanar) {
			vec3 n = abs(normalize(world_normal));
			n /= (n.x + n.y + n.z);
			vec3 c = texture(albedo_tex, world_pos.yz * tri_scale).rgb * n.x
					+ texture(albedo_tex, world_pos.xz * tri_scale).rgb * n.y
					+ texture(albedo_tex, world_pos.xy * tri_scale).rgb * n.z;
			base *= c;
		} else {
			base *= texture(albedo_tex, UV).rgb;
		}
	}
	ALBEDO = base;
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
