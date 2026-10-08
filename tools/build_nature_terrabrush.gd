extends SceneTree
## Turns the generated nature assets into TerraBrush foliage layers and object types,
## and paints where they grow. Output is wired into main.tscn by
## `python tools/nature/nature_pipeline.py apply`.
##
## Usually run by `python tools/nature/nature_pipeline.py build`; by hand:
##   "G:\Godot\Godot_v4.7-stable_win64_console.exe" --headless --path . --script tools/build_nature_terrabrush.gd -- [--only id,id] [--biome green] [--no-scatter] [--manifest res://...]
##
## Needs everything imported first (the pipeline runs `--import` before this).
##
## Per MESH asset (assets/generated/<id>/<id>.glb):
##   - assets/nature/meshes/<id>.res: every surface of the glb baked into one mesh,
##     scaled to the manifest size, base on y = 0, centred, with automatic LODs.
##     Meshy's auto_size is a fixed bounding-box normalisation, not a real size (see
##     .agents/learnings.md), and its bottom origin does not always hold, so neither is
##     trusted - the AABB is measured and corrected here.
##   - assets/nature/scenes/<id>.tscn: a wrapper (mesh, optional glow light, optional
##     StaticBody3D on the Environment layer) for hand placement and for the
##     PackedScenes strategy.
##   - assets/nature/terrabrush/<id>.tres: the ObjectResource. Glowing assets with a
##     light use PackedScenes (TerraBrush cannot put a light in a MultiMesh); everything
##     else uses OctreeMultiMeshes, which is what keeps hundreds of rocks cheap.
##   - Procedural trees with variants (<id>_v2.glb, ...) get a mesh and wrapper scene per
##     variant and use PackedScenes too, so TerraBrush mixes them (see _build_variants).
##
## Per CARD layer (all card assets sharing a biome and `layer`):
##   - assets/nature/terrabrush/foliage_<biome>_<layer>.tres: one FoliageResource whose
##     Texture2DArray holds every tile of the layer, each repeated `weight` times so
##     grass can outnumber flowers. One layer, not one per asset, because TerraBrush
##     runs its whole MultiMesh grid per foliage entry whether a cell is painted or not.
##
## Scatter: one mask image per entry, saved as scenes/misc/Main/Nature_<name>.res -
## the zone image TerraBrush paints into, so the result can be touched up by hand
## with TerraBrush's brushes afterwards. Only assets built in this run are repainted;
## --no-scatter keeps every existing mask (and creates empty ones for new entries).
## See _paint_objects / _paint_foliage for the rules.

const DEFAULT_MANIFEST := "res://tools/nature/nature_assets.json"
const MESH_DIR := "res://assets/nature/meshes/"
const SCENE_DIR := "res://assets/nature/scenes/"
const TB_DIR := "res://assets/nature/terrabrush/"
const MASK_DIR := "res://scenes/misc/Main/"
const HEIGHTMAP := "res://scenes/misc/Main/Heightmap_0_0.res"
const WATERMAP := "res://scenes/misc/Main/Water_0_0.res"
const FOLIAGE_SHADER := "res://assets/shaders/nature_foliage.gdshader"

## Physics layer 5 (value 16) is Environment - the layer the terrain itself is on.
const ENVIRONMENT_LAYER := 16

## TerraBrush enum values (FoliageStrategy / ObjectStrategy).
const FOLIAGE_MULTIMESH := 1
const OBJECTS_PACKED_SCENES := 1
const OBJECTS_OCTREE := 2

## Distance at which MultiMesh objects drop to their shadowless far LOD, and the
## distance past which they are not drawn at all.
const NEAR_LOD_M := 70.0
const FAR_LOD_M := {"clutter": 140.0, "bush": 200.0, "crystal": 260.0, "tree": 400.0, "landmark": 520.0}

var manifest: Dictionary
var options: Dictionary
var library := {"foliages": [], "objects": []}
var placement_noise: NoiseTexture2D


