shader_type spatial;
// The walls of light Judgment raises along its cross (BossTell). Additive, brightest at the
// ground and along a core line, fading out upwards and towards the arm's ends.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 tint : source_color = vec4(1.0, 0.95, 0.6, 1.0);
uniform float intensity = 1.0;

void fragment() {
	// UV.y is 0 at the top of the quad and 1 at its base.
	float rise = pow(UV.y, 1.6);
	float ends = smoothstep(0.0, 0.08, UV.x) * smoothstep(1.0, 0.92, UV.x);
	float shimmer = 0.8 + 0.2 * sin(TIME * 7.0 + UV.x * 40.0);
	float core = smoothstep(0.9, 1.0, UV.y) * 0.8;
	ALBEDO = tint.rgb * intensity * (rise * shimmer + core) * ends;
}
