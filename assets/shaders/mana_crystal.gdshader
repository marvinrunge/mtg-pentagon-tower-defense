shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// The mana crystals: one colourless set of shapes (assets/generated/crystal-*), recoloured
// per biome here - docs/NATURE_ASSETS.md section 3a.
//
// Albedo is the white texture's brightness times the biome tint, so the facets and inner
// shading Meshy painted survive and only the hue changes. Emission is the tint again,
// strongest where the crystal is brightest, plus a fresnel rim - which is what keeps them
// readable on the near-black nights, where they are meant to be the light the player
// sees by.

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec3 tint : source_color = vec3(1.0);
// How strongly the crystal lights itself, from its brightest parts outward.
uniform float glow_strength : hint_range(0.0, 8.0) = 1.6;
// The edge light, facing away from the camera.
uniform float rim_strength : hint_range(0.0, 8.0) = 1.2;
uniform float rim_power : hint_range(0.5, 8.0) = 3.0;
// How far into the night it is, 0 by day to 1 at night - set every frame by DayNightPacing
// from the clock. By day the crystals are matte, like the base crystal, and barely light
// themselves: lit up in daylight they jumped out of every view. At night they glow fully,
// which is what they are there for.
global uniform float crystal_night;
uniform float day_glow : hint_range(0.0, 2.0) = 0.12;
uniform float night_glow : hint_range(0.0, 2.0) = 1.0;

void fragment() {
	vec3 white = texture(albedo_texture, UV).rgb;
	float brightness = dot(white, vec3(0.299, 0.587, 0.114));
	// A floor under the brightness so the shaded faces still carry the colour instead of
	// going grey.
	ALBEDO = tint * mix(0.25, 0.8, brightness);
	// The base crystal's own surface by day; glassier at night, when the glow carries them.
	ROUGHNESS = mix(0.35, 0.12, crystal_night);
	SPECULAR = 0.75;
	METALLIC = 0.0;
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float rim = pow(1.0 - facing, rim_power);
	EMISSION = tint * (brightness * brightness * glow_strength + rim * rim_strength)
		* mix(day_glow, night_glow, crystal_night);
}