func _init() -> void:
	options = _parse_args()
	var manifest_path: String = options.get("manifest", DEFAULT_MANIFEST)
	manifest = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	for dir in [MESH_DIR, SCENE_DIR, TB_DIR]:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	placement_noise = _placement_noise()

	var objects := []  # [asset, ObjectResource, footprint radius] - built this run
	for asset: Dictionary in manifest["assets"]:
		# Procedural trees (tools/nature/blender/build_trees.py) land in the same
		# assets/generated/<id>/ folder as Meshy models and are built the same way.
		if not (asset["route"] in ["mesh", "procedural"]) or not _selected(asset):
			continue
		if asset["biome"] == "shared":
			# Colourless shapes tinted per biome (docs/NATURE_ASSETS.md 3a) - the tint
			# material and the per-biome "tint" entries are not wired in yet.
			print("[nature] %s: shared crystal shape, tinting not built yet - skipped" % asset["id"])
			continue
		var built := _build_mesh_asset(asset)
		if not built.is_empty():
			objects.append(built)

	# A foliage layer is rebuilt whole if any of its assets is selected, because its
	# texture array holds all of them.
	var layers := {}  # "biome/layer" -> [assets]
	for asset: Dictionary in manifest["assets"]:
		if asset["route"] == "card":
			var key := "%s/%s" % [asset["biome"], asset["layer"]]
			if not layers.has(key):
				layers[key] = []
			layers[key].append(asset)
	var foliages := []  # [name, biome, tier, FoliageResource] - built this run
	for key: String in layers:
		if (layers[key] as Array).any(_selected):
			var built := _build_foliage_layer(key, layers[key])
			if not built.is_empty():
				foliages.append(built)

	if not options.has("no_scatter"):
		var terrain := _load_terrain()
		_paint_objects(objects, terrain)
		_paint_foliage(foliages, terrain)

	# The library lists everything built so far, not just this run - `apply` replaces
	# the scene's arrays with it, so a partial list would drop the rest.
	for asset: Dictionary in manifest["assets"]:
		if asset["route"] in ["mesh", "procedural"] and ResourceLoader.exists(TB_DIR + asset["id"] + ".tres"):
			_add_to_library("objects", asset["id"])
	for key: String in layers:
		var layer_name := "foliage_" + key.replace("/", "_")
		if ResourceLoader.exists(TB_DIR + layer_name + ".tres"):
			_add_to_library("foliages", layer_name)

	var library_path := ProjectSettings.globalize_path(TB_DIR + "library.json")
	FileAccess.open(library_path, FileAccess.WRITE).store_string(JSON.stringify(library, "  "))
	print("[nature] library: %d foliage layer(s), %d object type(s)" % [
		library["foliages"].size(), library["objects"].size()])
	quit()


func _add_to_library(kind: String, entry_name: String) -> void:
	var mask_path := MASK_DIR + "Nature_%s.res" % entry_name
	_ensure_mask(mask_path)
	library[kind].append({"name": entry_name, "resource": TB_DIR + entry_name + ".tres", "mask": mask_path})


# --------------------------------------------------------------------------- meshes

