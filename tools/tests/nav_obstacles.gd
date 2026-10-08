extends Node
## Regression test: everything that blocks an enemy is in the navmesh bake.
##
## Run with:  godot --headless --path . res://tools/tests/nav_obstacles.tscn
##
## Props with a StaticBody3D on the environment layer stopped enemies dead while the navmesh
## knew nothing about them - paths ran straight through, and whole waves froze in front of
## the white well. This drops a block onto the white lane BEFORE the bake, the way a placed
## prop would be, and checks the path walks around it. It also checks every lane still
## reaches the crystal, since a bake that blocks too much fails the same waves a different way.

const OBSTACLE_CENTER := Vector3(0.0, 0.0, -145.0)
const OBSTACLE_HALF_SIZE: float = 4.0
## How far short of the crystal's centre a path may end. The crystal itself is not in the
## navmesh, so the path stops at its foot.
const CRYSTAL_REACH: float = 6.0
const TIMEOUT_FRAMES: int = 20000

var _frames: int = 0
var _injected: bool = false
var _done: bool = false
var _failures: Array[String] = []
var _obstacle: StaticBody3D = null


## Hooked up by the boot node before the scene swap, so the block is placed while the map
## is still entering the tree - ahead of the deferred bake, exactly where a prop saved in
## the scene would be.
func on_node_added(node: Node) -> void:
	if _injected or not node.has_method("bake_map_navigation"):
		return
	_injected = true
	_inject_obstacle.call_deferred(node)


func _process(_delta: float) -> void:
	if _done:
		return
	_frames += 1
	var main: Node = get_tree().current_scene
	if main == null or not main.has_method("bake_map_navigation"):
		return
	# The wave manager is the last thing bake_map_navigation sets up, after the navigation
	# map has taken the new navmesh in, so its arrival is the moment paths can be asked for.
	var ready: bool = main.has_node("WaveManager")
	if not ready and _frames < TIMEOUT_FRAMES:
		return
	_done = true
	if not ready:
		print("TEST RESULT: FAIL (the navmesh never finished baking)")
	else:
		_run(main, main.get_node("NavigationRegion3D"))
	get_tree().quit()


func _inject_obstacle(main: Node) -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(OBSTACLE_HALF_SIZE * 2.0, 40.0, OBSTACLE_HALF_SIZE * 2.0)
	shape.shape = box
	_obstacle = StaticBody3D.new()
	_obstacle.name = "TestObstacle"
	_obstacle.collision_layer = EnemyBase.ENVIRONMENT_LAYER
	_obstacle.collision_mask = 0
	_obstacle.add_child(shape)
	main.add_child(_obstacle)
	_obstacle.global_position = OBSTACLE_CENTER


func _check(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		print("  ok   %s" % label)
	else:
		print("  FAIL %s %s" % [label, detail])
		_failures.append(label)


func _run(main: Node, region: NavigationRegion3D) -> void:
	var map: RID = region.get_navigation_map()
	var crystal: Vector3 = (main.get_node("NavigationRegion3D/CrystalAnchor") as Node3D).global_position

	_check("the obstacle joined the bake", _obstacle.is_in_group(main.NAVMESH_SOURCE_GROUP))

	for lane_name: String in main.LANE_NAMES:
		var spawner: Node3D = main.get_node("NavigationRegion3D/Lanes/Lane_%s/EnemySpawner" % lane_name)
		var path: PackedVector3Array = NavigationServer3D.map_get_path(map, spawner.global_position, crystal, true)
		if path.is_empty():
			_check("%s lane has a path" % lane_name, false)
			continue
		var end: Vector3 = path[path.size() - 1]
		var reach: float = Vector2(end.x - crystal.x, end.z - crystal.z).length()
		_check("%s lane reaches the crystal" % lane_name, reach < CRYSTAL_REACH,
			"path ends %.2fm from it" % reach)
		if lane_name == "White":
			_check("White lane walks around the obstacle", not _crosses_obstacle(path))

	if _failures.is_empty():
		print("TEST RESULT: PASS")
	else:
		print("TEST RESULT: FAIL (%d)" % _failures.size())


## Samples every segment, so a path that cuts a corner of the block counts as well as one
## with a corner inside it.
func _crosses_obstacle(path: PackedVector3Array) -> bool:
	for i: int in range(path.size() - 1):
		var steps: int = maxi(1, int(path[i].distance_to(path[i + 1]) / 0.25))
		for s: int in range(steps + 1):
			var point: Vector3 = path[i].lerp(path[i + 1], float(s) / float(steps))
			if absf(point.x - OBSTACLE_CENTER.x) < OBSTACLE_HALF_SIZE \
					and absf(point.z - OBSTACLE_CENTER.z) < OBSTACLE_HALF_SIZE:
				return true
	return false
