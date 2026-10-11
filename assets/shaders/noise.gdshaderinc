// The value noise every procedural effect shader shares (wells, ground zones, shockwaves,
// flames, ...). One copy, so a fix lands everywhere.
//
// Why integer maths: the old float hash, fract(p * vec2(123.34, 456.21)) and on, ran out of
// precision once p grew - a zone's random `seed` offset of up to 100, times the higher
// octaves, puts p in the thousands, where p * 456 keeps only a few bits after the point. A
// lattice corner is evaluated by all four cells that share it, and the GPU compiler is free
// to fuse `(i + 1.0) * 456.21` differently from `i * 456.21` in the neighbour - so the two
// cells disagreed on the corner and the noise jumped at every cell edge: hard-edged boxes
// across the surface. Hashing the corner as an int is exact at any distance.

// PCG (Jarzynski & Olano, "Hash Functions for GPU Rendering").
uint pcg_hash(uint v) {
	uint state = v * 747796405u + 2891336453u;
	uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
	return (word >> 22u) ^ word;
}

// 0..1 for a lattice cell.
float hash_cell(ivec2 cell) {
	return float(pcg_hash(uint(cell.x) + pcg_hash(uint(cell.y))) >> 8u) / 16777216.0;
}

// 0..1 for any point, constant over 1/64 steps - for per-cell randoms like hash(cell + seed).
// Rounded rather than bit-cast, so an ulp of rounding difference cannot change the result.
float hash(vec2 p) {
	return hash_cell(ivec2(round(p * 64.0)));
}

// Value noise, 0..1, smooth across cell edges.
float noise(vec2 p) {
	vec2 floor_p = floor(p);
	ivec2 i = ivec2(floor_p);
	vec2 f = p - floor_p;
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash_cell(i), hash_cell(i + ivec2(1, 0)), u.x),
		mix(hash_cell(i + ivec2(0, 1)), hash_cell(i + ivec2(1, 1)), u.x), u.y);
}

// Turns each fbm octave against the last (about 37 degrees), so the octaves' square lattices
// do not line up and stack into a visible grid.
const mat2 OCTAVE_TURN = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
