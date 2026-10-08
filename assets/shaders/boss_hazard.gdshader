shader_type spatial;
// The ground a boss leaves behind (BossHazard): a burning patch or a frozen ring, projected
// onto the surface under it (ground_projection.gdshaderinc) so it follows the slope it fell on.
render_mode unshaded, blend_add, depth_draw_never, depth_test_disabled, cull_front, shadows_disabled;

#include "res://assets/shaders/ground_projection.gdshaderinc"

uniform vec4 tint : source_color = vec4(1.0, 0.32, 0.06, 1.0);
uniform float radius = 2.5;
uniform float inner_radius = 0.0;
uniform float fade = 1.0;
// 0 fire, 1 frost
uniform int style = 0;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	vec4 ground = project_to_ground(SCREEN_UV, INV_PROJECTION_MATRIX, INV_VIEW_MATRIX, MODEL_MATRIX);
	if (ground.w <= 0.0) {
		discard;
	}
	float r = length(ground.xz);
	float edge = min(radius - r, inner_radius > 0.0 ? r - inner_radius : 1e6);
	if (edge < 0.0) {
		discard;
	}
	float soft = smoothstep(0.0, 0.35, edge);
	float n = noise(ground.xz * 1.6 + vec2(0.0, TIME * (style == 0 ? 0.8 : 0.1)));
	float body = (style == 0) ? mix(0.35, 0.9, n) * (0.8 + 0.2 * sin(TIME * 8.0 + n * 12.0)) : mix(0.3, 0.6, n);
	ALBEDO = tint.rgb * body;
	ALPHA = soft * 0.55 * fade * ground.w;
}
