extends Node3D
## Mana crystals round every mana well: a cluster to each side of the lane, shard groups
## between them, and a light in the well's colour so it reads from across the map at night.
##
## Placed at runtime, round wherever each ManaSource stands, rather than painted into the
## terrain like the crystals in the wild (tools/build_nature_terrabrush.gd): TerraBrush's
## grid is too coarse for a ring a few metres wide, and the wells are getting new models -
## this follows them wherever they end up.
##
## The ring keeps clear of the lane - enemies walk spawner -> well -> crystal straight
## through it - and of the harvest slots, where Myrs stand (GameSettings.myr_well_slot_radius).
## Nothing here collides: it is added after the navmesh bake, and a solid crystal the
## navmesh does not know about is one enemies would walk into.
##
## Deliberately no `class_name` - preloaded by path, see scripts/icon_style.gd.

## Lane -> [cluster scene, shards scene], the biome tints built by the nature pipeline.
const CRYSTALS: Dictionary = {
	"White": ["nature-white-dawn-crystal-cluster", "nature-white-dawn-shards"],
	"Blue": ["nature-blue-sapphire-cluster", "nature-blue-tide-shards"],
	"Black": ["nature-black-void-amethyst", "nature-black-void-shards"],
	"Red": ["nature-red-ruby-crystals", "nature-red-ember-shards"],
	"Green": ["nature-green-emerald-root-crystals", "nature-green-emerald-shards"],
}
## Around each well, as [degrees from the lane's outward direction, which scene: 0 cluster,
## 1 shards]. Nothing within 40 degrees of the lane line, either way along it.
const RING: Array = [[90.0, 0], [-90.0, 0], [55.0, 1], [125.0, 1], [-55.0, 1], [-125.0, 1]]
const RING_RADIUS := Vector2(5.5, 7.5)
const LIGHT_COLORS: Dictionary = {
	"White": Color(1.0, 0.86, 0.55), "Blue": Color(0.35, 0.7, 1.0), "Black": Color(0.62, 0.3, 1.0),
	"Red": Color(1.0, 0.35, 0.12), "Green": Color(0.3, 1.0, 0.45),
}

var _terrain: StaticBody3D


## `wells` and `lane_names` are MainController's, in the same order; `crystal` is the hub
## the lanes run out from; `terrain` is the ground the crystals are stood on.
func place(wells: Array, lane_names: Array, crystal: Vector3, terrain: StaticBody3D) -> void:
	_terrain = terrain
	for i: int in wells.size():
		var lane: String = lane_names[i]
		if not CRYSTALS.has(lane):
			continue
		var well: Vector3 = (wells[i] as Node3D).global_position
		var outward := Vector3(well.x - crystal.x, 0.0, well.z - crystal.z).normalized()
		var rng := RandomNumberGenerator.new()
		rng.seed = hash("well_crystals:" + lane)
		var scenes: Array = []
		for id: String in CRYSTALS[lane]:
			scenes.append(load("res://assets/nature/scenes/%s.tscn" % id) as PackedScene)
		for slot: Array in RING:
			var scene: PackedScene = scenes[int(slot[1])]
			if scene == null:
				continue
			var angle: float = deg_to_rad(float(slot[0]) + rng.randf_range(-10.0, 10.0))
			var radius: float = rng.randf_range(RING_RADIUS.x, RING_RADIUS.y)
			var spot: Vector3 = well + outward.rotated(Vector3.UP, angle) * radius
			var crystal_node := scene.instantiate() as Node3D
			add_child(crystal_node)
			crystal_node.global_position = Vector3(spot.x, _ground(spot), spot.z)
			crystal_node.rotation.y = rng.randf_range(0.0, TAU)
			crystal_node.scale = Vector3.ONE * rng.randf_range(0.85, 1.25)

		var light := OmniLight3D.new()
		light.name = "WellGlow_" + lane
		light.light_color = LIGHT_COLORS[lane]
		light.light_energy = 1.4
		light.omni_range = 11.0
		light.shadow_enabled = false
		light.distance_fade_enabled = true
		light.distance_fade_begin = 70.0
		light.distance_fade_length = 25.0
		add_child(light)
		light.global_position = Vector3(well.x, _ground(well) + 2.2, well.z)


## The terrain's height under `at`; the Environment layer also holds trees and rocks, so
## anything else the ray meets is stepped through.
func _ground(at: Vector3) -> float:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(Vector3(at.x, 400.0, at.z), Vector3(at.x, -200.0, at.z), 1 << 4)
	var exclude: Array[RID] = []
	for i: int in 32:
		query.exclude = exclude
		var hit: Dictionary = space.intersect_ray(query)
		if hit.is_empty():
			return at.y
		if _terrain == null or hit.collider == _terrain:
			return hit.position.y
		exclude.append(hit.rid)
	return at.y
