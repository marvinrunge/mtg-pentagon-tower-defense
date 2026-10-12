extends RefCounted
## Preloaded by path, never by a global class name - the same reason as
## tools/animation_impact.gd: a `--script` run does not rescan the project.
##
## Fits a tree's collision cylinder to its TRUNK, measured off the baked mesh.
##
## Why it is measured: the nature builder centres every mesh on its bounding box, and for a
## tree that box is the CANOPY. A windswept pine's crown streams off to one side, a willow's
## curtain hangs lopsided, a cypress stands on one buttress - so a cylinder at the origin
## stood up to three metres away from the trunk the player could see, and walked into
## nothing while passing through the bark.
##
## Only the bark counts (the surface whose material is named `*_bark`, which every tree out of
## tools/nature/blender/build_trees.py has), and only at the heights where something can
## actually walk into it - leaves hang to the ground on a willow, and branches spread wide
## above head height.
##
## The trunk is TRACKED upward rather than sampled at fixed heights: a median at the foot,
## then slice by slice, each slice taking only the bark near where the trunk was heading.
## Sampling two fixed bands was tried first and read a branch forking off at two metres as
## the trunk leaning 35 degrees towards it. Tracked, a fork is left behind the moment it
## grows away, and a line fitted through every slice gives the lean - which is real on the
## windswept pines, and followed, so a leaning trunk is covered along its length.

## Where tracking starts (the foot, roots and all) and how high it follows the trunk. The
## big trees are decimated hardest - a ring every metre on the landmarks - so when the foot
## band holds too little bark it is grown upward a step at a time until it holds enough.
const FOOT_BAND := Vector2(0.2, 0.8)
const FOOT_BAND_MAX_TOP := 2.0
const TRACK_TOP := 3.0
## Each slice is SLICE tall and the next starts STEP higher. The trunks are decimated to a
## ring every half metre or so, so a slice has to be tall enough to catch one.
const SLICE := 0.5
const STEP := 0.25
## A slice is searched within this many trunk radii of where the trunk was predicted to
## be, plus a margin for the prediction itself...
const TRACK_WINDOW_RADII := 1.5
const TRACK_WINDOW_MARGIN := 0.2
## ...then re-centred a few times on only what lies within a trunk's width of the current
## centre. A branch leaves the trunk at its surface, so the first, wider look always takes
## in the foot of a branch or two; re-centring tightly lets the ring - all the way round
## the trunk - outvote them. Without it a fir, whose branches start at the ground, was read
## as leaning 35 degrees.
const RECENTRE_PASSES := 3
const RECENTRE_WINDOW_RADII := 1.15
const RECENTRE_MIN_WINDOW := 0.25
## Fewer bark vertices than this at the foot and there is no trunk to speak of.
const MIN_FOOT_VERTICES := 4
## The steepest lean the cylinder follows. Past this a "lean" is far more likely a branch
## the tracking failed to leave behind than a trunk.
const MAX_LEAN_DEGREES := 35.0
## How far the trunk is tracked, as a share of the recipe's trunk length: past the end of
## the trunk there are only branches to follow. The olive's trunk is 1.8 m.
const TRUNK_LENGTH_TRACKED := 0.85
## The recipe-derived ceiling on lean. tools/nature/blender/build_trees.py tilts a trunk by
## its recipe `lean`, which a variant scales by 0.4-1.8 and shifts by up to 2 degrees
## (variant_recipe), and the windswept pine's wind `bias` bends it further every segment.
## A conifer grows straight up whatever its lean says (grow_conifer). Anything the tracking
## measures beyond that bound is a branch it followed, not the trunk.
const RECIPE_LEAN_SCALE := 1.8
const RECIPE_LEAN_SHIFT := 2.0
const CONIFER_MAX_LEAN := 2.0
## The cylinder's length along the trunk: most of the tree, but never far above what can
## touch it. A 16 m oak's trunk curves long before 10 m, and a straight cylinder that far
## up stands in the air beside it.
const HEIGHT_FRACTION := 0.6
const MIN_HEIGHT := 2.5
const MAX_HEIGHT := 5.0
## How far below the ground the cylinder starts, so a tree on a slope - set at the terrain
## height under its origin - has no gap under its uphill side.
const BELOW_GROUND := 0.5


