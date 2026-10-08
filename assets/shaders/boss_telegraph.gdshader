shader_type spatial;
// The boss telegraph (AttackIndicator), in every style.
//
// Projected onto the ground under it (see ground_projection.gdshaderinc): a box covers the
// zone, and everything else is worked out per pixel from where the real surface point sits in
// the SHAPE, in the indicator's own XZ plane (+Z is the facing):
//   d  how far inside the edge, in world units - drives the soft edge and the glowing rim
//   t  0..1 along the direction the fill travels - drives the fill front, which reaches
//      the far edge exactly when the hit lands, as the old growing fill did
//
// Styles:
//   0 classic the original look: a flat translucent zone and a brighter fill growing over it
//   1 rim     a glowing rim, a faint interior and a bright front sweeping through it
//   2 themed  the rim plus a pattern in the boss's colour that creeps in organically:
//             embers, frost, roots, runes or smoke
//   3 late    the rim style, invisible for the first half of the windup - read the
//             animation first, the ground only confirms it
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_front, shadows_disabled;

#include "res://assets/shaders/ground_projection.gdshaderinc"

uniform vec4 tint : source_color = vec4(1.0, 0.4, 0.1, 1.0);
// 0 circle, 1 cone, 2 ring, 3 line
uniform int shape = 0;
uniform float radius = 5.0;
uniform float inner_radius = 0.0;
uniform float half_angle = 3.1416;
uniform float line_length = 5.0;
uniform float line_width = 1.0;
uniform bool centered = false;
uniform float progress = 0.0;
uniform float flash = 0.0;
uniform float fade = 1.0;
uniform int style = 2;
// 0 none, 1 embers, 2 frost, 3 roots, 4 runes, 5 smoke
uniform int pattern = 0;

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
		p = p * 2.03 + vec2(17.1, 9.2);
		a *= 0.5;
	}
	return v;
}

// Distance to the nearest cell edge of a voronoi pattern - ice crystal facets.
float cell_edges(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float f1 = 8.0;
	float f2 = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = vec2(hash(i + g), hash(i + g + 31.7));
			float dist = length(g + o - f);
			if (dist < f1) { f2 = f1; f1 = dist; } else if (dist < f2) { f2 = dist; }
		}
	}
	return f2 - f1;
}

// x: distance inside the edge (world units), y: 0..1 along the fill direction.
vec2 shape_field(vec2 p) {
	float r = length(p);
	if (shape == 0) {
		return vec2(radius - r, r / max(radius, 0.001));
	} else if (shape == 1) {
		float ang = abs(atan(p.x, p.y));
		float side = r * sin(clamp(half_angle - ang, -1.5707, 1.5707));
		return vec2(min(radius - r, side), r / max(radius, 0.001));
	} else if (shape == 2) {
		return vec2(min(r - inner_radius, radius - r), (r - inner_radius) / max(radius - inner_radius, 0.001));
	}
	float hw = line_width * 0.5;
	float ends;
	float t;
	if (centered) {
		ends = line_length * 0.5 - abs(p.y);
		t = abs(p.y) / max(line_length * 0.5, 0.001);
	} else {
		ends = min(p.y, line_length - p.y);
		t = p.y / max(line_length, 0.001);
	}
	return vec2(min(hw - abs(p.x), ends), t);
}

