// Leaf cards of the procedural trees (tools/nature/blender/build_trees.py).
// tools/build_nature_terrabrush.gd swaps this in for every alpha-cut leaf material it
// finds in a tree GLB.
//
// Three things the imported StandardMaterial3D cannot do:
//  - Back faces keep their normal. The cards carry normals bent outward from the crown,
//    so the canopy lights as one volume; with culling off Godot flips NORMAL on back
//    faces, which turns half the crown black (the same bug as the grass cards, see
//    assets/shaders/nature_foliage.gdshader).
//  - Wind. COLOR.r is the wind weight the generator bakes: 0 at the trunk base, 1 at the
//    leaf tips. Squared, so the trunk stays put and the outer crown moves most.
//  - Light through the leaves (BACKLIGHT), so a crown against the sun glows a little
//    instead of turning into a flat dark shape.
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic;
uniform vec3 albedo_tint : source_color = vec3(1.0);
// Same cut as the foliage cards and tools/alpha_key.gd.
uniform float alpha_scissor = 0.3;
uniform float wind_strength = 0.08;
uniform float wind_speed = 1.1;
uniform float translucency = 0.3;

void vertex() {
	float weight = COLOR.r * COLOR.r;
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float phase = TIME * wind_speed + dot(world.xz, vec2(0.11, 0.17));
	VERTEX.x += sin(phase) * wind_strength * weight;
	VERTEX.z += cos(phase * 0.83) * wind_strength * 0.7 * weight;
	VERTEX.y += sin(phase * 1.7) * wind_strength * 0.25 * weight;
}

void fragment() {
	vec4 texel = texture(albedo_texture, UV);
	ALBEDO = texel.rgb * albedo_tint;
	ALPHA = texel.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_scissor;
	ROUGHNESS = 0.8;
	SPECULAR = 0.3;
	BACKLIGHT = texel.rgb * translucency;
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
}
