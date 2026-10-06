extends Node
## Photographs the boss telegraphs - every new shape and the ground hazards - as one contact
## sheet, so what a player will be asked to read can be judged by eye.
##
## Run with (windowed - a headless run draws nothing; on Linux xvfb-run works):
##   godot --rendering-driver opengl3 --path . res://tools/tests/telegraph_shot.tscn -- <out.png>
##
## Each tile stages one boss on the base platform, starts one special against stand-in
## players (the small posts), and freezes its telegraphs at 70 % filled. The boss's own AI is
## switched off: only the telegraphs are wanted, not the fight.

const TILE := Vector2i(640, 360)
const COLUMNS := 2
## The base platform's top is a known flat y=0.5 (see boss_shot.gd).
const STAGE := Vector3(0.0, 0.5, 18.0)

## [colour, special display name, phase, stand-in offsets, extra strikes to draw]
const SHOTS: Array = [
	["Red", "Meteor Strike", 2, [Vector3(-5, 0, 6), Vector3(6, 0, 9), Vector3(1, 0, -7)], 0],
	["Red", "Unbound Whirlwind", 3, [Vector3(0, 0, 5)], 0],
	["Blue", "Ice Lances", 2, [Vector3(0, 0, 9)], 0],
	["Blue", "Absolute Zero", 3, [Vector3(0, 0, 2), Vector3(5, 0, 7)], 0],
	["Green", "Uprooting Leap", 3, [Vector3(4, 0, 9)], 2],
	["White", "Judgment", 2, [Vector3(2, 0, 9)], 0],
	["White", "Twin Slash", 3, [Vector3(0, 0, 5)], 1],
	["Black", "The Hunt", 3, [Vector3(-3, 0, 8)], 0],
]

var _frames: int = 0
var _sheet: Image = null
var _camera: Camera3D = null
var _caption: Label = null
var _scene: Node = null


func _ready() -> void:
	if get_meta("armed", false):
		return
	call_deferred("_boot")


func _boot() -> void:
	var shooter: Node = load("res://tools/tests/telegraph_shot.gd").new()
	shooter.name = "TelegraphShooter"
	shooter.set_meta("armed", true)
	get_tree().root.add_child(shooter)
	get_tree().change_scene_to_file("res://scenes/misc/main.tscn")


func _process(_delta: float) -> void:
	if not get_meta("armed", false):
		return
	_frames += 1
	if _frames == 90:
		_shoot_all()


class _Stand:
	extends Node3D
	var is_downed: bool = false
	var hp: float = 100.0
	var max_hp: float = 100.0
	func take_damage(_amount: float, _source: Node3D = null, _is_melee: bool = false, _exile: bool = false) -> void:
		pass
	func apply_slow(_duration: float) -> void:
		pass


func _shoot_all() -> void:
	_scene = get_tree().current_scene
	for node: Node in get_tree().get_nodes_in_group("player"):
		node.remove_from_group("player")
	for node: Node in _scene.find_children("*", "CanvasLayer", true, false):
		(node as CanvasLayer).visible = false

	_camera = Camera3D.new()
	_scene.add_child(_camera)
	_camera.global_position = STAGE + Vector3(0.0, 21.0, -9.0)
	_camera.look_at(STAGE + Vector3(0.0, 0.0, 3.0))
	_camera.fov = 62.0
	_camera.current = true

	var layer := CanvasLayer.new()
	add_child(layer)
	_caption = Label.new()
	_caption.position = Vector2(24, 16)
	_caption.add_theme_font_size_override("font_size", 40)
	_caption.add_theme_color_override("font_outline_color", Color.BLACK)
	_caption.add_theme_constant_override("outline_size", 10)
	layer.add_child(_caption)

	var rows: int = int(ceil(float(SHOTS.size() + 1) / float(COLUMNS)))
	_sheet = Image.create(TILE.x * COLUMNS, TILE.y * rows, false, Image.FORMAT_RGB8)
	for i: int in range(SHOTS.size()):
		await _shoot(i, SHOTS[i])
	await _shoot_hazards(SHOTS.size())

	var out_path: String = "telegraphs.png"
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not args.is_empty():
		out_path = args[0]
	_sheet.save_png(out_path)
	print("TELEGRAPH SHEET: %s" % out_path)
	get_tree().quit()


