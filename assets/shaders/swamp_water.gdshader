shader_type spatial;
// Swamp water: a flat, murky plane, as opposed to the clear lake water TerraBrush draws.
//
// TerraBrush has one water definition per terrain, so every lake on it shares one look -
// a swamp that needs to read differently cannot be painted with it. This is a separate
// plane instead, placed at a fixed height: wherever the terrain is sculpted below it is
// swamp. See scenes/environment/swamp.tscn.
//
// Lit, not unshaded: the scene's own light is what carries it through the Sky3D day and
// night cycle, the same way the terrain around it darkens.
//
// What makes it read as swamp rather than as dirty lake water:
//
//   MURK     nearly opaque within a short depth, so the bottom is never seen - the
//            opposite of the lake, which is all about seeing through.
//   ALGAE    slow drifting patches of duckweed on top, rough and flat, breaking up the
//            surface so it never reads as one sheet of glass.
//   DULL     low-contrast ripples and a high roughness; a swamp does not mirror the sky.
//   SOFT     the edge fades out over a few decimetres of depth, so where the plane cuts
//            into the terrain it becomes mud rather than a hard line.
//
// Patterns are sampled in world space, so scaling or moving the node never stretches
// them and two swamps side by side line up.
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D depth_texture : hint_depth_texture, filter_linear_mipmap;

// Water between the algae: shallow near the edge, deep further in.
uniform vec4 shallow_color : source_color = vec4(0.28, 0.26, 0.14, 1.0);
uniform vec4 deep_color : source_color = vec4(0.13, 0.13, 0.07, 1.0);
// Depth, in metres, over which the water goes from shallow to deep colour.
uniform float murk_depth = 0.8;

uniform vec4 algae_color : source_color = vec4(0.20, 0.24, 0.09, 1.0);
uniform sampler2D algae_noise : repeat_enable, filter_linear_mipmap;
// World metres per tile of the algae pattern.
uniform float algae_scale = 14.0;
// Drift of the algae across the surface, metres per second.
uniform vec2 algae_drift = vec2(0.015, 0.008);

uniform sampler2D ripple_normal : hint_normal, repeat_enable, filter_linear_mipmap;
uniform sampler2D ripple_normal_2 : hint_normal, repeat_enable, filter_linear_mipmap;
// World metres per tile of the ripple normal maps.
uniform float ripple_scale = 6.0;
uniform float ripple_speed = 0.02;
uniform float ripple_strength : hint_range(0.0, 1.0) = 0.25;

uniform float water_roughness : hint_range(0.0, 1.0) = 0.55;
uniform float algae_roughness : hint_range(0.0, 1.0) = 0.85;

// Depth, in metres, over which the edge fades into the terrain.
uniform float edge_fade = 0.35;

// Per swamp, set on the node under Instance Shader Parameters, so two swamps can share
// the one material and still differ.
instance uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
// How much of the surface is covered by algae, 0 (open water) to 1 (carpeted).
instance uniform float algae_amount : hint_range(0.0, 1.0) = 0.35;

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// How much water lies between this surface and the terrain behind it, in metres.
	// Forward+ (this project's renderer) keeps depth in [0, 1], so it goes straight in.
	float scene_depth = texture(depth_texture, SCREEN_UV).r;
	vec4 behind = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, scene_depth, 1.0);
	behind.xyz /= behind.w;
	float water_depth = max(VERTEX.z - behind.z, 0.0);

	vec2 xz = world_position.xz;

	// Algae: two octaves of the same noise, thresholded into patches. The second octave,
	// drifting the other way, frays the patch edges so they are not smooth blobs.
	vec2 drift = algae_drift * TIME;
	float coarse = texture(algae_noise, (xz + drift) / algae_scale).r;
	float fine = texture(algae_noise, (xz - drift * 1.7) / (algae_scale * 0.27)).r;
	float cover = coarse * 0.6 + fine * 0.4;
	float threshold = mix(0.85, 0.2, algae_amount);
	float algae = smoothstep(threshold, threshold + 0.16, cover);
	// Algae collects along the shore.
	algae = max(algae, (1.0 - smoothstep(0.0, edge_fade * 2.5, water_depth)) * algae_amount);

	float murk = smoothstep(0.0, murk_depth, water_depth);
	vec3 water = mix(shallow_color.rgb, deep_color.rgb, murk);
	vec3 color = mix(water, algae_color.rgb * (0.85 + fine * 0.3), algae);
	ALBEDO = color * tint.rgb;

	// Two ripple maps crossing each other, slowly. Flattened under the algae, which
	// floats on top and does not ripple.
	vec2 ripple_a = xz / ripple_scale + vec2(TIME * ripple_speed, 0.0);
	vec2 ripple_b = xz / (ripple_scale * 0.7) - vec2(0.0, TIME * ripple_speed * 0.8);
	// Combined in tangent space (whiteout blend), not by averaging the encoded colours,
	// which flattens both.
	vec3 n1 = texture(ripple_normal, ripple_a).rgb * 2.0 - 1.0;
	vec3 n2 = texture(ripple_normal_2, ripple_b).rgb * 2.0 - 1.0;
	NORMAL_MAP = normalize(vec3(n1.xy + n2.xy, n1.z * n2.z)) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = ripple_strength * (1.0 - algae);

	ROUGHNESS = mix(water_roughness, algae_roughness, algae);
	SPECULAR = mix(0.25, 0.15, algae);
	METALLIC = 0.0;

	ALPHA = smoothstep(0.0, edge_fade, water_depth) * tint.a;
}