## The cylinder and where it stands, for a tree mesh baked with its base on y = 0:
## {"shape": CylinderShape3D, "transform": Transform3D}. Empty when the mesh has no bark
## surface, which is what "not a tree" means here.
##
## `radius` is the manifest's trunk_radius_m, the trunk as it was designed; <= 0 measures
## it off the bark at the foot instead. `recipe` is the species recipe the tree was grown
## from (tools/nature/blender/species/<id>.json), which bounds how far to track and how
## much the trunk can lean; without one the generic limits apply.
static func fit(mesh: Mesh, radius: float = 0.0, recipe: Dictionary = {}) -> Dictionary:
	var bark: PackedVector3Array = _bark_vertices(mesh)
	if bark.is_empty():
		return {}
	var foot_top: float = FOOT_BAND.y
	var foot: Array[Vector2] = _points_between(bark, FOOT_BAND.x, foot_top)
	while foot.size() < MIN_FOOT_VERTICES and foot_top < FOOT_BAND_MAX_TOP:
		foot_top += STEP
		foot = _points_between(bark, FOOT_BAND.x, foot_top)
	if foot.size() < MIN_FOOT_VERTICES:
		return {}
	var foot_centre: Vector2 = _median(foot)
	if radius <= 0.0:
		radius = _typical_distance(foot, foot_centre)
	var window: float = radius * TRACK_WINDOW_RADII + TRACK_WINDOW_MARGIN
	var tight: float = maxf(radius * RECENTRE_WINDOW_RADII, RECENTRE_MIN_WINDOW)

	# [height, centre] of every slice the trunk was found in.
	var track: Array = [[(FOOT_BAND.x + foot_top) * 0.5, _recentre(foot, foot_centre, window, tight)]]
	var lean := Vector2.ZERO
	var y: float = foot_top + STEP
	var track_top: float = TRACK_TOP
	var trunk: Dictionary = recipe.get("trunk", {})
	if trunk.has("length"):
		track_top = minf(TRACK_TOP, float(trunk["length"]) * TRUNK_LENGTH_TRACKED)
	while y + SLICE * 0.5 <= track_top:
		var last: Array = track[-1]
		var predicted: Vector2 = (last[1] as Vector2) + lean * (y - float(last[0]))
		var near: Array[Vector2] = []
		for p: Vector2 in _points_between(bark, y - SLICE * 0.5, y + SLICE * 0.5):
			if p.distance_to(predicted) <= window:
				near.append(p)
		if near.size() >= 3:
			track.append([y, _recentre(near, predicted, window, tight)])
			lean = _fitted_lean(track)
		y += STEP

	var max_lean: float = tan(deg_to_rad(max_lean_degrees(recipe)))
	if lean.length() > max_lean:
		lean = lean.normalized() * max_lean
	# The fitted line through the track, evaluated at the ground.
	var mean_y: float = 0.0
	var mean_centre := Vector2.ZERO
	for entry: Array in track:
		mean_y += float(entry[0])
		mean_centre += entry[1]
	mean_y /= track.size()
	mean_centre /= track.size()
	var at_ground: Vector2 = mean_centre - lean * mean_y
	var base := Vector3(at_ground.x, 0.0, at_ground.y)
	var axis := Vector3(lean.x, 1.0, lean.y).normalized()

	var height: float = clampf(mesh.get_aabb().size.y * HEIGHT_FRACTION, MIN_HEIGHT, MAX_HEIGHT)
	var length: float = height + BELOW_GROUND
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = length
	# Y along the trunk; the cylinder's centre is half its length up the axis from where it
	# starts, BELOW_GROUND under the base.
	var start: Vector3 = base - axis * (BELOW_GROUND / axis.y)
	return {"shape": shape, "transform": Transform3D(_basis_with_up(axis), start + axis * length * 0.5)}


