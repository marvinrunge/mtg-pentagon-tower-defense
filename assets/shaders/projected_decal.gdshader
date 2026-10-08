shader_type spatial;
// A mark a spell leaves on the ground (ExplosionFx.scorch): a texture projected onto the real
// surface under it (ground_projection.gdshaderinc), so it lies on a slope instead of cutting
// through it, plus glowing embers in it that cool to nothing while the mark itself lingers.
//
// Blended normally, not additively - a scorch is pigment, and an additive one would brighten
// the ground it is meant to have burned (see docs/VFX_TEXTURES.md). Only the embers add light.
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_front, shadows_disabled;

#include "res://assets/shaders/ground_projection.gdshaderinc"

uniform sampler2D mark : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 tint : source_color = vec4(0.07, 0.04, 0.03, 0.85);
uniform float radius = 2.0;
uniform float fade = 1.0;
// 0..1: how hot the embers still are. Cools from 1 to 0 over a few seconds.
uniform float embers = 0.0;
uniform vec3 ember_color : source_color = vec3(1.0, 0.38, 0.06);
uniform float seed = 0.0;

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
	vec2 uv = ground.xz / (radius * 2.0) + vec2(0.5);
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) {
		discard;
	}
	float shape = texture(mark, uv).a;
	float alpha = shape * tint.a * fade * ground.w;

	// Embers: thin glowing cracks through the burnt middle, flickering as they cool.
	vec2 p = ground.xz * 2.2 + vec2(seed);
	float n = noise(p) * 0.65 + noise(p * 2.3) * 0.35;
	float cracks = 1.0 - smoothstep(0.0, 0.06, abs(n - 0.5));
	float centre = 1.0 - smoothstep(0.2, 0.75, length(ground.xz) / radius);
	float flicker = 0.75 + 0.25 * sin(TIME * 9.0 + n * 30.0);
	float glow = cracks * centre * shape * embers * flicker;

	ALBEDO = mix(tint.rgb, ember_color * 4.0, clamp(glow, 0.0, 1.0));
	ALPHA = clamp(max(alpha, glow * fade * ground.w), 0.0, 1.0);
}
