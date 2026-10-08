shader_type spatial;
// The ground a lingering zone covers (DoTZone): projected onto the real surface
// (ground_projection.gdshaderinc) with a soft, ragged edge instead of the hard octagon a
// cylinder mesh drew, and moving inside so a zone that lasts ten seconds stays alive.
//
//   style 0  fire   burnt ground with glowing veins crawling through it
//   style 1  toxic  sickly sludge with bubbles welling up
//   style 2  holy   warm light pooled on the ground, rays turning slowly
//   style 3  fog    damp, dew-dark ground under the cloud
//
// Pigment (the burn, the damp) blends normally; the light parts are pushed into HDR.
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_front, shadows_disabled, fog_disabled;

#include "res://assets/shaders/ground_projection.gdshaderinc"

uniform int style = 0;
uniform float radius = 3.0;
uniform float fade = 1.0;
uniform float seed = 0.0;
uniform vec3 base_color : source_color = vec3(0.08, 0.04, 0.02);
uniform vec3 glow_color : source_color = vec3(1.0, 0.4, 0.08);
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

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p = p * 2.03 + vec2(7.1, 3.7);
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec4 ground = project_to_ground(SCREEN_UV, INV_PROJECTION_MATRIX, INV_VIEW_MATRIX, MODEL_MATRIX);
	if (ground.w <= 0.0) {
		discard;
	}
	vec2 p = ground.xz;
	float r = length(p) / radius;
	if (r > 1.15) {
		discard;
	}
	// A ragged, wandering edge, so the zone reads as something spread over the ground.
	float edge_n = fbm(p * 0.9 + vec2(seed));
	float edge = 1.0 - smoothstep(0.82 + edge_n * 0.18, 1.0 + edge_n * 0.12, r);

	vec3 color = base_color;
	float alpha = 0.0;
	float light = 0.0;

	if (style == 0) {
		float burn = fbm(p * 1.4 + vec2(seed * 1.7));
		alpha = (0.45 + burn * 0.35) * edge;
		// Veins: thin lines along the noise's mid level, crawling as the field drifts.
		float n = fbm(p * 1.1 + vec2(seed, TIME * 0.25));
		float veins = 1.0 - smoothstep(0.0, 0.05, abs(n - 0.5));
		float hot = smoothstep(0.62, 0.85, fbm(p * 0.8 - vec2(TIME * 0.15, seed)));
		float flicker = 0.7 + 0.3 * sin(TIME * 8.0 + n * 25.0);
		light = (veins * 0.9 + hot * 0.5) * flicker * edge;
	} else if (style == 1) {
		float sludge = fbm(p * 1.6 + vec2(seed, TIME * 0.1));
		alpha = (0.5 + sludge * 0.3) * edge;
		vec2 cell = floor(p * 2.2);
		vec2 local = fract(p * 2.2) - 0.5;
		float phase = fract(TIME * 0.6 + hash(cell + seed));
		float bubble = (1.0 - smoothstep(0.0, 0.06, abs(length(local) - phase * 0.35))) * (1.0 - phase);
		light = (bubble * step(0.45, hash(cell * 1.3)) + smoothstep(0.6, 0.8, sludge) * 0.4) * edge;
	} else if (style == 2) {
		float a = atan(p.y, p.x);
		float rays = smoothstep(0.6, 1.0, sin(a * 9.0 + TIME * 0.6) * 0.5 + 0.5) * (1.0 - r);
		float pool = (1.0 - smoothstep(0.0, 1.0, r)) * (0.6 + 0.4 * fbm(p * 1.5 + vec2(TIME * 0.2)));
		alpha = 0.0;
		light = (pool * 0.55 + rays * 0.45) * edge;
	} else {
		float damp = fbm(p * 1.2 + vec2(seed));
		alpha = (0.18 + damp * 0.2) * edge;
		float sheen = smoothstep(0.65, 0.9, fbm(p * 2.5 + vec2(TIME * 0.08, seed)));
		light = sheen * 0.25 * edge;
	}

	light = clamp(light, 0.0, 1.0);
	ALBEDO = mix(base_color, glow_color * glow, light);
	ALPHA = clamp(max(alpha, light), 0.0, 1.0) * fade * ground.w;
}
