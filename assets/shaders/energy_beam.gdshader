shader_type spatial;
// See shockwave.gdshader for why this is premultiplied rather than additive: a beam that can
// only add light is invisible against a bright sky, and Lightning Bolt comes down out of one.
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

// A shaft of light on a quad: bright core across its width, tapered at both ends.
//
// Replaces drawing beams as emissive CYLINDERS, which have a visible silhouette and a hard
// cap at each end - the two things that made every beam in the game read as a coloured pipe.
// Callers cross two of these at right angles so the beam holds up from any angle without
// needing to billboard.

uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float energy : hint_range(0.0, 12.0) = 4.0;
// How tightly the light is packed into the middle. Higher is a thinner, hotter line.
uniform float core : hint_range(1.0, 12.0) = 3.5;
// The darker sheath around that core, in the same units. Lower than `core`, so it is always
// wider than the light it surrounds - that difference is the whole effect.
uniform float sheath : hint_range(0.2, 6.0) = 1.2;
uniform float rim : hint_range(0.0, 1.0) = 0.45;
// 0 while the beam is up, 1 once it has faded. Tweened by the caller.
uniform float fade : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	// Across the beam.
	float across = abs(UV.y - 0.5) * 2.0;
	float body = pow(clamp(1.0 - across, 0.0, 1.0), core);
	float halo = pow(clamp(1.0 - across, 0.0, 1.0), sheath);
	// Along it: eased in at the origin and out at the far end, so neither end is a cut.
	float along = smoothstep(0.0, 0.06, UV.x) * (1.0 - smoothstep(0.7, 1.0, UV.x));
	float alive = along * (1.0 - fade) * tint.a;
	ALBEDO = tint.rgb * energy * body * alive;
	ALPHA = clamp(body + halo * rim, 0.0, 1.0) * alive;
}
