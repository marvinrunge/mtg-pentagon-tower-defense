shader_type spatial;
// A column of light (SpellVisuals.light_pillar): Wrath of God's shaft from the sky, the glow
// a revived ally stands in, the core of a lightning strike.
//
// Drawn on an open cylinder. Brightest where the surface faces the camera - the middle of the
// column - and soft at its silhouette, so it reads as a volume of light rather than as a tube.
// Streaks scroll along it so the light is visibly pouring, and it is thinned at both ends so
// the top never shows as an edge against the sky.
//
// Premultiplied: covers what is behind it a little AND adds light, so it survives a bright
// noon sky as well as a black night (see SpellFx.premul_particle_mesh).
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec3 tint : source_color = vec3(1.0, 0.92, 0.6);
uniform float glow = 1.4;
uniform float fade = 1.0;
// How much of it covers rather than adds: 0 is pure light, 1 is opaque.
uniform float cover = 0.12;
// Streaks run down (negative) or up (positive), in heights per second.
uniform float flow = -1.6;
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
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float core = pow(facing, 3.0);
	// Streaks: noise stretched along the column and scrolling along it. UV.x runs round the
	// cylinder - wrapped by sampling it on a circle so there is no seam.
	float around = UV.x * 6.2831853;
	vec2 sp = vec2(cos(around), sin(around)) * 1.6 + vec2(seed);
	float streak = noise(vec2(sp.x * 3.0 + sp.y * 2.0, UV.y * 3.0 + TIME * flow));
	streak = smoothstep(0.35, 0.9, streak);
	float ends = smoothstep(0.0, 0.12, UV.y) * smoothstep(1.0, 0.75, UV.y);
	float a = (core * 0.45 + streak * core * 0.55) * ends * fade;
	vec3 deep = max(mix(vec3(dot(tint, vec3(0.299, 0.587, 0.114))), tint, 1.5), vec3(0.0));
	vec3 hot = mix(deep, vec3(1.0), core * 0.25);
	ALBEDO = hot * glow * a;
	ALPHA = clamp(a * cover, 0.0, 1.0);
}
