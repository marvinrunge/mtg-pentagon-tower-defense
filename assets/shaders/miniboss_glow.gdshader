shader_type spatial;
// A rim-light overlay, not a replacement material. This is meant to be set as the
// character's existing material's NEXT_PASS rather than swapped in as its own
// material_override - the base pass still draws the mesh's real skin and texture, and this
// pass only adds a coloured glow around the silhouette on top of it. A miniboss is supposed
// to read as "one of these, but bigger and glowing" - losing the actual model underneath a
// flat recolour would read as a different, cheaper-looking enemy instead.
//
// Same render_mode shape as the other overlay shaders in this folder (shockwave,
// energy_beam): unshaded because this pass contributes light, not surface response, and
// depth_draw_never because the base pass already wrote depth for this exact geometry -
// writing it twice buys nothing. blend_add rather than shockwave's blend_premul_alpha: a
// shockwave has to read against both dark ground and bright sky, so it needed to occlude a
// little too. A rim light never needs to occlude - it only ever adds glow at grazing
// angles - so plain additive is both simpler and correct here.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

// The lane colour (see WaveManager._get_lane_color / EnemyDatabase's visual_color) - this
// is what makes the shimmer read as "White" or "Red" rather than a generic magic glow.
uniform vec4 glow_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float intensity : hint_range(0.0, 6.0) = 2.2;
// How tightly the glow hugs the silhouette. Low = a thin rim on the very edge; high = the
// whole surface picks up colour, which starts to fight the base texture underneath.
uniform float rim_power : hint_range(0.5, 8.0) = 2.5;
// A slow breathing pulse so the glow reads as alive rather than a static outline - the
// difference between "shimmer" and "flat rim light."
uniform float pulse_speed : hint_range(0.0, 4.0) = 1.4;
uniform float pulse_depth : hint_range(0.0, 1.0) = 0.35;

varying vec3 world_normal;
varying vec3 world_view;

void vertex() {
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	world_view = normalize((INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz - (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz);
}

void fragment() {
	// Standard Fresnel term: near 0 face-on, near 1 at a grazing angle - the classic "rim
	// light" falloff. Raised to rim_power so the tunable above can sharpen or soften it.
	float fresnel = pow(1.0 - clamp(dot(normalize(world_normal), normalize(world_view)), 0.0, 1.0), rim_power);
	float pulse = 1.0 - pulse_depth * 0.5 * (1.0 + sin(TIME * pulse_speed * TAU));
	float glow = fresnel * intensity * pulse;
	ALBEDO = glow_color.rgb * glow;
	ALPHA = clamp(glow * glow_color.a, 0.0, 1.0);
}
