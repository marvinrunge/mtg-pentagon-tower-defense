shader_type spatial;
// Premultiplied rather than additive - see shockwave.gdshader. It matters most here: the
// wall stands four metres tall, so the top half of it is almost always seen against the sky,
// where an additive curtain washed out to nothing.
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

// The hanging veil of Wall of Souls, replacing the flat additive rectangle it used to be.
//
// A wall the player must not cross has one job: say exactly WHERE the line is. So the bright
// part is the FOOT, where it meets the ground, and everything above it thins out and
// dissolves - the opposite of a solid quad, which is brightest in the middle and has a hard
// edge everywhere.

uniform vec4 tint : source_color = vec4(0.65, 0.25, 0.9, 1.0);
uniform float energy : hint_range(0.0, 8.0) = 2.0;
uniform sampler2D veil_noise : repeat_enable;
uniform float scroll_speed = 0.35;
// Half the curtain's height in object space, so the vertex stage can normalise against it
// rather than trusting UV.y, whose direction depends on how the mesh was generated.
uniform float half_height = 2.0;
// How much of the sky the veil actually blocks. Black is the colour that should EAT light
// rather than emit it, so this sits higher than the other two shaders use.
uniform float rim : hint_range(0.0, 1.0) = 0.6;
// 0 while the wall stands, 1 once it has gone. Driven by the wall's own life timer.
uniform float fade : hint_range(0.0, 1.0) = 0.0;

varying float height_ratio;

void vertex() {
	height_ratio = clamp((VERTEX.y + half_height) / max(half_height * 2.0, 0.001), 0.0, 1.0);
}

void fragment() {
	// Solid at the base, gone well before the top.
	float body = 1.0 - smoothstep(0.0, 1.0, pow(height_ratio, 0.75));
	// Soft ends, so the wall stops by thinning rather than by being cut off.
	float ends = smoothstep(0.0, 0.07, UV.x) * (1.0 - smoothstep(0.93, 1.0, UV.x));
	// Two noise samples rising at unrelated rates. One alone reads as a texture sliding
	// past; two beating against each other read as something moving inside the veil.
	float near = texture(veil_noise, UV * vec2(2.0, 1.0) + vec2(0.0, -TIME * scroll_speed)).r;
	float far = texture(veil_noise, UV * vec2(3.5, 1.7) + vec2(0.15, -TIME * scroll_speed * 1.7)).r;
	float veil = clamp(near * 0.7 + far * 0.55, 0.0, 1.0);
	// The line on the ground. The one part that is never dissolved away, because it is the
	// part that carries the information.
	float foot = pow(1.0 - smoothstep(0.0, 0.16, height_ratio), 2.0);
	float alive = ends * (1.0 - fade) * tint.a;
	float glow = clamp(body * veil * 0.8 + foot * 0.9, 0.0, 1.0) * alive;
	// The veil occludes over its whole body, not only where it is bright: a curtain of
	// souls should dim what is behind it even in the gaps between the bright wisps.
	float occlusion = clamp(glow + body * mix(0.35, 1.0, veil) * rim, 0.0, 1.0) * alive;
	ALBEDO = tint.rgb * energy * glow;
	ALPHA = occlusion;
}
