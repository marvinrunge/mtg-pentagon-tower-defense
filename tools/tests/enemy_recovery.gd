extends Node
## Regression test: is an enemy that leaves the walkable map put back on it, alive?
##
## On the real map, once its navmesh is in: one enemy is dropped far under the terrain and
## has to be back on the navmesh within a moment; another is stood on a platform out past
## the edge of the map, off the navmesh but on solid ground, and has to stay put through
## the grace period and come back after it. Both must still be alive and unhurt - recovery
## is not a kill.
##
## Run with:  godot --headless --path . res://tools/tests/enemy_recovery.tscn
## Prints "TEST RESULT: PASS" or a FAIL listing what did not hold.

var _frames: int = 0
var _started: bool = false
var _failures: Array[String] = []


func _ready() -> void:
	if get_meta("armed", false):
		return
	call_deferred("_boot")


func _boot() -> void:
	var probe: Node = load("res://tools/tests/enemy_recovery.gd").new()
	probe.name = "EnemyRecoveryTest"
	probe.set_meta("armed", true)
	get_tree().root.add_child(probe)
	get_tree().change_scene_to_file("res://scenes/misc/main.tscn")


func _process(_delta: float) -> void:
	if _started or not get_meta("armed", false):
		return
	_frames += 1
	if _frames < 90:
		return
	# Until the map has taken the baked navmesh in, every query answers (0, 0, 0) - the same
	# wait MainController._wait_for_navigation_map does, measured the same way.
	var player: Node3D = PlayerRegistry.get_local()
	if player == null:
		return
	var probe: Vector3 = player.global_position + Vector3(6.0, 0.0, 6.0)
	if NavigationServer3D.map_get_closest_point(player.get_world_3d().navigation_map, probe) == Vector3.ZERO:
		return
	_started = true
	await _run()
	get_tree().quit()


func _spawn(at: Vector3) -> EnemyBase:
	var enemy: EnemyBase = (load("res://scenes/misc/enemy.tscn") as PackedScene).instantiate()
	enemy.set_meta("enemy_color", "Red")
	enemy.set_meta("enemy_type", "Melee")
	get_tree().current_scene.add_child(enemy)
	enemy.global_position = at
	return enemy


func _off_navmesh(enemy: EnemyBase) -> float:
	var map: RID = enemy.get_world_3d().navigation_map
	var nearest: Vector3 = NavigationServer3D.map_get_closest_point(map, enemy.global_position)
	return nearest.distance_to(enemy.global_position)


func _frames_pass(count: int) -> void:
	for i: int in count:
		await get_tree().physics_frame


func _run() -> void:
	var player: Node3D = PlayerRegistry.get_local()
	if player == null:
		print("TEST RESULT: FAIL (no player)")
		return
	var map: RID = player.get_world_3d().navigation_map

	# Fallen through the ground.
	var faller := _spawn(player.global_position + Vector3(6.0, 0.0, 6.0))
	await _frames_pass(20)
	var faller_health: float = faller.health
	faller.global_position += Vector3(0.0, -25.0, 0.0)
	await _frames_pass(45)
	_check("an enemy under the ground is put back on the navmesh", _off_navmesh(faller) < 1.0,
		"%.1fm off the navmesh" % _off_navmesh(faller))
	_check("and is still alive and unhurt", not faller.is_dying and is_equal_approx(faller.health, faller_health),
		"dying %s, health %.0f of %.0f" % [faller.is_dying, faller.health, faller_health])

	# Pushed off the edge onto solid ground the navmesh does not cover: a platform well
	# outside the map, at the height of the nearest walkable ground.
	var edge: Vector3 = NavigationServer3D.map_get_closest_point(map, Vector3(2000.0, 0.0, 0.0))
	var outside: Vector3 = edge + Vector3(40.0, 0.0, 0.0)
	var platform := StaticBody3D.new()
	platform.collision_layer = EnemyBase.ENVIRONMENT_LAYER
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(12.0, 1.0, 12.0)
	shape.shape = box
	platform.add_child(shape)
	get_tree().current_scene.add_child(platform)
	platform.global_position = outside - Vector3(0.0, 0.5, 0.0)
	await _frames_pass(2)
	var stray := _spawn(outside + Vector3(0.0, 0.2, 0.0))
	var stray_health: float = stray.health
	await _frames_pass(30)
	_check("an enemy just off the navmesh gets its grace period", _off_navmesh(stray) > 3.0,
		"already back after half a second (%.1fm off)" % _off_navmesh(stray))
	await _frames_pass(int((GameSettings.enemy_recovery_off_seconds + GameSettings.enemy_recovery_check_interval * 2.0) * 60.0))
	_check("an enemy left off the navmesh is put back on it", _off_navmesh(stray) < 1.0,
		"%.1fm off the navmesh" % _off_navmesh(stray))
	_check("and is still alive and unhurt", not stray.is_dying and is_equal_approx(stray.health, stray_health),
		"dying %s, health %.0f of %.0f" % [stray.is_dying, stray.health, stray_health])

	if _failures.is_empty():
		print("TEST RESULT: PASS")
	else:
		print("TEST RESULT: FAIL\n  " + "\n  ".join(_failures))


func _check(what: String, ok: bool, detail: String) -> void:
	print("%s %s (%s)" % ["ok  " if ok else "FAIL", what, detail])
	if not ok:
		_failures.append("%s: %s" % [what, detail])
