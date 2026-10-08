shader_type spatial;
// The shadow something falling or leaping casts where it will land (BossTell). A soft dark
// disc, projected onto the ground like the telegraphs (ground_projection.gdshaderinc), so it
// lies on a slope instead of being buried in it.
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_front, shadows_disabled;

#include "res://assets/shaders/ground_projection.gdshaderinc"

uniform vec4 shadow_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float strength = 0.5;
uniform float radius = 3.0;

void fragment() {
	vec4 ground = project_to_ground(SCREEN_UV, INV_PROJECTION_MATRIX, INV_VIEW_MATRIX, MODEL_MATRIX);
	if (ground.w <= 0.0) {
		discard;
	}
	float r = length(ground.xz) / max(radius, 0.001);
	float disc = 1.0 - smoothstep(0.55, 1.0, r);
	ALBEDO = shadow_color.rgb;
	ALPHA = disc * strength * ground.w;
}
