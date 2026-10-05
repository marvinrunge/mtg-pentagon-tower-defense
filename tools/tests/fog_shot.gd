extends Node
## Screenshots each biome's fog at several times of day, so a fog change can be judged
## against noon, dusk and night rather than whatever hour the run happened to start at.
##
## Run with (windowed - a headless run renders nothing):
##   "G:\Godot\Godot_v4.7-stable_win64_console.exe" --path . --resolution 1280x720 res://tools/tests/fog_shot.tscn -- <folder> [Black,Green] [13,19.5,23]
##
## The camera stands in a lane, 2 m above the ground partway out from the crystal, looking
## along the lane towards its spawner. One PNG per lane and hour lands in <folder>.

const DEFAULT_LANES: Array = ["Black", "Green"]
const DEFAULT_HOURS: Array = [13.0, 19.5, 23.0]
## How far out from the crystal the camera stands, metres.
const STAND_RADIUS := 70.0
## BiomeAtmosphere eases toward the new biome at ~1.5/s; this many frames lets it settle.
const SETTLE_FRAMES := 240

var _frames: int = 0
var _started: bool = false


func _ready() -> void:
	if get_meta("armed", false):
		return
	call_deferred("_boot")


func _boot() -> void:
	var probe: Node = load("res://tools/tests/fog_shot.gd").new()
	probe.name = "FogShot"
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
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var folder: String = args[0] if args.size() > 0 else "user://fog_shot"
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

	var camera := Camera3D.new()
	camera.far = 4000.0
	scene.add_child(camera)
	camera.current = true

	var center: Vector3 = Vector3.ZERO
	for lane: String in lanes:
		var spawner: Node3D = scene.get_node("NavigationRegion3D/Lanes/Lane_%s/EnemySpawner" % lane)
		var dir := Vector3(spawner.global_position.x - center.x, 0.0, spawner.global_position.z - center.z).normalized()
		var from: Vector3 = center + dir * STAND_RADIUS
		from.y = _ground_height(from) + 2.0
		var to: Vector3 = spawner.global_position
		to.y = _ground_height(to) + 2.0
		camera.global_position = from
		camera.look_at(to, Vector3.UP)
		for hour: float in hours:
			for enemy: Node in get_tree().get_nodes_in_group("enemies"):
				enemy.queue_free()
			sky.set("current_time", hour)
			for i: int in SETTLE_FRAMES:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var file: String = "%s_%05.2f.png" % [lane.to_lower(), hour]
			get_viewport().get_texture().get_image().save_png(folder.path_join(file))
			print("FOG saved %s" % file)
	get_tree().quit()


## The terrain's height under `at`, from a ray down onto the Environment layer.
func _ground_height(at: Vector3) -> float:
	var space: PhysicsDirectSpaceState3D = (get_tree().current_scene as Node3D).get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		Vector3(at.x, 1000.0, at.z), Vector3(at.x, -1000.0, at.z), 1 << 4)
	var hit: Dictionary = space.intersect_ray(query)
	return hit.position.y if hit else 0.0
