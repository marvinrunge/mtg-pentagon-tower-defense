shader_type spatial;
// Ground split open by an impact (SpellVisuals.ground_cracks): cracks running out from the
// point of impact, lit from inside, cooling while the scar lingers.
//
// Projected onto the real ground (ground_projection.gdshaderinc). The cracks are the edges
// of a Voronoi pattern, stretched along the radius so they run outward rather than forming
// cells, and thinned toward the rim. `spread` runs them out from the centre as the impact
// happens; `heat` is how brightly they still glow.
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_front, shadows_disabled, fog_disabled;

#include "res://assets/shaders/ground_projection.gdshaderinc"

uniform float radius = 3.0;
uniform float spread = 1.0;
uniform float heat = 1.0;
uniform float fade = 1.0;
uniform float seed = 0.0;
uniform vec3 scar_color : source_color = vec3(0.12, 0.09, 0.06);
uniform vec3 glow_color : source_color = vec3(0.55, 0.9, 0.45);
uniform float glow = 2.5;

vec2 hash2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

// Distance to the nearest Voronoi edge.
float voronoi_edge(vec2 x) {
	vec2 n = floor(x);
	vec2 f = fract(x);
	vec2 mg;
	vec2 mr;
	float md = 8.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 o = hash2(n + g + seed);
			vec2 r = g + o - f;
			float d = dot(r, r);
			if (d < md) {
				md = d;
				mr = r;
				mg = g;
			}
		}
	}
	md = 8.0;
	for (int j = -2; j <= 2; j++) {
		for (int i = -2; i <= 2; i++) {
			vec2 g = mg + vec2(float(i), float(j));
			vec2 o = hash2(n + g + seed);
			vec2 r = g + o - f;
			if (dot(mr - r, mr - r) > 0.00001) {
				md = min(md, dot(0.5 * (mr + r), normalize(r - mr)));
			}
		}
	}
	return md;
}

void fragment() {
	vec4 ground = project_to_ground(SCREEN_UV, INV_PROJECTION_MATRIX, INV_VIEW_MATRIX, MODEL_MATRIX);
	if (ground.w <= 0.0) {
		discard;
	}
	vec2 p = ground.xz;
	float r = length(p) / radius;
	if (r > 1.05) {
		discard;
	}
	// Polar coordinates stretched along the radius, so the cell edges run outward.
	float a = atan(p.y, p.x);
	vec2 q = vec2(a * 2.2, log(max(length(p), 0.05)) * 2.4);
	float e = voronoi_edge(q);
	float width = mix(0.09, 0.02, r);
	float crack = 1.0 - smoothstep(width * 0.5, width, e);
	// A crater of crushed ground in the middle.
	float crater = 1.0 - smoothstep(0.0, 0.22, r);
	float reach = 1.0 - smoothstep(spread - 0.08, spread, r);
	float rim = 1.0 - smoothstep(0.75, 1.0, r);
	float marks = max(crack * rim, crater * 0.8) * reach;

	float inner = crack * (1.0 - smoothstep(0.0, 0.8, r)) * reach;
	vec3 color = mix(scar_color, glow_color * glow, clamp(inner * heat + crater * heat * 0.4, 0.0, 1.0));
	ALBEDO = color;
	ALPHA = clamp(marks * 0.9 + crater * 0.25 * reach, 0.0, 1.0) * fade * ground.w;
}
