extends "res://tools/tests/vfx_stage.gd"
## Air shimmer (SpellFx.heat_haze) photographed close, full size, with and without it - a
## shimmer is a few pixels of shift and disappears in a scaled-down contact sheet.
##
## Run with (windowed - a headless run draws nothing; on Linux xvfb-run works):
##   godot --rendering-driver vulkan --rendering-method forward_plus --path . res://tools/tests/haze_shot.tscn -- <out_prefix>
## Forward+ (lavapipe in the container): the Compatibility renderer draws no shimmer, see
## SpellFx.haze_supported.
## Writes <out_prefix>_off.png and <out_prefix>_on.png: the same view of a standing stone
## behind a column of heat, first without the haze, then with it.


func _ready() -> void:
	build_stage()
	_shoot.call_deferred()


func _shoot() -> void:
	for _i: int in range(ready_frames()):
		await get_tree().physics_frame
	var prefix: String = "haze_shot"
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not args.is_empty() and not args[0].begins_with("--"):
		prefix = args[0]
	var stone := Vector3(12.0, 0.0, -3.0)
	var camera := Camera3D.new()
	add_child(camera)
	camera.current = true
	camera.global_position = stone + Vector3(0.0, 1.8, 7.0)
	camera.look_at(stone + Vector3(0.0, 1.4, 0.0))

	await _frame(prefix + "_off.png")
	var haze: Node3D = SpellFx.heat_haze(Vector3(1.2, 0.2, 0.6), 1.8, 30, 1.1, 1.6, 0.012)
	add_child(haze)
	haze.global_position = stone + Vector3(0.0, 0.2, 3.0)
	await get_tree().create_timer(1.2).timeout
	await _frame(prefix + "_on.png")
	get_tree().quit()


func _frame(path: String) -> void:
	await RenderingServer.frame_post_draw
	var frame: Image = get_viewport().get_texture().get_image()
	frame.convert(Image.FORMAT_RGB8)
	frame.save_png(path)
	print("HAZE SHOT: %s" % path)
