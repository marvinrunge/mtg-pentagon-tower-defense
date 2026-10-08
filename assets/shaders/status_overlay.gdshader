shader_type spatial;
// What a buff looks like ON the character for as long as it lasts (StatusFx): drawn as the
// material_overlay of every mesh of the player, over their own materials.
//
//   bark     Ironbark: bark grown over the skin, with faint green cracks
//   shield   Circle of Protection: a gold rim and a hex shimmer across the body
//   reprisal Reprisal Ward: bright bands of light climbing the body
//   exalted  Exalted Strike charged: a slow gold pulse at the silhouette
//   phoenix  Rally's ward: a flickering ember-gold rim
//   giant    Giant Growth: a faint green rim
//
// Each is a 0..1 amount, eased in and out by StatusFx, so they stack instead of replacing
// each other. Bark is pigment and covers; the rest are light and only brighten.
render_mode unshaded, blend_mix, depth_draw_never, cull_back, shadows_disabled, fog_disabled;

uniform float bark = 0.0;
uniform float shield = 0.0;
uniform float reprisal = 0.0;
uniform float exalted = 0.0;
uniform float phoenix = 0.0;
uniform float giant = 0.0;
uniform vec3 gold : source_color = vec3(1.0, 0.78, 0.36);
uniform vec3 bark_dark : source_color = vec3(0.16, 0.1, 0.05);
uniform vec3 bark_light : source_color = vec3(0.42, 0.29, 0.15);
uniform vec3 green : source_color = vec3(0.55, 0.9, 0.45);

varying vec3 v_world;

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

float hex_edge(vec2 p) {
	vec2 s = vec2(1.0, 1.7320508);
	vec2 a = mod(p, s) - s * 0.5;
	vec2 b = mod(p - s * 0.5, s) - s * 0.5;
	vec2 g = dot(a, a) < dot(b, b) ? a : b;
	g = abs(g);
	return 0.5 - max(dot(g, normalize(s)), g.x);
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz - NODE_POSITION_WORLD;
}

void fragment() {
	float fresnel = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 1.6);

	// Bark: ridges running along the mesh's own UVs, so it stays put on a moving limb.
	vec2 g = UV * vec2(38.0, 9.0);
	float ridge = noise(g + vec2(noise(g * 0.35) * 2.0, 0.0));
	float grooves = smoothstep(0.25, 0.6, ridge);
	vec3 bark_col = mix(bark_dark, bark_light, grooves) * (0.8 + fresnel * 0.4);
	float crack = (1.0 - smoothstep(0.02, 0.08, abs(ridge - 0.22))) * (0.6 + 0.4 * sin(TIME * 2.0 + UV.y * 20.0));
	bark_col = mix(bark_col, green * 1.6, crack * 0.35);
	// Patchy at first, growing over everything as the amount rises.
	float cover = smoothstep(1.0 - bark * 1.15, 1.0 - bark * 1.15 + 0.15, noise(UV * 14.0));

	vec3 light = vec3(0.0);
	float light_a = 0.0;

	float hex = 1.0 - smoothstep(0.0, 0.07, hex_edge(v_world.xy * 5.0 + vec2(v_world.z * 3.0, TIME * 0.4)));
	float shimmer = smoothstep(0.55, 1.0, noise(v_world.xy * 4.0 + vec2(TIME * 0.8)));
	float s = shield * (fresnel * 0.9 + hex * shimmer * 0.5 + 0.08);
	light += gold * 1.6 * s;
	light_a += s;

	float band = smoothstep(0.75, 1.0, sin(v_world.y * 9.0 - TIME * 4.0)) * (0.35 + fresnel);
	float r = reprisal * band * 0.8;
	light += mix(gold, vec3(1.0), 0.4) * 1.8 * r;
	light_a += r;

	float pulse = 0.55 + 0.45 * sin(TIME * 5.0);
	float e = exalted * (fresnel * 0.9 + 0.12) * pulse;
	light += gold * 2.0 * e;
	light_a += e;

	float flicker = 0.6 + 0.4 * noise(vec2(TIME * 6.0, v_world.y * 3.0));
	float ph = phoenix * fresnel * flicker;
	light += vec3(1.0, 0.55, 0.2) * 1.8 * ph;
	light_a += ph;

	float gi = giant * (fresnel * 0.8 + 0.05);
	light += green * 1.4 * gi;
	light_a += gi;

	light_a = clamp(light_a, 0.0, 1.0);
	float bark_a = bark * cover * 0.92;
	vec3 color = bark_col;
	if (light_a > 0.0) {
		color = mix(bark_col, light / max(light_a, 0.001), light_a / max(light_a + bark_a * (1.0 - light_a), 0.001));
	}
	ALBEDO = color;
	ALPHA = clamp(max(bark_a, light_a), 0.0, 1.0);
}
