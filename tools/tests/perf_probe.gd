extends Node
## Frame-time benchmark: flies a camera to fixed viewpoints on the real map and logs what
## each one costs, so every performance change gets a before and an after.
##
## Run with (windowed - a headless run renders nothing and measures nothing):
##   "G:\Godot\Godot_v4.7-stable_win64_console.exe" --path . --resolution 1600x900 res://tools/tests/perf_probe.tscn
##
## VSync and the frame cap are switched off for the run only (nothing is saved), and the
## enemies are cleared before each viewpoint so a wave arriving mid-measurement cannot skew
## one row against the others. Prints one row per viewpoint plus the video memory in use.
##
## User args (after `--`): a folder keeps a screenshot of each row; `--parallax` measures every
## viewpoint twice, terrain parallax off then on, back to back - Sky3D's sun moves between
## runs, so the clock is stopped at noon for the whole run.

## name -> [camera position, point it looks at, heights above ground?]. World space; the
## crystal is at the origin. With the third entry true, the two y values are metres above the
## terrain at that spot rather than absolute - for hillsides, whose height nobody knows offhand.
const VIEWPOINTS: Array = [
	["spawn, towards volcano", Vector3(0.0, 4.0, 22.0), Vector3(-146.0, 60.0, 172.0)],
	["spawn, towards crystal", Vector3(0.0, 4.0, 22.0), Vector3(0.0, 2.0, 0.0)],
	["overview", Vector3(0.0, 120.0, 60.0), Vector3(0.0, 0.0, 0.0)],
	["lane edge, inward", Vector3(0.0, 6.0, -170.0), Vector3(0.0, 2.0, 0.0)],
	["ground, grazing", Vector3(10.0, 1.7, 10.0), Vector3(60.0, 0.5, 60.0)],
	["ground, close-up", Vector3(12.0, 2.2, 12.0), Vector3(16.0, 0.0, 16.0)],
	# Hills, where parallax that only holds on flat ground shows itself first: a ~21 degree
	# slope west of the base seen face-on and along its contour, and the volcano's ~60 degree
	# flank, where the terrain's straight-down texture projection already streaks.
	["hill, facing", Vector3(-198.0, 1.8, -37.0), Vector3(-184.0, 0.0, -32.0), true],
	["hill, across", Vector3(-186.0, 1.8, -52.0), Vector3(-182.0, 0.0, -28.0), true],
	["volcano flank", Vector3(-118.0, 2.0, 150.0), Vector3(-118.0, 0.0, 165.0), true],
]
const SETTLE_FRAMES := 40
const MEASURE_FRAMES := 180

var _frames: int = 0
var _started: bool = false


func _ready() -> void:
	if get_meta("armed", false):
		return
	call_deferred("_boot")


func _boot() -> void:
	var probe: Node = load("res://tools/tests/perf_probe.gd").new()
	probe.name = "PerfProbe"
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
	var scene: Node = get_tree().current_scene
	var hud: Node = scene.get_node_or_null("HUD")
	if hud is CanvasLayer:
		(hud as CanvasLayer).visible = false
	# The clock stopped at noon. Sky3D's sun otherwise moves on between runs, which made the
	# same viewpoint measure differently from one run to the next (shadows cost more with a low
	# sun) and left the screenshots of a dusk run too dark to judge a texture change by.
	var sky: Node = scene.get_node_or_null("Sky3D")
	if sky != null:
		sky.set("game_time_enabled", false)
		sky.set("current_time", 12.0)
	var camera := Camera3D.new()
	camera.far = 4000.0
	scene.add_child(camera)
	camera.current = true

	print("PERF renderer=%s  %s" % [RenderingServer.get_current_rendering_method(), RenderingServer.get_video_adapter_name()])
	print("PERF %-36s %8s %8s %8s %10s %10s" % ["viewpoint", "avg ms", "fps", "1% ms", "draws", "prims"])
	var folder: String = ""
	var compare_parallax: bool = false
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--parallax":
			compare_parallax = true
		elif not arg.begins_with("--"):
			folder = arg
	var parallax_states: Array = [false, true] if compare_parallax else [GraphicsSettings.terrain_parallax]
	var parallax_before: bool = GraphicsSettings.terrain_parallax
	for entry: Array in VIEWPOINTS:
		for enemy: Node in get_tree().get_nodes_in_group("enemies"):
			enemy.queue_free()
		var from: Vector3 = entry[1]
		var to: Vector3 = entry[2]
		if entry.size() > 3 and entry[3]:
			from.y += _ground_height(from)
			to.y += _ground_height(to)
			print("PERF   (%s: camera at %.1f m, looking at %.1f m)" % [entry[0], from.y, to.y])
		camera.global_position = from
		camera.look_at(to, Vector3.UP)
		for parallax: bool in parallax_states:
			# Straight onto the global shader parameter, not through GraphicsSettings: that
			# would save the choice into the player's settings file.
			RenderingServer.global_shader_parameter_set(&"terrain_parallax_strength", 1.0 if parallax else 0.0)
			var label: String = String(entry[0]) + ((" [parallax]" if parallax else " [flat]") if compare_parallax else "")
			await _measure(label, folder)
	RenderingServer.global_shader_parameter_set(&"terrain_parallax_strength", 1.0 if parallax_before else 0.0)
	print("PERF video memory %.0f MB (textures %.0f MB, buffers %.0f MB)" % [
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0,
		Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED) / 1048576.0])
	get_tree().quit()


## The terrain's height under `at`, from a ray down onto the Environment layer.
func _ground_height(at: Vector3) -> float:
	var space: PhysicsDirectSpaceState3D = (get_tree().current_scene as Node3D).get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		Vector3(at.x, 1000.0, at.z), Vector3(at.x, -1000.0, at.z), 1 << 4)
	var hit: Dictionary = space.intersect_ray(query)
	return hit.position.y if hit else 0.0


func _measure(label: String, folder: String) -> void:
	for i: int in SETTLE_FRAMES:
		await get_tree().process_frame
	var times: Array[float] = []
	var draws: float = 0.0
	var prims: float = 0.0
	var last: int = Time.get_ticks_usec()
	for i: int in MEASURE_FRAMES:
		await get_tree().process_frame
		var now: int = Time.get_ticks_usec()
		times.append(float(now - last) / 1000.0)
		last = now
		draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		prims += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	var total: float = 0.0
	for t: float in times:
		total += t
	var avg: float = total / float(times.size())
	times.sort()
	var worst: float = times[int(times.size() * 0.99)]
	print("PERF %-36s %8.2f %8.0f %8.2f %10.0f %10.0f" % [
		label, avg, 1000.0 / avg, worst, draws / MEASURE_FRAMES, prims / MEASURE_FRAMES])
	# A folder also keeps a picture of each row, so a change that buys frames can be checked
	# for what it cost in looks.
	if folder != "":
		await RenderingServer.frame_post_draw
		var file: String = label.replace(", ", "_").replace(" [", "_").replace("]", "").replace(" ", "_") + ".png"
		get_viewport().get_texture().get_image().save_png(folder.path_join(file))
