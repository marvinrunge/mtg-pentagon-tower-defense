extends Node
## Regression test: does a killed enemy get thrown away from the hit that killed it?
##
## Kills two enemies on the real map, one with a huge hit and one with a light finishing
## tap, from a known direction, and lets real physics frames run. Both have to end up
## further along that direction than they started, back on the ground and in the corpse
## list (so Zombify still finds them where they landed) - and the huge hit has to throw its
## body further than the tap does.
##
## Run with:  godot --headless --path . res://tools/tests/death_launch.tscn
## Prints "TEST RESULT: PASS" or a FAIL listing what did not hold.

var _frames: int = 0
var _started: bool = false
var _failures: Array[String] = []


func _ready() -> void:
	if get_meta("armed", false):
		return
	call_deferred("_boot")


func _boot() -> void:
	var probe: Node = load("res://tools/tests/death_launch.gd").new()
	probe.name = "DeathLaunchTest"
	probe.set_meta("armed", true)
	get_tree().root.add_child(probe)
	get_tree().change_scene_to_file("res://scenes/misc/main.tscn")


func _process(_delta: float) -> void:
	if _started or not get_meta("armed", false):
		return
	_frames += 1
	if _frames < 90:
		return
	_started = true
	await _run()
	get_tree().quit()


func _spawn(offset: Vector3) -> EnemyBase:
	var player: Node3D = PlayerRegistry.get_local()
	var enemy: EnemyBase = (load("res://scenes/misc/enemy.tscn") as PackedScene).instantiate()
	enemy.set_meta("enemy_color", "Red")
	enemy.set_meta("enemy_type", "Melee")
	get_tree().current_scene.add_child(enemy)
	enemy.global_position = player.global_position + offset
	return enemy


## Kills `enemy` with `amount` from two metres behind it along -X, so the throw is along +X,
## and returns how far it travelled along X once it has come to rest.
func _kill_and_measure(enemy: EnemyBase, amount: float) -> Dictionary:
	for i: int in 20:
		await get_tree().physics_frame
	var source := Node3D.new()
	get_tree().current_scene.add_child(source)
	source.global_position = enemy.global_position - Vector3(2.0, 0.0, 0.0)
	var start: Vector3 = enemy.global_position
	enemy.take_damage(amount, source)
	source.queue_free()
	for i: int in 150:
		await get_tree().physics_frame
	return {
		"travel": enemy.global_position.x - start.x,
		"drop": absf(enemy.global_position.y - start.y),
		"launch": enemy.death_launch,
		"floor": enemy.is_on_floor(),
		"corpse": EnemyBase.corpses().has(enemy),
	}


func _run() -> void:
	if PlayerRegistry.get_local() == null:
		print("TEST RESULT: FAIL (no player)")
		return
	var heavy: EnemyBase = _spawn(Vector3(6.0, 0.0, 6.0))
	var heavy_result: Dictionary = await _kill_and_measure(heavy, heavy.health * 3.0)
	var light: EnemyBase = _spawn(Vector3(-6.0, 0.0, 6.0))
	light.health = 1.0
	var light_result: Dictionary = await _kill_and_measure(light, 1.0)
	print("heavy %s" % heavy_result)
	print("light %s" % light_result)

	_check("a heavy kill throws the body away from the hit", heavy_result["travel"] > 2.0,
		"%.2fm along the hit" % heavy_result["travel"])
	_check("a light kill still nudges it away", light_result["travel"] > 0.1,
		"%.2fm along the hit" % light_result["travel"])
	_check("a heavy kill throws further than a light one", heavy_result["travel"] > light_result["travel"],
		"%.2f vs %.2f" % [heavy_result["travel"], light_result["travel"]])
	_check("the launch is replicated state", (heavy_result["launch"] as Vector3).x > 0.0,
		"death_launch %s" % heavy_result["launch"])
	_check("the body comes back down", heavy_result["drop"] < 1.0 and light_result["drop"] < 1.0,
		"%.2f / %.2f off the start height" % [heavy_result["drop"], light_result["drop"]])
	_check("it stays a corpse Zombify can raise", heavy_result["corpse"] and light_result["corpse"],
		"heavy %s light %s" % [heavy_result["corpse"], light_result["corpse"]])

	if _failures.is_empty():
		print("TEST RESULT: PASS")
	else:
		print("TEST RESULT: FAIL\n  " + "\n  ".join(_failures))


func _check(what: String, ok: bool, detail: String) -> void:
	print("%s %s (%s)" % ["ok  " if ok else "FAIL", what, detail])
	if not ok:
		_failures.append("%s: %s" % [what, detail])
