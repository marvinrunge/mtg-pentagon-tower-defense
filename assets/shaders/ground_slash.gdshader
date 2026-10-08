shader_type spatial;
// A line cut into the ground (SpellVisuals.ground_slash): Doom Blade's path, a scar along
// local +Z from the node's origin out to `length`, glowing along its middle while it is
// fresh and drawn out from the start as the blade travels.
//
// Projected onto the real ground (ground_projection.gdshaderinc).
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_front, shadows_disabled, fog_disabled;

#include "res://assets/shaders/ground_projection.gdshaderinc"

uniform float length = 10.0;
uniform float width = 0.8;
// 0..1: how far along the line has been cut so far.
uniform float reach = 1.0;
uniform float heat = 1.0;
uniform float fade = 1.0;
uniform float seed = 0.0;
uniform vec3 scar_color : source_color = vec3(0.06, 0.02, 0.08);
uniform vec3 glow_color : source_color = vec3(0.62, 0.25, 0.92);
uniform float glow = 2.2;

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
	float along = ground.z / length;
	if (along < 0.0 || along > 1.0) {
		discard;
	}
	// Tapered at both ends, ragged along its sides.
	float taper = smoothstep(0.0, 0.08, along) * smoothstep(1.0, 0.85, along);
	float ragged = noise(vec2(ground.z * 3.0, seed)) * 0.35 + 0.65;
	float half_w = width * 0.5 * taper * ragged;
	float d = abs(ground.x) / max(half_w, 0.001);
	float scar = 1.0 - smoothstep(0.7, 1.0, d);
	float core = 1.0 - smoothstep(0.0, 0.35, d);
	float cut = 1.0 - smoothstep(reach - 0.03, reach, along);
	vec3 color = mix(scar_color, glow_color * glow, clamp(core * heat, 0.0, 1.0));
	ALBEDO = color;
	ALPHA = clamp(max(scar * 0.75, core * heat), 0.0, 1.0) * cut * fade * ground.w;
}