// The pattern for this boss's colour, 0..1, plus the colour to draw it in.
vec4 themed(vec2 p, float t) {
	vec3 base = tint.rgb;
	if (pattern == 1) {
		// Embers: glowing cracks in a dark crust, slowly drifting.
		float n = fbm(p * 0.9 + vec2(0.0, TIME * 0.35));
		float cracks = 1.0 - smoothstep(0.0, 0.07, abs(n - 0.5));
		float flicker = 0.75 + 0.25 * sin(TIME * 9.0 + n * 20.0);
		vec3 hot = mix(vec3(1.0, 0.35, 0.05), vec3(1.0, 0.85, 0.35), cracks);
		return vec4(hot, cracks * flicker * 0.9 + n * 0.25);
	} else if (pattern == 2) {
		// Frost: crystal facets with bright edges.
		float e = cell_edges(p * 1.1);
		float lines = 1.0 - smoothstep(0.0, 0.08, e);
		float sheen = fbm(p * 0.6 + TIME * 0.05);
		return vec4(mix(base, vec3(0.92, 0.98, 1.0), lines), lines * 0.8 + sheen * 0.25);
	} else if (pattern == 3) {
		// Roots: dark veins threading through moss.
		vec2 warp = vec2(fbm(p * 0.5), fbm(p * 0.5 + 7.3)) * 3.0;
		float n = noise(p * 0.8 + warp);
		float veins = 1.0 - smoothstep(0.0, 0.06, abs(n - 0.5));
		float moss = fbm(p * 1.7) * 0.5;
		return vec4(mix(base * 0.8, vec3(0.75, 1.0, 0.45), veins), veins * 0.75 + moss * 0.35);
	} else if (pattern == 4) {
		// Runes: rings and spokes turning slowly, like a sigil being drawn.
		float r = length(p);
		float a = atan(p.x, p.y) + TIME * 0.25;
		float rings = smoothstep(0.82, 1.0, sin(r * 4.2));
		float spokes = smoothstep(0.93, 1.0, cos(a * 10.0)) * step(0.6, fract(r * 0.35));
		float marks = max(rings, spokes);
		return vec4(mix(base, vec3(1.0, 1.0, 0.85), marks), marks * 0.85 + 0.1);
	} else if (pattern == 5) {
		// Smoke: swirling, slow, dark with violet wisps.
		vec2 q = vec2(fbm(p * 0.45 + TIME * 0.12), fbm(p * 0.45 - TIME * 0.1 + 5.2));
		float n = fbm(p * 0.7 + q * 2.5);
		float wisps = smoothstep(0.45, 0.8, n);
		return vec4(mix(vec3(0.3, 0.1, 0.42), base * 1.4, wisps), 0.4 + wisps * 0.5);
	}
	return vec4(base, 0.25);
}

void fragment() {
	vec4 ground = project_to_ground(SCREEN_UV, INV_PROJECTION_MATRIX, INV_VIEW_MATRIX, MODEL_MATRIX);
	if (ground.w <= 0.0) {
		discard;
	}
	vec2 local_xz = ground.xz;
	vec2 field = shape_field(local_xz);
	float d = field.x;
	float t = clamp(field.y, 0.0, 1.0);
	float aa = fwidth(d) + 0.002;
	float inside = smoothstep(-aa, aa, d);
	if (inside <= 0.0) {
		discard;
	}

	vec3 color = tint.rgb;
	float alpha = 0.0;
	float glow = 1.0;
	if (style == 0) {
		// Classic: what the old two-mesh decal drew - a dim zone, a brighter fill growing
		// through it, brightening towards the hit.
		float grown = 1.0 - smoothstep(progress - 0.01, progress + 0.01, t);
		alpha = max(0.22, grown * 0.5);
		glow = mix(1.2, 2.4, progress);
	} else {
		float reveal = (style == 3) ? smoothstep(0.45, 0.7, progress) : smoothstep(0.0, 0.15, progress);
		float urgency = smoothstep(0.6, 1.0, progress);

		// A rim that tightens and brightens as the hit nears.
		float rim_width = mix(0.35, 0.16, urgency);
		float rim = 1.0 - smoothstep(0.0, rim_width, d);
		// The fill front: where t meets progress. Behind it the zone is "spent".
		float organic = (style == 2) ? (fbm(local_xz * 0.8) - 0.5) * 0.18 : 0.0;
		float front_t = progress + organic;
		float behind = 1.0 - smoothstep(front_t - 0.015, front_t + 0.015, t);
		float front = exp(-abs(t - front_t) * 45.0) * (progress < 0.999 ? 1.0 : 0.0);

		alpha = 0.06 + behind * 0.14;
		if (style == 2) {
			vec4 pat = themed(local_xz, t);
			color = mix(tint.rgb, pat.rgb, behind);
			alpha = 0.08 + behind * pat.a * 0.85;
		}
		alpha = max(alpha, rim * mix(0.55, 0.95, urgency));
		alpha = max(alpha, front * 0.85);
		color = mix(color, vec3(1.0), front * 0.35 + rim * urgency * 0.25);
		alpha *= reveal;
		glow = 1.0 + urgency * 0.6;
	}

	// The moment it lands: a bright flash over the whole zone.
	color = mix(color, vec3(1.0, 1.0, 0.95), flash * 0.5);
	alpha = max(alpha, flash * 0.7);

	ALBEDO = color * (glow + flash);
	ALPHA = clamp(alpha * inside * fade * ground.w, 0.0, 1.0);
}
