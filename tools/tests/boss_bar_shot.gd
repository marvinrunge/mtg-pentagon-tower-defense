extends Node
## Photographs the HUD's boss bars over a live scene: one boss in phase 2 regenerating with a
## modifier, one fresh in phase 1, so name, phase, phase lines, regen tag and the stacking
## can all be judged by eye.
##
## Run with (windowed - a headless run draws nothing; on Linux xvfb-run works):
##   godot --rendering-driver opengl3 --path . res://tools/tests/boss_bar_shot.tscn -- <out.png>

const STAGE := Vector3(0.0, 0.5, 18.0)

var _frames: int = 0


func _ready() -> void:
	if get_meta("armed", false):
		return
	call_deferred("_boot")


func _boot() -> void:
	var shooter: Node = load("res://tools/tests/boss_bar_shot.gd").new()
	shooter.name = "BossBarShooter"
	shooter.set_meta("armed", true)
	get_tree().root.add_child(shooter)
	get_tree().change_scene_to_file("res://scenes/misc/main.tscn")


func _process(_delta: float) -> void:
	if not get_meta("armed", false):
		return
	_frames += 1
	if _frames == 90:
		_shoot()


func _spawn(scene: Node, color: String, modifier: String, at: Vector3) -> EnemyBase:
	var packed: PackedScene = load("res://scenes/misc/enemy.tscn") as PackedScene
	var boss: EnemyBase = packed.instantiate()
	boss.set_meta("enemy_color", color)
	boss.set_meta("enemy_type", "Boss")
	if modifier != "":
		boss.set_meta("boss_modifier", modifier)
	scene.get_node("Enemies").add_child(boss)
	boss.global_position = at
	boss.rotation.y = PI
	boss.set_physics_process(false)
	return boss


func _shoot() -> void:
	var scene: Node = get_tree().current_scene
	var red: EnemyBase = _spawn(scene, "Red", "Riot", STAGE + Vector3(-3.0, 0.0, 4.0))
	var blue: EnemyBase = _spawn(scene, "Blue", "", STAGE + Vector3(3.5, 0.0, 6.0))
	red.take_damage(red.health - red.enemy_data.health * 0.48)
	red._pending_phase_transition = false
	red.boss_regenerating = true
	blue.take_damage(blue.enemy_data.health * 0.12)

	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.global_position = STAGE + Vector3(0.0, 5.0, -10.0)
	camera.look_at(STAGE + Vector3(0.0, 3.0, 5.0))
	camera.current = true
	var hud: Node = scene.get_node("HUD")
	hud.refresh_boss_bars()
	for _i: int in range(8):
		await RenderingServer.frame_post_draw
	hud.refresh_boss_bars()
	await RenderingServer.frame_post_draw

	var out_path: String = "boss_bar.png"
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not args.is_empty():
		out_path = args[0]
	get_viewport().get_texture().get_image().save_png(out_path)
	print("BOSS BAR SHOT: %s" % out_path)
	get_tree().quit()
