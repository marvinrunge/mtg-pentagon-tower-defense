shader_type spatial;
// PREMULTIPLIED alpha, not additive.
//
// Additive was the obvious choice and the wrong one: it can only ever ADD light to what is
// behind it, so over dark ground the ring blazed and against a bright sky it disappeared
// entirely - there is no headroom left to add to something already near-white. Premultiplied
// alpha lets one pass do both jobs: ALBEDO is light added on top, ALPHA is how much of the
// background is covered first. The band therefore darkens the sky slightly before it lights
// it, which is what makes it read on any background.
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float energy : hint_range(0.0, 8.0) = 2.5;
// Where the wave's leading edge currently is, 0 at the centre and 1 at the quad's rim.
// Tweened by the caller: this, not a scale animation, is what expands the ring - so the
// band stays the same THICKNESS as it travels instead of growing with it.
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float thickness : hint_range(0.01, 1.0) = 0.22;
// How much of the ring's own width trails behind the edge as a dimmer wash.
uniform float wake : hint_range(0.0, 1.0) = 0.45;
// How strongly the skirt around the band occludes what is behind it. This is the whole
// against-the-sky fix; at 0 the ring is additive again and vanishes over bright ground.
uniform float rim : hint_range(0.0, 1.0) = 0.4;

void fragment() {
	// 0 at the middle of the quad, 1 at the inscribed circle's rim.
	float dist = length(UV - vec2(0.5)) * 2.0;
	// Gone by the time it reaches the rim, so the quad's own square edge is never seen.
	float life = (1.0 - smoothstep(0.7, 1.0, progress)) * step(dist, 1.0);
	// The bright band itself, soft on both sides so nothing steps.
	float band = 1.0 - smoothstep(0.0, thickness, abs(dist - progress));
	// Brighter on the OUTSIDE of the band than the inside: an edge running away from the
	// centre, rather than a bubble inflating.
	float lead = smoothstep(progress - thickness, progress, dist);
	float glow = band * mix(wake, 1.0, lead) * life;
	// A wider, softer skirt that only ever OCCLUDES - it contributes no colour of its own.
	// Against a bright sky this is the shadow the bright band sits on; over dark ground it
	// is almost invisible, which is why the ring did not need it before.
	float skirt = (1.0 - smoothstep(0.0, thickness * 2.4, abs(dist - progress))) * life;
	ALBEDO = tint.rgb * energy * glow * tint.a;
	ALPHA = clamp(glow + skirt * rim, 0.0, 1.0) * tint.a;
}
