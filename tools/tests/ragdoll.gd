extends Node3D
## Regression test: do killed enemies go limp the way the Ragdolls setting says, and stop
## costing anything once they have come to rest?
##
## On a flat stage, with real physics frames: Full ragdolls a light kill, Limited only a big
## one, Off none; the cap holds; a ragdoll lets go of the model's transform while it flies,
## comes to rest lying down near the corpse it belongs to, and then frees its bodies.
##
## Run with:  godot --headless --path . res://tools/tests/ragdoll.tscn
## Prints "TEST RESULT: PASS" or a FAIL listing what did not hold.

var _failures: Array[String] = []


func _ready() -> void:
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1 | EnemyBase.ENVIRONMENT_LAYER
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200.0, 0.2, 200.0)
	floor_shape.shape = box
	floor_shape.position.y = -0.1
	floor_body.add_child(floor_shape)
	add_child(floor_body)
	_run.call_deferred()


func _spawn(at: Vector3) -> EnemyBase:
	var enemy: EnemyBase = (load("res://scenes/misc/enemy.tscn") as PackedScene).instantiate()
	enemy.set_meta("enemy_color", "Red")
	enemy.set_meta("enemy_type", "Melee")
	add_child(enemy)
	enemy.global_position = at
	enemy.set_physics_process(false)
	return enemy


## Kills `enemy` with `fraction` of its full health from -X.
func _kill(enemy: EnemyBase, fraction: float) -> void:
	var source := Node3D.new()
	add_child(source)
	source.global_position = enemy.global_position - Vector3(2.0, 0.0, 0.0)
	var hit: float = enemy.enemy_data.health * fraction
	enemy.health = minf(enemy.health, hit)
	enemy.take_damage(hit, source)
	enemy.set_physics_process(true)
	source.queue_free()


func _frames(count: int) -> void:
	for i: int in count:
		await get_tree().physics_frame


func _ragdoll_of(enemy: EnemyBase) -> EnemyRagdoll:
	return enemy.get_node_or_null("Ragdoll") as EnemyRagdoll


func _run() -> void:
	var saved_quality: int = GraphicsSettings.ragdoll_quality
	var saved_caps: Array[int] = GameSettings.ragdoll_max_active.duplicate()
	await _frames(10)

	# Full: even a light kill goes limp.
	GraphicsSettings.apply_ragdoll_quality(GraphicsSettings.RagdollQuality.FULL)
	var light := _spawn(Vector3(0.0, 0.05, 0.0))
	await _frames(5)
	_kill(light, 0.15)
	await _frames(15)
	var ragdoll := _ragdoll_of(light)
	_check("Full ragdolls a light kill", ragdoll != null and EnemyRagdoll.active_count() == 1,
		"ragdoll %s, active %d" % [ragdoll != null, EnemyRagdoll.active_count()])
	var visual: Node3D = light._visual_root
	_check("the model lets go of the body while it flies", visual != null and visual.top_level, "still parented")

	# It comes to rest, lying down, near its corpse - and lets its bodies go.
	await _frames(int(GameSettings.ragdoll_max_seconds * 60.0) + 30)
	var bodies: int = 0
	if ragdoll != null:
		for child: Node in ragdoll.get_children():
			if child is RigidBody3D:
				bodies += 1
	_check("it freezes and frees its bodies", EnemyRagdoll.active_count() == 0 and bodies == 0,
		"active %d, bodies left %d" % [EnemyRagdoll.active_count(), bodies])
	var skeleton: Skeleton3D = visual.find_child("Skeleton3D", true, false) as Skeleton3D if visual != null else null
	if skeleton != null:
		var hips: Vector3 = (skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("mixamorig_Hips"))).origin
		_check("it lies on the ground", hips.y < 0.6, "hips %.2fm up" % hips.y)
		var apart: float = Vector2(hips.x - light.global_position.x, hips.z - light.global_position.z).length()
		_check("it lies near its corpse", apart < 3.0, "%.2fm from the corpse" % apart)
	else:
		_check("it lies on the ground", false, "no skeleton")

	# Limited: the light kill keeps its ordinary death, the big one goes limp.
	GraphicsSettings.apply_ragdoll_quality(GraphicsSettings.RagdollQuality.LIMITED)
	var tap := _spawn(Vector3(0.0, 0.05, 8.0))
	var blast := _spawn(Vector3(0.0, 0.05, 16.0))
	await _frames(5)
	_kill(tap, 0.15)
	_kill(blast, 1.5)
	await _frames(15)
	_check("Limited leaves a light kill alone", _ragdoll_of(tap) == null, "it ragdolled")
	_check("Limited ragdolls a big kill", _ragdoll_of(blast) != null, "it did not")

	# Off: nothing.
	GraphicsSettings.apply_ragdoll_quality(GraphicsSettings.RagdollQuality.OFF)
	var plain := _spawn(Vector3(0.0, 0.05, 24.0))
	await _frames(5)
	_kill(plain, 1.5)
	await _frames(15)
	_check("Off ragdolls nothing", _ragdoll_of(plain) == null, "it ragdolled")

	# The cap: with room for one, the second kill keeps its ordinary death.
	await _frames(int(GameSettings.ragdoll_max_seconds * 60.0) + 30)
	GameSettings.ragdoll_max_active = [0, 1, 1]
	GraphicsSettings.apply_ragdoll_quality(GraphicsSettings.RagdollQuality.FULL)
	var first := _spawn(Vector3(0.0, 0.05, 32.0))
	var second := _spawn(Vector3(0.0, 0.05, 40.0))
	await _frames(5)
	_kill(first, 1.5)
	_kill(second, 1.5)
	await _frames(15)
	_check("the cap holds", EnemyRagdoll.active_count() == 1
		and (_ragdoll_of(first) == null) != (_ragdoll_of(second) == null),
		"active %d" % EnemyRagdoll.active_count())

	GameSettings.ragdoll_max_active = saved_caps
	GraphicsSettings.apply_ragdoll_quality(saved_quality)
	if _failures.is_empty():
		print("TEST RESULT: PASS")
	else:
		print("TEST RESULT: FAIL\n  " + "\n  ".join(_failures))
	get_tree().quit()


func _check(what: String, ok: bool, detail: String) -> void:
	print("%s %s (%s)" % ["ok  " if ok else "FAIL", what, detail])
	if not ok:
		_failures.append("%s: %s" % [what, detail])
