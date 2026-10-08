shader_type spatial;
// A rune circle on the ground under a cast (SpellVisuals.magic_circle): rings, a band of
// glyphs and a figure in the middle, in one of five dialects - one per colour - so a player
// can tell from the floor alone which colour was cast.
//
// Projected onto the real ground (ground_projection.gdshaderinc), so it lies on a slope or a
// step instead of hanging off it. Everything is drawn by the fragment function; there is no
// texture, so the five dialects cost nothing but a uniform.
//
//   pattern 0  white  eight-point star, sun rays between the rings
//   pattern 1  blue   hexagram inside a hexagon, frost branches on the points
//   pattern 2  black  inverted pentagram, a ring of thorns
//   pattern 3  red    two crossed triangles, flame tongues licking off the outer ring
//   pattern 4  green  a seven-petal rose, a vine winding round the rim
//
// Blended normally with the lines pushed into HDR, so they read over bright ground in daylight
// and still bloom at night; a faint dark wash inside the circle gives them something to read
// against.
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_front, shadows_disabled, fog_disabled;

#include "res://assets/shaders/ground_projection.gdshaderinc"

uniform int pattern = 0;
uniform vec3 tint : source_color = vec3(1.0, 0.9, 0.6);
uniform float radius = 2.0;
// 0..1: draws the circle outward from its centre as it is cast.
uniform float reveal = 1.0;
uniform float fade = 1.0;
// Extra light for the release flash, on top of the steady glow.
uniform float flare = 0.0;
uniform float glow = 1.25;
// Radians per second; the glyph band turns the other way at half speed.
uniform float spin_speed = 0.6;
uniform float seed = 0.0;


float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

// A line of `width` metres (scaled by `px` for screen-space softness) at distance `d`.
float stroke(float d, float width, float px) {
	return 1.0 - smoothstep(width * 0.5, width * 0.5 + px, abs(d));
}

float ring(float r, float at, float width, float px) {
	return stroke(r - at, width, px);
}

float seg_dist(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h);
}

// The star polygon {n/k}: every vertex joined to the k-th one after it.
float star(vec2 p, int n, int k, float r, float rot) {
	float d = 1e5;
	for (int i = 0; i < 9; i++) {
		if (i >= n) {
			break;
		}
		float a0 = rot + TAU * float(i) / float(n);
		float a1 = rot + TAU * float(i + k) / float(n);
		d = min(d, seg_dist(p, vec2(cos(a0), sin(a0)) * r, vec2(cos(a1), sin(a1)) * r));
	}
	return d;
}

vec2 rotate(vec2 p, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec2(c * p.x - s * p.y, s * p.x + c * p.y);
}

// One glyph per angular cell of the band: a few strokes picked from a small grid, so the
// band reads as writing without ever spelling anything.
float glyphs(vec2 p, float r_in, float r_out, float cells, float rot, float px) {
	float r = length(p);
	if (r < r_in || r > r_out) {
		return 0.0;
	}
	float a = atan(p.y, p.x) + rot;
	float cell = floor(a / TAU * cells);
	float u = fract(a / TAU * cells);
	float v = (r - r_in) / (r_out - r_in);
	// Cell-local coordinates in metres, so strokes keep their width round the band.
	float cell_w = TAU * (r_in + r_out) * 0.5 / cells;
	vec2 q = vec2((u - 0.5) * cell_w, (v - 0.5) * (r_out - r_in));
	float h = hash(vec2(cell, seed + 3.1));
	float w = (r_out - r_in) * 0.09;
	float ink = 0.0;
	float half_w = cell_w * 0.28;
	float half_h = (r_out - r_in) * 0.32;
	// Always a stem, then bars and ticks by the cell's own hash.
	ink = max(ink, stroke(q.x - (h - 0.5) * half_w, w, px) * step(abs(q.y), half_h));
	if (fract(h * 7.0) > 0.35) {
		ink = max(ink, stroke(q.y - half_h * (fract(h * 13.0) > 0.5 ? 1.0 : -1.0), w, px) * step(abs(q.x), half_w));
	}
	if (fract(h * 17.0) > 0.5) {
		ink = max(ink, stroke(q.y, w, px) * step(abs(q.x - half_w * 0.4), half_w * 0.6));
	}
	if (fract(h * 29.0) > 0.6) {
		ink = max(ink, stroke(length(q - vec2(-half_w * 0.5, half_h * 0.4)) - half_h * 0.35, w, px));
	}
	// A gap between cells, so the glyphs read as separate marks.
	ink *= step(0.12, u) * step(u, 0.88);
	return ink;
}

