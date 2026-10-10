extends Node3D
## Photographs the feet of enemies, myrs and the player in clips they borrow from other
## rigs - the counterpart of boss_feet_shot.tscn for tools/retarget_pass.gd, so a before
## and an after compare directly.
##
## Run with (windowed - a headless run uses the dummy renderer and draws nothing):
##   "G:\Godot\Godot_v4.7-stable_win64_console.exe" --path . --resolution 1280x720 res://tools/tests/character_feet_shot.tscn -- <folder>
##
## One PNG per shot lands in <folder>: <scene>_<clip>_<percent>.png.

## [scene, clip, moment as a fraction of the clip, camera distance].
const SHOTS := [
	["res://scenes/melee/elf_melee.tscn", "walk", 0.25, 1.0],
	["res://scenes/melee/merfolk_melee.tscn", "walk", 0.75, 1.0],
	["res://scenes/melee/human_melee.tscn", "attack", 0.4, 1.0],
	["res://scenes/mage/human_mage.tscn", "walk", 0.25, 1.0],
	["res://scenes/mage/zombie_mage.tscn", "attack", 0.5, 1.0],
	["res://scenes/ranged/elf_ranged.tscn", "walk", 0.25, 1.0],
	["res://scenes/myrs/gold_myr.tscn", "walk_loaded", 0.25, 0.6],
	["res://scenes/misc/player_visual.tscn", "cast_white", 0.5, 1.1],
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
	var folder: String = args[0] if not args.is_empty() else "user://character_feet_shot"
	DirAccess.make_dir_recursive_absolute(folder)
	var camera := Camera3D.new()
	add_child(camera)
	camera.current = true
	for shot: Array in SHOTS:
		var character: Node3D = (load(String(shot[0])) as PackedScene).instantiate()
		add_child(character)
		var player: AnimationPlayer = character.find_child("AnimationPlayer", true, false)
		player.play(String(shot[1]))
		player.seek(player.current_animation_length * float(shot[2]), true)
		player.pause()
		var distance: float = float(shot[3])
		camera.position = Vector3(0.75, 0.32, 0.95) * distance
		camera.look_at(Vector3(0.0, 0.18 * distance, 0.0), Vector3.UP)
		for i: int in 3:
			await RenderingServer.frame_post_draw
		var file: String = "%s_%s_%03d.png" % [String(shot[0]).get_file().get_basename(), shot[1], int(float(shot[2]) * 100.0)]
		get_viewport().get_texture().get_image().save_png(folder.path_join(file))
		print("FEET saved %s" % file)
		character.free()
	get_tree().quit()
