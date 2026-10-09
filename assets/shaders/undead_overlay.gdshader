shader_type spatial;
// A raised ghoul (TemporaryAlly, Zombify): drawn as the material_overlay of every mesh of the
// corpse it rose from, over its own materials.
//
// Dead, not glowing: the body is darkened and drained, split by a network of black furrows
// - the skin burst open - with a thin violet glow breathing up out of the bottom of each.
// Two sizes of crack, so it reads as torn flesh rather than as a tiled pattern.
//
// Laid along the mesh's UVs, not world or object space: a crack has to stay on the limb it
// is on while the rig swings, and only the UVs move with the skin.
render_mode unshaded, blend_mix, depth_draw_never, cull_back, shadows_disabled, fog_disabled;

uniform vec3 crack_color : source_color = vec3(0.55, 0.15, 1.0);
// Above 1 so the cracks bloom where glow is on.
uniform float glow_energy = 1.5;
uniform float crack_scale = 9.0;
// How much of the body the dead grey-black lays over, outside the furrows. High, because
// it can only scale the lit model down: in noon sun a white armour plate is lit well above
// 1.0, and anything much lower left it gleaming white under its cracks.
uniform float decay = 0.86;
// Per ghoul, so no two crack the same way.
uniform float seed = 0.0;

vec2 hash2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

// Distance to the nearest cell border of a Voronoi pattern (the classic two-pass version),
// which is what a crack network is: thin where cells meet, nothing inside them.
float crack_distance(vec2 x) {
	vec2 n = floor(x);
	vec2 f = fract(x);
	vec2 nearest_cell;
	vec2 nearest;
	float best = 8.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 r = g + hash2(n + g) - f;
			float d = dot(r, r);
			if (d < best) {
				best = d;
				nearest = r;
				nearest_cell = g;
			}
		}
	}
	best = 8.0;
	for (int j = -2; j <= 2; j++) {
		for (int i = -2; i <= 2; i++) {
			vec2 g = nearest_cell + vec2(float(i), float(j));
			vec2 r = g + hash2(n + g) - f;
			if (dot(nearest - r, nearest - r) > 0.00001) {
				best = min(best, dot(0.5 * (nearest + r), normalize(r - nearest)));
			}
		}
	}
	return best;
}

void fragment() {
	vec2 uv = UV * crack_scale + vec2(seed * 3.7, seed * 1.3);
	// A little wobble so the borders are torn, not ruled.
	uv += vec2(sin(uv.y * 2.3), cos(uv.x * 2.1)) * 0.12;
	float big = crack_distance(uv);
	float small = crack_distance(uv * 2.4 + vec2(7.1, 3.3));

	// The furrow: a wide black groove around each border.
	float furrow = max(1.0 - smoothstep(0.08, 0.22, big), (1.0 - smoothstep(0.035, 0.11, small)) * 0.85);
	// The glow: a thin core at the very bottom of the groove, the big cracks brighter.
	float core = max(1.0 - smoothstep(0.0, 0.025, big), (1.0 - smoothstep(0.0, 0.012, small)) * 0.5);
	// Breathing slowly, out of step from one part of the body to the next.
	float pulse = 0.6 + 0.4 * sin(TIME * 2.1 + uv.x * 0.6 + uv.y * 0.8 + seed);
	float glow = core * pulse;

	float fresnel = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 2.0);

	vec3 dead = vec3(0.02, 0.015, 0.025);
	vec3 color = mix(dead, crack_color * glow_energy, clamp(glow, 0.0, 1.0));
	color += crack_color * fresnel * 0.15;
	ALBEDO = color;
	ALPHA = clamp(max(max(decay, furrow), glow), 0.0, 1.0);
}
