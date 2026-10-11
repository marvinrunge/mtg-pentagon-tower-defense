shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// The magical surface in a mana well's basin - golden light-water, sea-water, violet ooze,
// lava or luminous sap, one material per well (scenes/mana_wells/*.tscn). The basins are
// modelled empty (docs/MANA_WELL_PROMPTS.md); this fills them, on the flat mesh
// tools/tests/fit_mana_wells.gd cut to each basin's shape.
//
// Procedural, no textures: a domain-warped noise that slowly turns round the centre, so the
// surface reads as stirring rather than as a scrolling texture. Bright veins where the noise
// folds over carry the light. With `crust` above 0 dark plates float on top and only the
// cracks between them glow - the lava.
//
// Opaque and lit, like the swamp water: the scene's own light carries it through the day,
// and its emission follows the same `crystal_night` clock as the crystals - a calm glint by
// day, the brightest thing at the well at night.
//
// Patterns run in the mesh's own space, which is metres round the well's centre.

uniform vec3 deep_color : source_color = vec3(0.05, 0.15, 0.35);
uniform vec3 bright_color : source_color = vec3(0.4, 0.85, 1.0);
// Pattern features per metre.
uniform float pattern_scale = 4.0;
// How fast the pattern stirs.
uniform float flow_speed = 0.05;
// Turn round the centre, radians per second.
uniform float swirl_speed = 0.06;
// How sharp and how strong the bright veins are.
uniform float vein_sharpness : hint_range(1.0, 16.0) = 6.0;
uniform float vein_strength : hint_range(0.0, 4.0) = 1.0;
// Dark plates on top: 0 for a liquid, towards 1 for lava. Their colour.
uniform float crust : hint_range(0.0, 1.0) = 0.0;
uniform vec3 crust_color : source_color = vec3(0.04, 0.02, 0.02);
// A liquid is glossy; crust is not.
uniform float liquid_roughness : hint_range(0.0, 1.0) = 0.06;
uniform float ripple_strength : hint_range(0.0, 1.0) = 0.3;
// See mana_crystal.gdshader: 0 by day, 1 at night, set by DayNightPacing.
global uniform float crystal_night;
uniform float day_glow : hint_range(0.0, 4.0) = 0.3;
uniform float night_glow : hint_range(0.0, 8.0) = 1.3;

varying vec2 v_xz;

void vertex() {
	v_xz = VERTEX.xz;
}

#include "res://assets/shaders/noise.gdshaderinc"

float fbm(vec2 p) {
	float sum = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		sum += noise(p) * amp;
		p = OCTAVE_TURN * p * 2.03 + vec2(1.7, 9.2);
		amp *= 0.5;
	}
	return sum;
}

// The stirring field at `p` (metres): warped once by itself, drifting with time.
float field(vec2 p, float t) {
	vec2 q = vec2(fbm(p + vec2(0.0, t)), fbm(p + vec2(5.2, 1.3) - vec2(t * 0.7, 0.0)));
	return fbm(p + 1.8 * q);
}

void fragment() {
	float t = TIME * flow_speed;
	float angle = TIME * swirl_speed;
	mat2 turn = mat2(vec2(cos(angle), sin(angle)), vec2(-sin(angle), cos(angle)));
	vec2 p = turn * v_xz * pattern_scale;

	float f = field(p, t);
	// Veins: where the field crosses its middle value, sharpened into thin bright lines.
	float vein = pow(1.0 - abs(f * 2.0 - 1.0), vein_sharpness);
	// Plates of crust where a second, slower field is high; the veins only glow between them.
	float plates = crust > 0.0 ? smoothstep(0.5 - crust * 0.25, 0.56 - crust * 0.25, fbm(p * 0.6 + vec2(3.1, 7.4) - t * 0.3)) : 0.0;

	vec3 liquid = mix(deep_color, bright_color, smoothstep(0.25, 0.85, f));
	ALBEDO = mix(liquid * 0.7, crust_color, plates);

	// Ripples from the field's own slope, flattened under the crust.
	float e = 0.04;
	float fx = field(p + vec2(e, 0.0), t) - f;
	float fz = field(p + vec2(0.0, e), t) - f;
	NORMAL_MAP = normalize(vec3(-fx / e * 0.15, -fz / e * 0.15, 1.0)) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = ripple_strength * (1.0 - plates);
	ROUGHNESS = mix(liquid_roughness, 0.85, plates);
	SPECULAR = 0.5;
	METALLIC = 0.0;

	float glow = mix(day_glow, night_glow, crystal_night);
	float light = (0.15 + 0.85 * smoothstep(0.35, 0.85, f)) * (1.0 - plates) + vein * vein_strength * (1.0 - plates * 0.85);
	EMISSION = bright_color * light * glow;
}
