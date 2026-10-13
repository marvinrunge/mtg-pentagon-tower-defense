extends Node
## Frame-time benchmark for a real wave: jumps the live map to wave N and records what the
## frames cost while it spawns, forms up, marches and charges - the way the game does it,
## through WaveManager, squads and all. tools/tests/crowd_perf.tscn measures a standing crowd;
## this is the one that sees a group's spawn, and a squad breaking into its charge.
##
## Run with (windowed - a headless run renders nothing and measures nothing):
##   "G:\Godot\Godot_v4.7-stable_win64_console.exe" --path . --rendering-driver vulkan --resolution 1600x900 res://tools/tests/wave_perf.tscn -- [wave] [seconds]
##
## Prints one line per WINDOW seconds: average and worst frame, how many frames went over
## 33 ms, and the enemies alive at the end of it. The camera stands where a defending player
## does, by the crystal looking out down a lane.

const WINDOW := 5.0

var _frames: int = 0
var _started: bool = false


func _ready() -> void:
	if get_meta("armed", false):
		return
	call_deferred("_boot")


func _boot() -> void:
	var probe: Node = load("res://tools/tests/wave_perf.gd").new()
	probe.name = "WavePerf"
	probe.set_meta("armed", true)
	get_tree().root.add_child(probe)
	get_tree().change_scene_to_file("res://scenes/misc/main.tscn")


func _process(_delta: float) -> void:
	if _started or not get_meta("armed", false):
		return
	_frames += 1
	if _frames < 300:
		return
	_started = true
	_run()


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var wave: int = int(args[0]) if args.size() > 0 else 20
	var seconds: float = float(args[1]) if args.size() > 1 else 40.0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var scene: Node3D = get_tree().current_scene as Node3D
	var hud: Node = scene.get_node_or_null("HUD")
	if hud is CanvasLayer:
		(hud as CanvasLayer).visible = false
	var sky: Node = scene.get_node_or_null("Sky3D")
	if sky != null:
		sky.set("game_time_enabled", false)
		sky.set("current_time", 12.0)
	# The player stands still and takes no part; the crystal must not fall mid-measurement.
	for player: Node in get_tree().get_nodes_in_group("player"):
		player.set_physics_process(false)
	scene.set("crystal_health", 1.0e9)

	var spawners: Array = scene.get("enemy_spawners")
	var crystal: Vector3 = (scene.get("crystal_anchor") as Node3D).global_position
	var camera := Camera3D.new()
	camera.far = 4000.0
	scene.add_child(camera)
	camera.current = true
	camera.global_position = crystal + Vector3(0.0, 6.0, 0.0)
	camera.look_at((spawners[0] as Node3D).global_position, Vector3.UP)

	scene.get_node("WaveManager").call("debug_jump_to_wave", wave)
	print("WAVE %d  %s  %s" % [wave, RenderingServer.get_current_rendering_method(), RenderingServer.get_video_adapter_name()])
	print("WAVE %6s %8s %8s %6s %7s" % ["t", "avg ms", "worst", ">33ms", "alive"])
	var elapsed: float = 0.0
	var window_frames: Array[float] = []
	var window_end: float = WINDOW
	var all_frames: Array[float] = []
	var last: int = Time.get_ticks_usec()
	while elapsed < seconds:
		await get_tree().process_frame
		var now: int = Time.get_ticks_usec()
		var ms: float = float(now - last) / 1000.0
		last = now
		elapsed += ms / 1000.0
		window_frames.append(ms)
		all_frames.append(ms)
		if elapsed >= window_end:
			_report(window_end, window_frames)
			window_frames.clear()
			window_end += WINDOW
	all_frames.sort()
	var total: float = 0.0
	for ms: float in all_frames:
		total += ms
	print("WAVE total: avg %.1f ms, 1%% %.1f ms, worst %.1f ms, %d frames over 33 ms" % [
		total / all_frames.size(), all_frames[int(all_frames.size() * 0.99)], all_frames[-1],
		all_frames.filter(func(ms: float) -> bool: return ms > 33.0).size()])
	get_tree().quit()


func _report(at: float, frames: Array[float]) -> void:
	var total: float = 0.0
	var worst: float = 0.0
	var slow: int = 0
	for ms: float in frames:
		total += ms
		worst = maxf(worst, ms)
		if ms > 33.0:
			slow += 1
	print("WAVE %6.0f %8.1f %8.1f %6d %7d" % [at, total / maxf(frames.size(), 1), worst, slow,
		get_tree().get_nodes_in_group("enemies").size()])
