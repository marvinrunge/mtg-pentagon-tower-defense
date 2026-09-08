shader_type spatial;
// Premultiplied, like the rest of the effect layer: the globe is a dome standing in the
// open, so most of its silhouette is against sky, where an additive shell washes out to
// nothing. See shockwave.gdshader.
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

// Ice, rather than the tinted balloon this used to be.
//
// Two things make it read as frost instead of as coloured glass:
//
//   FRESNEL   the shell is nearly clear looking straight through it and bright at grazing
//             angles, which is how any thin transparent surface behaves. A uniform alpha
//             over a sphere reads as a solid object painted light blue.
//   CRYSTALS  thin ridged veins across the surface, sampled TRIPLANAR from world space so
//             they neither pinch at the poles the way sphere UVs do nor swim when the
//             globe is scaled.

uniform vec4 tint : source_color = vec4(0.72, 0.92, 1.0, 1.0);
uniform float energy : hint_range(0.0, 6.0) = 1.6;
uniform sampler2D frost_noise : repeat_enable;
// World units per tile of the crystal pattern.
uniform float crystal_scale = 0.55;
// How thin the veins are. Higher is finer and more fern-like.
uniform float crystal_sharpness : hint_range(0.02, 0.5) = 0.09;
uniform float fresnel_power : hint_range(0.5, 8.0) = 2.6;
// The haze filling the shell between the veins - what stops it being a wireframe.
uniform float body : hint_range(0.0, 1.0) = 0.10;
uniform float fade : hint_range(0.0, 1.0) = 0.0;

varying vec3 world_position;
varying vec3 world_normal;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// One channel of ridged noise: the zero crossings of the field, which read as the thin
// bright lines frost actually grows in.
float veins(vec2 uv) {
	float n = texture(frost_noise, uv).r;
	return 1.0 - smoothstep(0.0, crystal_sharpness, abs(n - 0.5));
}

void fragment() {
	// Triplanar: three samples blended by how much each axis faces the camera-independent
	// world normal, so there is no seam and no pole.
	vec3 blend = abs(world_normal);
	blend /= max(blend.x + blend.y + blend.z, 0.001);
	vec3 uvw = world_position / max(crystal_scale, 0.001);
	float crystal = veins(uvw.yz) * blend.x + veins(uvw.xz) * blend.y + veins(uvw.xy) * blend.z;

	float fresnel = pow(1.0 - clamp(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0), fresnel_power);
	// The veins are deliberately a MINORITY of the surface. This is cover the player stands
	// behind and shoots out of, so a shell dense enough to be pretty is a shell they cannot
	// see through - the frost has to sit on glass, not replace it.
	float coverage = clamp(fresnel * 0.85 + crystal * 0.32 + body, 0.0, 1.0) * (1.0 - fade);
	ALBEDO = tint.rgb * energy * coverage;
	// Occludes a little more than it glows, so the dome dims what is behind it - cover the
	// player can actually see the edge of.
	ALPHA = clamp(coverage * 1.15, 0.0, 1.0) * tint.a;
}