## The most a trunk grown from `recipe` can lean, in degrees. MAX_LEAN_DEGREES without one.
static func max_lean_degrees(recipe: Dictionary) -> float:
	if recipe.is_empty():
		return MAX_LEAN_DEGREES
	if String(recipe.get("form", "")) == "conifer":
		return CONIFER_MAX_LEAN
	var trunk: Dictionary = recipe.get("trunk", {})
	var degrees: float = absf(float(trunk.get("lean", 0.0))) * RECIPE_LEAN_SCALE + RECIPE_LEAN_SHIFT
	# The wind: every segment's direction gets `bias * bias_weight` added before it is
	# normalised, so over the trunk's segments it bends by about atan(that * segments).
	var bias: Array = recipe.get("bias", [])
	if bias.size() == 3:
		var push: float = Vector3(bias[0], bias[1], bias[2]).length() * float(trunk.get("bias_weight", 0.5))
		degrees += rad_to_deg(atan(push * float(trunk.get("segments", 1))))
	return minf(degrees, MAX_LEAN_DEGREES)


## Every vertex of the surfaces whose material is bark.
static func _bark_vertices(mesh: Mesh) -> PackedVector3Array:
	var out := PackedVector3Array()
	for surface in mesh.get_surface_count():
		var material: Material = mesh.surface_get_material(surface)
		if material == null or not material.resource_name.ends_with("_bark"):
			continue
		out.append_array(mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX])
	return out


static func _points_between(bark: PackedVector3Array, low: float, high: float) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for v: Vector3 in bark:
		if v.y >= low and v.y <= high:
			out.append(Vector2(v.x, v.z))
	return out


static func _median(points: Array[Vector2]) -> Vector2:
	var xs := PackedFloat32Array()
	var zs := PackedFloat32Array()
	for p: Vector2 in points:
		xs.append(p.x)
		zs.append(p.y)
	xs.sort()
	zs.sort()
	return Vector2(xs[xs.size() / 2], zs[zs.size() / 2])


## The mean of the points within `window` of `around` - a centre a stray root or branch
## cannot drag. `around` itself when none are.
static func _mean_near(points: Array[Vector2], around: Vector2, window: float) -> Vector2:
	var sum := Vector2.ZERO
	var count: int = 0
	for p: Vector2 in points:
		if p.distance_to(around) <= window:
			sum += p
			count += 1
	return sum / count if count > 0 else around


## The centre of the trunk in a slice: the mean within `wide` of the prediction, then
## re-centred on what lies within `tight` of that, RECENTRE_PASSES times.
static func _recentre(points: Array[Vector2], predicted: Vector2, wide: float, tight: float) -> Vector2:
	var centre: Vector2 = _mean_near(points, predicted, wide)
	for i in RECENTRE_PASSES:
		centre = _mean_near(points, centre, tight)
	return centre


## The trunk's radius when the manifest gives none: the median distance of the foot's bark
## from its centre.
static func _typical_distance(points: Array[Vector2], centre: Vector2) -> float:
	var distances := PackedFloat32Array()
	for p: Vector2 in points:
		distances.append(p.distance_to(centre))
	distances.sort()
	return maxf(distances[distances.size() / 2], 0.1)


## Least-squares slope of the tracked centres against height: metres sideways per metre up.
static func _fitted_lean(track: Array) -> Vector2:
	if track.size() < 2:
		return Vector2.ZERO
	var mean_y: float = 0.0
	var mean_centre := Vector2.ZERO
	for entry: Array in track:
		mean_y += float(entry[0])
		mean_centre += entry[1]
	mean_y /= track.size()
	mean_centre /= track.size()
	var numerator := Vector2.ZERO
	var denominator: float = 0.0
	for entry: Array in track:
		var dy: float = float(entry[0]) - mean_y
		numerator += ((entry[1] as Vector2) - mean_centre) * dy
		denominator += dy * dy
	return numerator / denominator if denominator > 0.0001 else Vector2.ZERO


static func _basis_with_up(up: Vector3) -> Basis:
	var side: Vector3 = Vector3.FORWARD.cross(up)
	if side.length() < 0.001:
		return Basis.IDENTITY
	side = side.normalized()
	# side x up, so the basis stays right-handed and the shape is not mirrored.
	return Basis(side, up, side.cross(up).normalized())