func _build_mesh_asset(asset: Dictionary) -> Array:
	var id: String = asset["id"]
	var glb := "res://assets/generated/%s/%s.glb" % [id, id]
	if not ResourceLoader.exists(glb):
		print("[nature] %s: no imported glb yet, skipped" % id)
		return []
	var tier := _tier(asset)
	var mesh := _bake_mesh(asset, load(glb) as PackedScene)
	if mesh == null:
		return []
	ResourceSaver.save(mesh, MESH_DIR + id + ".res")
	mesh = load(MESH_DIR + id + ".res")

	var bounds := mesh.get_aabb()
	var collision := _collision_shape(asset, tier, bounds)
	var glow: bool = asset.get("glow", false)
	var light: bool = asset.get("light", false)
	var scene := _wrapper_scene(asset, mesh, collision, light)
	ResourceSaver.save(scene, SCENE_DIR + id + ".tscn")
	scene = load(SCENE_DIR + id + ".tscn")
	var variant_scenes := _build_variants(asset, tier, light)

	var definition: Resource = ClassDB.instantiate("ObjectDefinitionResource")
	var spacing: int = tier["spacing_m"]
	definition.set("objectFrequency", spacing)
	# TerraBrush jitters each placement within +-randomRange of its grid point.
	definition.set("randomRange", spacing * 0.4)
	definition.set("noiseTexture", placement_noise)
	definition.set("randomRotation", true)
	definition.set("randomRotationMin", Vector3.ZERO)
	definition.set("randomRotationMax", Vector3(0, 360, 0))
	definition.set("randomSize", true)
	var landmark: bool = asset["tier"] == "landmark"
	definition.set("randomSizeFactorMin", 0.9 if landmark else 0.8)
	definition.set("randomSizeFactorMax", 1.1 if landmark else 1.2)

	if light or not variant_scenes.is_empty():
		definition.set("strategy", OBJECTS_PACKED_SCENES)
		definition.set("objectScenes", _typed([scene] + variant_scenes, "PackedScene"))
	else:
		definition.set("strategy", OBJECTS_OCTREE)
		var shadows: int = 0 if asset["tier"] == "clutter" else 1
		var near_lod: Resource = ClassDB.instantiate("ObjectOctreeLODDefinitionResource")
		near_lod.set("maxDistance", NEAR_LOD_M)
		near_lod.set("addCollision", collision != null)
		var far_lod: Resource = ClassDB.instantiate("ObjectOctreeLODDefinitionResource")
		far_lod.set("maxDistance", FAR_LOD_M.get(asset["tier"], 200.0))
		definition.set("lodList", _typed([near_lod, far_lod], "ObjectOctreeLODDefinitionResource"))
		var near_meshes := _lod_meshes(mesh, shadows, collision)
		var far_meshes := _lod_meshes(mesh, 0, null)
		definition.set("lodMeshes", _typed([near_meshes, far_meshes], "ObjectOctreeLODMeshesDefinitionResource"))

	var object: Resource = ClassDB.instantiate("ObjectResource")
	object.set("definition", definition)
	var resource_path := TB_DIR + id + ".tres"
	ResourceSaver.save(object, resource_path)
	print("[nature] %s: %d tris, %.1f x %.1f m, %s%s%s" % [
		id, _triangle_count(mesh), bounds.size.x, bounds.size.y,
		"scenes" if light or not variant_scenes.is_empty() else "multimesh", ", glow" if glow else "",
		", %d variant(s)" % (variant_scenes.size() + 1) if not variant_scenes.is_empty() else ""])
	var footprint: float = maxf(bounds.size.x, bounds.size.z) * 0.5
	return [asset, load(resource_path), footprint]


## The extra variants of a procedural tree (`<id>_v2.glb`, `_v3`, ... from
## tools/nature/blender/build_trees.py --variants), each baked and wrapped exactly like the
## base. Returns their wrapper scenes, in order, stopping at the first missing number.
##
## Variants are why such an asset uses the PackedScenes strategy: TerraBrush picks a random
## entry of `objectScenes` for every placement, while the OctreeMultiMeshes strategy draws
## only the first mesh of each LOD level and ignores the rest - checked on this map with
## three meshes in one level, where every placement used the first.
func _build_variants(asset: Dictionary, tier: Dictionary, light: bool) -> Array:
	var id: String = asset["id"]
	var scenes := []
	var variant := 2
	while true:
		var variant_id := "%s_v%d" % [id, variant]
		var glb := "res://assets/generated/%s/%s.glb" % [id, variant_id]
		if not ResourceLoader.exists(glb):
			break
		var variant_asset := asset.duplicate()
		variant_asset["id"] = variant_id
		var mesh := _bake_mesh(variant_asset, load(glb) as PackedScene)
		if mesh == null:
			break
		ResourceSaver.save(mesh, MESH_DIR + variant_id + ".res")
		mesh = load(MESH_DIR + variant_id + ".res")
		var collision := _collision_shape(asset, tier, mesh.get_aabb())
		ResourceSaver.save(_wrapper_scene(variant_asset, mesh, collision, light), SCENE_DIR + variant_id + ".tscn")
		scenes.append(load(SCENE_DIR + variant_id + ".tscn"))
		variant += 1
	return scenes


