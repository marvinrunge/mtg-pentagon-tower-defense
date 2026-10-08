shader_type spatial;
// Fire Cone's jet (SpellVisuals.fire_stream): a cone of fire poured out of the hands, drawn on
// an open cone whose narrow end is at the caster. UV.y runs along it (0 at the hands), UV.x
// round it.
//
// Fire is made of tongues, not a gradient: a noise field streams down the cone fast, and only
// its upper part burns, so the jet breaks into licks that tear off and thin toward the end.
// Heat falls along the length and with the noise, through white-yellow at the hands, orange,
// red, to soot at the tips. Hot parts are pushed above 1.0 so the game's bloom catches them;
// the soot covers rather than adds, so the end of the jet darkens a bright sky.
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

// 0..1: the jet catching (0 -> 1) and guttering out (1 -> 0).
uniform float intensity = 1.0;
uniform float glow = 2.2;
// Overall opacity, for the soft outer layer.
uniform float density = 1.0;
uniform float seed = 0.0;
// Streaming speed, lengths per second.
uniform float speed = 2.2;
// How far along the jet the fire burns before it is all smoke - lower for the inner core.
uniform float reach = 1.0;
uniform vec3 hot_color : source_color = vec3(1.0, 0.9, 0.62);
uniform vec3 fire_color : source_color = vec3(1.0, 0.5, 0.12);
uniform vec3 ember_color : source_color = vec3(0.75, 0.14, 0.03);
uniform vec3 smoke_color : source_color = vec3(0.12, 0.07, 0.05);

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p = p * 2.03 + vec2(3.1, 7.7);
		a *= 0.5;
	}
	return v;
}

void fragment() {
	float along = UV.y;
	// Round the cone sampled on a circle, so there is no seam where UV.x wraps.
	float around = UV.x * 6.2831853;
	vec2 ring = vec2(cos(around), sin(around)) * 1.3;
	float t = TIME * speed;
	// The field streams outward and twists a little as it goes.
	vec2 q = vec2(ring.x * 2.0 + ring.y * 1.3, along * 4.0 - t * 3.0) + vec2(seed);
	// Warped by a second field, so the tongues curl and bulge instead of running as straight
	// streaks down the cone.
	q.x += (noise(vec2(along * 3.0 - t * 1.7, ring.y * 2.0 + seed)) - 0.5) * 2.4;
	float n = fbm(q);
	float licks = noise(vec2(ring.x * 3.0 - ring.y * 2.0 + along * 2.0, along * 9.0 - t * 7.0) + vec2(seed * 1.7));
	float field = n * 0.75 + licks * 0.35;

	// Burns from the hands outward; past `reach` the field only feeds smoke.
	float burn_line = reach * (1.05 - along * 0.85);
	float heat = clamp((field - (1.0 - burn_line)) * 2.4, 0.0, 1.0);
	// Tongues: the field has to be high enough to show at all, and less of it does further out.
	// Patchy even at the hands, so the start of the jet is licks of flame and not a solid wedge.
	float body = smoothstep(0.4 + along * 0.18, 0.66 + along * 0.15, field);
	// Densest where the camera looks into the jet, and gone at its silhouette - the cone's
	// own outline must never show as an edge.
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float depth = smoothstep(0.05, 0.55, facing);
	// Pinched at the hands, frayed at the tips.
	float ends = smoothstep(0.0, 0.06, along) * (1.0 - smoothstep(0.75, 1.0, along + (n - 0.5) * 0.3));
	float a = body * depth * ends * intensity * density;

	vec3 col = mix(smoke_color, ember_color, smoothstep(0.05, 0.3, heat));
	col = mix(col, fire_color, smoothstep(0.3, 0.6, heat));
	col = mix(col, mix(fire_color, hot_color, 0.45), smoothstep(0.75, 1.0, heat));
	// Hottest right at the hands - yellow, not white: a white jet reads as light, not fire.
	col = mix(col, hot_color, smoothstep(0.15, 0.0, along) * heat * 0.6);
	float boost = mix(1.0, glow, smoothstep(0.45, 1.0, heat));
	ALBEDO = col * boost * a;
	// Fire adds light; smoke covers.
	ALPHA = clamp(a * mix(0.75, 0.25, heat), 0.0, 1.0);
}
