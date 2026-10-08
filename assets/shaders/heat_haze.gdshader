shader_type spatial;
// Air shimmer (SpellFx.heat_haze, SpellFx.haze_wall): what is behind the surface, shifted by
// a drifting noise field - heat rising off fire, or the air a shockwave shoves ahead of it.
// It draws no colour of its own; where the mask is zero the offset is zero too, so the
// surface has no visible edge.
//
// Two shapes:
//   * billboard = true: a particle quad, masked to a soft disc and faded by the particle's
//     own colour alpha (its colour ramp), so a system of them reads as one rising column
//   * billboard = false: an arc wall from SpellFx._arc_wall_mesh, masked to a band up its
//     height and faded at the ends of a partial arc
//
// Drawn BEFORE the rest of the effect layer (a low render_priority): the screen texture is
// copied once, before transparent things are drawn, so haze drawn after a flame would paint
// the flame over with the undistorted ground behind it.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
// Largest shift, as a fraction of the screen, for a surface about four metres away; nearer
// shifts more, further less, so the shimmer keeps its size in the world.
uniform float strength = 0.012;
// Noise cells across the surface: higher is a finer, busier shimmer.
uniform float scale = 4.0;
// How fast the field drifts along `drift` (UV units per second).
uniform float speed = 1.2;
uniform vec2 drift = vec2(0.0, 1.0);
uniform float fade = 1.0;
uniform bool billboard = true;
// Partial arcs only (billboard = false): 1 for a full circle.
uniform float arc_fraction = 1.0;

varying float seed;

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

void vertex() {
	// Per particle (or per node) so neighbouring quads do not shimmer in step.
	seed = fract(dot(MODEL_MATRIX[3].xyz, vec3(0.173, 0.311, 0.257))) * 50.0;
	if (billboard) {
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
		MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
			vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
			vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
			vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
			vec4(0.0, 0.0, 0.0, 1.0));
		MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	}
}

void fragment() {
	float mask;
	if (billboard) {
		float r = length(UV - 0.5) * 2.0;
		mask = (1.0 - smoothstep(0.15, 1.0, r)) * COLOR.a;
	} else {
		float band = sin(clamp(UV.y, 0.0, 1.0) * 3.14159265);
		float ends = arc_fraction >= 0.999 ? 1.0 : smoothstep(0.0, 0.15, UV.x) * smoothstep(1.0, 0.85, UV.x);
		mask = band * band * ends;
	}
	mask *= fade;
	if (mask <= 0.002) {
		discard;
	}
	vec2 flow = drift * TIME * speed;
	vec2 p = UV * scale + vec2(seed, seed * 0.7);
	vec2 n = vec2(noise(p - flow), noise(p * 1.37 - flow * 1.3 + vec2(11.0, 3.0))) - 0.5;
	float near = clamp(4.0 / max(-VERTEX.z, 0.5), 0.15, 1.6);
	vec2 shift = n * 2.0 * strength * near * mask;
	ALBEDO = textureLod(screen_texture, SCREEN_UV + shift, 0.0).rgb;
	ALPHA = clamp(mask * 3.0, 0.0, 1.0);
}
