extends "res://tools/tests/vfx_stage.gd"
## The Fireball's detonation as a strip of moments, so its look can be judged frame by frame
## and compared before and after a change.
##
## Run with (windowed - a headless run draws nothing; on Linux xvfb-run works):
##   godot --rendering-driver opengl3 --path . res://tools/tests/explosion_shot.tscn -- <out.png> [--glow]
##
## Shot on the light VfxStage rather than the real map (see vfx_stage.gd): a few seconds to
## boot instead of minutes. Each moment is its own detonation, photographed that many seconds
## after it went off - a software renderer is too slow to catch several moments of one
## explosion in sequence. The blast is set off through Projectile._fireball_blast_visuals, the
## same call the game makes, so whatever that builds is what is photographed.

const MOMENTS: Array[float] = [0.04, 0.12, 0.25, 0.45, 0.8, 1.6, 3.0, 6.0]
const TILE := Vector2i(480, 270)
const COLUMNS := 4

var _caption: Label = null
var _sheet: Image = null


func _ready() -> void:
	build_stage()
	_shoot_all.call_deferred()


func _shoot_all() -> void:
	for _i: int in range(ready_frames()):
		await get_tree().physics_frame
	var camera := Camera3D.new()
	add_child(camera)
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
		var before: Array[Node] = get_children()
		var projectile: Projectile = (load("res://scenes/misc/projectile.tscn") as PackedScene).instantiate()
		add_child(projectile)
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
		for child: Node in get_children():
			if not before.has(child):
				child.queue_free()
		await get_tree().create_timer(0.3).timeout

	var out_path: String = "explosion.png"
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not args.is_empty() and not args[0].begins_with("--"):
		out_path = args[0]
	_sheet.save_png(out_path)
	print("EXPLOSION SHEET: %s" % out_path)
	get_tree().quit()
