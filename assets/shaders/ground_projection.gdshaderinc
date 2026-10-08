// Projects a ground mark onto whatever is actually under it - slopes, rocks, steps - instead
// of drawing it on a flat plane that the rising ground swallows.
//
// How: the mark is drawn on a box around its zone (back faces only, no depth test, so it is
// drawn even with the camera inside the box). Each pixel reads the depth buffer, rebuilds the
// world point of the opaque surface behind it, and moves that into the node's own space - so
// the shape maths can run on the real ground point's XZ exactly as it did on the flat plane.
// It is a decal done in the shader rather than with Godot's Decal node, because Decal draws
// nothing in the Compatibility renderer, which the options menu offers.
//
// Usage, in a spatial shader with
//   render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_front;
// include this, then in fragment():
//   vec4 ground = project_to_ground(SCREEN_UV, INV_PROJECTION_MATRIX, INV_VIEW_MATRIX, MODEL_MATRIX);
//   if (ground.w <= 0.0) { discard; }
//   ... ground.xz is the surface point in the node's local XZ ...
//   ALPHA *= ground.w;

uniform sampler2D projection_depth : hint_depth_texture, filter_nearest, repeat_disable;
// How far above and below the node's origin a surface still receives the mark, in metres.
// Below covers a slope falling away; above stops it climbing onto shoulders and treetops.
uniform float projection_up = 3.0;
uniform float projection_down = 6.0;
// Where the projection box sits inside the node that anchors the shape. The box is centred on
// the zone's footprint and its height band, the shape on its own origin; this puts the
// rebuilt point back in the anchor's space.
uniform vec3 projection_offset = vec3(0.0);

// xyz: the surface point in the node's local space. w: 0..1, how much the mark shows there -
// nothing outside the height band, on the sky, or on anything steeper than a steep slope
// (a wall, a standing stone, a character's legs).
vec4 project_to_ground(vec2 screen_uv, mat4 inv_projection, mat4 inv_view, mat4 model) {
	float depth = texture(projection_depth, screen_uv).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(screen_uv, depth) * 2.0 - 1.0;
#else
	vec3 ndc = vec3(screen_uv * 2.0 - 1.0, depth);
#endif
	vec4 view = inv_projection * vec4(ndc, 1.0);
	view.xyz /= view.w;
	vec3 world = (inv_view * vec4(view.xyz, 1.0)).xyz;

	// The node is only ever yawed, translated and uniformly scaled, so its inverse is a
	// projection onto each axis - no per-pixel matrix inverse needed.
	vec3 rel = world - model[3].xyz;
	vec3 ax = model[0].xyz;
	vec3 ay = model[1].xyz;
	vec3 az = model[2].xyz;
	vec3 local = vec3(dot(rel, ax) / dot(ax, ax), dot(rel, ay) / dot(ay, ay), dot(rel, az) / dot(az, az));
	local += projection_offset;

	vec3 normal = normalize(cross(dFdx(world), dFdy(world)));
	float flat_enough = smoothstep(0.35, 0.6, abs(normal.y));
	float height = local.y * length(ay);
	float band = smoothstep(-projection_down, -projection_down + 0.5, height)
		* (1.0 - smoothstep(projection_up - 0.5, projection_up, height));
	return vec4(local, flat_enough * band);
}