## Bakes every MeshInstance3D in the imported scene into one mesh: transformed so the
## manifest size holds, the base sits on y = 0 and the footprint is centred, then run
## through ImporterMesh for automatic LODs (the bake drops the importer's own).
func _bake_mesh(asset: Dictionary, packed: PackedScene) -> ArrayMesh:
	var root := packed.instantiate() as Node3D
	var parts := []  # [MeshInstance3D, transform relative to root]
	_collect_meshes(root, Transform3D.IDENTITY, parts)
	if parts.is_empty():
		push_error("[nature] %s: glb has no meshes" % asset["id"])
		root.free()
		return null

	var bounds := AABB()
	var first := true
	for part: Array in parts:
		var box: AABB = part[1] * (part[0] as MeshInstance3D).mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false

	# Scale on the manifest's dominant dimension. Height for upright things; width for
	# flat ones (pebbles, lily pads), where a few centimetres of height error would
	# otherwise blow the whole asset up.
	var target: Array = asset["size_m"]
	var width: float = maxf(bounds.size.x, bounds.size.z)
	var factor: float
	if target[1] >= target[0] * 0.5:
		factor = target[1] / maxf(bounds.size.y, 0.0001)
	else:
		factor = target[0] / maxf(width, 0.0001)
	var centre := bounds.get_center()
	var fix := Transform3D(Basis.from_scale(Vector3.ONE * factor),
		-Vector3(centre.x, bounds.position.y, centre.z) * factor - Vector3(0, _sink_m(asset), 0))

	var importer := ImporterMesh.new()
	var glow: bool = asset.get("glow", false)
	for part: Array in parts:
		var instance := part[0] as MeshInstance3D
		for surface in instance.mesh.get_surface_count():
			var surface_tool := SurfaceTool.new()
			surface_tool.append_from(instance.mesh, surface, fix * part[1])
			if not (instance.mesh.surface_get_format(surface) & Mesh.ARRAY_FORMAT_TANGENT):
				surface_tool.generate_tangents()
			var material := _leaf_material(_non_metallic(instance.get_active_material(surface)))
			if glow:
				material = _glow_material(material, asset)
			importer.add_surface(Mesh.PRIMITIVE_TRIANGLES, surface_tool.commit_to_arrays(), [], {}, material, "")
	importer.generate_lods(25.0, 60.0, [])
	root.free()
	return importer.get_mesh()


## Extra air under the trunk the sink allows for: TerraBrush's ground height under a
## placement is not exact either.
const SINK_MARGIN_M := 0.15


## How far below y = 0 the base is baked, so the asset stands IN the ground rather than on
## a single point of it. TerraBrush sets each object at the terrain height under its
## origin, and on a slope the downhill side of a trunk then hangs in the air by its radius
## times the slope - so the sink is sized for the steepest slope the tier is allowed on,
## with the flare at the foot counted in. Only assets with a trunk get one by default;
## anything can set `sink_m` (on the asset or its tier) to choose its own.
func _sink_m(asset: Dictionary) -> float:
	var tier := _tier(asset)
	if asset.has("sink_m"):
		return float(asset["sink_m"])
	if tier.has("sink_m"):
		return float(tier["sink_m"])
	if not asset.has("trunk_radius_m"):
		return 0.0
	var flared_radius: float = float(asset["trunk_radius_m"]) * 1.3
	return flared_radius * tan(deg_to_rad(float(tier.get("max_slope_deg", 30.0)))) + SINK_MARGIN_M


func _collect_meshes(node: Node, parent: Transform3D, out: Array) -> void:
	var here := parent
	if node is Node3D:
		here = parent * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		out.append([node, here])
	for child in node.get_children():
		_collect_meshes(child, here, out)


const LEAF_SHADER := "res://assets/shaders/nature_leaves.gdshader"


## Alpha-cut materials are leaf cards (the procedural trees export their leaves as glTF
## alphaMode MASK, which Godot imports as an alpha scissor). They get
## assets/shaders/nature_leaves.gdshader: back faces keep their normal, the crown sways
## by the baked wind weight, and light shows through. Everything else is left alone.
func _leaf_material(source: Material) -> Material:
	if not (source is StandardMaterial3D):
		return source
	var standard := source as StandardMaterial3D
	if standard.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED or standard.albedo_texture == null:
		return source
	var leaves := ShaderMaterial.new()
	leaves.shader = load(LEAF_SHADER)
	leaves.set_shader_parameter("albedo_texture", standard.albedo_texture)
	var tint := standard.albedo_color
	leaves.set_shader_parameter("albedo_tint", Vector3(tint.r, tint.g, tint.b))
	return leaves


## Meshy's PBR pass guesses metal where there is none: the giant clam came back with
## metallicFactor 1.0 and a metallic map averaging 15%, which renders shells and wet
## stone as dark chrome. Nothing in the nature set is metal, so metalness is switched off
## (roughness and normal maps are kept).
func _non_metallic(source: Material) -> Material:
	if not (source is StandardMaterial3D):
		return source
	var material := (source as StandardMaterial3D).duplicate() as StandardMaterial3D
	material.metallic = 0.0
	material.metallic_texture = null
	return material


