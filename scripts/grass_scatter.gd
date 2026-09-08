extends Node3D
class_name GrassScatter
## Scatters one biome's four grass billboards across a lane wedge, as MultiMeshes.
##
## Built at runtime rather than committed as scene data: 5 lanes x 4 variants x 4
## depth bands is 80 MultiMeshInstance3D nodes and several thousand transforms, which
## is a lot of .tscn to hand-maintain for something fully derivable from a seed. The
## seed is per-lane, so a lane looks the same every run.
##
## Geometry comes from the lane wedge in scenes/misc/main.tscn: the pentagon base has
## a circumradius of 50, so each lane's inner edge sits at its apothem, 50*cos(36) =
## 40.45, and the wedge runs 144 further out. The wedge sides follow the +/-36 degree
## rays from the arena centre, which is why half-width at any depth is just
## depth * tan(36).
##
## Grass carries no collision. It is set dressing the player and enemies walk through,
## and adding bodies for it would mean re-baking NavigationRegion3D for no gain.

## Lane-local depth of the wedge's inner and outer edges. Negative in Z because lanes
## are built looking down -Z, and the lane node's own rotation puts each one in place.
const INNER_DEPTH := 40.4508
const OUTER_DEPTH := 184.4508

## tan(36 degrees) - half the wedge's angular width, as a slope on depth.
const WEDGE_SLOPE := 0.726543

## Depth bands the scatter is split into. Each band is its own set of MultiMeshes
## positioned at the band's centre, so Godot's visibility range can cull the far end
## of a 144 m lane instead of keeping every tuft resident because one shared AABB
## covers the whole wedge.
const BAND_COUNT := 4

## Beyond this distance from the camera a band stops drawing, with FADE_MARGIN of
## dithered fade before it. Tufts are ~1.5 m; drawing them 150 m down the lane is
## spend with nothing to show for it.
const VISIBILITY_END := 85.0
const FADE_MARGIN := 12.0

## Alpha below this is cut away outright. Scissor rather than blend: blended grass
## needs back-to-front sorting that MultiMesh will not do, and sorting artefacts read
## far worse than a slightly hard blade edge.
##
## Kept low deliberately. Mipmapping averages a tuft's alpha down as it recedes, so a
## threshold up near half erodes distant grass away a mip level at a time.
const ALPHA_SCISSOR := 0.3

## Intersecting planes per tuft. Three at 60 degrees apart reads as a solid clump from
## any angle, which a single billboarded quad never quite does. It is also the main
## cost knob in here - every plane is another alpha-scissor quad's worth of overdraw,
## so drop to 2 before reducing cluster counts if a lane needs to get cheaper.
const PLANE_COUNT := 3

## Baked ambient occlusion, as a shade multiplied into the tuft's base vertices.
##
## Cheaper and better behaved than SSAO here. Screen-space AO on thin alpha-tested
## foliage halos against the sky and crawls as the camera moves, and it costs a
## full-screen pass; this costs two extra vertex rows per plane and nothing at all per
## frame. It only has to sell one thing - that the clump grows out of the ground
## rather than resting on it - and a darkened base does that on its own.
##
## AO_MID_HEIGHT keeps the falloff near the ground. Spread linearly over the whole
## tuft it reads as dirty grass rather than as contact shade.
const AO_BASE_SHADE := 0.45
const AO_MID_SHADE := 0.82
const AO_MID_HEIGHT := 0.3

## Used only when the ground raycast finds nothing. The lane wedges are 0.5 m thick
## slabs sitting on y = 0, so their walkable surface is at 0.5 - grass planted at 0
## is buried to the shoulders.
const GROUND_FALLBACK_Y := 0.5

## How far above and below the nominal surface the ground probe looks. Generous
## enough to survive the lanes gaining real height once terrain lands.
const PROBE_UP := 30.0
const PROBE_DOWN := 15.0

@export var biome: String = "green"

