extends Node
## Frame-time benchmark for crowds: fills the real map with N live enemies and logs what
## each step costs, split into script, physics, navigation and GPU time, so a change aimed
## at "the game drops frames when many enemies are alive" has a before and an after.
##
## Run with (windowed - a headless run renders nothing and measures nothing):
##   "G:\Godot\Godot_v4.7-stable_win64_console.exe" --path . --resolution 1600x900 res://tools/tests/crowd_perf.tscn -- [40,80,160] [--off=<what>]
##
## --off takes one suspect out after the spawn, to see what a spike is made of:
##   path   no periodic repathing or target re-evaluation
##   ai     no enemy _physics_process at all (no AI, no movement)
##   anim   every enemy AnimationPlayer paused
##   bars   health bars removed
##   recovery  no off-navmesh recovery check (EnemyBase._check_recovery)
##
## The waves are stopped and the enemies are spawned through MainController.request_enemy,
## the same path a wave takes, spread evenly over the five lanes from each spawner inward,
## so they are marching on the crystal while they are measured. Every count is measured
## twice: with the camera looking down a lane into the crowd, and looking at the sky, which
## leaves the CPU cost and takes away most of the rendering one.

const DEFAULT_COUNTS: Array = [0, 40, 80, 160]
const TYPES: Array = ["Melee", "Melee", "Ranged", "Mage"]
const SETTLE_FRAMES := 60
const MEASURE_FRAMES := 240

var _frames: int = 0
var _started: bool = false
var _scene: Node3D
var _camera: Camera3D
var _off: String = ""


func _ready() -> void:
	if get_meta("armed", false):
		return
	call_deferred("_boot")


func _boot() -> void:
	var probe: Node = load("res://tools/tests/crowd_perf.gd").new()
	probe.name = "CrowdPerf"
	probe.set_meta("armed", true)
	get_tree().root.add_child(probe)
	get_tree().change_scene_to_file("res://scenes/misc/main.tscn")


func _process(_delta: float) -> void:
	if _started or not get_meta("armed", false):
		return
	_frames += 1
	# Long enough for the navigation bake and the terrain to finish building.
	if _frames < 300:
		return
	_started = true
	_run()


func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	_scene = get_tree().current_scene as Node3D
	var hud: Node = _scene.get_node_or_null("HUD")
	if hud is CanvasLayer:
		(hud as CanvasLayer).visible = false
	var sky: Node = _scene.get_node_or_null("Sky3D")
	if sky != null:
		sky.set("game_time_enabled", false)
		sky.set("current_time", 12.0)
	var waves: Node = _scene.get_node_or_null("WaveManager")
	if waves != null:
		waves.set_process(false)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)

	_camera = Camera3D.new()
	_camera.far = 4000.0
	_scene.add_child(_camera)
	_camera.current = true

	var counts: Array = DEFAULT_COUNTS
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--off="):
			_off = arg.trim_prefix("--off=")
		elif not arg.begins_with("--"):
			counts = [0]
			for c: String in arg.split(","):
				counts.append(int(c))
	if _off == "path":
		GameSettings.enemy_path_update_interval = 1.0e9
		GameSettings.enemy_target_eval_interval = 1.0e9
	if _off == "recovery":
		GameSettings.enemy_recovery_check_interval = 1.0e9
	print("CROWD off=%s" % (_off if _off != "" else "nothing"))
	_time_closest_point()

	print("CROWD %s  %s" % [RenderingServer.get_current_rendering_method(), RenderingServer.get_video_adapter_name()])
	print("CROWD %-18s %6s %7s %7s %7s %7s %7s %7s %7s %7s %6s" % [
		"view", "alive", "avg ms", "1% ms", "proc", "phys", "nav", "gpu", "draws", "objects", ">30ms"])
	for count: int in counts:
		_clear_enemies()
		await get_tree().physics_frame
		_spawn(count)
		await get_tree().process_frame
		_take_out()
		await _measure("lane", count, true)
		await _measure("sky", count, false)
		_report_off_path()
	get_tree().quit()


## What one closest-point query on the real navmesh costs - the recovery check makes one per
## enemy, and wave spawning one per unit.
func _time_closest_point() -> void:
	var map: RID = (_scene.get("nav_region") as NavigationRegion3D).get_navigation_map()
	var start: int = Time.get_ticks_usec()
	for i: int in 50:
		NavigationServer3D.map_get_closest_point(map, Vector3(randf_range(-150, 150), 5.0, randf_range(-150, 150)))
	print("CROWD map_get_closest_point: %.3f ms per call" % [float(Time.get_ticks_usec() - start) / 50000.0])