func _shoot(tile: int, shot: Array) -> void:
	var color: String = shot[0]
	var display_name: String = shot[1]
	var phase: int = shot[2]
	var scene: PackedScene = load("res://scenes/misc/enemy.tscn") as PackedScene
	var boss: EnemyBase = scene.instantiate()
	boss.set_meta("enemy_color", color)
	boss.set_meta("enemy_type", "Boss")
	_scene.get_node("Enemies").add_child(boss)
	boss.global_position = STAGE
	boss.rotation.y = 0.0
	boss.set_physics_process(false)
	var stands: Array[Node3D] = []
	for offset: Vector3 in shot[3]:
		stands.append(_make_stand(STAGE + offset))
	boss.current_target = stands[0]

	var ratio: float = 0.5 if phase == 2 else 0.2
	boss.take_damage(boss.health - boss.enemy_data.health * ratio)
	boss._pending_phase_transition = false
	var index: int = -1
	for i: int in range(boss._specials.size()):
		var config: Dictionary = boss._specials[i]
		if String(config["display_name"]) == display_name and BossDatabase.special_in_phase(config, phase):
			index = i
	boss._begin_special(index)
	# Followup strikes are drawn too, so a combo shows as the whole combo.
	for extra: int in range(int(shot[4])):
		if extra + 1 < boss._cast_strikes.size():
			boss._start_strike(extra + 1)
	_freeze_indicators(boss)
	await _capture(tile, "%s  -  %s" % [color.to_upper(), display_name])
	boss._cancel_special()
	boss.queue_free()
	for stand: Node3D in stands:
		stand.remove_from_group("player")
		stand.queue_free()
	await get_tree().process_frame


func _shoot_hazards(tile: int) -> void:
	var main: Node = _scene
	main.request_effect({"kind": "boss_hazard", "position": STAGE + Vector3(-4, 0, 4), "style": "fire",
		"radius": 2.5, "duration": 30.0, "dps": 0.0})
	main.request_effect({"kind": "boss_hazard", "position": STAGE + Vector3(3, 0, 7), "style": "frost",
		"radius": 7.5, "inner_radius": 6.0, "duration": 30.0, "slow": 0.6})
	for _i: int in range(20):
		await get_tree().process_frame
	await _capture(tile, "HAZARDS  -  fire patch, frost ring")


func _make_stand(at: Vector3) -> Node3D:
	var stand := _Stand.new()
	stand.add_to_group("player")
	var post := CSGCylinder3D.new()
	post.radius = 0.35
	post.height = 1.8
	post.position.y = 0.9
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.95, 0.2)
	post.material = mat
	stand.add_child(post)
	_scene.add_child(stand)
	stand.global_position = at
	return stand


## Every telegraph this boss has standing, frozen at 70 % filled. Includes ones parented to
## the world rather than the boss (anything aimed at a stand-in).
func _freeze_indicators(boss: EnemyBase) -> void:
	for indicator: AttackIndicator in boss._cast_indicators:
		if is_instance_valid(indicator):
			indicator._elapsed = indicator._duration * 0.7
			indicator._auto_resolve = false
			indicator._process(0.0)
			indicator.set_process(false)


func _capture(tile: int, caption: String) -> void:
	_caption.text = caption
	for _i: int in range(4):
		await RenderingServer.frame_post_draw
	var frame: Image = get_viewport().get_texture().get_image()
	frame.convert(Image.FORMAT_RGB8)
	frame.resize(TILE.x, TILE.y, Image.INTERPOLATE_BILINEAR)
	var x: int = (tile % COLUMNS) * TILE.x
	var y: int = (tile / COLUMNS) * TILE.y
	_sheet.blit_rect(frame, Rect2i(Vector2i.ZERO, TILE), Vector2i(x, y))
	print("  shot %d: %s" % [tile, caption])
