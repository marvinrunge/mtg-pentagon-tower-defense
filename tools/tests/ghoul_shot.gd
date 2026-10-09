extends Node3D
## Screenshots raised ghouls (Zombify) up close under the game's own sky, at noon and at
## night, so their look - dead flesh, black furrows, violet cracks - can be judged against
## both ends of the day.
##
## Run with (windowed - a headless run uses the dummy renderer and draws nothing):
##   "G:\Godot\Godot_v4.7-stable_win64_console.exe" --path . --resolution 1280x720 res://tools/tests/ghoul_shot.tscn -- <folder> [--glow]

const HOURS: Array[float] = [12.0, 23.0]
const COLORS: Array[String] = ["White", "Red", "Green"]

var _sky: Sky3D


func _ready() -> void:
	_sky = Sky3D.new()
	add_child(_sky)
	if _sky.tod:
		_sky.tod.game_time_enabled = false
	if OS.get_cmdline_user_args().has("--glow") and _sky.environment != null:
		GraphicsSettings.configure_glow(_sky.environment, true)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60.0, 60.0)
	ground.mesh = plane
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color(0.22, 0.26, 0.20)
	ground.material_override = ground_material
	add_child(ground)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1 | EnemyBase.ENVIRONMENT_LAYER
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60.0, 0.2, 60.0)
	floor_shape.shape = box
	floor_shape.position.y = -0.1
	floor_body.add_child(floor_shape)
	add_child(floor_body)

	for index: int in COLORS.size():
		var ghoul := TemporaryAlly.new()
		ghoul.configure("undead", 100.0, 600.0, 10.0, null)
		ghoul.visual_color = COLORS[index]
		ghoul.visual_class = "Melee"
		add_child(ghoul)
		ghoul.position = Vector3((index - 1) * 1.6, 0.0, 0.0)
		ghoul.rotation.y = PI * 0.0 + (index - 1) * 0.35

	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 1.5, 4.2)
	camera.current = true
	add_child(camera)
	camera.look_at(Vector3(0.0, 1.0, 0.0), Vector3.UP)
	_shoot.call_deferred()


func _shoot() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var folder: String = "user://ghoul_shot"
	if not args.is_empty() and not args[0].begins_with("--"):
		folder = args[0]
	DirAccess.make_dir_recursive_absolute(folder)
	for hour: float in HOURS:
		if _sky.tod:
			_sky.tod.current_time = hour
		await get_tree().create_timer(0.8).timeout
		await RenderingServer.frame_post_draw
		var file: String = "ghouls_%05.2f.png" % hour
		get_viewport().get_texture().get_image().save_png(folder.path_join(file))
		print("GHOUL saved %s" % file)
	get_tree().quit()