## How many live enemies the recovery check would still send to the expensive navmesh query,
## and why: no path yet, or standing somewhere other than on it.
func _report_off_path() -> void:
	var no_path: int = 0
	var off: int = 0
	var total: int = 0
	var far: Array = []
	for enemy: Node in get_tree().get_nodes_in_group("enemies"):
		if enemy.get("is_dying"):
			continue
		total += 1
		var agent: NavigationAgent3D = enemy.get("nav_agent")
		if agent == null or agent.get_current_navigation_path().is_empty():
			no_path += 1
		elif not enemy.call("_on_planned_path"):
			off += 1
			if far.size() < 4:
				var path: PackedVector3Array = agent.get_current_navigation_path()
				var idx: int = agent.get_current_navigation_path_index()
				far.append("pos=%s idx=%d/%d next=%s fin=%s" % [(enemy as Node3D).global_position.snapped(Vector3.ONE * 0.1), idx, path.size(), path[clampi(idx, 0, path.size() - 1)].snapped(Vector3.ONE * 0.1), agent.is_navigation_finished()])
	print("CROWD off-path: %d of %d (no path %d)  %s" % [off, total, no_path, far])


func _clear_enemies() -> void:
	for enemy: Node in get_tree().get_nodes_in_group("enemies"):
		enemy.free()


func _spawn(count: int) -> void:
	var controller: Node = _scene
	var spawners: Array = controller.get("enemy_spawners")
	var colors: Array = controller.get("LANE_NAMES")
	var map: RID = (controller.get("nav_region") as NavigationRegion3D).get_navigation_map()
	var crystal: Vector3 = (controller.get("crystal_anchor") as Node3D).global_position
	for i: int in count:
		var lane: int = i % spawners.size()
		var start: Vector3 = (spawners[lane] as Node3D).global_position
		# Spread from the spawner a third of the way to the crystal, a few metres either side.
		var along: float = float(i / spawners.size()) / maxf(float(count / spawners.size()), 1.0) * 0.33
		var side: Vector3 = (crystal - start).cross(Vector3.UP).normalized() * randf_range(-6.0, 6.0)
		var at: Vector3 = NavigationServer3D.map_get_closest_point(map, start.lerp(crystal, along) + side)
		controller.call("request_enemy", {
			"position": controller.to_local(at + Vector3(0, 0.5, 0)),
			"color": String(colors[lane]),
			"type": String(TYPES[i % TYPES.size()]),
		})


func _take_out() -> void:
	for enemy: Node in get_tree().get_nodes_in_group("enemies"):
		match _off:
			"ai":
				enemy.set_physics_process(false)
			"anim":
				for player: Node in enemy.find_children("*", "AnimationPlayer", true, false):
					(player as AnimationPlayer).pause()
			"bars":
				var bar: Node = enemy.get("health_bar")
				if bar != null:
					bar.queue_free()


func _point_camera(into_crowd: bool) -> void:
	var spawners: Array = _scene.get("enemy_spawners")
	var crystal: Vector3 = (_scene.get("crystal_anchor") as Node3D).global_position
	var spawner: Vector3 = (spawners[0] as Node3D).global_position
	# Where a player defending a lane stands: a third of the way out, looking at the spawner.
	_camera.global_position = crystal.lerp(spawner, 0.35) + Vector3.UP * 6.0
	if into_crowd:
		_camera.look_at(spawner, Vector3.UP)
	else:
		_camera.look_at(_camera.global_position + Vector3(0.01, 1.0, 0.0), Vector3.FORWARD)


func _measure(view: String, count: int, into_crowd: bool) -> void:
	_point_camera(into_crowd)
	for i: int in SETTLE_FRAMES:
		await get_tree().process_frame
	var vp: RID = get_viewport().get_viewport_rid()
	var times: Array[float] = []
	var proc: float = 0.0
	var phys: float = 0.0
	var nav: float = 0.0
	var gpu: float = 0.0
	var draws: float = 0.0
	var last: int = Time.get_ticks_usec()
	for i: int in MEASURE_FRAMES:
		await get_tree().process_frame
		var now: int = Time.get_ticks_usec()
		times.append(float(now - last) / 1000.0)
		last = now
		proc += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		phys += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		nav += Performance.get_monitor(Performance.TIME_NAVIGATION_PROCESS) * 1000.0
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
		draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	var total: float = 0.0
	for t: float in times:
		total += t
	var avg: float = total / float(times.size())
	var spikes: int = 0
	for t: float in times:
		if t > 30.0:
			spikes += 1
	times.sort()
	var n: float = float(MEASURE_FRAMES)
	print("CROWD %-18s %6d %7.2f %7.2f %7.2f %7.2f %7.2f %7.2f %7.0f %7.0f %6d" % [
		view, get_tree().get_nodes_in_group("enemies").size(), avg, times[int(times.size() * 0.99)],
		proc / n, phys / n, nav / n, gpu / n, draws / n, Performance.get_monitor(Performance.OBJECT_NODE_COUNT), spikes])