## Clusters per lane, and how many tufts each one drops. Grass grows in clumps, and an
## evenly spread scatter at the same total count reads as texture noise rather than as
## planting. Total tufts is roughly cluster_count * the midpoint of the per-cluster
## range.
@export var cluster_count: int = 150
@export var cluster_tufts_min: int = 4
@export var cluster_tufts_max: int = 9
@export var cluster_radius: float = 2.4

@export var height_min: float = 0.9
@export var height_max: float = 1.7
@export var random_seed: int = 0

## Structures the scatter keeps clear of, as lane-local depth and a radius. The well
## and spawner both sit on the lane's centre line; grass growing through them reads as
## a bug rather than as landscaping.
const CLEARANCES := [
	{"depth": 112.4508, "radius": 7.0}, # ManaSource
	{"depth": 179.4508, "radius": 5.0}, # EnemySpawner
]


func _ready() -> void:
	# Tuft height is sampled off the collision surface, so the physics space has to be
	# live before any of this can run.
	await get_tree().physics_frame
	if not is_inside_tree():
		return
	_build()


func _build() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = random_seed

	var materials: Array[StandardMaterial3D] = []
	var meshes: Array[ArrayMesh] = []
	for variant in 4:
		var texture := _load_variant(variant)
		if texture == null:
			return
		materials.append(_build_material(texture))
		meshes.append(_build_cross_mesh(texture))

	# transforms[band][variant] - bucketed as they are drawn so each band/variant pair
	# can be handed to its own MultiMesh in one go.
	var transforms: Array = []
	var colours: Array = []
	for band in BAND_COUNT:
		var band_transforms: Array = []
		var band_colours: Array = []
		for variant in 4:
			band_transforms.append([] as Array[Transform3D])
			band_colours.append([] as Array[Color])
		transforms.append(band_transforms)
		colours.append(band_colours)

	var band_span: float = (OUTER_DEPTH - INNER_DEPTH) / float(BAND_COUNT)
	for cluster in cluster_count:
		var centre_depth := _sample_depth(rng)
		if _is_cleared(centre_depth):
			continue
		var centre_half_width: float = centre_depth * WEDGE_SLOPE
		var centre_x := rng.randf_range(-centre_half_width, centre_half_width)
		var ground_y := _ground_height(centre_x, centre_depth)

		# One variant per cluster. Mixing all four inside a single clump makes it read
		# as four separate plants rather than as one patch of the same grass.
		var variant: int = rng.randi_range(0, 3)
		var tufts: int = rng.randi_range(cluster_tufts_min, cluster_tufts_max)

		for tuft in tufts:
			# sqrt keeps the clump evenly filled instead of bunched at its centre.
			var offset_angle := rng.randf_range(0.0, TAU)
			var offset_distance: float = cluster_radius * sqrt(rng.randf())
			var x: float = centre_x + cos(offset_angle) * offset_distance
			var depth: float = centre_depth + sin(offset_angle) * offset_distance
			if _is_cleared(depth):
				continue
			# Keep the clump's outliers inside the wedge rather than spilling over the
			# lane edge into the gap between lanes.
			var half_width: float = depth * WEDGE_SLOPE
			x = clampf(x, -half_width, half_width)

			var band: int = clampi(int((depth - INNER_DEPTH) / band_span), 0, BAND_COUNT - 1)
			var height := rng.randf_range(height_min, height_max)
			# Crossed planes have a real orientation, so spinning each tuft stops the
			# whole lane from sharing one silhouette.
			var basis := Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(
				Vector3(height, height, height)
			)
			# Positions are stored relative to the band's own origin, set below, so the
			# band node's position is what the visibility range measures against.
			var origin := Vector3(x, ground_y, -depth + _band_centre_depth(band))
			transforms[band][variant].append(Transform3D(basis, origin))

			# Brightness jitter only - hue shifts would fight the biome palette the
			# sheets were authored around.
			var shade := rng.randf_range(0.82, 1.08)
			colours[band][variant].append(Color(shade, shade, shade, 1.0))

	for band in BAND_COUNT:
		for variant in 4:
			var band_transforms: Array = transforms[band][variant]
			if band_transforms.is_empty():
				continue
			_add_multimesh(
				meshes[variant],
				materials[variant],
				band_transforms,
				colours[band][variant],
				_band_centre_depth(band),
				"%s_band%d_var%d" % [biome, band, variant + 1],
			)