void fragment() {
	vec4 ground = project_to_ground(SCREEN_UV, INV_PROJECTION_MATRIX, INV_VIEW_MATRIX, MODEL_MATRIX);
	if (ground.w <= 0.0) {
		discard;
	}
	// Normalised to the circle, so every figure below is laid out in 0..1 of the radius.
	vec2 p = ground.xz / radius;
	float r = length(p);
	if (r > 1.05) {
		discard;
	}
	// Screen-space softness, in the same units as p: lines stay crisp near and far.
	float px = max(fwidth(r), 0.002) * 1.2;
	// Line widths are given for a 2.5 m circle; a wider one keeps roughly the same widths in
	// metres instead of growing fat lines, and fits more glyphs in its band.
	float lw = clamp(2.5 / radius, 0.3, 1.2);
	float cells = floor(28.0 / clamp(lw, 0.45, 1.0));
	float t = TIME * spin_speed;
	vec2 pr = rotate(p, t);
	float a = atan(pr.y, pr.x);
	float ink = 0.0;

	// The frame every dialect shares: a double outer ring and an inner one.
	ink = max(ink, ring(r, 0.97, 0.022 * lw, px));
	ink = max(ink, ring(r, 0.90, 0.010 * lw, px));
	ink = max(ink, ring(r, 0.62, 0.014 * lw, px));
	ink = max(ink, glyphs(p, 0.66, 0.86, cells, -t * 0.5, px));
	ink = max(ink, ring(r, 0.10, 0.012 * lw, px));

	if (pattern == 0) {
		ink = max(ink, stroke(star(pr, 8, 3, 0.6, 0.0), 0.016 * lw, px));
		ink = max(ink, stroke(star(pr, 4, 1, 0.42, PI * 0.25), 0.010 * lw, px));
		// Rays outside the frame, longer on the cardinal points.
		float ray = abs(fract(a / TAU * 16.0) - 0.5);
		float long_ray = step(0.5, fract(a / TAU * 8.0 + 0.25));
		ink = max(ink, stroke(ray * 0.14, 0.012 * lw, px) * step(0.97, r) * step(r, mix(1.01, 1.05, long_ray)));
	} else if (pattern == 1) {
		ink = max(ink, stroke(star(pr, 6, 2, 0.6, PI / 6.0), 0.014 * lw, px));
		ink = max(ink, stroke(star(pr, 6, 1, 0.6, PI / 6.0), 0.010 * lw, px));
		ink = max(ink, stroke(star(pr, 6, 1, 0.3, 0.0), 0.010 * lw, px));
		// Frost branches: short spurs off each spoke.
		float spoke = abs(fract(a / TAU * 6.0 + 0.5) - 0.5) * r * TAU / 6.0;
		ink = max(ink, stroke(spoke, 0.010 * lw, px) * step(0.3, r) * step(r, 0.6));
		vec2 local = rotate(pr, -floor(a / TAU * 6.0 + 0.5) * TAU / 6.0);
		float spur = abs(abs(local.y) - (local.x - 0.42) * 0.7);
		ink = max(ink, stroke(spur, 0.008 * lw, px) * step(0.42, local.x) * step(local.x, 0.55));
	} else if (pattern == 2) {
		ink = max(ink, stroke(star(pr, 5, 2, 0.6, -PI * 0.5), 0.016 * lw, px));
		// Thorns: a jagged ring of teeth pointing inward from the frame.
		float tooth = abs(fract(a / TAU * 24.0) - 0.5) * 2.0;
		float thorn_r = 0.62 - (1.0 - tooth) * 0.07;
		ink = max(ink, stroke(r - thorn_r, 0.010 * lw, px) * step(r, 0.63));
		ink = max(ink, ring(r, 0.32, 0.010 * lw, px));
	} else if (pattern == 3) {
		ink = max(ink, stroke(star(pr, 3, 1, 0.6, PI * 0.5), 0.016 * lw, px));
		ink = max(ink, stroke(star(pr, 3, 1, 0.6, -PI * 0.5), 0.016 * lw, px));
		// Flames: tongues off the outer ring that flicker in length.
		float lobes = sin(a * 12.0 + TIME * 3.0) * 0.5 + 0.5;
		float flame_r = 0.97 + 0.07 * pow(lobes, 3.0) * (0.7 + 0.3 * sin(TIME * 7.0 + a * 5.0));
		ink = max(ink, stroke(r - flame_r, 0.012 * lw, px) * step(0.96, r));
		ink = max(ink, ring(r, 0.3, 0.012 * lw, px));
	} else {
		// A rose curve r = cos(3.5 a) folded to seven petals.
		float petal = abs(cos(a * 3.5)) * 0.58;
		ink = max(ink, stroke(r - petal, 0.014 * lw, px) * step(r, 0.6));
		ink = max(ink, ring(r, 0.28, 0.010 * lw, px));
		// The vine: a wave winding between the two outer rings.
		float vine = 0.935 + 0.025 * sin(a * 18.0 - TIME * 1.5);
		ink = max(ink, stroke(r - vine, 0.009 * lw, px));
	}

	// Drawn outward from the centre as it is cast, with a bright leading edge.
	float shown = 1.0 - smoothstep(reveal * 1.1 - 0.06, reveal * 1.1, r);
	float edge = stroke(r - reveal * 1.1, 0.05 * lw, px) * step(reveal, 0.999);
	ink = ink * shown;

	float wash = (1.0 - smoothstep(0.85, 1.0, r)) * 0.16 * shown;
	// Lines in the colour itself, brightened toward white only by the flare - a white-hot
	// line at rest washes every dialect out to the same white.
	// Saturated before it is brightened: the tonemapper pulls a bright colour toward white,
	// and a green or blue circle that comes out white has lost the one thing it says.
	vec3 deep = max(mix(vec3(dot(tint, vec3(0.299, 0.587, 0.114))), tint, 1.7), vec3(0.0));
	vec3 hot = mix(deep, vec3(1.0), 0.05 + flare * 0.5);
	vec3 color = mix(deep * 0.2, hot * (glow + flare * 2.5), clamp(ink + edge, 0.0, 1.0));
	ALBEDO = color;
	ALPHA = clamp(max(ink + edge, wash), 0.0, 1.0) * fade * ground.w;
}
