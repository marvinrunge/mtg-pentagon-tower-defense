extends Node
## Regression test for the debug wave controls: does a run start at the wave asked for, and
## does a jump clear the wave in progress and start the new one - from the middle of a wave
## and from an open Upkeep alike?
##
## Run with:  godot --headless --path . res://tools/tests/debug_wave_jump.tscn
## Prints "TEST RESULT: PASS" or a FAIL listing what did not hold.

const START_WAVE := 5

var _frames: int = 0
var _started: bool = false
var _failures: Array[String] = []


func _ready() -> void:
	if get_meta("armed", false):
		return
	call_deferred("_boot")


func _boot() -> void:
	GameSettings.debug_start_wave = START_WAVE
	var probe: Node = load("res://tools/tests/debug_wave_jump.gd").new()
	probe.name = "DebugWaveJumpTest"
	probe.set_meta("armed", true)
	get_tree().root.add_child(probe)
	get_tree().change_scene_to_file("res://scenes/misc/main.tscn")


func _process(_delta: float) -> void:
	if _started or not get_meta("armed", false):
		return
	_frames += 1
	if _frames < 90:
		return
	if _waves() == null:
		return
	_started = true
	# Group delays are seconds long; this only makes the waiting shorter.
	Engine.time_scale = 4.0
	await _run()
	Engine.time_scale = 1.0
	GameSettings.debug_start_wave = 1
	if _failures.is_empty():
		print("TEST RESULT: PASS")
	else:
		print("TEST RESULT: FAIL\n  " + "\n  ".join(_failures))
	get_tree().quit()


func _waves() -> WaveManager:
	var scene: Node = get_tree().current_scene
	return scene.get_node_or_null("WaveManager") as WaveManager if scene != null else null


func _check(ok: bool, what: String, detail: String) -> void:
	print("%s   %s (%s)" % ["ok" if ok else "FAIL", what, detail])
	if not ok:
		_failures.append("%s (%s)" % [what, detail])


func _enemies() -> Array[Node]:
	return get_tree().get_nodes_in_group("enemies")


## Waits until the wave has put something on the map, or gives up after `seconds`.
func _wait_for_enemies(seconds: float) -> bool:
	var until: int = Time.get_ticks_msec() + int(seconds * 1000.0 / Engine.time_scale)
	while _enemies().is_empty() and Time.get_ticks_msec() < until:
		await get_tree().process_frame
	return not _enemies().is_empty()


func _run() -> void:
	var waves: WaveManager = _waves()
	_check(waves.current_wave + 1 == START_WAVE, "a run starts at the debug start wave",
		"wave %d, asked for %d" % [waves.current_wave + 1, START_WAVE])

	_check(await _wait_for_enemies(40.0), "that wave sends enemies", "%d alive" % _enemies().size())

	# Mid-wave jump.
	var old: Array[Node] = _enemies()
	waves.debug_jump_to_wave(12)
	await get_tree().process_frame
	var survivors: int = 0
	for enemy: Node in old:
		if is_instance_valid(enemy):
			survivors += 1
	_check(survivors == 0, "a jump clears the wave in progress", "%d of %d left" % [survivors, old.size()])
	_check(waves.current_wave + 1 == 12, "and starts the wave asked for", "wave %d" % [waves.current_wave + 1])
	_check(waves.is_spawning and waves.active_enemies == 0, "with a fresh count",
		"spawning %s, active %d" % [waves.is_spawning, waves.active_enemies])
	_check(await _wait_for_enemies(40.0), "which sends its enemies", "%d alive" % _enemies().size())

	# Jump out of an open Upkeep: end the wave the ordinary way first.
	for enemy: Node in _enemies():
		enemy.queue_free()
	waves.pending_groups.clear()
	waves.is_spawning = false
	waves.active_enemies = 0
	waves._trigger_next_wave()
	await get_tree().process_frame
	_check(waves.in_upkeep, "the wave ended into Upkeep", "in_upkeep %s" % waves.in_upkeep)
	waves.debug_jump_to_wave(3)
	await get_tree().process_frame
	var panel: Node = get_tree().current_scene.find_child("UpkeepPanel", true, false)
	_check(not waves.in_upkeep and waves.current_wave + 1 == 3 and waves.is_spawning,
		"a jump from Upkeep closes it and starts the wave",
		"in_upkeep %s, wave %d, spawning %s" % [waves.in_upkeep, waves.current_wave + 1, waves.is_spawning])
	if panel != null:
		_check(not (panel as CanvasLayer).visible, "and the Upkeep panel is gone", "visible %s" % (panel as CanvasLayer).visible)
