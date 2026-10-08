extends Node
## The Fireball's detonation as a strip of moments, so its look can be judged frame by frame
## and compared before and after a change.
##
## Run with (windowed - a headless run draws nothing; on Linux xvfb-run works):
##   godot --rendering-driver opengl3 --path . res://tools/tests/explosion_shot.tscn -- <out.png>
##
## Each moment is its own detonation, photographed that many seconds after it went off - the
## software renderer is far too slow to catch several moments of one explosion in sequence.
## The blast is set off through Projectile._fireball_blast_visuals, the same call the game
## makes, so whatever that builds is what is photographed.

const MOMENTS: Array[float] = [0.04, 0.12, 0.25, 0.45, 0.8, 1.6, 3.0, 6.0]
const TILE := Vector2i(480, 270)
const COLUMNS := 4
const STAGE := Vector3(2.0, 0.5, 16.0)

var _frames: int = 0
var _scene: Node = null
var _caption: Label = null
var _sheet: Image = null


func _ready() -> void:
	if get_meta("armed", false):
		return
	call_deferred("_boot")


func _boot() -> void:
	var shooter: Node = load("res://tools/tests/explosion_shot.gd").new()
	shooter.name = "ExplosionShooter"
	shooter.set_meta("armed", true)
	get_tree().root.add_child(shooter)
	get_tree().change_scene_to_file("res://scenes/misc/main.tscn")


func _process(_delta: float) -> void:
	if not get_meta("armed", false):
		return
	_frames += 1
	if _frames == 90:
		_shoot_all()


func _shoot_all() -> void:
	_scene = get_tree().current_scene
	for node: Node in get_tree().get_nodes_in_group("player"):
		node.remove_from_group("player")
		(node as Node3D).visible = false
	for node: Node in _scene.find_children("*", "CanvasLayer", true, false):
		(node as CanvasLayer).visible = false
	var sky: Node = _scene.get_node_or_null("Sky3D")
	if sky != null:
		sky.set("game_time_enabled", false)
		sky.set("current_time", 15.0)
	# `-- <out.png> --glow` renders with the game's bloom, configured straight onto the map's
	# own sky rather than through GraphicsSettings.apply_glow, which would also save the switch
	# into the player's settings.
	if OS.get_cmdline_user_args().has("--glow") and sky is WorldEnvironment:
		GraphicsSettings.configure_glow((sky as WorldEnvironment).environment, true)

	var camera := Camera3D.new()
	_scene.add_child(camera)
	camera.global_position = STAGE + Vector3(0.0, 2.6, -8.5)
	camera.look_at(STAGE + Vector3(0.0, 1.3, 0.0))
	camera.current = true
	var layer := CanvasLayer.new()
	add_child(layer)
	_caption = Label.new()
	_caption.position = Vector2(24, 14)
	_caption.add_theme_font_size_override("font_size", 44)
	_caption.add_theme_color_override("font_outline_color", Color.BLACK)
	_caption.add_theme_constant_override("outline_size", 10)
	layer.add_child(_caption)

	var rows: int = int(ceil(float(MOMENTS.size()) / float(COLUMNS)))
	_sheet = Image.create(TILE.x * COLUMNS, TILE.y * rows, false, Image.FORMAT_RGB8)
	for i: int in range(MOMENTS.size()):
		var before: Array[Node] = _scene.get_children()
		var packed: PackedScene = load("res://scenes/misc/projectile.tscn") as PackedScene
		var projectile: Projectile = packed.instantiate()
		_scene.add_child(projectile)
		projectile.activate(STAGE + Vector3(0.0, 1.2, 0.0), Vector3.FORWARD, 4, false, 1.0, -1.0, 0.0, null, "magic", Color(1.0, 0.45, 0.1))
		projectile.global_position = STAGE + Vector3(0.0, 1.2, 0.0)
		projectile.set_physics_process(false)
		projectile.visible = false
		projectile._fireball_blast_visuals()
		await get_tree().create_timer(MOMENTS[i]).timeout
		_caption.text = "+%.2fs" % MOMENTS[i]
		await RenderingServer.frame_post_draw
		var frame: Image = get_viewport().get_texture().get_image()
		frame.convert(Image.FORMAT_RGB8)
		frame.resize(TILE.x, TILE.y, Image.INTERPOLATE_BILINEAR)
		_sheet.blit_rect(frame, Rect2i(Vector2i.ZERO, TILE), Vector2i((i % COLUMNS) * TILE.x, (i / COLUMNS) * TILE.y))
		print("  +%.2fs" % MOMENTS[i])
		for child: Node in _scene.get_children():
			if not before.has(child) and child != camera:
				child.queue_free()
		await get_tree().create_timer(0.3).timeout

	var out_path: String = "explosion.png"
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not args.is_empty() and not args[0].begins_with("--"):
		out_path = args[0]
	_sheet.save_png(out_path)
	print("EXPLOSION SHEET: %s" % out_path)
	get_tree().quit()
