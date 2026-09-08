shader_type canvas_item;

// Rounds the corners of a TextureRect by masking its alpha, because a TextureRect has
// no corner_radius of its own and clip_children off the slot's StyleBoxFlat would also
// multiply the icon by that stylebox's translucent background.
//
// The radius is a FRACTION of the shorter side, not a pixel count: hotbar slots are
// square and sized from HOTBAR_SLOT_SIZE, so a ratio keeps the rounding proportional if
// that size ever changes.
uniform float radius_ratio : hint_range(0.0, 0.5) = 0.25;
uniform bool ignore_tint = false;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	// Signed distance to a rounded box in UV space, folded into one quadrant by abs().
	vec2 corner = abs(UV - vec2(0.5)) - (vec2(0.5) - vec2(radius_ratio));
	float dist = length(max(corner, vec2(0.0))) - radius_ratio;
	// fwidth() gives the edge one pixel of falloff, so the corners are not stair-stepped.
	tex.a *= 1.0 - smoothstep(0.0, fwidth(dist), dist);
	COLOR = tex * (ignore_tint ? vec4(1.0) : COLOR);
}
