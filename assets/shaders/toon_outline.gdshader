shader_type spatial;
render_mode cull_front, unshaded, shadows_disabled;

// Inverse-hull silhouette: assigned as `next_pass` on a toon material, it
// re-draws the mesh grown along its normals with front faces culled, leaving a
// clean cartoon contour around the actor.

uniform vec4 outline_color : source_color = vec4(0.04, 0.04, 0.06, 1.0);
uniform float outline_width = 0.012;


void vertex() {
	VERTEX += NORMAL * outline_width;
}


void fragment() {
	ALBEDO = outline_color.rgb;
}