## Meshy's emission map is black in practice (.agents/learnings.md), so crystals and
## glowing fungi get their glow here: the albedo drives emission, tinted to the colour
## of their biome. This lights the whole surface a little, rock base included - fine at
## this strength; a dedicated crystal shader is Phase 4 in docs/NATURE_ASSETS.md.
func _glow_material(source: Material, asset: Dictionary) -> Material:
	if not (source is StandardMaterial3D):
		return source
	var material := (source as StandardMaterial3D).duplicate() as StandardMaterial3D
	var glow: Array = manifest["biomes"][asset["biome"]]["crystal_glow"]
	material.emission_enabled = true
	material.emission = Color(glow[0], glow[1], glow[2])
	material.emission_texture = material.albedo_texture
	material.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
	material.emission_energy_multiplier = 1.2
	return material


func _collision_shape(asset: Dictionary, tier: Dictionary, bounds: AABB) -> Shape3D:
	var kind: String = tier.get("collision", "none")
	if kind == "none":
		return null
	var shape := CylinderShape3D.new()
	if kind == "trunk":
		shape.radius = asset.get("trunk_radius_m", 0.1 * maxf(bounds.size.x, bounds.size.z))
		shape.height = bounds.size.y * 0.6
	else:
		shape.radius = 0.4 * minf(bounds.size.x, bounds.size.z)
		shape.height = bounds.size.y
	return shape


func _wrapper_scene(asset: Dictionary, mesh: ArrayMesh, collision: Shape3D, light: bool) -> PackedScene:
	var root := Node3D.new()
	root.name = (asset["id"] as String).to_pascal_case()
	var visual := MeshInstance3D.new()
	visual.name = "Mesh"
	visual.mesh = mesh
	if asset["tier"] == "clutter":
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(visual)
	visual.owner = root

	if collision != null:
		var body := StaticBody3D.new()
		body.name = "Body"
		body.collision_layer = ENVIRONMENT_LAYER
		body.collision_mask = 0
		root.add_child(body)
		body.owner = root
		var shape := CollisionShape3D.new()
		shape.name = "Shape"
		shape.shape = collision
		shape.position.y = (collision as CylinderShape3D).height * 0.5
		body.add_child(shape)
		shape.owner = root

	if light:
		var glow: Array = manifest["biomes"][asset["biome"]]["crystal_glow"]
		var omni := OmniLight3D.new()
		omni.name = "Glow"
		omni.light_color = Color(glow[0], glow[1], glow[2])
		omni.light_energy = 1.5
		omni.omni_range = 7.0
		omni.shadow_enabled = false
		# Lights are the expensive part of a crystal; let them fade out well before
		# the mesh does.
		omni.distance_fade_enabled = true
		omni.distance_fade_begin = 50.0
		omni.distance_fade_length = 20.0
		omni.position.y = mesh.get_aabb().size.y * 0.6
		root.add_child(omni)
		omni.owner = root

	var packed := PackedScene.new()
	packed.pack(root)
	root.free()
	return packed


func _lod_meshes(mesh: Mesh, shadows: int, collision: Shape3D) -> Resource:
	var entry: Resource = ClassDB.instantiate("ObjectOctreeLODMeshDefinitionResource")
	entry.set("mesh", mesh)
	entry.set("scale", Vector3.ONE)
	entry.set("castShadow", shadows)
	var level: Resource = ClassDB.instantiate("ObjectOctreeLODMeshesDefinitionResource")
	level.set("meshes", _typed([entry], "ObjectOctreeLODMeshDefinitionResource"))
	if collision != null:
		level.set("collisionShape", collision)
		level.set("collisionOffset", Vector3(0, (collision as CylinderShape3D).height * 0.5, 0))
	return level


# --------------------------------------------------------------------------- foliage

