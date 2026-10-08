shader_type spatial;
// A front of force running out along the ground (SpellFx.shockwave) - projected onto the real
// surface (ground_projection.gdshaderinc), so it rolls over slopes and steps instead of
// cutting through them the way a flat quad did.
//
// Three layers, all keyed to the leading edge at `progress * radius`:
//   * the edge itself: a crisp bright line a fixed width in METRES, so a wide wave stays a
//     sharp front instead of growing into a fat glowing tube
//   * the wake: dust and energy dragged behind it, torn up by noise and streaked with
//     radial speed lines, thinning as the wave runs out of strength
//   * a dark band of pressed-down ground just inside the edge - pigment, not light - which
//     gives the bright line something to read against in daylight
//
// `arc_half` limits it to a sector around the node's -Z (its forward), for a push that goes
// one way; PI is the whole circle.
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_front, shadows_disabled, fog_disabled;

#include "res://assets/shaders/ground_projection.gdshaderinc"

uniform vec3 tint : source_color = vec3(1.0, 0.9, 0.6);
uniform float radius = 5.0;
uniform float progress = 0.0;
uniform float energy = 1.5;
uniform float fade = 1.0;
uniform float seed = 0.0;
// Width of the bright edge and length of the wake behind it, in metres.
uniform float edge_width = 0.25;
uniform float wake_length = 2.0;
uniform float arc_half = 3.14159265;
// How bright the edge line is. A gust keeps it low: its wall of air is the front, and a
// bright line under it outlived the wall and stayed behind as a long thin streak.
uniform float edge_strength = 1.0;

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
	for (int i = 0; i < 3; i++) {
		v += a * noise(p);
		p = p * 2.07 + vec2(5.3, 1.9);
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
	float r = length(p);
	float edge_r = progress * radius;
	if (r > edge_r + edge_width * 2.0) {
		discard;
	}
	// Angle round the centre measured from -Z, so the sector faces the node's forward.
	float a = atan(p.x, -p.y);
	float sector = arc_half >= 3.14 ? 1.0 : 1.0 - smoothstep(arc_half - 0.25, arc_half, abs(a));
	if (sector <= 0.0) {
		discard;
	}

	float d = r - edge_r;
	// The edge: bright and sharp, its width wavering a little round the ring.
	float waver = 0.75 + 0.5 * noise(vec2(a * radius * 0.9 + seed, progress * 3.0));
	float edge = 1.0 - smoothstep(0.0, edge_width * waver, abs(d + edge_width * 0.25));
	// Behind it: how far back into the wake this point is, 0 at the edge, 1 at its end.
	float back = clamp(-d / max(wake_length, 0.01), 0.0, 1.0);
	float in_wake = step(d, 0.0) * (1.0 - back);
	float torn = fbm(vec2(a * radius * 0.7, r * 1.3 - progress * 5.0) + vec2(seed));
	// Speed lines: thin radial streaks through the wake, dragged outward with it.
	float lines = smoothstep(0.55, 0.9, noise(vec2(a * 30.0 + seed, r * 0.2 - progress * 2.0)));
	float wake = pow(in_wake, 1.5) * (smoothstep(0.2, 0.65, torn + in_wake * 0.35) * 0.55 + lines * 0.9);
	// Pressed ground just inside the edge.
	float pressed = (1.0 - smoothstep(0.0, edge_width * 3.0, abs(d + edge_width * 2.2))) * step(d, 0.0);

	// Fades as it spends itself. The edge goes with the wake: kept bright to the end, the
	// last thing on screen was a hairline arc at full radius.
	float spent = 1.0 - smoothstep(0.55, 1.0, progress);
	// The first instant: the whole ground inside the front flashes.
	float flash = (1.0 - smoothstep(0.0, 0.2, progress)) * step(d, 0.0) * (1.0 - r / max(edge_r, 0.01)) * 0.8;
	float light = clamp(edge * edge_strength * spent + wake * 0.8 * spent + flash, 0.0, 1.0) * sector;
	float dark = pressed * 0.5 * spent * sector;

	vec3 deep = max(mix(vec3(dot(tint, vec3(0.299, 0.587, 0.114))), tint, 1.4), vec3(0.0));
	vec3 hot = mix(deep, vec3(1.0), edge * 0.2);
	vec3 dust = deep * 0.12;
	float total = max(light, dark);
	ALBEDO = mix(dust, hot * energy, light / max(light + dark * (1.0 - light), 0.001));
	ALPHA = clamp(total, 0.0, 1.0) * fade * ground.w;
}
