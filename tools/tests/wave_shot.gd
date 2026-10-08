extends "res://tools/tests/vfx_stage.gd"
## Close-ups of the shockwave, the gust, Fire Cone's stream and Titanic Brawl's slam at a few
## moments each, on the light VfxStage - for tuning them without casting whole spells.
##
## Run with (windowed - a headless run draws nothing; on Linux xvfb-run works):
##   godot --rendering-driver opengl3 --path . res://tools/tests/wave_shot.tscn -- <out.png> [gust,shockwave] [--glow]
## Each tile is its own effect, photographed that many seconds after it started.

const TILE := Vector2i(480, 270)
const MOMENTS: Array[float] = [0.06, 0.14, 0.26, 0.45]
const ALL_ROWS: Array[String] = ["shockwave", "gust", "fire_stream", "slam"]

## Narrowed by a user arg naming rows ("gust" or "gust,shockwave"); all three without one.
var _rows: Array[String] = ALL_ROWS.duplicate()

var _caption: Label = null


func _ready() -> void:
	build_stage()
	_shoot_all.call_deferred()


func _shoot_all() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.split(",")[0] in ALL_ROWS:
			_rows.clear()
			for row: String in arg.split(","):
				_rows.append(row)
	for _i: int in range(ready_frames()):
		await get_tree().physics_frame
	var camera := Camera3D.new()
	add_child(camera)
	camera.current = true
	var layer := CanvasLayer.new()
	add_child(layer)
	_caption = Label.new()
	_caption.position = Vector2(24, 14)
	_caption.add_theme_font_size_override("font_size", 40)
	_caption.add_theme_color_override("font_outline_color", Color.BLACK)
	_caption.add_theme_constant_override("outline_size", 10)
	layer.add_child(_caption)

	var sheet := Image.create(TILE.x * MOMENTS.size(), TILE.y * _rows.size(), false, Image.FORMAT_RGB8)
	for row: int in range(_rows.size()):
		for column: int in range(MOMENTS.size()):
			var keep: Array[Node] = get_children()
			var effect: Node3D = _build(_rows[row])
			add_child(effect)
			match _rows[row]:
				"shockwave":
					effect.position = STAGE
					camera.global_position = STAGE + Vector3(0.0, 4.5, 9.0)
					camera.look_at(STAGE + Vector3(0.0, 0.3, -1.0))
				"gust":
					effect.position = STAGE + Vector3(0.0, 1.0, 0.0)
					effect.look_at(effect.global_position + Vector3.FORWARD, Vector3.UP)
					camera.global_position = STAGE + Vector3(7.0, 4.0, 2.0)
					camera.look_at(STAGE + Vector3(0.0, 0.5, -4.5))
				"slam":
					effect.position = STAGE
					camera.global_position = STAGE + Vector3(0.0, 3.0, 7.5)
					camera.look_at(STAGE + Vector3(0.0, 1.0, 0.0))
				"fire_stream":
					effect.position = STAGE + Vector3(0.0, 1.2, 0.0)
					camera.global_position = STAGE + Vector3(6.5, 3.2, 1.5)
					camera.look_at(STAGE + Vector3(0.0, 0.9, -3.5))
			await get_tree().create_timer(MOMENTS[column] if _rows[row] != "fire_stream" else MOMENTS[column] * 3.0).timeout
			_caption.text = "%s +%.2fs" % [_rows[row], MOMENTS[column] if _rows[row] != "fire_stream" else MOMENTS[column] * 3.0]
			await RenderingServer.frame_post_draw
			var frame: Image = get_viewport().get_texture().get_image()
			frame.convert(Image.FORMAT_RGB8)
			frame.resize(TILE.x, TILE.y, Image.INTERPOLATE_BILINEAR)
			sheet.blit_rect(frame, Rect2i(Vector2i.ZERO, TILE), Vector2i(column * TILE.x, row * TILE.y))
			for child: Node in get_children():
				if not keep.has(child):
					child.free()

	var out_path: String = "wave_shot.png"
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not args.is_empty() and not args[0].begins_with("--"):
		out_path = args[0]
	sheet.save_png(out_path)
	print("WAVE SHEET: %s" % out_path)
	get_tree().quit()


func _build(kind: String) -> Node3D:
	match kind:
		"shockwave":
			return SpellFx.shockwave(SpellVisuals.WHITE_GOLD, 6.0, 0.5)
		"gust":
			return SpellFx.gust(9.0, Player.FX_BLUE)
		"slam":
			return SpellVisuals.titanic_slam(GameSettings.spell_green_leap_radius)
		_:
			return SpellVisuals.fire_stream(GameSettings.spell_red_fire_cone_length)