func _build_foliage_layer(key: String, assets: Array) -> Array:
	var textures := []
	var size := Vector2.ZERO
	for asset: Dictionary in assets:
		var tiles := []
		# A sheet is split by shape, so it can yield any number of tiles, not just four.
		var index := 1
		while ResourceLoader.exists("res://assets/nature/cards/%s_%02d.png" % [asset["id"], index]):
			tiles.append(load("res://assets/nature/cards/%s_%02d.png" % [asset["id"], index]))
			index += 1
		if tiles.is_empty():
			print("[nature] %s: no card tiles yet, left out of %s" % [asset["id"], key])
			continue
		for repeat in int(asset.get("weight", 1)):
			textures.append_array(tiles)
		var card: Array = asset["card_size_m"]
		size = Vector2(maxf(size.x, card[0]), maxf(size.y, card[1]))
	if textures.is_empty():
		return []

	var parts := key.split("/")
	var biome := parts[0]
	var layer := parts[1]
	var shader_material := ShaderMaterial.new()
	shader_material.shader = load(FOLIAGE_SHADER)
	var definition: Resource = ClassDB.instantiate("FoliageDefinitionResource")
	definition.set("strategy", FOLIAGE_MULTIMESH)
	definition.set("mesh", _cross_quad(size))
	definition.set("meshScale", Vector3.ONE)
	definition.set("windStrength", 0.08 if layer == "low" else 0.14)
	definition.set("albedoTextures", _typed(textures, "Texture2D"))
	# The cards carry their own biome colour; tinting them with the ground would muddy
	# the five palettes into each other.
	definition.set("useGroundColor", false)
	definition.set("castShadow", false)
	definition.set("useBrushScale", true)
	definition.set("customShader", shader_material)

	var foliage: Resource = ClassDB.instantiate("FoliageResource")
	foliage.set("definition", definition)
	var layer_name := "foliage_%s_%s" % [biome, layer]
	ResourceSaver.save(foliage, TB_DIR + layer_name + ".tres")
	print("[nature] %s: %d texture(s), card %.1f x %.1f m" % [layer_name, textures.size(), size.x, size.y])
	var tier := "groundcover" if layer == "low" else "tallcover"
	return [layer_name, biome, tier, load(TB_DIR + layer_name + ".tres")]


## Two quads crossed at right angles, base on y = 0. Normals point up rather than out
## of each quad, so a card is lit like the ground under it from every view angle
## instead of flashing light and dark as the camera orbits.
func _cross_quad(size: Vector2) -> ArrayMesh:
	var surface_tool := SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := size.x * 0.5
	for axis: Vector3 in [Vector3.RIGHT, Vector3.BACK]:
		var a := -axis * half
		var b := axis * half
		var corners := [a, b, b + Vector3.UP * size.y, a + Vector3.UP * size.y]
		var uvs := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		for index: int in [0, 1, 2, 0, 2, 3]:
			surface_tool.set_normal(Vector3.UP)
			surface_tool.set_uv(uvs[index])
			surface_tool.add_vertex(corners[index])
	return surface_tool.commit()


# --------------------------------------------------------------------------- scatter

## World position of zone pixel (x, y). The single zone is centred on the origin,
## one pixel per metre - verified against the volcano peak (pixel 87,447 is world
## -169,191, inside the Red wedge where the volcano is).
func _world(x: int, y: int) -> Vector2:
	var half: float = manifest["scatter"]["zone_size"] * 0.5
	return Vector2(x - half, y - half)


## Per-pixel biome, slope and wetness, computed once - the foliage pass visits every
## pixel of the zone once per layer, which is too slow to redo all of this inline.
func _load_terrain() -> Dictionary:
	var size: int = manifest["scatter"]["zone_size"]
	var height := load(HEIGHTMAP) as Image
	var water := load(WATERMAP) as Image
	var edge_noise := FastNoiseLite.new()
	edge_noise.seed = 7919
	edge_noise.frequency = 0.012
	var biome_names: Array = manifest["biomes"].keys()
	var biome := PackedByteArray()
	var slope := PackedFloat32Array()
	var wet := PackedByteArray()
	biome.resize(size * size)
	slope.resize(size * size)
	wet.resize(size * size)
	for y in size:
		for x in size:
			var index := y * size + x
			biome[index] = _biome_at(_world(x, y), edge_noise, biome_names)
			slope[index] = _slope_deg(height, x, y)
			wet[index] = 1 if water.get_pixel(x, y).r > 0.01 else 0
	return {"size": size, "biome_names": biome_names, "biome": biome, "slope": slope, "wet": wet}


## Which biome a world point belongs to, as an index into biome_names: the nearest
## lane angle, with the border pushed around by noise so wedges interlock instead of
## meeting on a ruler line.
func _biome_at(point: Vector2, edge_noise: FastNoiseLite, biome_names: Array) -> int:
	var jitter: float = manifest["scatter"]["biome_edge_jitter_deg"]
	var angle := rad_to_deg(atan2(point.y, point.x)) + edge_noise.get_noise_2dv(point) * jitter
	var best := 0
	var best_delta := 999.0
	for index in biome_names.size():
		var lane: float = manifest["biomes"][biome_names[index]]["lane_angle_deg"]
		var delta := absf(wrapf(angle - lane, -180.0, 180.0))
		if delta < best_delta:
			best_delta = delta
			best = index
	return best