## Where the lane's surface actually sits under this point, in lane-local space.
##
## Raycast rather than a constant because the lane wedges are 0.5 m thick slabs, not
## a ground plane at zero - and because the terrain work will replace those slabs with
## something that has real height, at which point this keeps working unchanged.
func _ground_height(x: float, depth: float) -> float:
	var space := get_world_3d().direct_space_state
	var from: Vector3 = global_transform * Vector3(x, PROBE_UP, -depth)
	var to: Vector3 = global_transform * Vector3(x, -PROBE_DOWN, -depth)
	var query := PhysicsRayQueryParameters3D.create(from, to)
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		return GROUND_FALLBACK_Y
	return to_local(hit["position"] as Vector3).y


## Area-uniform depth within the wedge. Uniform depth would clump grass at the narrow
## inner end, because the wedge is four and a half times wider at the spawner than at
## the base. Width grows linearly with depth, so area grows with depth squared, and
## inverting that means interpolating between the squared bounds.
func _sample_depth(rng: RandomNumberGenerator) -> float:
	var near_squared: float = INNER_DEPTH * INNER_DEPTH
	var far_squared: float = OUTER_DEPTH * OUTER_DEPTH
	return sqrt(lerp(near_squared, far_squared, rng.randf()))


func _is_cleared(depth: float) -> bool:
	for clearance: Dictionary in CLEARANCES:
		if absf(depth - float(clearance["depth"])) < float(clearance["radius"]):
			return true
	return false


func _band_centre_depth(band: int) -> float:
	var band_span: float = (OUTER_DEPTH - INNER_DEPTH) / float(BAND_COUNT)
	return INNER_DEPTH + band_span * (float(band) + 0.5)


func _load_variant(variant: int) -> Texture2D:
	var path := "res://assets/foliage/grass/%s_grass_%02d.png" % [biome, variant + 1]
	if not ResourceLoader.exists(path):
		push_error("GrassScatter: missing %s - run tools/build_grass_billboards.gd" % path)
		return null
	return load(path) as Texture2D


func _build_material(texture: Texture2D) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_texture = texture
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	material.alpha_scissor_threshold = ALPHA_SCISSOR
	# Alpha testing is binary - a blade edge is fully on or fully off, with no
	# antialiasing whatsoever. On geometry made of hundreds of hair-thin blades that is
	# what reads as "messy". Alpha to coverage converts the alpha value into MSAA
	# sample coverage instead, so edges get antialiased without needing the back-to-
	# front sorting that real transparency would.
	#
	# It only does anything when MSAA is enabled on the viewport. GraphicsSettings
	# turns that on at MEDIUM and HIGH, so this is a no-op on LOW rather than a bug.
	material.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE
	material.alpha_antialiasing_edge = ALPHA_SCISSOR
	# Grass is nearly always seen at a grazing angle, which is precisely the case
	# ordinary mipmapping handles worst - it picks a blurry mip for the whole quad
	# based on the steepest axis. Anisotropic filtering keeps blades sharp along the
	# direction that still has detail.
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	# Deliberately NOT CULL_DISABLED. A double-sided material makes Godot flip the
	# normal on back-facing fragments, and since every normal in the cross mesh points
	# straight up, the flipped half ends up pointing at the ground - unlit, black, and
	# very obvious once a clump is more than a few metres off. _build_cross_mesh emits
	# both windings as real geometry instead, so whichever side faces the camera is a
	# front face with an upward normal and normal culling drops the other.
	material.cull_mode = BaseMaterial3D.CULL_BACK
	material.vertex_color_use_as_albedo = true
	# Grass is thin and backlit as often as not; a specular highlight on a flat card
	# only ever reads as a sheen on a sheet of paper.
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	material.roughness = 1.0
	return material


