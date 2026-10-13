extends Node3D
## Photographs the two shield bearers - the White soldier and the White paladin - with
## their shields, from the front, the shield side and the back, in the resting walk,
## mid-swing and mid-flinch. What to look at after moving a Shield node by hand.
##
## Run with (windowed - a headless run uses the dummy renderer and draws nothing):
##   "G:\Godot\Godot_v4.7-stable_win64_console.exe" --path . --resolution 1280x720 res://tools/tests/shield_shot.tscn -- <folder>
##
## One PNG per character, clip and view lands in <folder>: <name>_<clip>_<view>.png.

const CHARACTERS := {
	"soldier": "res://scenes/melee/human_melee.tscn",
	"paladin": "res://scenes/bosses/white_paladin.tscn",
}
const CLIPS := [["walk", 0.25], ["attack", 0.5], ["hit", 0.4]]
## Camera positions around a 1.7 m body, looking at its chest. The shield is on the
## left arm, which is +X for a character facing +Z.
const VIEWS := {
	"front": Vector3(0.0, 1.1, 2.8),
	"shield_side": Vector3(2.8, 1.1, 0.4),
	"back": Vector3(-1.2, 1.3, -2.5),
}


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
	var folder: String = args[0] if not args.is_empty() else "user://shield_shot"
	DirAccess.make_dir_recursive_absolute(folder)
	var camera := Camera3D.new()
	add_child(camera)
	camera.current = true
	for character_name: String in CHARACTERS:
		var character: Node3D = (load(CHARACTERS[character_name]) as PackedScene).instantiate()
		add_child(character)
		if character.find_child("Shield", true, false) == null:
			push_error("%s has no Shield node" % character_name)
		var player: AnimationPlayer = character.find_child("AnimationPlayer", true, false)
		for clip: Array in CLIPS:
			player.play(String(clip[0]))
			player.seek(player.current_animation_length * float(clip[1]), true)
			player.pause()
			for view: String in VIEWS:
				camera.position = VIEWS[view]
				camera.look_at(Vector3(0.0, 0.95, 0.0), Vector3.UP)
				for i: int in 3:
					await RenderingServer.frame_post_draw
				var file: String = "%s_%s_%s.png" % [character_name, clip[0], view]
				get_viewport().get_texture().get_image().save_png(folder.path_join(file))
				print("SHIELD saved %s" % file)
		character.free()
	get_tree().quit()
