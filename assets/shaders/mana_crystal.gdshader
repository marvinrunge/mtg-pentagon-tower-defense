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

void fragment() {
	vec3 white = texture(albedo_texture, UV).rgb;
	float brightness = dot(white, vec3(0.299, 0.587, 0.114));
	// A floor under the brightness so the shaded faces still carry the colour instead of
	// going grey.
	ALBEDO = tint * mix(0.35, 1.0, brightness);
	ROUGHNESS = 0.12;
	SPECULAR = 0.75;
	METALLIC = 0.0;
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float rim = pow(1.0 - facing, rim_power);
	EMISSION = tint * (brightness * brightness * glow_strength + rim * rim_strength);
}