## Three quads standing in the same spot, rotated evenly about Y so the tuft holds up
## from any viewing angle without billboarding.
##
## Every normal points straight up rather than out of its own plane. That is the usual
## foliage trick: lit by its own face normal, each plane goes dark the moment the sun
## is off to one side, and a clump built from three of them turns into a dark smudge.
## Borrowing the ground's normal instead keeps the whole clump lit like the surface it
## grows out of.
##
## Each plane's four vertices carry two triangle pairs, one per winding, so the mesh is
## genuinely two-sided rather than relying on a double-sided material. That matters
## precisely because of the upward normals above: a double-sided material flips the
## normal on backfaces, which would point half of every clump's fragments at the
## ground and render them black. With both windings present, CULL_BACK keeps whichever
## pair faces the camera and the surviving fragment always has its normal up.
func _build_cross_mesh(texture: Texture2D) -> ArrayMesh:
	var size := texture.get_size()
	var aspect: float = size.x / size.y if size.y > 0.0 else 1.0
	var half: float = aspect * 0.5

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colours := PackedColorArray()
	var indices := PackedInt32Array()

	# Three rows rather than two, so the baked AO can fall off close to the ground
	# instead of stretching linearly to the tips.
	var rows := [
		{"height": 0.0, "shade": AO_BASE_SHADE},
		{"height": AO_MID_HEIGHT, "shade": AO_MID_SHADE},
		{"height": 1.0, "shade": 1.0},
	]

	for plane in PLANE_COUNT:
		var angle: float = PI * float(plane) / float(PLANE_COUNT)
		var across := Vector3(cos(angle), 0.0, sin(angle))
		var base: int = vertices.size()

		# Unit height, scaled per instance, with the base at y = 0 so the instance
		# transform plants the tuft on the ground rather than burying it to the middle.
		for row: Dictionary in rows:
			var height: float = float(row["height"])
			var shade: float = float(row["shade"])
			vertices.append(-across * half + Vector3.UP * height)
			vertices.append(across * half + Vector3.UP * height)
			for i in 2:
				normals.append(Vector3.UP)
				colours.append(Color(shade, shade, shade, 1.0))
			uvs.append(Vector2(0.0, 1.0 - height))
			uvs.append(Vector2(1.0, 1.0 - height))

		for row_index in rows.size() - 1:
			var bottom_left: int = base + row_index * 2
			var bottom_right: int = bottom_left + 1
			var top_left: int = bottom_left + 2
			var top_right: int = bottom_left + 3
			# Front-facing pair, then the same quads wound the other way. Only one of
			# the two survives culling for any given view, so this costs vertex memory
			# rather than fill rate.
			indices.append_array([
				bottom_left, bottom_right, top_right,
				bottom_left, top_right, top_left,
			])
			indices.append_array([
				bottom_left, top_right, bottom_right,
				bottom_left, top_left, top_right,
			])

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	# Multiplied with the per-instance brightness jitter set on the MultiMesh, so the
	# two variations stack rather than one overwriting the other.
	arrays[Mesh.ARRAY_COLOR] = colours
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _add_multimesh(
	mesh: ArrayMesh,
	material: StandardMaterial3D,
	transforms: Array,
	colours: Array,
	band_centre: float,
	node_name: String,
) -> void:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = mesh
	multimesh.instance_count = transforms.size()
	for i in transforms.size():
		multimesh.set_instance_transform(i, transforms[i])
		multimesh.set_instance_color(i, colours[i])

	var instance := MultiMeshInstance3D.new()
	instance.name = node_name
	instance.multimesh = multimesh
	instance.material_override = material
	instance.position = Vector3(0.0, 0.0, -band_centre)
	instance.visibility_range_end = VISIBILITY_END
	instance.visibility_range_end_margin = FADE_MARGIN
	instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	# Thousands of thin alpha-scissor cards are the worst possible shadow casters -
	# every one costs a depth pass for a shadow nobody can pick out of the grass.
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
