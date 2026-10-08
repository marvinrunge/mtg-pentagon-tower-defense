shader_type spatial;
// The air a shockwave shoves ahead of it (SpellFx.shockwave, SpellFx.gust): a low wall riding
// on the ground edge of the wave, bright at its foot and thinning upward into nothing, with
// streaks of moving air running through it.
//
// Drawn on an open arc of wall built by SpellFx._arc_wall_mesh: UV.x runs along the arc
// (0..1), UV.y up the wall (0 at the foot). A partial arc fades out at both ends.
// Premultiplied like the rest of the effect layer, so it reads against a bright sky.
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec3 tint : source_color = vec3(1.0, 0.9, 0.6);
uniform float energy = 2.0;
uniform float fade = 1.0;
uniform float seed = 0.0;
// 1 for a full circle (no end fade); smaller for an arc.
uniform float arc_fraction = 1.0;
// How many streak cells run round the arc - scaled with the wave's size by the caller.
uniform float streak_cells = 40.0;
// Streaks run along the arc (blown sideways) at this speed, and climb at `rise`.
uniform float rise = 2.5;

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
	float v = UV.y;
	// Bright at the foot, gone by the top - and the very top edge torn by noise.
	float n = noise(vec2(UV.x * streak_cells + seed, v * 3.0 - TIME * rise));
	float top = 1.0 - smoothstep(0.35 + n * 0.4, 0.95, v);
	float foot = smoothstep(0.0, 0.06, v);
	float column = pow(1.0 - v, 1.4);
	float streak = smoothstep(0.45, 0.95, noise(vec2(UV.x * streak_cells * 2.5 + seed * 3.0, v * 1.2 - TIME * rise * 1.6)));
	float ends = arc_fraction >= 0.999 ? 1.0 : smoothstep(0.0, 0.18, UV.x) * smoothstep(1.0, 0.82, UV.x);
	// Seen edge-on the wall is denser; face-on it is thin air.
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float depth = mix(1.0, 0.45, facing);
	float a = (column * 0.7 + streak * column * 0.9) * top * foot * ends * depth * fade;
	vec3 deep = max(mix(vec3(dot(tint, vec3(0.299, 0.587, 0.114))), tint, 1.3), vec3(0.0));
	vec3 col = mix(deep, vec3(1.0), column * 0.3);
	ALBEDO = col * energy * a;
	ALPHA = clamp(a * 0.35, 0.0, 1.0);
}
