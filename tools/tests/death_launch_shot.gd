extends Node3D
## Films the death launch: three enemies killed side by side by a light, a medium and a huge
## hit from the same direction, seen from the side, as a run of frames. On a flat stage under
## the game's sky rather than on the map, which a software renderer cannot draw fast enough
## for the frames to be anywhere near the timing they are meant to show.
##
## Run with (windowed - a headless run renders nothing):
##   "G:\Godot\Godot_v4.7-stable_win64_console.exe" --path . --resolution 1280x720 res://tools/tests/death_launch_shot.tscn -- <folder>
##
## seq_00.png, seq_01.png, ... land in <folder>.

const FRAMES := 36
const STEP := 0.06
## Damage as a fraction of each enemy's full health: a finishing tap, a solid hit, a huge one.
const SEVERITIES: Array[float] = [0.15, 0.5, 1.5]

var _sky: Sky3D


func _ready() -> void:
	_sky = Sky3D.new()
	add_child(_sky)
	if _sky.tod:
		_sky.tod.game_time_enabled = false
		_sky.tod.current_time = 15.0

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(80.0, 80.0)
	ground.mesh = plane
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color(0.22, 0.26, 0.20)
	ground.material_override = ground_material
	add_child(ground)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1 | EnemyBase.ENVIRONMENT_LAYER
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80.0, 0.2, 80.0)
	floor_shape.shape = box
	floor_shape.position.y = -0.1
	floor_body.add_child(floor_shape)
	add_child(floor_body)
	_run.call_deferred()


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var folder: String = args[0] if args.size() > 0 else "user://death_launch_shot"
	DirAccess.make_dir_recursive_absolute(folder)

	var enemies: Array[EnemyBase] = []
	for index: int in SEVERITIES.size():
		var enemy: EnemyBase = (load("res://scenes/misc/enemy.tscn") as PackedScene).instantiate()
		enemy.set_meta("enemy_color", ["Red", "Black", "White"][index])
		enemy.set_meta("enemy_type", "Melee")
		add_child(enemy)
		enemy.global_position = Vector3(-3.0, 0.05, (index - 1) * 3.0)
		# Standing still until the hit: no crystal or lane here for the AI to walk to.
		enemy.set_physics_process(false)
		enemies.append(enemy)

	var camera := Camera3D.new()
	add_child(camera)
	camera.current = true
	camera.global_position = Vector3(2.0, 3.0, 12.0)
	camera.look_at(Vector3(1.0, 0.8, 0.0), Vector3.UP)
	for i: int in 20:
		await get_tree().physics_frame

	# All three from the same side, so they fly the same way and their distances compare.
	for index: int in enemies.size():
		var enemy: EnemyBase = enemies[index]
		var source := Node3D.new()
		add_child(source)
		source.global_position = enemy.global_position - Vector3(2.0, 0.0, 0.0)
		# Left with exactly the hit's worth of health, so every one of the three is a kill.
		var hit: float = enemy.enemy_data.health * SEVERITIES[index]
		enemy.health = minf(enemy.health, hit)
		enemy.take_damage(hit, source)
		enemy.set_physics_process(true)
		source.queue_free()

	for index: int in FRAMES:
		await get_tree().create_timer(STEP).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(folder.path_join("seq_%02d.png" % index))
	print("DEATH_SHOT saved %d frames" % FRAMES)
	get_tree().quit()
