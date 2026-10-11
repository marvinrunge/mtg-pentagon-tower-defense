extends Node
## Screenshots each mana well up close at several times of day - to judge the well models
## and the magical surface in their basins (scenes/mana_wells/*.tscn) by day and by night.
##
## Run with (windowed - a headless run renders nothing):
##   "G:\Godot\Godot_v4.7-stable_win64_console.exe" --path . --resolution 1280x720 res://tools/tests/well_shot.tscn -- <folder> [White,Red] [13,23]
##
## The camera stands on the crystal's side of each well, a little above it, looking down
## into the basin. One PNG per lane and hour lands in <folder>.

const DEFAULT_LANES: Array = ["White", "Blue", "Black", "Red", "Green"]
const DEFAULT_HOURS: Array = [13.0, 23.0]
## From the well towards the crystal, and up, in metres.
const STAND_BACK := 6.5
const STAND_UP := 3.6
const SETTLE_FRAMES := 120

var _frames: int = 0
var _started: bool = false


func _ready() -> void:
	if get_meta("armed", false):
		return
	call_deferred("_boot")


func _boot() -> void:
	var probe: Node = load("res://tools/tests/well_shot.gd").new()
	probe.name = "WellShot"
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
	var folder: String = args[0] if args.size() > 0 else "user://well_shot"
	var lanes: Array = Array(args[1].split(",")) if args.size() > 1 else DEFAULT_LANES
	var hours: Array = DEFAULT_HOURS
	if args.size() > 2:
		hours = []
		for h: String in args[2].split(","):
			hours.append(float(h))
	DirAccess.make_dir_recursive_absolute(folder)

	var scene: Node = get_tree().current_scene
	var hud: Node = scene.get_node_or_null("HUD")
	if hud is CanvasLayer:
		(hud as CanvasLayer).visible = false
	var sky: Node = scene.get_node_or_null("Sky3D")
	sky.set("game_time_enabled", false)
	var pacing: Node = sky.get_node_or_null("DayNightPacing")
	if pacing != null:
		pacing.set_process(false)
	# The players stand at the crystal and would not be in these shots, but the camera rig
	# follows the local one - this camera takes over instead.
	var camera := Camera3D.new()
	camera.far = 4000.0
	camera.fov = 55.0
	scene.add_child(camera)
	camera.current = true

	for lane: String in lanes:
		var well: Node3D = scene.get_node("NavigationRegion3D/Lanes/Lane_%s/ManaSource/Visual" % lane)
		var at: Vector3 = well.global_position
		var inward := Vector3(-at.x, 0.0, -at.z).normalized()
		camera.global_position = at + inward * STAND_BACK + Vector3(0.0, STAND_UP, 0.0)
		camera.look_at(at + Vector3(0.0, 0.9, 0.0), Vector3.UP)
		for hour: float in hours:
			for enemy: Node in get_tree().get_nodes_in_group("enemies"):
				enemy.queue_free()
			sky.set("current_time", hour)
			if pacing != null:
				pacing.call("_update_crystal_night", hour)
			for i: int in SETTLE_FRAMES:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var file: String = "%s_%05.2f.png" % [lane.to_lower(), hour]
			get_viewport().get_texture().get_image().save_png(folder.path_join(file))
			print("WELL saved %s" % file)
	get_tree().quit()
