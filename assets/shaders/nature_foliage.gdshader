// TerraBrush's own foliage shader, with one change: the alpha-scissor threshold.
//
// TerraBrush cuts foliage at alpha 0.01, i.e. almost any non-zero pixel draws as solid.
// The cards are keyed by tools/alpha_key.gd so that the antialiased halo sits BELOW
// 0.3 (its SCISSOR_THRESHOLD) - at 0.01 that whole halo would draw, as an opaque pale
// outline round every leaf. The two numbers must match; change them together.
//
// Assigned as `customShader` on every nature FoliageDefinitionResource by
// tools/build_nature_terrabrush.gd. Lives outside addons/terrabrush, so an addon
// update cannot overwrite it - but if TerraBrush renames calculateFoliageVertex/
// calculateFoliageFragment, this needs the same rename.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx, alpha_to_coverage;

#include "res://addons/terrabrush/Resources/Shaders/foliage_multimesh_shader_include.gdshaderinc"

const float SCISSOR_THRESHOLD = 0.3;

varying flat vec3 _instancePosition;

void vertex() {
	_instancePosition = vec3(0);
	calculateFoliageVertex(
		INSTANCE_ID,
		VERTEX,
		NORMAL,
		COLOR,
		_instancePosition
	);
}

void fragment() {
	calculateFoliageFragment(
		UV,
		COLOR,
		_instancePosition,
		ALBEDO,
		ALPHA,
		ALPHA_SCISSOR_THRESHOLD,
		ALPHA_ANTIALIASING_EDGE
	);
	ALPHA_SCISSOR_THRESHOLD = SCISSOR_THRESHOLD;
	// The cards' normals point straight up (see _cross_quad in
	// tools/build_nature_terrabrush.gd), so they light like the ground. With culling
	// off Godot flips NORMAL on back faces - which turns "up" into "down" and draws the
	// far side of every card black. Undo the flip.
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
}
