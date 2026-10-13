extends Node3D
## Photographs every armed boss holding its weapon, from the front and the side, in the
## resting walk and mid-swing - what to look at after moving a Weapon node by hand.
##
## Run with (windowed - a headless run uses the dummy renderer and draws nothing):
##   "G:\Godot\Godot_v4.7-stable_win64_console.exe" --path . --resolution 1280x720 res://tools/tests/boss_weapon_shot.tscn -- <folder>
##
## One PNG per boss, clip and view lands in <folder>: <boss>_<clip>_<view>.png. On a flat
## stage under a plain light, like boss_feet_shot, so two runs differ only in the grip.

const BOSSES := ["fire_giant", "frost_giant", "white_paladin"]
const CLIPS := [["walk", 0.25], ["attack", 0.5]]
## Camera positions around a 1.7 m body, looking at its chest.
const VIEWS := {
	"front": Vector3(0.0, 1.1, 2.6),
	"side": Vector3(2.6, 1.1, 0.0),
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
	var folder: String = args[0] if not args.is_empty() else "user://boss_weapon_shot"
	DirAccess.make_dir_recursive_absolute(folder)
	var camera := Camera3D.new()
	add_child(camera)
	camera.current = true
	for boss_name: String in BOSSES:
		var boss: Node3D = (load("res://scenes/bosses/%s.tscn" % boss_name) as PackedScene).instantiate()
		add_child(boss)
		if boss.find_child("Weapon", true, false) == null:
			push_error("%s has no Weapon node" % boss_name)
		var player: AnimationPlayer = boss.find_child("AnimationPlayer", true, false)
		for clip: Array in CLIPS:
			player.play(String(clip[0]))
			player.seek(player.current_animation_length * float(clip[1]), true)
			player.pause()
			for view: String in VIEWS:
				camera.position = VIEWS[view]
				camera.look_at(Vector3(0.0, 0.95, 0.0), Vector3.UP)
				for i: int in 3:
					await RenderingServer.frame_post_draw
				var file: String = "%s_%s_%s.png" % [boss_name, clip[0], view]
				get_viewport().get_texture().get_image().save_png(folder.path_join(file))
				print("WEAPON saved %s" % file)
		boss.free()
	get_tree().quit()
