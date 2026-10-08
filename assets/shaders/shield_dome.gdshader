shader_type spatial;
// One shield for every shield (SpellVisuals.shield_dome): a dome of light whose silhouette
// burns, with a faint pattern drifting across its face, a bright line where it cuts the
// ground, and a dissolve for going up and coming down.
//
//   pattern 0  hexagons (white wards)
//   pattern 1  runes (Reprisal Ward)
//   pattern 2  bark (Ironbark)
//
// The ground line reads the depth buffer: where the dome's surface is within a few
// centimetres of whatever is behind it, it glows - which is where the dome meets the ground,
// and also where it passes through the caster's own feet.
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform sampler2D scene_depth : hint_depth_texture, filter_nearest, repeat_disable;
uniform vec3 tint : source_color = vec3(1.0, 0.92, 0.6);
uniform int pattern = 0;
uniform float glow = 1.3;
uniform float fade = 1.0;
// 0..1: raised from the ground up as it goes on, eaten away again as it drops.
uniform float reveal = 1.0;
// A flash across the whole surface - a hit taken, or the moment it goes up.
uniform float flare = 0.0;
uniform float seed = 0.0;

varying vec3 v_local;

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

// Distance to the nearest hexagon edge, for a hex grid of unit spacing.
float hex_edge(vec2 p) {
	vec2 s = vec2(1.0, 1.7320508);
	vec2 a = mod(p, s) - s * 0.5;
	vec2 b = mod(p - s * 0.5, s) - s * 0.5;
	vec2 g = dot(a, a) < dot(b, b) ? a : b;
	g = abs(g);
	return 0.5 - max(dot(g, normalize(s)), g.x);
}

void vertex() {
	v_local = VERTEX;
}

void fragment() {
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float rim = pow(1.0 - facing, 3.0);

	// Pattern coordinates: around and up the dome, so it wraps without stretching much.
	vec3 n = normalize(v_local);
	vec2 sphere_uv = vec2(atan(n.z, n.x) * 3.0, n.y * 4.0);
	float marks = 0.0;
	if (pattern == 0) {
		float e = hex_edge(sphere_uv * 1.2 + vec2(0.0, TIME * 0.08));
		marks = 1.0 - smoothstep(0.0, 0.06, e);
		// Cells light up and dim one at a time, so the surface is visibly alive.
		marks *= 0.35 + 0.65 * smoothstep(0.6, 1.0, noise(sphere_uv * 1.2 + vec2(TIME * 0.6, seed)));
	} else if (pattern == 1) {
		float band = abs(fract(sphere_uv.y * 0.5 + TIME * 0.05) - 0.5);
		float glyph = step(0.55, noise(vec2(floor(sphere_uv.x * 4.0 + TIME * 0.8), floor(sphere_uv.y * 2.0)) + seed));
		marks = (1.0 - smoothstep(0.03, 0.06, band)) + glyph * (1.0 - smoothstep(0.08, 0.2, band)) * 0.6;
	} else {
		float grain = noise(vec2(sphere_uv.x * 6.0, sphere_uv.y * 0.8 + seed));
		marks = smoothstep(0.55, 0.75, grain) * 0.8;
	}

	// The ground line: how close this surface point is to whatever is behind it.
	float depth = texture(scene_depth, SCREEN_UV).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(SCREEN_UV, depth) * 2.0 - 1.0;
#else
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
#endif
	vec4 behind = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	behind.xyz /= behind.w;
	float gap = abs(behind.z - VERTEX.z);
	float contact = 1.0 - smoothstep(0.0, 0.25, gap);

	// Up from the ground as it is raised, with a bright edge where it is still forming.
	float height = clamp(n.y, 0.0, 1.0);
	float edge_noise = noise(sphere_uv * 3.0 + seed) * 0.15;
	float shown = 1.0 - smoothstep(reveal - 0.05, reveal, height + edge_noise);
	float forming = (1.0 - smoothstep(0.0, 0.06, abs(height + edge_noise - reveal))) * step(reveal, 0.999);

	float a = (rim * 0.7 + marks * 0.22 + 0.03 + flare * 0.15) * shown + contact * 0.7 * shown + forming * 0.6;
	a *= fade;
	vec3 hot = mix(tint, vec3(1.0), clamp(rim * 0.25 + contact * 0.35 + flare * 0.6, 0.0, 1.0));
	ALBEDO = hot * glow * a;
	ALPHA = clamp(a * 0.25, 0.0, 1.0);
}
