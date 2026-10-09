shader_type spatial;
// One tiny ember, drawn as a short glowing streak along the way it is moving - the motion
// blur a real spark leaves on the eye - facing the camera around that axis.
//
// The point of a shader rather than a billboard is the size. A real spark is far smaller
// than a pixel a few metres away, and a quad that small is simply skipped by the rasteriser
// on most frames: it blinks in and out, which reads as cheap, not as fine. So the streak is
// never drawn thinner or shorter than `min_pixels`, and whatever it is widened by comes off
// its brightness instead. A distant spark becomes a faint steady point of light rather than
// a flickering one, and the same total light reaches the screen either way.
//
// Expects a 1 x 1 QuadMesh, and a particle TRANSFORM whose Y runs along the travel
// (ember_sparks.gdshader sets one up).
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

// World size at particle scale 1.
uniform float width = 0.018;
uniform float streak_length = 0.075;
uniform float min_pixels = 1.5;
// Above 1 so the core blooms where glow is on.
uniform float energy = 2.4;

varying float coverage;

void vertex() {
	vec3 center = (VIEW_MATRIX * vec4(MODEL_MATRIX[3].xyz, 1.0)).xyz;
	vec3 axis_world = MODEL_MATRIX[1].xyz;
	float scale = max(length(axis_world), 0.0001);
	vec3 axis = normalize((VIEW_MATRIX * vec4(axis_world / scale, 0.0)).xyz);
	// Across the streak, perpendicular to both its axis and the line of sight.
	vec3 side = cross(axis, center);
	side = length(side) > 0.00001 ? normalize(side) : vec3(1.0, 0.0, 0.0);

	// One pixel's size in metres at this depth.
	float depth = max(-center.z, 0.01);
	float pixel = 2.0 * depth / (PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y);
	float w = width * scale;
	float l = streak_length * scale;
	float w_drawn = max(w, pixel * min_pixels);
	float l_drawn = max(l, pixel * min_pixels);
	coverage = (w * l) / (w_drawn * l_drawn);

	vec3 pos = center + side * VERTEX.x * w_drawn + axis * VERTEX.y * l_drawn;
	POSITION = PROJECTION_MATRIX * vec4(pos, 1.0);
}

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	// Soft across, fading out at both ends - a smear of light, not a hard-edged rod.
	float across = exp(-uv.x * uv.x * 3.5);
	float along = 1.0 - smoothstep(0.35, 1.0, abs(uv.y));
	float a = clamp(across * along * COLOR.a * coverage, 0.0, 1.0);
	ALBEDO = COLOR.rgb * energy * a;
	ALPHA = a;
}
