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

// Every foliage layer runs the same 1 m grid, and TerraBrush derives both the jitter
// (the shared noise texture) and the yaw (a hash of the grid point) from the grid point
// alone - so two layers painted on the same spot put their cards in exactly the same
// planes and z-fight. Each layer turns and shifts its card in mesh space first, which
// survives TerraBrush's own rotation. Set per layer by tools/build_nature_terrabrush.gd;
// the yaws must differ mod 90 degrees (the card is a cross).
uniform float LayerYawDegrees = 0.0;
uniform vec2 LayerOffset = vec2(0.0);

varying flat vec3 _instancePosition;

void vertex() {
	VERTEX = VERTEX * rotateY(radians(LayerYawDegrees));
	VERTEX.xz += LayerOffset;
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