func _slope_deg(height: Image, x: int, y: int) -> float:
	var x0 := clampi(x - 1, 0, height.get_width() - 1)
	var x1 := clampi(x + 1, 0, height.get_width() - 1)
	var y0 := clampi(y - 1, 0, height.get_height() - 1)
	var y1 := clampi(y + 1, 0, height.get_height() - 1)
	var dx := (height.get_pixel(x1, y).r - height.get_pixel(x0, y).r) / maxf(x1 - x0, 1)
	var dz := (height.get_pixel(x, y1).r - height.get_pixel(x, y0).r) / maxf(y1 - y0, 1)
	return rad_to_deg(atan(Vector2(dx, dz).length()))


## True where something solid would stand in the enemies' way: a strip along each
## lane's centre line (enemies walk spawner -> well -> crystal along it), and a ring
## round each mana well. The navmesh is baked from the terrain and the stone rings
## only (MainController.bake_map_navigation), so TerraBrush objects are invisible to
## it - anything blocking has to stay out of the paths instead.
func _in_lane_corridor(point: Vector2) -> bool:
	var scatter: Dictionary = manifest["scatter"]
	var radii: Array = scatter["corridor_radius_m"]
	for biome: String in manifest["biomes"]:
		var direction := Vector2.from_angle(deg_to_rad(manifest["biomes"][biome]["lane_angle_deg"]))
		var along := point.dot(direction)
		if along >= radii[0] and along <= radii[1] and absf(point.cross(direction)) < scatter["corridor_half_width_m"]:
			return true
	return false


func _near_well(point: Vector2) -> bool:
	var scatter: Dictionary = manifest["scatter"]
	for biome: String in manifest["biomes"]:
		var well: Vector2 = Vector2.from_angle(deg_to_rad(manifest["biomes"][biome]["lane_angle_deg"])) * float(scatter["well_radius_m"])
		if point.distance_to(well) < scatter["well_clearance_m"]:
			return true
	return false


## Shared placement test for one candidate point.
func _allowed(asset_biome: String, tier: Dictionary, water_rule: String, point: Vector2,
		x: int, y: int, terrain: Dictionary) -> bool:
	var radius := point.length()
	var band: Array = tier["radius_m"]
	if radius < maxf(band[0], manifest["scatter"]["plateau_radius_m"]) or radius > band[1]:
		return false
	var index: int = y * terrain["size"] + x
	if terrain["biome_names"][terrain["biome"][index]] != asset_biome:
		return false
	var wet: bool = terrain["wet"][index] == 1
	if (water_rule == "none" and wet) or (water_rule == "only" and not wet):
		return false
	if terrain["slope"][index] > tier["max_slope_deg"]:
		return false
	return not _near_well(point)


## Objects: TerraBrush spawns one instance at every pixel with alpha > 0 whose x and y
## are both multiples of objectFrequency, so only those grid points are written. Each
## is kept with probability density x clump noise. Biggest assets go first and claim a
## disc of ground, so a bush never spawns inside a tree trunk.
func _paint_objects(objects: Array, terrain: Dictionary) -> void:
	objects.sort_custom(func(a: Array, b: Array) -> bool: return a[2] > b[2])
	var size: int = manifest["scatter"]["zone_size"]
	var occupied := PackedByteArray()
	occupied.resize(size * size)
	for built: Array in objects:
		var asset: Dictionary = built[0]
		var mask_path := MASK_DIR + "Nature_%s.res" % asset["id"]
		var tier := _tier(asset)
		var spacing: int = tier["spacing_m"]
		var clump := FastNoiseLite.new()
		clump.seed = hash(asset["id"])
		clump.frequency = 0.02
		var random := RandomNumberGenerator.new()
		random.seed = hash(asset["id"] + "/scatter")
		var mask := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
		var claim := int(ceil(built[2] as float)) + 1
		var placed := 0
		for y in range(0, size, spacing):
			for x in range(0, size, spacing):
				var point := _world(x, y)
				if not _allowed(asset["biome"], tier, asset.get("water", "none"), point, x, y, terrain):
					continue
				if tier["blocking"] and _in_lane_corridor(point):
					continue
				if occupied[y * size + x]:
					continue
				var chance: float = tier["density"] * (0.5 + 0.5 * clump.get_noise_2d(x, y)) * 2.0
				if random.randf() >= chance:
					continue
				mask.set_pixel(x, y, Color(1, 0, 0, 1))
				_claim(occupied, size, x, y, claim)
				placed += 1
		ResourceSaver.save(mask, mask_path)
		print("[nature] %s: %d placed" % [asset["id"], placed])


