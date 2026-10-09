shader_type particles;
// Embers rising off a fire (EmberFx.build_rising_sparks): let go near the ground, carried
// up by the heat and swirling on the way - slow loops with a fast nervous jitter on top,
// every spark on a path of its own.
//
// Not ParticleProcessMaterial: its turbulence re-aims the stored velocity a fraction every
// step, which throws the climb away along with it - the sparks ended up hovering. Here the
// climb and the swirl are separate terms, so a spark can loop as hard as it likes and still
// rise, and neither depends on the frame rate.
//
// Each spark's TRANSFORM points its Y along its travel, scaled, which is what
// ember_spark_streak.gdshader draws it from.

uniform float emission_radius = 4.0;
uniform float emission_height = 0.3;
// Upward speed, m/s, picked per spark.
uniform float rise_min = 0.7;
uniform float rise_max = 1.5;
// Sideways speed of the slow loops, and how fast they turn.
uniform float swirl_speed = 0.9;
uniform float swirl_rate = 2.2;
// The fast flutter on top of the loops.
uniform float jitter_speed = 0.35;
uniform float jitter_rate = 11.0;
// Shortest life, as a fraction of LIFETIME.
uniform float life_min = 0.55;
uniform float scale_min = 0.7;
uniform float scale_max = 1.3;

float rand_from_seed(inout uint seed) {
	int k;
	int s = int(seed);
	if (s == 0) {
		s = 305420679;
	}
	k = s / 127773;
	s = 16807 * (s - k * 127773) - 2836 * k;
	if (s < 0) {
		s += 2147483647;
	}
	seed = uint(s);
	return float(seed % uint(65536)) / 65535.0;
}

uint hash(uint x) {
	x = ((x >> uint(16)) ^ x) * uint(73244475);
	x = ((x >> uint(16)) ^ x) * uint(73244475);
	x = (x >> uint(16)) ^ x;
	return x;
}

// White-yellow when it leaves the fire, orange, then a dull red that goes out.
vec4 ember_color(float age) {
	vec3 hot = vec3(1.0, 0.86, 0.55);
	vec3 orange = vec3(1.0, 0.5, 0.12);
	vec3 red = vec3(0.75, 0.15, 0.03);
	vec3 rgb = age < 0.25 ? mix(hot, orange, age / 0.25) : mix(orange, red, (age - 0.25) / 0.75);
	float alpha = smoothstep(0.0, 0.05, age) * (1.0 - smoothstep(0.65, 1.0, age));
	return vec4(rgb, alpha);
}

void start() {
	uint seed = hash(NUMBER + uint(1) + RANDOM_SEED);
	if (RESTART_POSITION) {
		// Even over the disc, not bunched at its centre.
		float angle = rand_from_seed(seed) * TAU;
		float dist = sqrt(rand_from_seed(seed)) * emission_radius;
		vec3 local = vec3(cos(angle) * dist, rand_from_seed(seed) * emission_height, sin(angle) * dist);
		TRANSFORM = mat4(1.0);
		TRANSFORM[3].xyz = (EMISSION_TRANSFORM * vec4(local, 1.0)).xyz;
	}
	if (RESTART_CUSTOM) {
		// x: a phase of its own for the swirl, y: age (0..1), z: rise speed, w: life factor.
		CUSTOM = vec4(rand_from_seed(seed) * 100.0, 0.0,
			mix(rise_min, rise_max, rand_from_seed(seed)),
			mix(life_min, 1.0, rand_from_seed(seed)));
		USERDATA1 = vec4(mix(scale_min, scale_max, rand_from_seed(seed)), rand_from_seed(seed), 0.0, 0.0);
	}
	VELOCITY = vec3(0.0, CUSTOM.z, 0.0);
	COLOR = ember_color(0.0);
}

void process() {
	CUSTOM.y += DELTA / max(LIFETIME * CUSTOM.w, 0.001);
	if (CUSTOM.y >= 1.0) {
		ACTIVE = false;
	}
	float age = clamp(CUSTOM.y, 0.0, 1.0);
	float ph = CUSTOM.x;
	float t = TIME;
	vec3 p = TRANSFORM[3].xyz;

	// Slow loops, driven by where the spark is as well as by time, so neighbours drift
	// apart instead of swaying in step.
	vec3 swirl = vec3(
		sin(t * swirl_rate + ph + p.y * 1.7) + 0.5 * sin(t * swirl_rate * 1.73 + ph * 2.3 + p.z * 2.1),
		0.0,
		cos(t * swirl_rate * 0.87 + ph * 1.7 + p.y * 1.9) + 0.5 * cos(t * swirl_rate * 1.41 + ph * 3.1 + p.x * 2.3));
	// The flutter: much faster and smaller, in all three axes.
	vec3 jitter = vec3(
		sin(t * jitter_rate + ph * 5.0),
		sin(t * jitter_rate * 1.31 + ph * 7.0),
		cos(t * jitter_rate * 0.89 + ph * 3.0));
	// Fastest just off the fire, slowing as it cools.
	float rise = CUSTOM.z * (1.25 - 0.55 * age);
	VELOCITY = vec3(0.0, rise, 0.0) + swirl * swirl_speed + jitter * jitter_speed;

	// Y along the travel, so the streak shader can stretch it the way it moves.
	vec3 dir = normalize(VELOCITY + vec3(0.0, 0.0001, 0.0));
	vec3 helper = abs(dir.y) < 0.99 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
	vec3 x_axis = normalize(cross(helper, dir));
	vec3 z_axis = cross(x_axis, dir);
	// A fast uneven flicker in brightness, the way a real ember glints as it turns.
	float flicker = 0.7 + 0.3 * sin(t * 23.0 + ph * 11.0) * sin(t * 17.0 + ph * 3.0);
	float s = USERDATA1.x * (1.0 - 0.4 * age);
	TRANSFORM[0].xyz = x_axis * s;
	TRANSFORM[1].xyz = dir * s;
	TRANSFORM[2].xyz = z_axis * s;
	vec4 col = ember_color(age);
	COLOR = vec4(col.rgb, col.a * flicker);
}
