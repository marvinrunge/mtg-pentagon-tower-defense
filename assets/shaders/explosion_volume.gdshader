shader_type spatial;
// The body of an explosion (ExplosionFx): a sphere that billows out of itself, burns from
// white-hot through orange to soot, and erodes away rather than fading flat.
//
// The sphere's surface is pushed out along its normal by 3D noise, so it reads as a churning
// mass, not a ball. `age` (0..1 over the fireball's life, driven from GDScript) moves the noise
// and drives everything else: how hot each part still is, and how much has burned through.
// Hot parts are pushed far above 1.0 so the game's bloom catches them; the smoke stays dim.
// The colours are source_color, so they are given in sRGB and darken when converted - which is
// why they look brighter here than the fire on screen.
render_mode unshaded, blend_mix, depth_draw_never, cull_back, shadows_disabled;

uniform float age = 0.0;
// Different per detonation, so two fireballs never billow the same way.
uniform float seed = 0.0;
// How far the surface is pushed out, as a share of the radius.
uniform float billow = 0.45;
uniform vec3 hot_color : source_color = vec3(1.0, 0.93, 0.7);
uniform vec3 fire_color : source_color = vec3(1.0, 0.62, 0.2);
uniform vec3 ember_color : source_color = vec3(0.72, 0.2, 0.06);
uniform vec3 smoke_color : source_color = vec3(0.2, 0.17, 0.15);
uniform float heat_boost = 6.0;

varying float v_billow;
varying vec3 v_local;

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), u.x),
			mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), u.x), u.y),
		mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), u.x),
			mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), u.x), u.y), u.z);
}

float fbm3(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise3(p);
		p = p * 2.02 + vec3(11.3, 7.1, 3.7);
		a *= 0.5;
	}
	return v;
}

void vertex() {
	// Churning: the field slides upward as the fireball ages, so lumps roll up its sides.
	vec3 p = NORMAL * 2.2 + vec3(seed, seed * 0.7, seed * 1.3) + vec3(0.0, -age * 2.4, 0.0);
	float n = fbm3(p);
	v_billow = n;
	VERTEX += NORMAL * (n - 0.45) * billow * 2.0;
	// Hot air rises: the whole mass drifts up and flattens a little as it cools.
	VERTEX.y += age * 0.35;
	VERTEX.y *= 1.0 - age * 0.15;
	v_local = VERTEX;
}

void fragment() {
	// Detail finer than the vertices can carry, in the same field so the two agree.
	float fine = fbm3(v_local * 3.1 + vec3(seed) + vec3(0.0, -age * 3.0, 0.0));
	float n = mix(v_billow, fine, 0.45);

	// Heat: everything starts white-hot and cools; the bulges (high n) stay hot longest, the
	// folds between them go to soot first - which is what gives it depth.
	// Cools fast at first and slower after: white-hot only for the first instant, orange
	// by a tenth of a second, embers and soot by half its life.
	float heat = clamp(1.05 - pow(age, 0.6) * 1.6 + (n - 0.5) * 1.4, 0.0, 1.0);
	vec3 color = mix(smoke_color, ember_color, smoothstep(0.05, 0.3, heat));
	color = mix(color, fire_color, smoothstep(0.3, 0.6, heat));
	color = mix(color, hot_color, smoothstep(0.72, 1.0, heat));
	float glow = mix(1.0, heat_boost, smoothstep(0.35, 1.0, heat));

	// Erosion: holes open where the field is lowest, earlier and wider as it ages - it burns
	// through and comes apart instead of turning transparent all at once.
	float burn = smoothstep(age * 1.15 - 0.1, age * 1.15 + 0.06, n + 0.08);
	// Soft silhouette: grazing angles thin out, so the sphere's outline never shows as a rim.
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float edge = smoothstep(0.0, 0.45, facing);
	float alpha = burn * edge * (1.0 - smoothstep(0.75, 1.0, age));

	ALBEDO = color * glow;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
