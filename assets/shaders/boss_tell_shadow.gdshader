shader_type spatial;
// The shadow something falling or leaping casts where it will land (BossTell).
// A soft dark disc: solid in the middle, feathered at the edge, darkening as it nears.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 shadow_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float strength = 0.5;

void fragment() {
	float r = length(UV - vec2(0.5)) * 2.0;
	float disc = 1.0 - smoothstep(0.55, 1.0, r);
	ALBEDO = shadow_color.rgb;
	ALPHA = disc * strength;
}