func _claim(occupied: PackedByteArray, size: int, cx: int, cy: int, radius: int) -> void:
	for y in range(maxi(cy - radius, 0), mini(cy + radius + 1, size)):
		for x in range(maxi(cx - radius, 0), mini(cx + radius + 1, size)):
			if (x - cx) * (x - cx) + (y - cy) * (y - cy) <= radius * radius:
				occupied[y * size + x] = 1


## Foliage: the red channel switches a cell on, alpha scales the plant (TerraBrush's
## useBrushScale). Clumped by noise so ground cover grows in drifts rather than as an
## even carpet; `coverage` is roughly the share of allowed ground that gets planted.
func _paint_foliage(foliages: Array, terrain: Dictionary) -> void:
	var size: int = manifest["scatter"]["zone_size"]
	for built: Array in foliages:
		var layer_name: String = built[0]
		var mask_path := MASK_DIR + "Nature_%s.res" % layer_name
		var tier: Dictionary = manifest["tiers"][built[2]]
		var clump := FastNoiseLite.new()
		clump.seed = hash(layer_name)
		clump.frequency = 0.035
		var threshold: float = 1.0 - 2.0 * float(tier["coverage"])
		var mask := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
		var cells := 0
		for y in size:
			for x in size:
				var value := clump.get_noise_2d(x, y) * 1.6
				if value < threshold:
					continue
				var point := _world(x, y)
				if not _allowed(built[1], tier, "none", point, x, y, terrain):
					continue
				mask.set_pixel(x, y, Color(1, 0, 0, clampf(0.75 + (value - threshold) * 0.4, 0.75, 1.0)))
				cells += 1
		ResourceSaver.save(mask, mask_path)
		print("[nature] %s: %d m2 planted" % [layer_name, cells])


## Every library entry needs an image to pair with (TerraBrush matches them by
## index). An existing mask is kept; a missing one (--no-scatter) is created empty,
## ready to be painted by hand with TerraBrush's own brushes.
func _ensure_mask(path: String) -> void:
	if not ResourceLoader.exists(path):
		var size: int = manifest["scatter"]["zone_size"]
		ResourceSaver.save(Image.create_empty(size, size, false, Image.FORMAT_RGBA8), path)


# --------------------------------------------------------------------------- helpers

func _tier(asset: Dictionary) -> Dictionary:
	var tier: Dictionary = (manifest["tiers"][asset["tier"]] as Dictionary).duplicate()
	tier.merge(asset.get("scatter", {}), true)
	if asset.has("collision"):
		tier["collision"] = asset["collision"]
	return tier


func _placement_noise() -> NoiseTexture2D:
	var path := TB_DIR + "placement_noise.tres"
	if ResourceLoader.exists(path):
		return load(path)
	var texture := NoiseTexture2D.new()
	texture.width = 256
	texture.height = 256
	texture.seamless = true
	texture.noise = FastNoiseLite.new()
	ResourceSaver.save(texture, path)
	return load(path)


## Typed arrays for TerraBrush's typed properties (Array[ObjectResource] and so on);
## GDExtension classes are registered in ClassDB, so they type an Array like any other.
func _typed(items: Array, item_class: StringName) -> Array:
	var typed := Array([], TYPE_OBJECT, item_class, null)
	typed.assign(items)
	return typed


func _triangle_count(mesh: Mesh) -> int:
	var total := 0
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		total += indices.size() / 3 if not indices.is_empty() else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return total


func _selected(asset: Dictionary) -> bool:
	if options.has("only") and not (options["only"] as PackedStringArray).has(asset["id"]):
		return false
	return not options.has("biome") or asset["biome"] == options["biome"]


func _parse_args() -> Dictionary:
	var parsed := {}
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		match args[i]:
			"--only":
				parsed["only"] = args[i + 1].split(",")
			"--biome":
				parsed["biome"] = args[i + 1]
			"--manifest":
				parsed["manifest"] = args[i + 1]
			"--no-scatter":
				parsed["no_scatter"] = true
	return parsed
