extends Node3D
## Photographs every boss's feet in the clips most likely to show a bad retarget - one
## frame of each, the same frames every run, so a before and an after compare directly.
##
## Run with (windowed - a headless run uses the dummy renderer and draws nothing):
##   "G:\Godot\Godot_v4.7-stable_win64_console.exe" --path . --resolution 1280x720 res://tools/tests/boss_feet_shot.tscn -- <folder>
##
## One PNG per boss, clip and moment lands in <folder>: <boss>_<clip>_<percent>.png. On a
## flat stage under a plain light rather than on the map, so nothing but the pose is
## different between two runs.

const SHOTS := [
	["fire_giant", "walk", 0.25], ["fire_giant", "walk", 0.75], ["fire_giant", "attack", 0.5],
	["frost_giant", "walk", 0.25], ["frost_giant", "death", 1.0],
	["treant", "walk", 0.25], ["treant", "hit", 0.5],
	["white_paladin", "walk", 0.25],
	["zombie_lord", "walk", 0.25], ["zombie_lord", "walk", 0.75],
]


func _ready() -> void:
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.55, 0.62, 0.7)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.6, 0.6, 0.6)
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, 30.0, 0.0)
	add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(20.0, 20.0)
	ground.mesh = plane
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.3, 0.33, 0.28)
	ground.material_override = material
	add_child(ground)
	_shoot.call_deferred()


func _shoot() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var folder: String = args[0] if not args.is_empty() else "user://boss_feet_shot"
	DirAccess.make_dir_recursive_absolute(folder)
	var camera := Camera3D.new()
	add_child(camera)
	camera.current = true
	for shot: Array in SHOTS:
		var boss: Node3D = (load("res://scenes/bosses/%s.tscn" % shot[0]) as PackedScene).instantiate()
		add_child(boss)
		var player: AnimationPlayer = boss.find_child("AnimationPlayer", true, false)
		player.play(String(shot[1]))
		player.seek(player.current_animation_length * float(shot[2]), true)
		player.pause()
		# Three-quarter view at shin height, close in: feet, ankles and how the soles meet the
		# floor fill the frame.
		camera.position = Vector3(0.75, 0.32, 0.95)
		camera.look_at(Vector3(0.0, 0.18, 0.0), Vector3.UP)
		for i: int in 3:
			await RenderingServer.frame_post_draw
		var file: String = "%s_%s_%03d.png" % [shot[0], shot[1], int(float(shot[2]) * 100.0)]
		get_viewport().get_texture().get_image().save_png(folder.path_join(file))
		print("FEET saved %s" % file)
		boss.free()
	get_tree().quit()
