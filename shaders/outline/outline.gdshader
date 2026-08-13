shader_type spatial;
// Inverted-hull outline. Assign this shader to a ShaderMaterial, then set
// that material as the `next_pass` of the model's normal (white) material.
// Godot renders the base pass first, then this pass — depth testing means
// the pushed-out backfaces only survive at the silhouette edge, which is
// exactly the black border look we want. Cheap, works on any mesh, and
// needs zero per-model setup beyond assigning the material.
render_mode cull_front, unshaded, depth_draw_always;

uniform float outline_width : hint_range(0.0, 0.05) = 0.012;
uniform vec4 outline_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);

void vertex() {
	// Expand along the view-space normal, scaled by distance from the
	// camera, so the line reads as a constant screen-space width whether
	// the boat is close or the moon-lit island is far away.
	vec3 view_normal = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec4 view_pos = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	view_pos.xyz += view_normal * outline_width * -view_pos.z;
	POSITION = PROJECTION_MATRIX * view_pos;
}

void fragment() {
	ALBEDO = outline_color.rgb;
}
