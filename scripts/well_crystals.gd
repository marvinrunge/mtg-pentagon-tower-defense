extends Node3D
## Mana crystals round every mana well: a cluster to each side of the lane, shard groups
## between them, and a light in the well's colour so it reads from across the map at night.
## And at the hub (place_hub), where all five colours meet: round the base crystal, at the
## foot of the standing stones, and a spire of each colour at the five carved pillars.
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

## Lane -> [cluster scene, shards scene, spire scene], the biome tints built by the nature
## pipeline.
const CRYSTALS: Dictionary = {
	"White": ["nature-white-dawn-crystal-cluster", "nature-white-dawn-shards", "nature-white-sunspire-crystal"],
	"Blue": ["nature-blue-sapphire-cluster", "nature-blue-tide-shards", "nature-blue-tide-crystal-spires"],
	"Black": ["nature-black-void-amethyst", "nature-black-void-shards", "nature-black-rootbound-obelisk"],
	"Red": ["nature-red-ruby-crystals", "nature-red-ember-shards", "nature-red-magma-spire"],
	"Green": ["nature-green-emerald-root-crystals", "nature-green-emerald-shards", "nature-green-verdant-spire"],
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
		var scenes: Array = [_scene(lane, 0), _scene(lane, 1)]
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


## The hub, where all five colours meet. Round the base crystal: a cluster of each colour in
## the gaps between the lanes - the lanes run straight in to it - with shards between them.
## At the foot of every standing stone, on its outer side: a cluster or shards of a random
## colour. At each of the five carved pillars: a spire, one per colour, glowing.
##
## `lane_angles` are the lanes' directions out from the crystal, in radians.
func place_hub(crystal: Vector3, lane_angles: Array, stones: Array, pillars: Array, terrain: StaticBody3D) -> void:
	_terrain = terrain
	var colours: Array = CRYSTALS.keys()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("hub_crystals")

	# Round the base crystal: one ring of 15, leaning outward like a crown opening round
	# where the crystal floats. Every third is a cluster - one of each colour, since 0, 3,
	# 6, 9, 12 land on all five - with two shard groups between each pair, packed close so
	# the ring reads as one growth rather than a scatter.
	var crown: int = 15
	var start: float = rng.randf_range(0.0, TAU)
	for k: int in crown:
		var angle: float = start + TAU * float(k) / float(crown) + rng.randf_range(-0.05, 0.05)
		var outward := Vector3(cos(angle), 0.0, sin(angle))
		var cluster: bool = k % 3 == 0
		var radius: float = rng.randf_range(2.3, 2.6) if cluster else rng.randf_range(1.9, 2.4)
		var lean: float = deg_to_rad(rng.randf_range(24.0, 32.0) if cluster else rng.randf_range(30.0, 40.0))
		_put_leaning(_scene(colours[k % colours.size()], 0 if cluster else 1), crystal + outward * radius,
			outward, lean, rng.randf_range(0.9, 1.15) * (0.95 if cluster else 1.0), rng)

	# At the foot of every standing stone, on the side away from the crystal.
	for stone: Node3D in stones:
		var at: Vector3 = stone.global_position
		var outward := Vector3(at.x - crystal.x, 0.0, at.z - crystal.z).normalized()
		var reach: float = _footprint(stone) + rng.randf_range(0.4, 1.0)
		var angle: float = rng.randf_range(-0.9, 0.9)
		var kind: int = 0 if rng.randf() < 0.6 else 1
		_put(_scene(colours[rng.randi() % colours.size()], kind), at + outward.rotated(Vector3.UP, angle) * reach, rng, 1.0)

	# A spire of each colour at the five carved pillars, lit.
	for i: int in pillars.size():
		var pillar: Node3D = pillars[i]
		var at: Vector3 = pillar.global_position
		var outward := Vector3(at.x - crystal.x, 0.0, at.z - crystal.z).normalized()
		var spire: Node3D = _put(_scene(colours[i % colours.size()], 2), at + outward * (_footprint(pillar) + 1.2), rng, 1.0)
		if spire != null:
			# Added after the navmesh bake, so it may not block: enemies would walk into a
			# solid the navmesh does not know about.
			for body: Node in spire.find_children("*", "StaticBody3D", true, false):
				body.queue_free()


func _scene(colour: String, kind: int) -> PackedScene:
	return load("res://assets/nature/scenes/%s.tscn" % CRYSTALS[colour][kind]) as PackedScene


## One crystal of `scene` stood on the ground at `spot`, turned and sized at random.
func _put(scene: PackedScene, spot: Vector3, rng: RandomNumberGenerator, scale_mult: float) -> Node3D:
	if scene == null:
		return null
	var node := scene.instantiate() as Node3D
	add_child(node)
	node.global_position = Vector3(spot.x, _ground(spot), spot.z)
	node.rotation.y = rng.randf_range(0.0, TAU)
	node.scale = Vector3.ONE * rng.randf_range(0.85, 1.25) * scale_mult
	return node


## A crystal at `spot` that leans `lean` radians away from the centre, along `outward`:
## turned about its own axis first, at random, so no two in a ring are the same, then
## tipped over. Set a little into the ground, since a tipped base lifts on its low side.
func _put_leaning(scene: PackedScene, spot: Vector3, outward: Vector3, lean: float, size: float,
		rng: RandomNumberGenerator) -> Node3D:
	var node: Node3D = _put(scene, spot, rng, 1.0)
	if node == null:
		return null
	var tip := Basis(Vector3.UP.cross(outward).normalized(), lean)
	node.global_basis = (tip * Basis(Vector3.UP, rng.randf_range(0.0, TAU))).scaled(Vector3.ONE * size)
	node.global_position.y -= 0.12 * size
	return node


## Half the widest side of what `node` draws on the ground, in metres.
func _footprint(node: Node3D) -> float:
	var widest: float = 0.5
	for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null:
			continue
		var box: AABB = mesh.global_transform * mesh.mesh.get_aabb()
		widest = maxf(widest, maxf(box.size.x, box.size.z) * 0.5)
	return widest


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
