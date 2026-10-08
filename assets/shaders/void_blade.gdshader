shader_type spatial;
// Doom Blade's crescent (SpellVisuals.doom_blade): a blade of black smoke with a violet
// cutting edge. UV.x runs from tip to tip, UV.y from the cutting edge (0) to the trailing
// smoke (1). The trailing side tears into wisps that scroll back off the blade, and the
// whole thing erodes away as it fades rather than turning transparent.
//
// Premultiplied so the black reads as black against a bright sky - an additive blade could
// only ever be light.
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec3 edge_color : source_color = vec3(0.75, 0.4, 1.0);
uniform vec3 smoke_color : source_color = vec3(0.05, 0.01, 0.08);
uniform float glow = 2.5;
uniform float fade = 1.0;
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
	float tips = sin(UV.x * 3.14159265);
	float n = noise(vec2(UV.x * 9.0 + seed, UV.y * 3.0 - TIME * 4.0)) * 0.6
		+ noise(vec2(UV.x * 21.0, UV.y * 7.0 - TIME * 7.0)) * 0.4;
	// Thickest in the middle, the trailing side torn by the noise.
	float body = 1.0 - smoothstep(tips * 0.75 - 0.25 + n * 0.35, tips * 0.75 + n * 0.35, UV.y);
	float edge = (1.0 - smoothstep(0.0, 0.12, UV.y)) * tips;
	float erode = smoothstep(1.0 - fade - 0.1, 1.0 - fade + 0.1, n);
	float a = clamp(body * 0.9 + edge, 0.0, 1.0) * erode;
	vec3 color = mix(smoke_color, edge_color * glow, edge);
	ALBEDO = color * a;
	ALPHA = a;
}
