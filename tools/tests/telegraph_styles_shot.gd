extends Node
## Compares the telegraph styles side by side: one row per attack, one column per style, the
## last column with the ground telegraphs switched off so only the world tells (BossTell) are
## left.
##
## Run with (windowed - a headless run draws nothing; on Linux xvfb-run works):
##   godot --rendering-driver opengl3 --path . res://tools/tests/telegraph_styles_shot.tscn -- <out.png>
##
## Every tile freezes its telegraphs and tells at 70 % of the windup - the moment a player is
## deciding where to go.

const TILE := Vector2i(560, 315)
## The flat top of the base platform (y=0.5, see boss_shot.gd). Off it the ground rises,
## and flat telegraphs disappear into the slope.
const STAGE := Vector3(0.0, 0.5, 18.0)
const FREEZE_AT := 0.7
## [label, attack-indicator style, ground telegraphs shown]
const COLUMNS: Array = [
	["CLASSIC", "classic", true],
	["GLOWING RIM", "rim", true],
	["THEMED", "themed", true],
	["LATE REVEAL", "late", true],
	["WORLD TELLS ONLY", "themed", false],
]
## [colour, special, phase, stand-in offsets, followup strikes to draw too]
## Targets stand off to the side, so lines and cones run across the camera's view rather than
## away from it into the standing stone behind the stage.
const ROWS: Array = [
	["Red", "Meteor Strike", 2, [Vector3(-5, 0, 6), Vector3(6, 0, 7), Vector3(1, 0, -5)], 0],
	["Red", "Whirlwind", 1, [Vector3(-4, 0, 3)], 0],
	["Blue", "Ice Lances", 2, [Vector3(-9, 0, 3)], 0],
	["Blue", "Absolute Zero", 3, [Vector3(-1.5, 0, 1), Vector3(-6, 0, 4)], 0],
	["Green", "Uprooting Leap", 3, [Vector3(-7, 0, 4)], 2],
	["White", "Judgment", 2, [Vector3(-3, 0, 5)], 0],
	["White", "Twin Slash", 3, [Vector3(-5, 0, 1)], 1],
	["Black", "The Hunt", 3, [Vector3(-8, 0, 2)], 0],
]

var _frames: int = 0
var _sheet: Image = null
var _caption: Label = null
var _scene: Node = null


func _ready() -> void:
	if get_meta("armed", false):
		return
	call_deferred("_boot")


func _boot() -> void:
	var shooter: Node = load("res://tools/tests/telegraph_styles_shot.gd").new()
	shooter.name = "TelegraphStylesShooter"
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

	# Noon, so the stones' shadows are short and every tile is lit the same.
	var sky: Node = _scene.get_node_or_null("Sky3D")
	if sky != null:
		sky.set("game_time_enabled", false)
		sky.set("current_time", 12.0)
	var camera := Camera3D.new()
	_scene.add_child(camera)
	camera.global_position = STAGE + Vector3(0.0, 15.0, -13.0)
	camera.look_at(STAGE + Vector3(0.0, 0.0, 4.0))
	camera.fov = 66.0
	camera.current = true

	var layer := CanvasLayer.new()
	add_child(layer)
	_caption = Label.new()
	_caption.position = Vector2(24, 14)
	_caption.add_theme_font_size_override("font_size", 46)
	_caption.add_theme_color_override("font_outline_color", Color.BLACK)
	_caption.add_theme_constant_override("outline_size", 12)
	layer.add_child(_caption)

	# "-- <out.png> quick" renders a handful of tiles instead of the whole sheet - a check of
	# framing and lighting before the half-hour software-rendered run.
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var rows: Array = range(ROWS.size())
	var columns: Array = range(COLUMNS.size())
	if args.has("quick"):
		rows = [0, 2, 7]
		columns = [2, 4]
	_sheet = Image.create(TILE.x * COLUMNS.size(), TILE.y * ROWS.size(), false, Image.FORMAT_RGB8)
	var keep_style: String = GameSettings.attack_indicator_style
	var keep_shown: bool = GameSettings.show_attack_indicators
	for row: int in rows:
		for column: int in columns:
			GameSettings.attack_indicator_style = String(COLUMNS[column][1])
			GameSettings.show_attack_indicators = bool(COLUMNS[column][2])
			await _shoot(row, column)
	GameSettings.attack_indicator_style = keep_style
	GameSettings.show_attack_indicators = keep_shown

	var out_path: String = "telegraph_styles.png"
	if not args.is_empty():
		out_path = args[0]
	_sheet.save_png(out_path)
	print("TELEGRAPH STYLES SHEET: %s" % out_path)
	get_tree().quit()


func _shoot(row: int, column: int) -> void:
	var shot: Array = ROWS[row]
	var color: String = shot[0]
	var phase: int = shot[2]
	var packed: PackedScene = load("res://scenes/misc/enemy.tscn") as PackedScene
	var boss: EnemyBase = packed.instantiate()
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
	if phase > 1:
		boss.take_damage(boss.health - boss.enemy_data.health * (0.5 if phase == 2 else 0.2))
		boss._pending_phase_transition = false
	var index: int = -1
	for i: int in range(boss._specials.size()):
		var config: Dictionary = boss._specials[i]
		if String(config["display_name"]) == String(shot[1]) and BossDatabase.special_in_phase(config, phase):
			index = i
	boss._begin_special(index)
	for extra: int in range(int(shot[4])):
		if extra + 1 < boss._cast_strikes.size():
			boss._start_strike(extra + 1)
	for indicator: AttackIndicator in boss._cast_indicators:
		if is_instance_valid(indicator):
			indicator._elapsed = indicator._duration * FREEZE_AT
			indicator._auto_resolve = false
			indicator._process(0.0)
			indicator.set_process(false)
	for tell: BossTell in boss._cast_tells:
		if is_instance_valid(tell):
			tell.freeze_at(FREEZE_AT)

	_caption.text = "%s - %s" % [String(shot[1]).to_upper(), COLUMNS[column][0]] if column == 0 else String(COLUMNS[column][0])
	for _i: int in range(4):
		await RenderingServer.frame_post_draw
	var frame: Image = get_viewport().get_texture().get_image()
	frame.convert(Image.FORMAT_RGB8)
	frame.resize(TILE.x, TILE.y, Image.INTERPOLATE_BILINEAR)
	_sheet.blit_rect(frame, Rect2i(Vector2i.ZERO, TILE), Vector2i(column * TILE.x, row * TILE.y))
	print("  %s / %s" % [shot[1], COLUMNS[column][0]])

	boss._cancel_special()
	boss.queue_free()
	for stand: Node3D in stands:
		stand.remove_from_group("player")
		stand.queue_free()
	await get_tree().process_frame


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
